import Foundation
import SwiftData
import SwiftUI
import AppKit
import Testing
@testable import KsefiarzCore

// Testy domykające pokrycie rzadkich gałęzi generatorów XML/PDF/JPK oraz
// drobnych luk w modelach. Nazwy i komentarze po polsku. Wszystko czyste
// (bez sieci): ModelContext w pamięci, generatory PDF/XML bez zależności.

// MARK: - Pomocnicze (unikalne nazwy z sufiksem _render)

/// Świeży kontekst SwiftData w pamięci (bez zapisu na dysk).
private func makeMemoryContext_render() throws -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Invoice.self, configurations: configuration)
    return ModelContext(container)
}

/// Data z łańcucha "yyyy-MM-dd".
private func day_render(_ string: String) -> Date {
    FA2Format.dateFormatter.date(from: string)!
}

// MARK: - Luki modelu i szkicu ręcznego zakupu

@Suite("Luki modelu — korekta w applyDetails i ręczne zakupy")
struct ModelGapsTests {

    @Test("applyDetails z dokumentem KOR uzupełnia dane faktury korygowanej")
    func applyDetailsUzupelniaKorekte() throws {
        let context = try makeMemoryContext_render()
        let invoice = makeTestInvoice(number: "KOR/1", kind: .sales)
        context.insert(invoice)

        let originalDate = day_render("2026-05-10")
        let data = FA2InvoiceData(
            invoiceNumber: "KOR/1",
            issueDate: day_render("2026-06-01"),
            sellerName: "Sprzedawca",
            sellerNIP: "5260250274",
            buyerName: "Nabywca",
            buyerNIP: "1111111111",
            netAmount: -50,
            vatAmount: -11.5,
            grossAmount: -61.5,
            documentType: "KOR",
            correction: InvoiceCorrectionInfo(
                originalNumber: "FV/PIERWOTNA",
                originalIssueDate: originalDate,
                originalKsefNumber: "KSEF-ORIG",
                reason: "Błędna cena jednostkowa"
            ),
            rawXML: "<Faktura>KOR</Faktura>"
        )

        invoice.applyDetails(from: data)

        #expect(invoice.documentTypeRaw == "KOR")
        #expect(invoice.isCorrection)
        #expect(invoice.correctionReason == "Błędna cena jednostkowa")
        #expect(invoice.correctedInvoiceNumber == "FV/PIERWOTNA")
        #expect(invoice.correctedInvoiceKsefId == "KSEF-ORIG")
        #expect(invoice.correctedInvoiceIssueDate == originalDate)
    }

    @Test("apply(to:) ustawia opłacenie i datę zapłaty (nadrzędność znacznika isPaid)")
    func applyUstawiaOplacenie() {
        // Wariant bez podanej daty zapłaty — używa daty wystawienia.
        let invoiceA = makeTestInvoice(number: "ZAKUP/RECZNY/A", kind: .purchase)
        var draftA = ManualPurchaseDraft(from: invoiceA)
        draftA.isPaid = true
        draftA.paymentDate = nil
        draftA.issueDate = day_render("2026-06-20")
        draftA.apply(to: invoiceA)
        #expect(invoiceA.isPaid)
        #expect(invoiceA.paymentDate == day_render("2026-06-20"))

        // Wariant z jawną datą zapłaty — używa jej.
        let invoiceB = makeTestInvoice(number: "ZAKUP/RECZNY/B", kind: .purchase)
        var draftB = ManualPurchaseDraft(from: invoiceB)
        draftB.isPaid = true
        draftB.issueDate = day_render("2026-06-20")
        draftB.paymentDate = day_render("2026-06-25")
        draftB.apply(to: invoiceB)
        #expect(invoiceB.isPaid)
        #expect(invoiceB.paymentDate == day_render("2026-06-25"))
    }

