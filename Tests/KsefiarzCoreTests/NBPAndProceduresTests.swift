import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Kursy NBP

@Suite("NBP — pobieranie kursów średnich")
struct NBPExchangeRateTests {

    private static let ratesJSON = Data("""
    {"table":"A","currency":"euro","code":"EUR","rates":[
      {"no":"110/A/NBP/2026","effectiveDate":"2026-06-09","mid":4.2311},
      {"no":"112/A/NBP/2026","effectiveDate":"2026-06-11","mid":4.2484}
    ]}
    """.utf8)

    @Test("Zwraca najnowszy kurs z zakresu (ostatni dzień roboczy)")
    func najnowszyKursZZakresu() async throws {
        let transport = MockTransport()
        transport.routeOK("/api/exchangerates/rates/a/eur/", data: Self.ratesJSON)
        let service = NBPExchangeRateService(transport: transport)

        let rate = try await service.midRate(
            currency: "EUR",
            onOrBefore: FA2Format.dateFormatter.date(from: "2026-06-11")!
        )

        #expect(rate.mid == 4.2484)
        #expect(rate.effectiveDate == "2026-06-11")
        #expect(rate.tableNumber == "112/A/NBP/2026")
        // Zapytanie obejmuje zakres dat (10 dni wstecz) i format JSON.
        let url = transport.requests.first?.url?.absoluteString ?? ""
        #expect(url.contains("/2026-06-01/2026-06-11/"))
        #expect(url.contains("format=json"))
    }

    @Test("Nieznana waluta (404) zgłasza zrozumiały błąd")
    func nieznanaWaluta() async {
        let transport = MockTransport()
        transport.route("/api/exchangerates/rates/a/xyz/") { _ in (404, Data()) }
        let service = NBPExchangeRateService(transport: transport)
        await #expect(throws: NBPExchangeRateService.RateError.unsupportedCurrency("XYZ")) {
            _ = try await service.midRate(currency: "XYZ", onOrBefore: .now)
        }
    }

    @Test("PLN nie wymaga zapytania — kurs 1")
    func plnBezZapytania() async throws {
        let transport = MockTransport()
        let service = NBPExchangeRateService(transport: transport)
        let rate = try await service.midRate(currency: "PLN", onOrBefore: .now)
        #expect(rate.mid == 1)
        #expect(transport.requests.isEmpty)
    }
}

// MARK: - Korekty zaliczek, marża, procedury

@Suite("FA(3) — korekty zaliczek, marża i procedury")
struct AdvancedDocumentTypesTests {

