import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Pobieranie danych kontrahenta (Biała lista)

@Suite("Wykaz podatników VAT — pobieranie danych po NIP")
struct ContractorLookupTests {

    private static let subjectJSON = Data("""
    {"result":{"subject":{
        "name":"PRZYKŁADOWA FIRMA SPÓŁKA AKCYJNA",
        "nip":"9999999999",
        "statusVat":"Czynny",
        "workingAddress":"UL. PRZYKŁADOWA 50, 31-523 KRAKÓW",
        "residenceAddress":null
    },"requestDateTime":"2026-06-12","requestId":"aa111-22b333"}}
    """.utf8)

    @Test("Pobiera nazwę, adres i status VAT z wykazu")
    func pobieranieDanych() async throws {
        let transport = MockTransport()
        transport.routeOK("/api/search/nip/9999999999", data: Self.subjectJSON)
        let service = ContractorLookupService(transport: transport)

        let result = try await service.lookup(nip: "999-999-99-99")

        #expect(result.name == "PRZYKŁADOWA FIRMA SPÓŁKA AKCYJNA")
        #expect(result.nip == "9999999999")
        #expect(result.street == "UL. PRZYKŁADOWA")
        #expect(result.houseNumber == "50")
        #expect(result.postalCode == "31-523")
        #expect(result.city == "KRAKÓW")
        #expect(result.vatStatus == "Czynny")
        // Zapytanie musi zawierać datę (wymóg API wykazu).
        let url = transport.request(matching: "/api/search/nip")?.url?.absoluteString ?? ""
        #expect(url.contains("date="))
    }