    @Test("Opisy statusów wysyłki, terminów offline oraz settery advanceInvoiceRefs/kind")
    func opisyISettery() {
        // displayName wszystkich statusów wysyłki.
        for status in KSeFSubmissionStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
        // displayName i deadlineDescription wszystkich powodów trybu offline.
        for reason in Invoice.OfflineReason.allCases {
            #expect(!reason.displayName.isEmpty)
            #expect(!reason.deadlineDescription.isEmpty)
        }
        // Settery pól przechowywanych jako łańcuch/RawValue.
        let invoice = makeTestInvoice(kind: .purchase)
        invoice.advanceInvoiceRefs = ["KSEF-A", "KSEF-B"]
        #expect(invoice.advanceInvoiceRefsRaw == "KSEF-A\nKSEF-B")
        #expect(invoice.advanceInvoiceRefs == ["KSEF-A", "KSEF-B"])
        invoice.kind = .sales
        #expect(invoice.kindRaw == Invoice.Kind.sales.rawValue)
        #expect(invoice.kind == .sales)
    }

    @Test("Opisy błędów walidacji ręcznego zakupu są niepuste dla każdego przypadku")
    func opisyBledowWalidacji() {
        let errors: [ManualPurchaseValidationError] = [
            .emptyDocumentNumber, .emptySellerName, .zeroAmount, .missingExchangeRate,
        ]
        for error in errors {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }
}

// MARK: - Luki generatora JPK_V7M

@Suite("Luki JPK_V7M — pusty koszyk, nieznana stawka i waluta bez kursu")
struct JPKGapsTests {

    @Test("SalesBuckets.isEmpty rozpoznaje pusty i niepusty koszyk")
    func salesBucketsIsEmpty() {
        var buckets = JPKV7Generator.SalesBuckets()
        #expect(buckets.isEmpty)
        buckets.k19 = 100
        #expect(!buckets.isEmpty)
        buckets.k19 = 0
        buckets.k20 = 23
        #expect(!buckets.isEmpty)
    }

    @Test("JPK: waluta obca bez kursu i nieznana stawka VAT — kwoty nominalne, K_19/K_20")
    func jpkWalutaBezKursuINieznanaStawka() {
        let invoice = Invoice(
            invoiceNumber: "FV/EUR/17",
            issueDate: day_render("2026-06-10"),
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            netAmount: 100,
            vatAmount: 17,
            grossAmount: 117,
            currency: "EUR",
            exchangeRate: 0,
            kind: .sales
        )
        // Stawka „17" nie jest znana schemie → gałąź `case nil` (podstawowa).
        invoice.lines = [
            InvoiceLine(index: 1, name: "Usługa", netAmount: 100, vatRate: "17", vatAmount: 17),
        ]
        let options = JPKV7Options(
            year: 2026, month: 6,
            sellerNIP: "5260250274", sellerName: "ACME Sp. z o.o.",
            email: "biuro@acme.pl", taxOfficeCode: "1219"
        )

        let result = JPKV7Generator.generate(invoices: [invoice], options: options)

        #expect(result.salesCount == 1)
        // Nieznana stawka „17" → wykazana jako podstawowa (K_19/K_20) + ostrzeżenie.
        #expect(result.warnings.contains { $0.contains("nieznana stawka") })
        #expect(result.xml.contains("<K_19>100.00</K_19>"))
        #expect(result.xml.contains("<K_20>17.00</K_20>"))
        // Waluta EUR bez kursu → kwoty przyjęte nominalnie (ostrzeżenie, bez duplikatu).
        let currencyWarnings = result.warnings.filter { $0.contains("bez kursu") }
        #expect(currencyWarnings.count == 1)
    }

    @Test("JPK: procedura marży dodaje SprzedazVAT_Marza, znacznik MR_T i ostrzeżenie")
    func jpkProceduraMarzy() {
        let invoice = Invoice(
            invoiceNumber: "FV/MARZA/1",
            issueDate: day_render("2026-06-05"),
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            marginProcedure: "2",
            kind: .sales
        )
        invoice.lines = [
            InvoiceLine(index: 1, name: "Wycieczka", netAmount: 100, vatRate: "23", vatAmount: 23),
        ]
        let options = JPKV7Options(
            year: 2026, month: 6,
            sellerNIP: "5260250274", sellerName: "ACME Sp. z o.o.",
            email: "biuro@acme.pl", taxOfficeCode: "1219"
        )

        let result = JPKV7Generator.generate(invoices: [invoice], options: options)

        #expect(result.xml.contains("<SprzedazVAT_Marza>123.00</SprzedazVAT_Marza>"))
        #expect(result.xml.contains("<MR_T>1</MR_T>"))
        #expect(result.warnings.contains { $0.contains("procedura marży") })
    }
}

// MARK: - Luki generatora i parsera FA(3)

@Suite("Luki FA(3) — sumy stawek 5%/zw. oraz błędy parsera")
struct FA2GapsTests {