    private func makeDraft(lines: Bool = true) -> InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: "FV/9/2026",
            issueDate: FA2Format.dateFormatter.date(from: "2026-06-12")!,
            sellerName: "S", sellerNIP: "9999999999",
            sellerAddress: "Adres 1",
            buyerName: "N", buyerNIP: "1111111111",
            lines: lines ? [InvoiceLineDraft(name: "Pozycja", quantity: 1, unitNetPrice: 100)] : []
        )
    }

    @Test("Korekta zaliczkowej daje KOR_ZAL, rozliczeniowej KOR_ROZ, zwykłej KOR")
    func mapowanieKorektZaliczek() {
        let correction = InvoiceCorrectionInfo(originalNumber: "FV/1/2026", originalIssueDate: .now)
        var draft = makeDraft()
        draft.correction = correction

        draft.invoiceType = "VAT"
        #expect(draft.documentType == "KOR")
        draft.invoiceType = "ZAL"
        #expect(draft.documentType == "KOR_ZAL")
        draft.invoiceType = "ROZ"
        #expect(draft.documentType == "KOR_ROZ")

        let xml = FA2XMLGenerator.generateXML(for: draft)
        #expect(xml.contains("<RodzajFaktury>KOR_ROZ</RodzajFaktury>"))
    }

    @Test("Typ bazowy dokumentu: KOR_ZAL→ZAL, KOR_ROZ→ROZ, KOR→VAT")
    func typBazowy() {
        #expect(InvoiceDraft.baseType(for: "KOR") == "VAT")
        #expect(InvoiceDraft.baseType(for: "KOR_ZAL") == "ZAL")
        #expect(InvoiceDraft.baseType(for: "KOR_ROZ") == "ROZ")
        #expect(InvoiceDraft.baseType(for: "UPR") == "UPR")
    }

    @Test("Faktura uproszczona (UPR) ma właściwy RodzajFaktury")
    func fakturaUproszczona() {
        var draft = makeDraft()
        draft.invoiceType = "UPR"
        #expect(FA2XMLGenerator.generateXML(for: draft).contains("<RodzajFaktury>UPR</RodzajFaktury>"))
    }

    @Test("Procedura marży generuje P_PMarzy ze znacznikiem; brak — P_PMarzyN")
    func proceduraMarzy() {
        var draft = makeDraft()
        draft.marginProcedure = "3_1"

        let xml = FA2XMLGenerator.generateXML(for: draft)
        #expect(xml.contains("<P_PMarzy>1</P_PMarzy>"))
        #expect(xml.contains("<P_PMarzy_3_1>1</P_PMarzy_3_1>"))
        #expect(!xml.contains("<P_PMarzyN>"))

        let bare = FA2XMLGenerator.generateXML(for: makeDraft())
        #expect(bare.contains("<P_PMarzyN>1</P_PMarzyN>"))
        #expect(!bare.contains("<P_PMarzy>1</P_PMarzy>"))
    }

    @Test("Filtr rodzaju dokumentu: korekty obejmują KOR, KOR_ZAL i KOR_ROZ")
    func filtrRodzajuDokumentu() {
        #expect(DocumentTypeFilter.all.matches("VAT"))
        #expect(DocumentTypeFilter.vat.matches("VAT"))
        #expect(!DocumentTypeFilter.vat.matches("ZAL"))
        #expect(DocumentTypeFilter.zal.matches("ZAL"))
        #expect(DocumentTypeFilter.upr.matches("UPR"))
        #expect(DocumentTypeFilter.corrections.matches("KOR"))
        #expect(DocumentTypeFilter.corrections.matches("KOR_ZAL"))
        #expect(DocumentTypeFilter.corrections.matches("KOR_ROZ"))
        #expect(!DocumentTypeFilter.corrections.matches("VAT"))
    }

    @Test("Numeracja per rodzaj: wzorce tworzą niezależne serie")
    func numeracjaPerRodzaj() {
        let existing = ["FV/01/06/2026", "FV/02/06/2026", "ZAL/01/06/2026"]
        let date = FA2Format.dateFormatter.date(from: "2026-06-12")!
        // Seria VAT liczy tylko numery pasujące do wzorca VAT…
        let nextVAT = InvoiceNumberGenerator.nextNumber(
            pattern: "FV/{NN}/{MM}/{RRRR}", existing: existing, date: date
        )
        #expect(nextVAT == "FV/03/06/2026")
        // …a seria ZAL rośnie niezależnie.
        let nextZAL = InvoiceNumberGenerator.nextNumber(
            pattern: "ZAL/{NN}/{MM}/{RRRR}", existing: existing, date: date
        )
        #expect(nextZAL == "ZAL/02/06/2026")
    }

    @Test("Oznaczenie procedury pozycji trafia do elementu Procedura po GTU")
    func proceduraPozycji() throws {
        var draft = makeDraft()
        draft.lines[0].gtu = "GTU_12"
        draft.lines[0].procedure = "WSTO_EE"

        let xml = FA2XMLGenerator.generateXML(for: draft)
        #expect(xml.contains("<Procedura>WSTO_EE</Procedura>"))
        #expect(xml.range(of: "<GTU>")!.lowerBound < xml.range(of: "<Procedura>")!.lowerBound)

        // Round-trip przez parser.
        let parsed = try FA2XMLParser.parse(xml: xml)
        #expect(parsed.lines[0].procedure == "WSTO_EE")
    }
}
