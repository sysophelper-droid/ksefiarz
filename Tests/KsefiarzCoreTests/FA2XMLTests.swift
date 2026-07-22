import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Generator XML FA(2)")
struct FA2XMLGeneratorTests {

    private func makeDraft() -> InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: "FV/2026/06/001",
            issueDate: FA2Format.dateFormatter.date(from: "2026-06-01")!,
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Przykładowa 1, 00-001 Warszawa",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            buyerAddress: "ul. Odbiorcza 5, 30-001 Kraków",
            netAmount: 100.0,
            vatAmount: 23.0,
            paymentDueDate: FA2Format.dateFormatter.date(from: "2026-06-15")!,
            paymentForm: .transfer,
            paymentBankAccount: "11 2222 3333 4444 5555 6666 7777"
        )
    }

    private func makeDraftWithLines() -> InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: "FV/2026/06/002",
            issueDate: FA2Format.dateFormatter.date(from: "2026-06-01")!,
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Przykładowa 1, 00-001 Warszawa",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            lines: [
                InvoiceLineDraft(name: "Usługa programistyczna", unit: "godz.", quantity: 10, unitNetPrice: 150, vatRate: .standard),
                InvoiceLineDraft(name: "Książka techniczna", unit: "szt.", quantity: 2, unitNetPrice: 50, vatRate: .reducedFirst),
            ]
        )
    }

    @Test("Wygenerowany XML zawiera wszystkie wymagane elementy FA(2)")
    func containsRequiredElements() {
        let xml = FA2XMLGenerator.generateXML(for: makeDraft())

        #expect(xml.contains("<Faktura xmlns=\"\(FA2XMLGenerator.namespace)\">"))
        #expect(xml.contains("<KodFormularza"))
        #expect(xml.contains("<WariantFormularza>3</WariantFormularza>"))
        #expect(xml.contains(#"kodSystemowy="FA (3)""#))
        #expect(xml.contains("<NIP>5260250274</NIP>"))
        #expect(xml.contains("<NIP>1111111111</NIP>"))
        #expect(xml.contains("<P_1>2026-06-01</P_1>"))
        #expect(xml.contains("<P_2>FV/2026/06/001</P_2>"))
        #expect(xml.contains("<P_13_1>100.00</P_13_1>"))
        #expect(xml.contains("<P_14_1>23.00</P_14_1>"))
        #expect(xml.contains("<P_15>123.00</P_15>"))
        #expect(xml.contains("<Termin>2026-06-15</Termin>"))
        // Elementy obowiązkowe schemy FA(2).
        #expect(xml.contains("<AdresL1>ul. Przykładowa 1, 00-001 Warszawa</AdresL1>"))
        #expect(xml.contains("<AdresL1>ul. Odbiorcza 5, 30-001 Kraków</AdresL1>"))
        #expect(xml.contains("<Adnotacje>"))
        #expect(xml.contains("<P_19N>1</P_19N>"))
        #expect(xml.contains("<RodzajFaktury>VAT</RodzajFaktury>"))
        // Dane płatności.
        #expect(xml.contains("<FormaPlatnosci>6</FormaPlatnosci>"))
        #expect(xml.contains("<NrRB>11222233334444555566667777</NrRB>"))
    }

    @Test("Pozycje generują FaWiersz i sumy per stawka VAT")
    func generatesLinesAndVatSummary() {
        let xml = FA2XMLGenerator.generateXML(for: makeDraftWithLines())

        // Pozycje.
        #expect(xml.contains("<NrWierszaFa>1</NrWierszaFa>"))
        #expect(xml.contains("<P_7>Usługa programistyczna</P_7>"))
        #expect(xml.contains("<P_8A>godz.</P_8A>"))
        #expect(xml.contains("<P_8B>10</P_8B>"))
        #expect(xml.contains("<P_9A>150.00</P_9A>"))
        #expect(xml.contains("<P_11>1500.00</P_11>"))
        #expect(xml.contains("<P_12>23</P_12>"))
        #expect(xml.contains("<NrWierszaFa>2</NrWierszaFa>"))
        #expect(xml.contains("<P_12>8</P_12>"))

        // Sumy per stawka: 1500 netto / 345 VAT (23%), 100 netto / 8 VAT (8%).
        #expect(xml.contains("<P_13_1>1500.00</P_13_1>"))
        #expect(xml.contains("<P_14_1>345.00</P_14_1>"))
        #expect(xml.contains("<P_13_2>100.00</P_13_2>"))
        #expect(xml.contains("<P_14_2>8.00</P_14_2>"))
        #expect(xml.contains("<P_15>1953.00</P_15>"))
    }

    @Test("Kod z kropkami trafia do PKWiU, sam ciąg cyfr do CN, GTU po P_12")
    func cnPkwiuIGtuWPozycji() {
        var draft = makeDraftWithLines()
        draft.lines[0].cnPkwiu = "62.01.11.0"
        draft.lines[0].gtu = "GTU_12"
        draft.lines[1].cnPkwiu = "49019900"

        let xml = FA2XMLGenerator.generateXML(for: draft)

        #expect(xml.contains("<PKWiU>62.01.11.0</PKWiU>"))
        #expect(xml.contains("<CN>49019900</CN>"))
        #expect(xml.contains("<GTU>GTU_12</GTU>"))
        // Kolejność wg XSD: PKWiU przed P_8A, GTU po P_12.
        let pkwiuIndex = xml.range(of: "<PKWiU>")!.lowerBound
        let unitIndex = xml.range(of: "<P_8A>")!.lowerBound
        #expect(pkwiuIndex < unitIndex)
        let rateIndex = xml.range(of: "<P_12>")!.lowerBound
        let gtuIndex = xml.range(of: "<GTU>")!.lowerBound
        #expect(rateIndex < gtuIndex)
    }

    @Test("Parser odczytuje CN/PKWiU, GTU i uwagi z wygenerowanego dokumentu")
    func parserRoundTrip() throws {
        var draft = makeDraftWithLines()
        draft.lines[0].cnPkwiu = "62.01.11.0"
        draft.lines[0].gtu = "GTU_12"
        draft.lines[1].cnPkwiu = "49019900"
        draft.notes = "Płatność na rachunek z białej listy"

        let parsed = try FA2XMLParser.parse(xml: FA2XMLGenerator.generateXML(for: draft))

        #expect(parsed.lines[0].cnPkwiu == "62.01.11.0")
        #expect(parsed.lines[0].gtu == "GTU_12")
        #expect(parsed.lines[1].cnPkwiu == "49019900")
        #expect(parsed.lines[1].gtu.isEmpty)
        #expect(parsed.notes == "Płatność na rachunek z białej listy")
    }

    @Test("Puste kody klasyfikacji nie generują elementów PKWiU/CN/GTU")
    func brakKodowKlasyfikacji() {
        let xml = FA2XMLGenerator.generateXML(for: makeDraftWithLines())
        #expect(!xml.contains("<PKWiU>"))
        #expect(!xml.contains("<CN>"))
        #expect(!xml.contains("<GTU>"))
    }

    @Test("Uwagi generują Stopkę po elemencie Fa; brak uwag — brak Stopki")
    func uwagiWStopce() {
        var draft = makeDraft()
        draft.notes = "Mechanizm podzielonej płatności"

        let xml = FA2XMLGenerator.generateXML(for: draft)
        #expect(xml.contains("<StopkaFaktury>Mechanizm podzielonej płatności</StopkaFaktury>"))
        let faCloseIndex = xml.range(of: "</Fa>")!.lowerBound
        let stopkaIndex = xml.range(of: "<Stopka>")!.lowerBound
        #expect(faCloseIndex < stopkaIndex)

        let bare = FA2XMLGenerator.generateXML(for: makeDraft())
        #expect(!bare.contains("<Stopka>"))
    }

    @Test("MPP ustawia P_18A=1; bez MPP P_18A=2")
    func mechanizmPodzielonejPlatnosci() {
        var draft = makeDraft()
        draft.splitPayment = true
        #expect(FA2XMLGenerator.generateXML(for: draft).contains("<P_18A>1</P_18A>"))
        #expect(FA2XMLGenerator.generateXML(for: makeDraft()).contains("<P_18A>2</P_18A>"))
    }

    @Test("Waluta obca: KodWaluty i VAT przeliczony na PLN (P_14_1W)")
    func walutaObca() {
        var draft = makeDraftWithLines()
        draft.currency = "EUR"
        draft.exchangeRate = 4.25

        let xml = FA2XMLGenerator.generateXML(for: draft)

        #expect(xml.contains("<KodWaluty>EUR</KodWaluty>"))
        // 345.00 EUR VAT (23%) × 4.25 = 1466.25 PLN; 8.00 × 4.25 = 34.00.
        #expect(xml.contains("<P_14_1W>1466.25</P_14_1W>"))
        #expect(xml.contains("<P_14_2W>34.00</P_14_2W>"))
        // PLN bez kursu nie generuje pól W.
        #expect(!FA2XMLGenerator.generateXML(for: makeDraftWithLines()).contains("P_14_1W"))
    }

    @Test("Kod PLN z odstępami nie generuje kwot VAT przeliczonych na PLN")
    func znormalizowanyKodPLNBezKwotW() {
        var draft = makeDraftWithLines()
        draft.currency = " pln\n"
        draft.exchangeRate = 4.25

        let xml = FA2XMLGenerator.generateXML(for: draft)

        #expect(!xml.contains("<P_14_1W>"))
        #expect(!xml.contains("<P_14_2W>"))
    }

    @Test("Faktura zaliczkowa (ZAL): RodzajFaktury i data otrzymania zapłaty P_6")
    func fakturaZaliczkowa() {
        var draft = makeDraft()
        draft.invoiceType = "ZAL"
        draft.saleDate = FA2Format.dateFormatter.date(from: "2026-06-10")

        let xml = FA2XMLGenerator.generateXML(for: draft)

        #expect(xml.contains("<RodzajFaktury>ZAL</RodzajFaktury>"))
        #expect(xml.contains("<P_6>2026-06-10</P_6>"))
        // P_6 musi być przed sumami P_13_x (kolejność XSD).
        #expect(xml.range(of: "<P_6>")!.lowerBound < xml.range(of: "<P_13_1>")!.lowerBound)
    }

    @Test("Faktura rozliczeniowa (ROZ): odwołania do faktur zaliczkowych przed FaWiersz")
    func fakturaRozliczeniowa() {
        var draft = makeDraftWithLines()
        draft.invoiceType = "ROZ"
        draft.advanceInvoiceRefs = ["9999999999-20260610-AAA-01", "9999999999-20260611-BBB-02"]

        let xml = FA2XMLGenerator.generateXML(for: draft)

        #expect(xml.contains("<RodzajFaktury>ROZ</RodzajFaktury>"))
        #expect(xml.contains("<NrKSeFFaZaliczkowej>9999999999-20260610-AAA-01</NrKSeFFaZaliczkowej>"))
        #expect(xml.contains("<NrKSeFFaZaliczkowej>9999999999-20260611-BBB-02</NrKSeFFaZaliczkowej>"))
        let zalIndex = xml.range(of: "<FakturaZaliczkowa>")!.lowerBound
        let lineIndex = xml.range(of: "<FaWiersz>")!.lowerBound
        #expect(zalIndex < lineIndex)
    }

    @Test("Parser czyta walutę, MPP i datę sprzedaży (round-trip)")
    func parserWalutaMppP6() throws {
        var draft = makeDraftWithLines()
        draft.currency = "EUR"
        draft.exchangeRate = 4.25
        draft.splitPayment = true
        draft.saleDate = FA2Format.dateFormatter.date(from: "2026-06-10")

        let parsed = try FA2XMLParser.parse(xml: FA2XMLGenerator.generateXML(for: draft))

        #expect(parsed.currency == "EUR")
        #expect(parsed.splitPayment)
        #expect(parsed.saleDate == draft.saleDate)
    }

    @Test("Walidacja: waluta obca bez kursu i ROZ bez zaliczek są odrzucane")
    func walidacjaNowychPol() {
        var foreign = makeDraftWithLines()
        foreign.currency = "EUR"
        #expect(InvoiceValidator.validate(foreign).contains(.missingExchangeRate))
        foreign.exchangeRate = 4.25
        #expect(!InvoiceValidator.validate(foreign).contains(.missingExchangeRate))

        var settlement = makeDraftWithLines()
        settlement.invoiceType = "ROZ"
        #expect(InvoiceValidator.validate(settlement).contains(.missingAdvanceInvoiceRefs))
        settlement.advanceInvoiceRefs = ["9999999999-20260610-AAA-01"]
        #expect(!InvoiceValidator.validate(settlement).contains(.missingAdvanceInvoiceRefs))
    }

    @Test("Brak danych płatności nie generuje bloku Platnosc")
    func noPaymentBlock() {
        var draft = makeDraft()
        draft.paymentDueDate = nil
        draft.paymentForm = nil
        draft.paymentBankAccount = ""
        let xml = FA2XMLGenerator.generateXML(for: draft)
        #expect(!xml.contains("<Platnosc>"))
    }

    @Test("Pusty adres nabywcy nie generuje bloku Adres w Podmiot2")
    func noBuyerAddressBlock() {
        var draft = makeDraft()
        draft.buyerAddress = ""
        let xml = FA2XMLGenerator.generateXML(for: draft)
        // Adres sprzedawcy musi być, nabywcy — nie.
        #expect(xml.contains("ul. Przykładowa 1"))
        #expect(!xml.contains("ul. Odbiorcza 5"))
    }

    @Test("Znaki specjalne XML są poprawnie escapowane")
    func escapesSpecialCharacters() {
        var draft = makeDraft()
        draft.sellerName = "Firma <A&B> \"Żółć\""
        let xml = FA2XMLGenerator.generateXML(for: draft)
        #expect(xml.contains("Firma &lt;A&amp;B&gt; &quot;Żółć&quot;"))
        #expect(!xml.contains("<A&B>"))
    }

    @Test("Kwoty są formatowane z kropką dziesiętną niezależnie od locale")
    func amountFormatting() {
        #expect(FA2Format.amount(1234.5) == "1234.50")
        #expect(FA2Format.amount(0) == "0.00")
        #expect(FA2Format.quantity(10) == "10")
        #expect(FA2Format.quantity(2.5) == "2.5")
        #expect(FA2Format.quantity(0.125) == "0.125")
    }
}