    @Test("XML FA(3): sumy dla stawki 5% (P_13_3) i zwolnionej (P_13_7)")
    func xmlSumyDlaStawek5iZw() {
        let draft = InvoiceDraft(
            invoiceNumber: "FV/RATES/1",
            issueDate: day_render("2026-06-01"),
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Testowa 1, 00-001 Warszawa",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            lines: [
                InvoiceLineDraft(name: "Towar 5%", quantity: 1, unitNetPrice: 200, vatRate: .reducedSecond),
                InvoiceLineDraft(name: "Usługa zwolniona", quantity: 1, unitNetPrice: 300, vatRate: .exempt),
            ]
        )

        let xml = FA2XMLGenerator.generateXML(for: draft)

        #expect(xml.contains("<P_13_3>200.00</P_13_3>"))
        #expect(xml.contains("<P_14_3>10.00</P_14_3>"))
        #expect(xml.contains("<P_13_7>300.00</P_13_7>"))
    }

    /// Sprawdza, że parser rzuca `xmlParsingFailed` z komunikatem zawierającym `fragment`.
    private func expectParsingError(_ xml: String, contains fragment: String) {
        do {
            _ = try FA2XMLParser.parse(xml: xml)
            Issue.record("Parser powinien odrzucić dokument: \(fragment)")
        } catch let KSeFError.xmlParsingFailed(message) {
            #expect(message.contains(fragment), "Komunikat „\(message)” nie zawiera „\(fragment)”")
        } catch {
            Issue.record("Nieoczekiwany błąd: \(error)")
        }
    }

    @Test("Parser odrzuca dokument bez elementu Podmiot1")
    func parserBrakPodmiot1() {
        expectParsingError("<Faktura></Faktura>", contains: "Podmiot1")
    }

    @Test("Parser odrzuca dokument bez elementu Podmiot2")
    func parserBrakPodmiot2() {
        expectParsingError("<Faktura><Podmiot1/></Faktura>", contains: "Podmiot2")
    }

    @Test("Parser odrzuca dokument bez elementu Fa")
    func parserBrakFa() {
        expectParsingError("<Faktura><Podmiot1/><Podmiot2/></Faktura>", contains: "<Fa>")
    }

    @Test("Parser odrzuca fakturę z nieprawidłową datą wystawienia (P_1)")
    func parserZlaDataWystawienia() {
        let xml = """
        <Faktura><Podmiot1/><Podmiot2/><Fa>\
        <P_2>FV/1</P_2><P_1>NIEDATA</P_1><P_15>123.00</P_15>\
        </Fa></Faktura>
        """
        expectParsingError(xml, contains: "P_1")
    }

    @Test("Parser odrzuca fakturę z nieprawidłową kwotą brutto (P_15)")
    func parserZlaKwotaBrutto() {
        let xml = """
        <Faktura><Podmiot1/><Podmiot2/><Fa>\
        <P_2>FV/1</P_2><P_1>2026-06-01</P_1><P_15>abc</P_15>\
        </Fa></Faktura>
        """
        expectParsingError(xml, contains: "P_15")
    }

    @Test("Parser wylicza sumy netto/VAT z pozycji, gdy brak pól P_13/P_14")
    func parserSumyZPozycji() throws {
        let xml = """
        <Faktura>
          <Podmiot1><DaneIdentyfikacyjne><NIP>5260250274</NIP><Nazwa>ACME</Nazwa></DaneIdentyfikacyjne></Podmiot1>
          <Podmiot2><DaneIdentyfikacyjne><NIP>1111111111</NIP><Nazwa>Kontrahent</Nazwa></DaneIdentyfikacyjne></Podmiot2>
          <Fa>
            <P_1>2026-06-01</P_1>
            <P_2>FV/1</P_2>
            <P_15>123.00</P_15>
            <FaWiersz>
              <NrWierszaFa>1</NrWierszaFa>
              <P_7>Usługa</P_7>
              <P_11>100.00</P_11>
              <P_12>23</P_12>
            </FaWiersz>
          </Fa>
        </Faktura>
        """
        let data = try FA2XMLParser.parse(xml: xml)
        #expect(data.lines.count == 1)
        // Brak P_13_x/P_14_x → sumy policzone z pozycji.
        #expect(abs(data.netAmount - 100) < 0.001)
        #expect(abs(data.vatAmount - 23) < 0.001)
    }
}

