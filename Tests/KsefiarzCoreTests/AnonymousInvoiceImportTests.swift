import Foundation
import SwiftData
import Testing
@testable import KsefiarzCore

private let anonymousTestKSeFNumber = "9999999999-20260714-0EC0EB000000-1D"

private func anonymousRequest(
    identifierType: AnonymousInvoiceBuyerIdentifierType = .nip,
    identifierValue: String = "111-111-11-11",
    buyerName: String? = "Nabywca Testowy Sp. z o.o."
) -> AnonymousInvoiceAccessRequest {
    AnonymousInvoiceAccessRequest(
        ksefNumber: " \(anonymousTestKSeFNumber.lowercased()) ",
        invoiceNumber: " FV/7/2026 ",
        buyerIdentifierType: identifierType,
        buyerIdentifierValue: identifierValue,
        buyerName: buyerName,
        grossAmount: Decimal(string: "123.45")!
    )
}

private func formFields(of request: URLRequest) -> [String: String] {
    guard let body = request.httpBody,
          let string = String(data: body, encoding: .utf8) else { return [:] }
    var components = URLComponents()
    // Dekodowanie w semantyce application/x-www-form-urlencoded: serwer
    // traktuje dosłowny `+` jako spację, więc asercje na tych polach
    // sprawdzają wartości widziane przez bramkę, nie surowe ciało żądania.
    components.percentEncodedQuery = string.replacingOccurrences(of: "+", with: "%20")
    return Dictionary(
        (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        },
        uniquingKeysWith: { first, _ in first }
    )
}