@Suite("Parser XML FA(2)")
struct FA2XMLParserTests {

    /// Ręcznie przygotowany dokument FA(2) — taki, jaki zwraca KSeF
    /// (z adresami, pozycjami i danymi płatności).
    private let sampleXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Faktura xmlns="http://crd.gov.pl/wzor/2023/06/29/12648/">
      <Naglowek>
        <KodFormularza kodSystemowy="FA (2)" wersjaSchemy="1-0E">FA</KodFormularza>
        <WariantFormularza>2</WariantFormularza>
        <DataWytworzeniaFa>2026-06-01T10:00:00Z</DataWytworzeniaFa>
      </Naglowek>
      <Podmiot1>
        <DaneIdentyfikacyjne>
          <NIP>5260250274</NIP>
          <Nazwa>Dostawca Sp. z o.o.</Nazwa>
        </DaneIdentyfikacyjne>
        <Adres>
          <KodKraju>PL</KodKraju>
          <AdresL1>ul. Dostawcza 7</AdresL1>
          <AdresL2>00-950 Warszawa</AdresL2>
        </Adres>
      </Podmiot1>
      <Podmiot2>
        <DaneIdentyfikacyjne>
          <NIP>1111111111</NIP>
          <Nazwa>Moja Firma</Nazwa>
        </DaneIdentyfikacyjne>
        <Adres>
          <KodKraju>PL</KodKraju>
          <AdresL1>ul. Własna 12, 31-000 Kraków</AdresL1>
        </Adres>
      </Podmiot2>
      <Fa>
        <KodWaluty>PLN</KodWaluty>
        <P_1>2026-05-20</P_1>
        <P_2>ZK/2026/05/077</P_2>
        <P_13_1>200.00</P_13_1>
        <P_14_1>46.00</P_14_1>
        <P_15>246.00</P_15>
        <Adnotacje>
          <P_16>2</P_16>
          <P_17>2</P_17>
          <P_18>2</P_18>
          <P_18A>2</P_18A>
          <Zwolnienie><P_19N>1</P_19N></Zwolnienie>
          <NoweSrodkiTransportu><P_22N>1</P_22N></NoweSrodkiTransportu>
          <P_23>2</P_23>
          <PMarzy><P_PMarzyN>1</P_PMarzyN></PMarzy>
        </Adnotacje>
        <RodzajFaktury>VAT</RodzajFaktury>
        <FaWiersz>
          <NrWierszaFa>1</NrWierszaFa>
          <P_7>Abonament internetowy</P_7>
          <P_8A>szt.</P_8A>
          <P_8B>1</P_8B>
          <P_9A>120.00</P_9A>
          <P_11>120.00</P_11>
          <P_12>23</P_12>
        </FaWiersz>
        <FaWiersz>
          <NrWierszaFa>2</NrWierszaFa>
          <P_7>Dzierżawa routera</P_7>
          <P_8A>szt.</P_8A>
          <P_8B>2</P_8B>
          <P_9A>40.00</P_9A>
          <P_11>80.00</P_11>
          <P_12>23</P_12>
        </FaWiersz>
        <Platnosc>
          <Zaplacono>1</Zaplacono>
          <DataZaplaty>2026-05-20</DataZaplaty>
          <TerminPlatnosci>
            <Termin>2026-06-03</Termin>
          </TerminPlatnosci>
          <FormaPlatnosci>2</FormaPlatnosci>
          <RachunekBankowy>
            <NrRB>11222233334444555566667777</NrRB>
          </RachunekBankowy>
        </Platnosc>
      </Fa>
    </Faktura>
    """

    @Test("Parsowanie poprawnego dokumentu FA(2) ze wszystkimi danymi")
    func parseValidDocument() throws {
        let data = try FA2XMLParser.parse(xml: sampleXML)

        #expect(data.invoiceNumber == "ZK/2026/05/077")
        #expect(FA2Format.dateFormatter.string(from: data.issueDate) == "2026-05-20")
        #expect(data.sellerName == "Dostawca Sp. z o.o.")
        #expect(data.sellerNIP == "5260250274")
        #expect(data.sellerAddress == "ul. Dostawcza 7, 00-950 Warszawa")
        #expect(data.buyerName == "Moja Firma")
        #expect(data.buyerNIP == "1111111111")
        #expect(data.buyerAddress == "ul. Własna 12, 31-000 Kraków")
        #expect(abs(data.netAmount - 200.0) < 0.001)
        #expect(abs(data.vatAmount - 46.0) < 0.001)
        #expect(abs(data.grossAmount - 246.0) < 0.001)
        let due = try #require(data.paymentDueDate)
        #expect(FA2Format.dateFormatter.string(from: due) == "2026-06-03")
        #expect(data.rawXML.contains("<Faktura"))
    }

    @Test("Parser wyciąga pozycje faktury (FaWiersz)")
    func parsesLines() throws {
        let data = try FA2XMLParser.parse(xml: sampleXML)

        #expect(data.lines.count == 2)
        let first = try #require(data.lines.first)
        #expect(first.index == 1)
        #expect(first.name == "Abonament internetowy")
        #expect(first.unit == "szt.")
        #expect(abs(first.quantity - 1) < 0.001)
        #expect(abs(first.unitNetPrice - 120) < 0.001)
        #expect(abs(first.netAmount - 120) < 0.001)
        #expect(first.vatRate == "23")
        #expect(abs(first.vatAmount - 27.6) < 0.001)

        let second = try #require(data.lines.last)
        #expect(second.name == "Dzierżawa routera")
        #expect(abs(second.quantity - 2) < 0.001)
        #expect(abs(second.netAmount - 80) < 0.001)
    }

    @Test("Parser wyciąga dane płatności i znacznik zapłaty")
    func parsesPaymentInfo() throws {
        let data = try FA2XMLParser.parse(xml: sampleXML)

        // Zaplacono=1 → faktura opłacona przy wystawieniu (tu: kartą).
        #expect(data.isPaidMarker)
        #expect(data.paymentForm == "2")
        #expect(data.paymentBankAccount == "11222233334444555566667777")
        let paid = try #require(data.paymentDate)
        #expect(FA2Format.dateFormatter.string(from: paid) == "2026-05-20")
    }

    @Test("Brak znacznika Zaplacono oznacza fakturę nieopłaconą")
    func noPaidMarker() throws {
        let xml = sampleXML
            .replacingOccurrences(of: "<Zaplacono>1</Zaplacono>", with: "")
            .replacingOccurrences(of: "<DataZaplaty>2026-05-20</DataZaplaty>", with: "")
        let data = try FA2XMLParser.parse(xml: xml)
        #expect(!data.isPaidMarker)
        #expect(data.paymentDate == nil)
    }

    @Test("Sumy netto/VAT liczone z wielu stawek (P_13_x)")
    func sumsMultipleRates() throws {
        let xml = sampleXML.replacingOccurrences(
            of: "<P_13_1>200.00</P_13_1>\n    <P_14_1>46.00</P_14_1>",
            with: "<P_13_1>100.00</P_13_1>\n    <P_14_1>23.00</P_14_1>\n    <P_13_2>50.00</P_13_2>\n    <P_14_2>4.00</P_14_2>\n    <P_13_7>50.00</P_13_7>"
        )
        let data = try FA2XMLParser.parse(xml: xml)
        #expect(abs(data.netAmount - 200.0) < 0.001)
        #expect(abs(data.vatAmount - 27.0) < 0.001)
    }

    @Test("Dokument bez elementu Faktura jest odrzucany")
    func rejectsWrongRoot() {
        #expect(throws: KSeFError.self) {
            _ = try FA2XMLParser.parse(xml: "<Inny><P_2>x</P_2></Inny>")
        }
    }

    @Test("Tekst niebędący XML jest odrzucany")
    func rejectsGarbage() {
        #expect(throws: KSeFError.self) {
            _ = try FA2XMLParser.parse(xml: "to nie jest xml")
        }
    }

    @Test("Brak numeru faktury (P_2) jest odrzucany")
    func rejectsMissingInvoiceNumber() {
        let xml = sampleXML.replacingOccurrences(of: "<P_2>ZK/2026/05/077</P_2>", with: "")
        #expect(throws: KSeFError.self) {
            _ = try FA2XMLParser.parse(xml: xml)
        }
    }

    @Test("Round-trip: generator → parser zachowuje wszystkie dane wraz z pozycjami")
    func roundTrip() throws {
        let draft = InvoiceDraft(
            invoiceNumber: "FV/2026/06/042",
            issueDate: FA2Format.dateFormatter.date(from: "2026-06-10")!,
            sellerName: "Żółta Firma & Synowie <Sp. z o.o.>",
            sellerNIP: "5260250274",
            sellerAddress: "ul. Złota 44, 00-120 Warszawa",
            buyerName: "Nabywca",
            buyerNIP: "1111111111",
            buyerAddress: "Rynek 1, 50-101 Wrocław",
            lines: [
                InvoiceLineDraft(name: "Konsultacje & wdrożenie", unit: "godz.", quantity: 12.5, unitNetPrice: 200, vatRate: .standard),
                InvoiceLineDraft(name: "Licencja", unit: "szt.", quantity: 1, unitNetPrice: 499.99, vatRate: .reducedFirst),
            ],
            paymentDueDate: FA2Format.dateFormatter.date(from: "2026-06-24")!,
            paymentForm: .transfer,
            paymentBankAccount: "11222233334444555566667777"
        )
        let xml = FA2XMLGenerator.generateXML(for: draft)
        let parsed = try FA2XMLParser.parse(xml: xml)

        #expect(parsed.invoiceNumber == draft.invoiceNumber)
        #expect(parsed.sellerName == draft.sellerName)
        #expect(parsed.sellerNIP == draft.sellerNIP)
        #expect(parsed.sellerAddress == draft.sellerAddress)
        #expect(parsed.buyerName == draft.buyerName)
        #expect(parsed.buyerNIP == draft.buyerNIP)
        #expect(parsed.buyerAddress == draft.buyerAddress)
        #expect(abs(parsed.netAmount - draft.netAmount) < 0.001)
        #expect(abs(parsed.vatAmount - draft.vatAmount) < 0.001)
        #expect(abs(parsed.grossAmount - draft.grossAmount) < 0.001)
        #expect(parsed.paymentForm == "6")
        #expect(parsed.paymentBankAccount == "11222233334444555566667777")
        #expect(FA2Format.dateFormatter.string(from: parsed.issueDate) == "2026-06-10")
        let due = try #require(parsed.paymentDueDate)
        #expect(FA2Format.dateFormatter.string(from: due) == "2026-06-24")

        // Pozycje przechodzą round-trip bez strat.
        #expect(parsed.lines.count == 2)
        let first = try #require(parsed.lines.first)
        #expect(first.name == "Konsultacje & wdrożenie")
        #expect(abs(first.quantity - 12.5) < 0.001)
        #expect(abs(first.netAmount - 2500) < 0.001)
        #expect(first.vatRate == "23")
        let second = try #require(parsed.lines.last)
        #expect(abs(second.netAmount - 499.99) < 0.001)
        #expect(second.vatRate == "8")
    }
}