// MARK: - Luki paczki księgowej i wydruków PDF (główny wątek)

@Suite("Luki wydruków PDF i paczki księgowej — warianty rysowania")
@MainActor
struct RenderingGapsTests {

    /// Faktura sprzedażowa z pozycjami o zadanej liczbie wierszy.
    private func makeLinedInvoice(count: Int) -> Invoice {
        let invoice = Invoice(
            invoiceNumber: "FV/WIELO/\(count)",
            issueDate: day_render("2026-06-01"),
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Testowa 1, 00-001 Warszawa",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            buyerAddress: "ul. Odbiorcza 5, 30-001 Kraków",
            netAmount: Double(count) * 100,
            vatAmount: Double(count) * 23,
            grossAmount: Double(count) * 123,
            kind: .sales
        )
        invoice.lines = (1...count).map {
            InvoiceLine(index: $0, name: "Pozycja \($0)", quantity: 1,
                        unitNetPrice: 100, netAmount: 100, vatRate: "23", vatAmount: 23)
        }
        return invoice
    }

    /// Rysuje stronę wydruku do kontekstu PDF (jak `InvoicePDFGenerator`),
    /// aby wykonać całą ścieżkę rysowania body widoku.
    private func renderPage(_ view: InvoicePrintPageView) {
        let content = view
            .frame(width: 515)
            .padding(40)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { return }
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 595, height: nil)
        renderer.render { _, render in
            context.beginPDFPage(nil)
            render(context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    @Test("PDF: faktura z pełnym podsumowaniem — uwagi, płatność, termin, opłacona")
    func pdfPelnePodsumowanie() throws {
        let invoice = Invoice(
            invoiceNumber: "FV/SUM/1",
            issueDate: day_render("2026-06-01"),
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Testowa 1",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            buyerAddress: "ul. Odbiorcza 5",
            netAmount: 100,
            vatAmount: 23,
            grossAmount: 123,
            isPaid: true,
            paymentDueDate: day_render("2026-06-15"),
            paymentForm: .transfer,
            paymentBankAccount: "11222233334444555566667777",
            notes: "Dziękujemy za współpracę.",
            kind: .sales
        )
        invoice.lines = [
            InvoiceLine(index: 1, name: "Usługa", netAmount: 100, vatRate: "23", vatAmount: 23),
        ]

        let pdf = try #require(InvoicePDFGenerator.pdfData(for: invoice))
        #expect(pdf.prefix(5) == Data("%PDF-".utf8))
    }

    @Test("PDF: długa faktura na wielu stronach — nagłówek kontynuacji i numeracja")
    func pdfWieleStron() throws {
        let invoice = makeLinedInvoice(count: 15)

        // Wariant polski.
        let pdfPL = try #require(InvoicePDFGenerator.pdfData(for: invoice, bilingual: false))
        #expect(pdfPL.prefix(5) == Data("%PDF-".utf8))

        // Wariant dwujęzyczny (inna gałąź numeracji stron).
        let pdfEN = try #require(InvoicePDFGenerator.pdfData(for: invoice, bilingual: true))
        #expect(pdfEN.prefix(5) == Data("%PDF-".utf8))
    }

    @Test("PDF: sekcja kodów QR z ostrzeżeniem o braku certyfikatu (KOD II) oraz z certyfikatem")
    func pdfSekcjaKodowQR() throws {
        let invoice = Invoice(
            invoiceNumber: "FV/QR/RENDER",
            issueDate: day_render("2026-06-01"),
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            kind: .sales
        )
        let qrImage = try #require(QRCodeRenderer.image(for: "https://przyklad.test/qr"))

        // Dokument offline bez certyfikatu typu 2 → renderowany komunikat (KOD II brak).
        // Pominięcie argumentu `labels` uruchamia domyślną wartość etykiet.
        let pageWithNote = InvoicePrintPageView(
            invoice: invoice, lines: [],
            isFirstPage: true, isLastPage: true,
            pageNumber: 1, pageCount: 1,
            qrCodes: InvoicePDFGenerator.InvoiceQRCodes(
                verification: qrImage,
                verificationLabel: "OFFLINE",
                certificate: nil,
                certificateNote: "Brak certyfikatu offline (typ 2) — dokument offline wymaga KODU II.",
                payment: nil
            )
        )
        renderPage(pageWithNote)

        // Dokument offline z certyfikatem typu 2 → renderowany KOD II „CERTYFIKAT".
        let pageWithCert = InvoicePrintPageView(
            invoice: invoice, lines: [],
            isFirstPage: true, isLastPage: true,
            pageNumber: 1, pageCount: 1,
            qrCodes: InvoicePDFGenerator.InvoiceQRCodes(
                verification: qrImage,
                verificationLabel: "OFFLINE",
                certificate: qrImage,
                certificateNote: nil,
                payment: qrImage
            ),
            labels: InvoicePDFLabels(bilingual: true)
        )
        renderPage(pageWithCert)
    }

    @Test("documentIssues: dokument offline24 czeka na dosłanie do KSeF")
    func documentIssuesOffline24() {
        let invoice = makeTestInvoice(number: "FV/OFF/1", kind: .sales)
        invoice.rawXmlContent = "<Faktura/>"
        invoice.ksefSubmissionStatus = .offlinePending

        let issues = AccountingPackageBuilder.documentIssues(for: invoice)

        #expect(issues.contains("offline24 — oczekuje na dosłanie do KSeF"))
    }

    @Test("documentIssues: dokument w trakcie przetwarzania przez KSeF")
    func documentIssuesProcessing() {
        let invoice = makeTestInvoice(number: "FV/PROC/1", kind: .sales)
        invoice.rawXmlContent = "<Faktura/>"
        invoice.ksefSubmissionStatus = .processing

        let issues = AccountingPackageBuilder.documentIssues(for: invoice)

        #expect(issues.contains("w trakcie przetwarzania przez KSeF (brak numeru KSeF)"))
    }

    @Test("makeQRCodes zwraca nil dla dokumentu offline bez skrótu i bez XML")
    func makeQRCodesOfflineBezSkrotu() {
        let invoice = Invoice(
            invoiceNumber: "FV/OFF/NOHASH",
            issueDate: day_render("2026-06-01"),
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            kind: .sales
        )
        invoice.isOfflineMode = true
        invoice.offlineHashBase64 = ""
        invoice.rawXmlContent = nil

        let codes = InvoicePDFGenerator.makeQRCodes(for: invoice, offlineCertificate: nil)

        #expect(codes == nil)
    }

    @Test("PDF noty odsetkowej — wiele stron, adres dłużnika i wstęp noty")
    func pdfNotaOdsetkowa() throws {
        let due = day_render("2026-01-10")
        let issue = day_render("2026-01-01")
        // 17 pozycji → dokument dzieli się na dwie strony (numeracja > 1).
        let items = (1...17).map { i in
            PaymentDemandItem(
                invoiceNumber: "FV/\(i)",
                issueDate: issue,
                dueDate: due,
                outstanding: 100,
                daysOverdue: 30,
                interest: 5,
                currency: "PLN"
            )
        }
        let document = PaymentDemandDocument(
            kind: .interestNote,
            number: "NO/1/2026",
            sellerName: "ACME Sp. z o.o.",
            sellerAddress: "ul. Testowa 1, Kraków",
            sellerNIP: "5260250274",
            bankAccount: "11222233334444555566667777",
            buyerName: "Dłużnik Sp. z o.o.",
            buyerNIP: "1111111111",
            buyerAddress: "ul. Dłużna 5, Warszawa",
            items: items,
            annualRatePercent: 11.25,
            paymentDays: 7
        )

        let pdf = try #require(PaymentDemandPDFGenerator.pdfData(for: document))
        #expect(pdf.prefix(5) == Data("%PDF-".utf8))
        #expect(pdf.count > 1000)
    }
}