    @Test("Nieprawidłowy NIP jest odrzucany przed zapytaniem sieciowym")
    func walidacjaNIP() async {
        let transport = MockTransport()
        let service = ContractorLookupService(transport: transport)
        await #expect(throws: ContractorLookupService.LookupError.invalidNIP) {
            _ = try await service.lookup(nip: "1234567890")
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("Brak podmiotu w wykazie zgłasza zrozumiały błąd")
    func brakPodmiotu() async {
        let transport = MockTransport()
        transport.routeOK("/api/search/nip", data: Data(#"{"result":{"subject":null}}"#.utf8))
        let service = ContractorLookupService(transport: transport)
        await #expect(throws: ContractorLookupService.LookupError.notFound) {
            _ = try await service.lookup(nip: "9999999999")
        }
    }

    @Test("Parsowanie adresu: ulica z numerem domu i lokalu")
    func parsowanieAdresu() {
        let parsed = ContractorLookupService.parseAddress("UL. KWIATOWA 12A/3, 00-950 WARSZAWA")
        #expect(parsed.street == "UL. KWIATOWA")
        #expect(parsed.houseNumber == "12A")
        #expect(parsed.apartmentNumber == "3")
        #expect(parsed.postalCode == "00-950")
        #expect(parsed.city == "WARSZAWA")
    }

    @Test("Parsowanie adresu: bez przecinka całość trafia do ulicy")
    func parsowanieAdresuBezPrzecinka() {
        let parsed = ContractorLookupService.parseAddress("FACIMIECH 12")
        #expect(parsed.street == "FACIMIECH")
        #expect(parsed.houseNumber == "12")
        #expect(parsed.postalCode.isEmpty)
        #expect(parsed.city.isEmpty)
    }

    @Test("Weryfikacja rachunku przez endpoint check (obsługuje rachunki wirtualne)")
    func weryfikacjaRachunku() async throws {
        let transport = MockTransport()
        transport.route("/api/check/nip/9999999999/bank-account/") { request in
            // Endpoint check dostaje numer znormalizowany do 26 cyfr —
            // bez spacji i bez prefiksu IBAN "PL".
            let path = request.url?.path ?? ""
            let assigned = path.hasSuffix("/26109024020000000612345678") ? "TAK" : "NIE"
            return (200, Data(#"{"result":{"accountAssigned":"\#(assigned)"}}"#.utf8))
        }
        let service = ContractorLookupService(transport: transport)

        // Format z fakturą bywa różny: spacje, IBAN z "PL" — normalizujemy.
        let onList = try await service.verifyAccount(
            nip: "9999999999", account: "PL26 1090 2402 0000 0006 1234 5678"
        )
        #expect(onList)

        let notOnList = try await service.verifyAccount(
            nip: "9999999999", account: "00 0000 0000 0000 0000 0000 0000"
        )
        #expect(!notOnList)
    }

    @Test("Parsowanie adresu: miejscowość wieloczłonowa")
    func parsowanieAdresuMiastoWieloczlonowe() {
        let parsed = ContractorLookupService.parseAddress("RYNEK 1, 34-300 ŻYWIEC ZABŁOCIE")
        #expect(parsed.street == "RYNEK")
        #expect(parsed.houseNumber == "1")
        #expect(parsed.postalCode == "34-300")
        #expect(parsed.city == "ŻYWIEC ZABŁOCIE")
    }
}

// MARK: - Podstawianie danych słowników

@Suite("Słowniki — podstawianie danych do faktury")
struct DictionaryPrefillTests {

    @Test("Towar ze słownika wypełnia pozycję, ale nie blokuje edycji")
    func podstawienieTowaru() {
        let product = Product()
        product.name = "Konsultacje IT"
        product.unit = "godz."
        product.basePriceNet = 250
        product.basePriceVatRate = .standard
        product.cnPkwiu = "62.02.10.0"
        product.gtu = "GTU_12"

        var line = InvoiceLineDraft()
        line.quantity = 5
        line.apply(product: product)

        #expect(line.name == "Konsultacje IT")
        #expect(line.unit == "godz.")
        #expect(line.unitNetPrice == 250)
        #expect(line.vatRate == .standard)
        #expect(line.cnPkwiu == "62.02.10.0")
        #expect(line.gtu == "GTU_12")
        // Ilość nie jest częścią słownika — pozostaje bez zmian.
        #expect(line.quantity == 5)

        // Po podstawieniu pola pozostają zwykłymi polami szkicu — edycja działa.
        line.unitNetPrice = 300
        line.vatRate = .reducedFirst
        #expect(line.unitNetPrice == 300)
    }

    @Test("Adres kontrahenta składany do formatu z faktury")
    func adresKontrahenta() {
        let contractor = Contractor()
        contractor.street = "ul. Moniuszki"
        contractor.houseNumber = "50"
        contractor.apartmentNumber = "3"
        contractor.postalCode = "31-523"
        contractor.city = "Kraków"
        #expect(contractor.invoiceAddress == "ul. Moniuszki 50/3, 31-523 Kraków")

        let bare = Contractor()
        bare.city = "Kraków"
        bare.postalCode = "31-523"
        #expect(bare.invoiceAddress == "31-523 Kraków")
    }

    @Test("Ceny brutto produktu wyliczane ze stawki VAT")
    func cenyBrutto() {
        let product = Product()
        product.basePriceNet = 100
        product.basePriceVatRate = .standard
        #expect(product.basePriceGross == 123)
        product.purchasePriceNet = 81.30
        product.purchasePriceVatRate = .reducedFirst
        #expect(product.purchasePriceGross == 87.80)
    }
}

// MARK: - Kopia zapasowa wersji 2

@Suite("Kopia zapasowa — słowniki i nowe pola (wersja 2)")
struct BackupV2Tests {

    @Test("Słowniki przechodzą przez eksport i import bez strat")
    func slownikiRoundTrip() throws {
        let contractor = Contractor()
        contractor.name = "Testowy Nabywca"
        contractor.nip = "9999999999"
        contractor.city = "Kraków"

        let product = Product()
        product.name = "Usługa testowa"
        product.cnPkwiu = "62.01.11.0"

        let account = BankAccount()
        account.label = "Firmowy"
        account.accountNumber = "26109024020000000612345678"

        let data = try BackupService.makeBackup(
            invoices: [],
            settings: [:],
            contractors: [contractor],
            products: [product],
            bankAccounts: [account]
        )
        let decoded = try BackupService.decode(data)

        #expect(decoded.version == BackupService.currentVersion)
        #expect(decoded.contractors?.first?.name == "Testowy Nabywca")
        #expect(decoded.products?.first?.cnPkwiu == "62.01.11.0")
        #expect(decoded.bankAccounts?.first?.accountNumber == "26109024020000000612345678")

        // Import pomija duplikaty po NIP/nazwie/numerze rachunku.
        #expect(BackupService.contractorsToImport(from: decoded, existing: [contractor]).isEmpty)
        #expect(BackupService.productsToImport(from: decoded, existing: [product]).isEmpty)
        #expect(BackupService.bankAccountsToImport(from: decoded, existing: [account]).isEmpty)
        #expect(BackupService.contractorsToImport(from: decoded, existing: []).count == 1)
    }

    @Test("Uwagi i CN/PKWiU faktury przechodzą przez kopię zapasową")
    func uwagiICnPkwiuRoundTrip() throws {
        let invoice = Invoice(
            invoiceNumber: "FV/1/2026",
            issueDate: .now,
            sellerName: "S", sellerNIP: "9999999999",
            buyerName: "B", buyerNIP: "1111111111",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            notes: "Mechanizm podzielonej płatności",
            kind: .sales
        )
        invoice.lines = [InvoiceLine(index: 1, name: "X", cnPkwiu: "62.01.11.0", gtu: "GTU_12")]

        let data = try BackupService.makeBackup(invoices: [invoice], settings: [:])
        let decoded = try BackupService.decode(data)

        #expect(decoded.invoices.first?.notes == "Mechanizm podzielonej płatności")
        #expect(decoded.invoices.first?.lines.first?.cnPkwiu == "62.01.11.0")
        let rebuilt = BackupService.makeInvoice(from: try #require(decoded.invoices.first))
        #expect(rebuilt.notes == "Mechanizm podzielonej płatności")
        let lines = BackupService.makeLines(for: try #require(decoded.invoices.first))
        #expect(lines.first?.gtu == "GTU_12")
    }

    @Test("Kopia w starym formacie (wersja 1, bez słowników) dalej się importuje")
    func zgodnoscWstecz() throws {
        let v1JSON = Data("""
        {"version":1,"exportedAt":"2026-06-01T10:00:00Z","settings":{},
         "invoices":[{"id":"\(UUID().uuidString)","invoiceNumber":"FV/9/2026",
         "issueDate":"2026-06-01T10:00:00Z","sellerName":"S","sellerNIP":"9999999999",
         "sellerAddress":"","buyerName":"B","buyerNIP":"1111111111","buyerAddress":"",
         "netAmount":10,"vatAmount":2.3,"grossAmount":12.3,"isPaid":false,
         "isArchivedOrHidden":false,"documentTypeRaw":"VAT","kindRaw":"sprzedaz",
         "lines":[{"index":1,"name":"X","unit":"szt.","quantity":1,
         "unitNetPrice":10,"netAmount":10,"vatRate":"23","vatAmount":2.3}]}]}
        """.utf8)

        let decoded = try BackupService.decode(v1JSON)
        #expect(decoded.version == 1)
        #expect(decoded.contractors == nil)
        let invoice = BackupService.makeInvoice(from: try #require(decoded.invoices.first))
        #expect(invoice.notes.isEmpty)
        let lines = BackupService.makeLines(for: try #require(decoded.invoices.first))
        #expect(lines.first?.cnPkwiu == "")
    }
}
