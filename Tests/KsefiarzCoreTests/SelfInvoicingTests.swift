import Foundation
import Testing
@testable import KsefiarzCore

/// Testy samofakturowania (A3): faktura wystawiana przez nabywcę w imieniu
/// dostawcy — adnotacja P_17 = 1, zamienione role stron, dokument zakupowy
/// z pełnym cyklem wysyłki do KSeF.
@Suite("Samofakturowanie (P_17)")
struct SelfInvoicingTests {

    /// Szkic samofaktury: sprzedawcą (Podmiot1) jest dostawca, nabywcą
    /// (Podmiot2) nasza firma — role zamienia formularz przed budową szkicu.
    private func makeSelfInvoicingDraft(
        invoiceType: String = "VAT",
        correction: InvoiceCorrectionInfo? = nil
    ) -> InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: "SF/2026/07/001",
            issueDate: FA2Format.dateFormatter.date(from: "2026-07-10")!,
            sellerName: "Dostawca Sp. z o.o.",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Dostawcza 7, 00-001 Warszawa",
            buyerName: "Moja Firma",
            buyerNIP: "1111111111",
            buyerAddress: "ul. Własna 1, 30-001 Kraków",
            lines: [
                InvoiceLineDraft(name: "Surowiec A", unit: "kg", quantity: 100, unitNetPrice: 4, vatRate: .standard),
            ],
            paymentDueDate: FA2Format.dateFormatter.date(from: "2026-07-24")!,
            paymentForm: .transfer,
            paymentBankAccount: "11 2222 3333 4444 5555 6666 7777",
            invoiceType: invoiceType,
            isSelfInvoicing: true,
            correction: correction
        )
    }

    private func makeSelfInvoice(kind: Invoice.Kind = .purchase) -> Invoice {
        let invoice = makeTestInvoice(number: "SF/2026/07/001", kind: kind)
        invoice.isSelfInvoicing = true
        return invoice
    }

    // MARK: Generator XML

    @Test("Samofaktura dostaje w Adnotacjach P_17 = 1")
    func generatorEmitujeP17() {
        let xml = FA2XMLGenerator.generateXML(for: makeSelfInvoicingDraft())

        #expect(xml.contains("<P_17>1</P_17>"))
        #expect(!xml.contains("<P_17>2</P_17>"))
        // Role stron pozostają jak w szkicu: Podmiot1 = dostawca.
        #expect(xml.contains("<NIP>5260250274</NIP>"))
        #expect(xml.contains("<NIP>1111111111</NIP>"))
        #expect(xml.contains("<RodzajFaktury>VAT</RodzajFaktury>"))
    }

    @Test("Zwykła faktura zachowuje P_17 = 2")
    func zwyklaFakturaBezAdnotacji() {
        var draft = makeSelfInvoicingDraft()
        draft.isSelfInvoicing = false
        let xml = FA2XMLGenerator.generateXML(for: draft)

        #expect(xml.contains("<P_17>2</P_17>"))
        #expect(!xml.contains("<P_17>1</P_17>"))
    }

    @Test("Korekta samofaktury zachowuje adnotację P_17 = 1")
    func korektaSamofaktury() {
        let correction = InvoiceCorrectionInfo(
            originalNumber: "SF/2026/06/009",
            originalIssueDate: FA2Format.dateFormatter.date(from: "2026-06-01")!,
            originalKsefNumber: "1111111111-20260601-ABCDEF123456-00",
            reason: "błędna ilość"
        )
        let xml = FA2XMLGenerator.generateXML(for: makeSelfInvoicingDraft(correction: correction))

        #expect(xml.contains("<P_17>1</P_17>"))
        #expect(xml.contains("<RodzajFaktury>KOR</RodzajFaktury>"))
    }

    // MARK: Parser XML

    @Test("Parser odczytuje P_17 = 1 jako samofakturowanie (round-trip)")
    func parserRoundTrip() throws {
        let xml = FA2XMLGenerator.generateXML(for: makeSelfInvoicingDraft())
        let parsed = try FA2XMLParser.parse(xml: xml)

        #expect(parsed.isSelfInvoicing)
        #expect(parsed.sellerNIP == "5260250274")
        #expect(parsed.buyerNIP == "1111111111")
    }

    @Test("Parser traktuje P_17 = 2 (i brak pola) jako zwykłą fakturę")
    func parserZwyklaFaktura() throws {
        var draft = makeSelfInvoicingDraft()
        draft.isSelfInvoicing = false
        let parsed = try FA2XMLParser.parse(xml: FA2XMLGenerator.generateXML(for: draft))
        #expect(!parsed.isSelfInvoicing)

        // Dokument bez bloku Adnotacje w ogóle (np. minimalna FA(2)).
        let minimal = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Faktura xmlns="http://crd.gov.pl/wzor/2023/06/29/12648/">
          <Podmiot1><DaneIdentyfikacyjne><NIP>5260250274</NIP><Nazwa>A</Nazwa></DaneIdentyfikacyjne></Podmiot1>
          <Podmiot2><DaneIdentyfikacyjne><NIP>1111111111</NIP><Nazwa>B</Nazwa></DaneIdentyfikacyjne></Podmiot2>
          <Fa><KodWaluty>PLN</KodWaluty><P_1>2026-07-10</P_1><P_2>F/1</P_2><P_15>123.00</P_15></Fa>
        </Faktura>
        """
        let parsedMinimal = try FA2XMLParser.parse(xml: minimal)
        #expect(!parsedMinimal.isSelfInvoicing)
    }

    // MARK: Model Invoice

    @Test("Invoice(from:) i applyDetails przenoszą flagę samofakturowania")
    func modelPrzenosiFlage() throws {
        let xml = FA2XMLGenerator.generateXML(for: makeSelfInvoicingDraft())
        let data = try FA2XMLParser.parse(xml: xml)

        let invoice = Invoice(from: data, kind: .purchase)
        #expect(invoice.isSelfInvoicing)

        // Odświeżenie szczegółów dokumentem bez adnotacji zdejmuje flagę
        // (treść dokumentu jest źródłem prawdy).
        var plain = makeSelfInvoicingDraft()
        plain.isSelfInvoicing = false
        let plainData = try FA2XMLParser.parse(xml: FA2XMLGenerator.generateXML(for: plain))
        invoice.applyDetails(from: plainData)
        #expect(!invoice.isSelfInvoicing)
    }

    @Test("isSelfIssuedPurchase: tylko zakupowe dokumenty wystawiane przez nas")
    func klasyfikacjaSamofaktur() {
        #expect(makeSelfInvoice(kind: .purchase).isSelfIssuedPurchase)
        // Sprzedaż z adnotacją P_17 wystawił klient — to nie nasz dokument.
        #expect(!makeSelfInvoice(kind: .sales).isSelfIssuedPurchase)

        let rr = makeTestInvoice(number: "RR/1", kind: .purchase)
        rr.documentTypeRaw = "VAT_RR"
        #expect(rr.isSelfIssuedPurchase)

        #expect(!makeTestInvoice(number: "Z/1", kind: .purchase).isSelfIssuedPurchase)
    }

    @Test("Cykl wysyłki KSeF obejmuje własną sprzedaż, VAT RR i nasze samofaktury")
    func klasyfikacjaCykluWysylkiKSeF() {
        let sales = makeTestInvoice(number: "FV/1", kind: .sales)
        #expect(sales.hasKSeFSubmissionLifecycle)

        let selfInvoicedSales = makeSelfInvoice(kind: .sales)
        #expect(!selfInvoicedSales.hasKSeFSubmissionLifecycle)

        let selfInvoice = makeSelfInvoice(kind: .purchase)
        #expect(selfInvoice.hasKSeFSubmissionLifecycle)

        let rr = makeTestInvoice(number: "RR/1", kind: .purchase)
        rr.documentTypeRaw = "VAT_RR"
        #expect(rr.hasKSeFSubmissionLifecycle)

        let purchase = makeTestInvoice(number: "Z/1", kind: .purchase)
        #expect(!purchase.hasKSeFSubmissionLifecycle)
    }

    @Test("Kontekst KODU II to NIP nabywcy dla samofaktury i VAT RR")
    func kontekstWysylkiDlaDokumentowZakupowych() {
        let selfInvoice = makeSelfInvoice(kind: .purchase)
        #expect(selfInvoice.ksefSubmissionContextNIP == selfInvoice.buyerNIP)

        let rr = makeTestInvoice(number: "RR/1", kind: .purchase)
        rr.documentTypeRaw = "VAT_RR"
        #expect(rr.ksefSubmissionContextNIP == rr.buyerNIP)

        let sales = makeTestInvoice(number: "FV/1", kind: .sales)
        #expect(sales.ksefSubmissionContextNIP == sales.sellerNIP)
    }

    @Test("Lokalna samofaktura i VAT RR nie są ręcznymi fakturami kosztowymi")
    func recznyZakupVsSamofaktura() {
        // Ręczny zakup spoza KSeF — edytowalny formularzem zakupu.
        #expect(makeTestInvoice(number: "Z/1", kind: .purchase).isManualPurchase)

        // Lokalna (jeszcze niewysłana) samofaktura ma cykl KSeF.
        #expect(!makeSelfInvoice(kind: .purchase).isManualPurchase)

        // Regresja: lokalna faktura VAT RR także nie jest ręcznym zakupem.
        let rr = makeTestInvoice(number: "RR/1", kind: .purchase)
        rr.documentTypeRaw = "VAT_RR"
        #expect(!rr.isManualPurchase)

        // Zakup z numerem KSeF nigdy nie jest ręczny.
        #expect(!makeTestInvoice(number: "Z/2", kind: .purchase, ksefId: "KSEF-1").isManualPurchase)
    }

    // MARK: Szkic i szablony

    @Test("InvoiceDraft(from:) zachowuje flagę samofakturowania")
    func szkicZachowujeFlage() {
        let invoice = makeSelfInvoice()
        let draft = InvoiceDraft(from: invoice)
        #expect(draft.isSelfInvoicing)

        let plain = makeTestInvoice(number: "FV/1", kind: .sales)
        #expect(!InvoiceDraft(from: plain).isSelfInvoicing)
    }

    @Test("Szablon (InvoicePreset) przenosi samofakturowanie przez round-trip")
    func szablonRoundTrip() throws {
        let preset = InvoicePreset(draft: makeSelfInvoicingDraft())
        let encoded = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(InvoicePreset.self, from: encoded)
        #expect(decoded.draft().isSelfInvoicing)

        // Zwykły szkic nie zapisuje pola (zgodność ze starszymi szablonami:
        // brak klucza w JSON dekoduje się do nil → false).
        var plainDraft = makeSelfInvoicingDraft()
        plainDraft.isSelfInvoicing = false
        let plainEncoded = try JSONEncoder().encode(InvoicePreset(draft: plainDraft))
        let plainJSON = String(decoding: plainEncoded, as: UTF8.self)
        #expect(!plainJSON.contains("isSelfInvoicing"))
        let plainDecoded = try JSONDecoder().decode(InvoicePreset.self, from: plainEncoded)
        #expect(!plainDecoded.draft().isSelfInvoicing)
    }

    // MARK: Walidacja

    @Test("Poprawna samofaktura przechodzi walidację")
    func walidacjaPoprawnejSamofaktury() {
        #expect(InvoiceValidator.validate(makeSelfInvoicingDraft()).isEmpty)
    }

    @Test("Samofakturowanie nie łączy się z fakturą VAT RR")
    func walidacjaKonfliktuZRR() {
        var draft = makeSelfInvoicingDraft(invoiceType: "VAT_RR")
        draft.lines = [
            InvoiceLineDraft(name: "Żyto", unit: "t", quantity: 1, unitNetPrice: 900, vatRate: .rr, rrQuality: "klasa I"),
        ]
        let errors = InvoiceValidator.validate(draft)
        #expect(errors.contains(.selfInvoicingUnsupportedForRR))
    }

    @Test("Samofaktura wymaga adresu dostawcy (Podmiot1/Adres)")
    func walidacjaAdresuDostawcy() {
        var draft = makeSelfInvoicingDraft()
        draft.sellerAddress = "  "
        let errors = InvoiceValidator.validate(draft)
        #expect(errors.contains(.emptySellerAddress))
    }

    // MARK: Branding PDF

    @Test("Branding nie obejmuje dokumentów samofakturowania w obie strony")
    func brandingWylaczony() {
        let branding = InvoicePDFBranding(isEnabled: true, companyNIP: "1111111111")

        // Nasza samofaktura: dokument formalnie należy do dostawcy.
        let selfPurchase = makeSelfInvoice(kind: .purchase)
        #expect(!branding.applies(to: selfPurchase))

        // Nasza sprzedaż z adnotacją P_17 — wystawił ją klient.
        let ownBranding = InvoicePDFBranding(isEnabled: true, companyNIP: "5260250274")
        let selfSales = makeSelfInvoice(kind: .sales)
        #expect(!ownBranding.applies(to: selfSales))
        // Ta sama sprzedaż bez adnotacji podlega brandingowi.
        let plainSales = makeTestInvoice(number: "FV/2", kind: .sales)
        #expect(ownBranding.applies(to: plainSales))
    }

    // MARK: Kopia zapasowa

    @Test("Kopia zapasowa zachowuje samofakturowanie (round-trip)")
    func kopiaZapasowaRoundTrip() throws {
        let invoice = makeSelfInvoice()
        let data = try BackupService.makeBackup(invoices: [invoice], settings: [:])
        let decoded = try BackupService.decode(data)

        let entry = try #require(decoded.invoices.first)
        #expect(entry.isSelfInvoicing == true)

        let restored = BackupService.makeInvoice(from: entry)
        #expect(restored.isSelfInvoicing)
        #expect(restored.kind == .purchase)
    }

    @Test("Starsza kopia bez pola samofakturowania odtwarza zwykłą fakturę")
    func kopiaZapasowaStarszaWersja() throws {
        let invoice = makeTestInvoice(number: "FV/3", kind: .sales)
        let data = try BackupService.makeBackup(invoices: [invoice], settings: [:])
        var decoded = try BackupService.decode(data)

        var entry = try #require(decoded.invoices.first)
        // Pole nie jest zapisywane dla zwykłych faktur (nil = brak klucza),
        // dokładnie jak w kopiach sprzed wersji 12.
        #expect(entry.isSelfInvoicing == nil)
        entry.isSelfInvoicing = nil
        decoded.invoices = [entry]

        let restored = BackupService.makeInvoice(from: entry)
        #expect(!restored.isSelfInvoicing)
    }

    // MARK: Metadane KSeF

    @Test("Metadane KSeF dekodują flagę isSelfInvoicing")
    func metadaneDekodujaFlage() throws {
        let json = """
        {"invoices": [
          {"ksefNumber": "5260250274-20260710-AAAA-01", "isSelfInvoicing": true},
          {"ksefNumber": "5260250274-20260710-BBBB-02"}
        ]}
        """
        let response = try JSONDecoder().decode(InvoiceQueryResponseDTO.self, from: Data(json.utf8))
        #expect(response.invoices[0].isSelfInvoicing == true)
        #expect(response.invoices[1].isSelfInvoicing == nil)
    }
}