private func successfulAnonymousTransport(xml: Data) -> MockTransport {
    let transport = MockTransport()
    var call = 0
    transport.route("invoice/search") { _ in
        call += 1
        switch call {
        case 1:
            return (200, Data(#"<input name="__RequestVerificationToken" type="hidden" value="TOKEN-1" />"#.utf8))
        case 2:
            return (200, Data(#"<input name="__RequestVerificationToken" type="hidden" value="TOKEN-2" />"#.utf8))
        default:
            let encoded = xml.base64EncodedString()
                .replacingOccurrences(of: "+", with: "&#x2B;")
            return (200, Data(#"<div data-xml-text="\#(encoded)"></div>"#.utf8))
        }
    }
    return transport
}

@Suite("Anonimowy dostęp do faktury — publiczna bramka MF")
struct KSeFAnonymousAccessServiceTests {

    @Test("Dwuetapowy formularz wysyła komplet danych i zwraca oryginalny XML")
    func downloadSuccess() async throws {
        let xml = Data("<?xml version=\"1.0\"?><Faktura>Zażółć + test</Faktura>".utf8)
        let transport = successfulAnonymousTransport(xml: xml)
        let service = KSeFAnonymousAccessService(environment: .test, transport: transport)

        let result = try await service.downloadInvoice(anonymousRequest())

        #expect(result == xml)
        #expect(transport.requests.count == 3)
        #expect(transport.requests[0].httpMethod == "GET")
        #expect(transport.requests[0].url?.absoluteString == "https://qr-test.ksef.mf.gov.pl/invoice/search")

        let numberForm = formFields(of: transport.requests[1])
        #expect(transport.requests[1].httpMethod == "POST")
        #expect(numberForm["KsefNumber"] == anonymousTestKSeFNumber)
        #expect(numberForm["RedirectUrl"] == "https://ap-test.ksef.mf.gov.pl/web/")
        #expect(numberForm["__RequestVerificationToken"] == "TOKEN-1")

        let details = transport.requests[2]
        let detailsForm = formFields(of: details)
        #expect(details.url?.path == "/client-app/invoice/search/\(anonymousTestKSeFNumber)/verify-download")
        #expect(URLComponents(url: details.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Format")
        #expect(detailsForm["InvoiceNumber"] == "FV/7/2026")
        #expect(detailsForm["BuyerIdentifierType"] == "Nip")
        #expect(detailsForm["BuyerIdentifierValue"] == "1111111111")
        #expect(detailsForm["BuyerName"] == "Nabywca Testowy Sp. z o.o.")
        #expect(detailsForm["Amount"] == "123,45")
        #expect(detailsForm["__RequestVerificationToken"] == "TOKEN-2")
        #expect(details.value(forHTTPHeaderField: "Origin") == "https://qr-test.ksef.mf.gov.pl")
    }

    @Test("Wariant bez identyfikatora i nazwy wysyła puste wartości")
    func noBuyerIdentity() async throws {
        let transport = successfulAnonymousTransport(xml: Data("<Faktura/>".utf8))
        let service = KSeFAnonymousAccessService(environment: .demo, transport: transport)

        _ = try await service.downloadInvoice(anonymousRequest(
            identifierType: .none,
            identifierValue: "wartość do pominięcia",
            buyerName: nil
        ))

        let numberForm = formFields(of: transport.requests[1])
        #expect(numberForm["RedirectUrl"] == "https://ap-demo.ksef.mf.gov.pl/web/")
        let details = formFields(of: transport.requests[2])
        #expect(details["BuyerIdentifierType"] == "None")
        #expect(details["BuyerIdentifierValue"] == "")
        #expect(details["BuyerName"] == "")
    }

    @Test("Brak zgodnej faktury jest rozpoznawany po odpowiedzi bramki")
    func invoiceNotFound() async {
        let transport = MockTransport()
        var call = 0
        transport.route("invoice/search") { _ in
            call += 1
            if call == 1 {
                return (200, Data(#"<input name="__RequestVerificationToken" value="TOKEN-1">"#.utf8))
            }
            if call == 2 {
                return (200, Data(#"<input name="__RequestVerificationToken" value="TOKEN-2">"#.utf8))
            }
            return (200, Data("<span>Nie znaleziono faktury</span><div data-xml-text=\"\"></div>".utf8))
        }
        let service = KSeFAnonymousAccessService(environment: .production, transport: transport)

        await #expect(throws: AnonymousInvoiceAccessError.invoiceNotFound) {
            try await service.downloadInvoice(anonymousRequest())
        }
    }

    @Test("Błędny numer KSeF zatrzymuje żądanie przed połączeniem")
    func invalidNumber() async {
        let transport = MockTransport()
        let service = KSeFAnonymousAccessService(environment: .test, transport: transport)
        var request = anonymousRequest()
        request.ksefNumber = "KSEF-1"

        await #expect(throws: AnonymousInvoiceAccessError.invalidKSeFNumber) {
            try await service.downloadInvoice(request)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("Brak tokenu CSRF i błąd HTTP są raportowane jawnie")
    func gatewayErrors() async {
        let missingToken = MockTransport()
        missingToken.routeOK("invoice/search", data: Data("<html></html>".utf8))
        let firstService = KSeFAnonymousAccessService(environment: .test, transport: missingToken)
        await #expect(throws: AnonymousInvoiceAccessError.invalidGatewayResponse) {
            try await firstService.downloadInvoice(anonymousRequest())
        }

        let badStatus = MockTransport()
        badStatus.route("invoice/search") { _ in (503, Data()) }
        let secondService = KSeFAnonymousAccessService(environment: .test, transport: badStatus)
        await #expect(throws: AnonymousInvoiceAccessError.gatewayHTTPStatus(503)) {
            try await secondService.downloadInvoice(anonymousRequest())
        }
    }

    @Test("Dekoder HTML odtwarza encje używane wewnątrz Base64")
    func htmlEntities() {
        #expect(KSeFAnonymousAccessService.decodeHTMLEntities("A&#x2B;B&#43;C&amp;D") == "A+B+C&D")
        #expect(KSeFAnonymousAccessService.amountString(Decimal(string: "-1.2")!) == "-1,20")
    }

    @Test("Znak + w polach i tokenie CSRF dociera do bramki bez zniekształcenia")
    func plusSignSurvivesFormEncoding() async throws {
        let transport = MockTransport()
        var call = 0
        transport.route("invoice/search") { _ in
            call += 1
            switch call {
            case 1, 2:
                return (200, Data(#"<input name="__RequestVerificationToken" type="hidden" value="TOK+EN/\#(call)==" />"#.utf8))
            default:
                return (200, Data(#"<div data-xml-text="\#(Data("<Faktura/>".utf8).base64EncodedString())"></div>"#.utf8))
            }
        }
        let service = KSeFAnonymousAccessService(environment: .test, transport: transport)
        var request = anonymousRequest(buyerName: "A+B Sp. j.")
        request.invoiceNumber = "FV+7/2026"

        _ = try await service.downloadInvoice(request)

        // W surowym ciele `+` musi być procentowo zakodowany — dosłowny `+`
        // serwer form-urlencoded zdekodowałby jako spację.
        let rawBody = String(data: transport.requests[2].httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(!rawBody.contains("+"))

        let details = formFields(of: transport.requests[2])
        #expect(details["InvoiceNumber"] == "FV+7/2026")
        #expect(details["BuyerName"] == "A+B Sp. j.")
        #expect(details["__RequestVerificationToken"] == "TOK+EN/2==")
    }

    @Test("Ścisłe parsowanie kwoty obsługuje grupowanie i odrzuca dwuznaczne wpisy")
    func amountParsing() {
        #expect(KSeFAnonymousAccessService.parseAmountInput("123") == Decimal(123))
        #expect(KSeFAnonymousAccessService.parseAmountInput(" 123,45 ") == Decimal(string: "123.45"))
        #expect(KSeFAnonymousAccessService.parseAmountInput("123.45") == Decimal(string: "123.45"))
        #expect(KSeFAnonymousAccessService.parseAmountInput("0,5") == Decimal(string: "0.5"))
        #expect(KSeFAnonymousAccessService.parseAmountInput("-1,20") == Decimal(string: "-1.2"))
        // Grupowanie: zwykła spacja, twarda spacja (kopiuj-wklej), kropka, przecinek.
        #expect(KSeFAnonymousAccessService.parseAmountInput("1 234,56") == Decimal(string: "1234.56"))
        #expect(KSeFAnonymousAccessService.parseAmountInput("1\u{00A0}234,56") == Decimal(string: "1234.56"))
        #expect(KSeFAnonymousAccessService.parseAmountInput("1.234,56") == Decimal(string: "1234.56"))
        #expect(KSeFAnonymousAccessService.parseAmountInput("1,234.56") == Decimal(string: "1234.56"))
        #expect(KSeFAnonymousAccessService.parseAmountInput("1.234.567,89") == Decimal(string: "1234567.89"))
        #expect(KSeFAnonymousAccessService.parseAmountInput("1.234") == Decimal(1234))
        // Dotąd Decimal(string:) obcinał takie wpisy do prefiksu — teraz odrzucane.
        #expect(KSeFAnonymousAccessService.parseAmountInput("1.23.4") == nil)
        #expect(KSeFAnonymousAccessService.parseAmountInput("123,456") == nil)
        #expect(KSeFAnonymousAccessService.parseAmountInput("1,234") == nil)
        #expect(KSeFAnonymousAccessService.parseAmountInput("123,") == nil)
        #expect(KSeFAnonymousAccessService.parseAmountInput("12a34") == nil)
        #expect(KSeFAnonymousAccessService.parseAmountInput("") == nil)
    }
}

@Suite("Anonimowy import faktury zakupowej")
@MainActor
struct AnonymousInvoiceImportEngineTests {

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Invoice.self, configurations: configuration)
        return ModelContext(container)
    }

    private func invoiceXML(number: String = "FV/7/2026") -> Data {
        let draft = InvoiceDraft(
            invoiceNumber: number,
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-14")!,
            sellerName: "Dostawca Sp. z o.o.",
            sellerNIP: "9999999999",
            sellerAddress: "ul. Testowa 1, Warszawa",
            buyerName: "Nabywca Sp. z o.o.",
            buyerNIP: "1111111111",
            buyerAddress: "ul. Zakupowa 2, Kraków",
            lines: [
                InvoiceLineDraft(
                    name: "Usługa",
                    unit: "szt.",
                    quantity: 1,
                    unitNetPrice: 100,
                    vatRate: .standard
                )
            ],
            paymentForm: .transfer
        )
        return Data(FA2XMLGenerator.generateXML(for: draft).utf8)
    }

    @Test("Pobrany XML tworzy zakup z numerem KSeF i pozycjami")
    func insertsPurchase() throws {
        let context = try makeContext()

        let result = try AnonymousInvoiceImportEngine.importInvoice(
            xmlData: invoiceXML(),
            ksefNumber: anonymousTestKSeFNumber,
            prepaidForms: [],
            context: context
        )

        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        let saved = try #require(invoices.first)
        #expect(result == .inserted)
        #expect(invoices.count == 1)
        #expect(saved.kind == .purchase)
        #expect(saved.ksefId == anonymousTestKSeFNumber)
        #expect(saved.invoiceNumber == "FV/7/2026")
        #expect(saved.lines.count == 1)
        #expect(saved.rawXmlContent?.contains("<Faktura") == true)
        #expect(saved.ksefSubmissionStatus == .accepted)
        #expect(context.hasChanges == false)
    }

    @Test("Istniejący ukryty zakup nie wraca i ręczne Opłacona nie jest cofane")
    func hiddenDuplicateStaysHiddenAndPaid() throws {
        let context = try makeContext()
        let existing = Invoice(
            ksefId: anonymousTestKSeFNumber,
            invoiceNumber: "FV/7/2026",
            issueDate: .now,
            sellerName: "Dostawca",
            sellerNIP: "9999999999",
            buyerName: "Nabywca",
            buyerNIP: "1111111111",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123,
            isPaid: true,
            isArchivedOrHidden: true,
            kind: .purchase
        )
        context.insert(existing)
        try context.save()

        let result = try AnonymousInvoiceImportEngine.importInvoice(
            xmlData: invoiceXML(),
            ksefNumber: anonymousTestKSeFNumber,
            prepaidForms: [],
            context: context
        )

        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        #expect(result == .alreadyExists)
        #expect(invoices.count == 1)
        #expect(invoices.first?.id == existing.id)
        #expect(invoices.first?.isArchivedOrHidden == true)
        #expect(invoices.first?.isPaid == true)
        #expect(invoices.first?.lines.count == 1)
    }
}
