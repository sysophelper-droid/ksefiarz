import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Pomocnicze

private func makeOptions(
    from: String = "2026-06-01",
    to: String = "2026-06-30",
    ulica: String = "Wesoła",
    nrLokalu: String = "3"
) -> JPKFAOptions {
    JPKFAOptions(
        dateFrom: FA2Format.dateFormatter.date(from: from)!,
        dateTo: FA2Format.dateFormatter.date(from: to)!,
        sellerNIP: "526-025-02-74",
        sellerName: "ACME Sp. z o.o.",
        taxOfficeCode: "1219",
        wojewodztwo: "małopolskie",
        powiat: "Kraków",
        gmina: "Kraków",
        ulica: ulica,
        nrDomu: "12",
        nrLokalu: nrLokalu,
        miejscowosc: "Kraków",
        kodPocztowy: "30-001"
    )
}

private func makeSale(
    number: String = "FV/6/2026",
    issue: String = "2026-06-10",
    saleDate: String? = nil,
    buyerName: String = "Kontrahent S.A.",
    buyerNIP: String = "1111111111",
    buyerAddress: String = "ul. Prosta 1, 00-001 Warszawa",
    sellerName: String = "ACME Sp. z o.o.",
    sellerAddress: String = "ul. Wesoła 12/3, 30-001 Kraków",
    lines: [InvoiceLine] = [],
    net: Double = 100,
    vat: Double = 23,
    gross: Double? = nil,
    currency: String = "PLN",
    exchangeRate: Double = 0,
    documentType: String = "VAT",
    correctionReason: String? = nil,
    correctedInvoiceNumber: String? = nil,
    advanceInvoiceRefs: [String] = [],
    marginProcedure: String = "",
    splitPayment: Bool = false,
    isSelfInvoicing: Bool = false,
    hidden: Bool = false,
    kind: Invoice.Kind = .sales
) -> Invoice {
    let invoice = Invoice(
        invoiceNumber: number,
        issueDate: FA2Format.dateFormatter.date(from: issue)!,
        sellerName: sellerName, sellerNIP: "5260250274",
        sellerAddress: sellerAddress,
        buyerName: buyerName, buyerNIP: buyerNIP,
        buyerAddress: buyerAddress,
        netAmount: net, vatAmount: vat, grossAmount: gross ?? (net + vat),
        isArchivedOrHidden: hidden,
        documentType: documentType,
        correctionReason: correctionReason,
        correctedInvoiceNumber: correctedInvoiceNumber,
        currency: currency,
        exchangeRate: exchangeRate,
        splitPayment: splitPayment,
        saleDate: saleDate.flatMap { FA2Format.dateFormatter.date(from: $0) },
        advanceInvoiceRefs: advanceInvoiceRefs,
        marginProcedure: marginProcedure,
        isSelfInvoicing: isSelfInvoicing,
        kind: kind
    )
    invoice.lines = lines
    return invoice
}

private func line(
    _ name: String, net: Double, rate: String, vat: Double,
    unit: String = "szt.", quantity: Double = 1, unitPrice: Double = 0,
    ossRate: Double? = nil
) -> InvoiceLine {
    InvoiceLine(
        index: 1, name: name, unit: unit, quantity: quantity,
        unitNetPrice: unitPrice, netAmount: net, vatRate: rate,
        vatAmount: vat, ossRate: ossRate
    )
}

@Suite("Generator JPK_FA(4) — JPK faktur na żądanie")
struct JPKFAGeneratorTests {

    // MARK: Nagłówek i podmiot

    @Test("Nagłówek zawiera kod formularza JPK_FA (4), cel złożenia 1 i zakres dat")
    func naglowek() {
        let result = JPKFAGenerator.generate(
            invoices: [makeSale()], options: makeOptions()
        )
        #expect(result.xml.contains(#"<JPK xmlns="http://jpk.mf.gov.pl/wzor/2022/02/17/02171/" xmlns:etd="http://crd.gov.pl/xml/schematy/dziedzinowe/mf/2018/08/24/eD/DefinicjeTypy/">"#))
        #expect(result.xml.contains(#"<KodFormularza kodSystemowy="JPK_FA (4)" wersjaSchemy="1-0">JPK_FA</KodFormularza>"#))
        #expect(result.xml.contains("<WariantFormularza>4</WariantFormularza>"))
        #expect(result.xml.contains("<CelZlozenia>1</CelZlozenia>"))
        #expect(result.xml.contains("<DataOd>2026-06-01</DataOd>"))
        #expect(result.xml.contains("<DataDo>2026-06-30</DataDo>"))
        #expect(result.xml.contains("<KodUrzedu>1219</KodUrzedu>"))
    }

    @Test("Podmiot1 ma NIP bez separatorów, pełną nazwę i adres polski z ulicą i lokalem")
    func podmiot() {
        let result = JPKFAGenerator.generate(
            invoices: [makeSale()], options: makeOptions()
        )
        #expect(result.xml.contains("<NIP>5260250274</NIP>"))
        #expect(result.xml.contains("<PelnaNazwa>ACME Sp. z o.o.</PelnaNazwa>"))
        #expect(result.xml.contains("<etd:KodKraju>PL</etd:KodKraju>"))
        #expect(result.xml.contains("<etd:Wojewodztwo>małopolskie</etd:Wojewodztwo>"))
        #expect(result.xml.contains("<etd:Ulica>Wesoła</etd:Ulica>"))
        #expect(result.xml.contains("<etd:NrDomu>12</etd:NrDomu>"))
        #expect(result.xml.contains("<etd:NrLokalu>3</etd:NrLokalu>"))
        #expect(result.xml.contains("<etd:KodPocztowy>30-001</etd:KodPocztowy>"))
    }

    @Test("Pusta ulica i numer lokalu nie tworzą elementów (opcjonalne w XSD)")
    func adresBezUlicy() {
        let result = JPKFAGenerator.generate(
            invoices: [makeSale()],
            options: makeOptions(ulica: "", nrLokalu: "")
        )
        #expect(!result.xml.contains("<etd:Ulica>"))
        #expect(!result.xml.contains("<etd:NrLokalu>"))
    }

    // MARK: Kwalifikacja dokumentów

    @Test("Plik obejmuje wyłącznie widoczne faktury sprzedaży z okresu")
    func kwalifikacja() {
        let invoices = [
            makeSale(number: "FV/1"),
            makeSale(number: "FV/UKRYTA", hidden: true),
            makeSale(number: "Z/1", kind: .purchase),
            makeSale(number: "FV/POZA", issue: "2026-07-01"),
            makeSale(number: "FV/PRZED", issue: "2026-05-31"),
        ]
        let result = JPKFAGenerator.generate(invoices: invoices, options: makeOptions())
        #expect(result.invoiceCount == 1)
        #expect(result.xml.contains("<P_2A>FV/1</P_2A>"))
        #expect(!result.xml.contains("FV/UKRYTA"))
        #expect(!result.xml.contains("Z/1"))
        #expect(!result.xml.contains("FV/POZA"))
        #expect(!result.xml.contains("FV/PRZED"))
    }

    @Test("Granice zakresu dat są włączne (pierwszy i ostatni dzień)")
    func graniceZakresu() {
        let invoices = [
            makeSale(number: "FV/OD", issue: "2026-06-01"),
            makeSale(number: "FV/DO", issue: "2026-06-30"),
        ]
        let result = JPKFAGenerator.generate(invoices: invoices, options: makeOptions())
        #expect(result.invoiceCount == 2)
    }

    @Test("Samofaktura zakupowa i faktura VAT RR nie wchodzą do naszego JPK_FA")
    func samofakturyIRRPoza() {
        let selfIssued = makeSale(number: "SF/1", isSelfInvoicing: true, kind: .purchase)
        let rr = makeSale(number: "RR/1", documentType: "VAT_RR", kind: .purchase)
        let result = JPKFAGenerator.generate(
            invoices: [selfIssued, rr, makeSale(number: "FV/1")],
            options: makeOptions()
        )
        #expect(result.invoiceCount == 1)
        #expect(!result.xml.contains("SF/1"))
        #expect(!result.xml.contains("RR/1"))
    }

    @Test("Sprzedaż z adnotacją samofakturowania (P_17) wchodzi do pliku z true")
    func sprzedazSamofakturowanie() {
        let sale = makeSale(number: "FV/SF", isSelfInvoicing: true)
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.invoiceCount == 1)
        #expect(result.xml.contains("<P_17>true</P_17>"))
    }

    @Test("Brak faktur w okresie daje ostrzeżenie o wymogu XSD")
    func brakFaktur() {
        let result = JPKFAGenerator.generate(invoices: [], options: makeOptions())
        #expect(result.invoiceCount == 0)
        #expect(result.warnings.contains { $0.contains("co najmniej jednej faktury") })
    }

    // MARK: Sekcja Faktura — pola i stawki

    @Test("Faktura ma dane stron, daty i kwotę należności ogółem")
    func poleFaktury() {
        let sale = makeSale(saleDate: "2026-06-05")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<KodWaluty>PLN</KodWaluty>"))
        #expect(result.xml.contains("<P_1>2026-06-10</P_1>"))
        #expect(result.xml.contains("<P_3A>Kontrahent S.A.</P_3A>"))
        #expect(result.xml.contains("<P_3B>ul. Prosta 1, 00-001 Warszawa</P_3B>"))
        #expect(result.xml.contains("<P_3C>ACME Sp. z o.o.</P_3C>"))
        #expect(result.xml.contains("<P_3D>ul. Wesoła 12/3, 30-001 Kraków</P_3D>"))
        #expect(result.xml.contains("<P_4B>5260250274</P_4B>"))
        #expect(result.xml.contains("<P_5B>1111111111</P_5B>"))
        #expect(result.xml.contains("<P_6>2026-06-05</P_6>"))
        #expect(result.xml.contains("<P_15>123.00</P_15>"))
        #expect(result.xml.contains("<RodzajFaktury>VAT</RodzajFaktury>"))
    }

    @Test("Data sprzedaży równa dacie wystawienia nie tworzy P_6")
    func p6TylkoGdyInna() {
        let sale = makeSale(saleDate: "2026-06-10")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(!result.xml.contains("<P_6>"))
    }

    @Test("Pozycje per stawka trafiają do właściwych pól P_13_x/P_14_x")
    func stawki() {
        let sale = makeSale(lines: [
            line("Usługa 23%", net: 100, rate: "23", vat: 23),
            line("Towar 8%", net: 200, rate: "8", vat: 16),
            line("Towar 5%", net: 300, rate: "5", vat: 15),
            line("WDT 0%", net: 400, rate: "0", vat: 0),
            line("Zwolnione", net: 500, rate: "zw", vat: 0),
        ], net: 1500, vat: 54)
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_13_1>100.00</P_13_1>"))
        #expect(result.xml.contains("<P_14_1>23.00</P_14_1>"))
        #expect(result.xml.contains("<P_13_2>200.00</P_13_2>"))
        #expect(result.xml.contains("<P_14_2>16.00</P_14_2>"))
        #expect(result.xml.contains("<P_13_3>300.00</P_13_3>"))
        #expect(result.xml.contains("<P_14_3>15.00</P_14_3>"))
        #expect(result.xml.contains("<P_13_6>400.00</P_13_6>"))
        #expect(result.xml.contains("<P_13_7>500.00</P_13_7>"))
        // Sprzedaż zwolniona ustawia P_19 z ostrzeżeniem o braku podstawy.
        #expect(result.xml.contains("<P_19>true</P_19>"))
        #expect(result.warnings.contains { $0.contains("P_19A") })
    }

    @Test("Stawki historyczne 22, 7, 4 i 3 trafiają do właściwych koszyków")
    func stawkiHistoryczne() {
        let sale = makeSale(lines: [
            line("Stawka 22%", net: 100, rate: "22", vat: 22),
            line("Stawka 7%", net: 200, rate: "7", vat: 14),
            line("Stawka 4%", net: 300, rate: "4", vat: 12),
            line("Stawka 3%", net: 400, rate: "3", vat: 12),
        ], net: 1000, vat: 60)
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_13_1>100.00</P_13_1>"))
        #expect(result.xml.contains("<P_14_1>22.00</P_14_1>"))
        #expect(result.xml.contains("<P_13_2>200.00</P_13_2>"))
        #expect(result.xml.contains("<P_14_2>14.00</P_14_2>"))
        #expect(result.xml.contains("<P_13_4>700.00</P_13_4>"))
        #expect(result.xml.contains("<P_14_4>24.00</P_14_4>"))
        #expect(result.xml.contains("<P_18>false</P_18>"))
        #expect(!result.warnings.contains { $0.contains("nieznana stawka") })
    }

    @Test("Stawki oo i np mapują sumy faktury oraz znacznik odwrotnego obciążenia")
    func odwrotneObciazenieINiepodlegajace() {
        let sale = makeSale(lines: [
            line("Odwrotne obciążenie", net: 100, rate: "oo", vat: 0),
            line("Poza terytorium kraju", net: 200, rate: "np", vat: 0),
        ], net: 300, vat: 0)
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_13_4>100.00</P_13_4>"))
        #expect(result.xml.contains("<P_14_4>0.00</P_14_4>"))
        #expect(result.xml.contains("<P_13_5>200.00</P_13_5>"))
        #expect(!result.xml.contains("<P_14_5>"))
        #expect(result.xml.contains("<P_18>true</P_18>"))
        #expect(result.xml.contains("<P_12>oo</P_12>"))
        #expect(result.xml.contains("<P_12>np</P_12>"))
        #expect(!result.xml.contains("<P_13_1>"))
    }

    @Test("Faktura bez pozycji wchodzi kwotami jako stawka podstawowa z ostrzeżeniem")
    func fakturaBezPozycji() {
        let result = JPKFAGenerator.generate(invoices: [makeSale()], options: makeOptions())
        #expect(result.xml.contains("<P_13_1>100.00</P_13_1>"))
        #expect(result.xml.contains("<P_14_1>23.00</P_14_1>"))
        #expect(result.warnings.contains { $0.contains("brak pozycji") })
        #expect(result.lineCount == 0)
        #expect(result.warnings.contains { $0.contains("FakturaWiersz") })
    }

    @Test("Pozycja OSS idzie do P_13_5/P_14_5, a w wierszu do P_12_XII")
    func oss() {
        let sale = makeSale(lines: [
            line("Usługa OSS", net: 100, rate: "23", vat: 19, ossRate: 19),
        ], net: 100, vat: 19)
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_13_5>100.00</P_13_5>"))
        #expect(result.xml.contains("<P_14_5>19.00</P_14_5>"))
        #expect(result.xml.contains("<P_12_XII>19</P_12_XII>"))
        #expect(!result.xml.contains("<P_13_1>"))
    }

    @Test("Faktura walutowa ma kod waluty i podatek przeliczony w P_14_1W")
    func waluta() {
        let sale = makeSale(
            lines: [line("Usługa", net: 100, rate: "23", vat: 23)],
            net: 100, vat: 23, currency: "EUR", exchangeRate: 4.25
        )
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<KodWaluty>EUR</KodWaluty>"))
        #expect(result.xml.contains("<P_14_1W>97.75</P_14_1W>"))
    }

    @Test("Waluta obca bez kursu pomija pola W z ostrzeżeniem")
    func walutaBezKursu() {
        let sale = makeSale(
            lines: [line("Usługa", net: 100, rate: "23", vat: 23)],
            net: 100, vat: 23, currency: "EUR", exchangeRate: 0
        )
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(!result.xml.contains("P_14_1W"))
        #expect(result.warnings.contains { $0.contains("bez kursu") })
    }

    @Test("Mieszane waluty w pliku dają ostrzeżenie o sumach nominalnych")
    func mieszaneWaluty() {
        let result = JPKFAGenerator.generate(
            invoices: [
                makeSale(number: "FV/PLN"),
                makeSale(number: "FV/EUR", currency: "EUR", exchangeRate: 4.25),
            ],
            options: makeOptions()
        )
        #expect(result.currencies == ["EUR", "PLN"])
        #expect(result.warnings.contains { $0.contains("sumami nominalnymi") })
    }

    // MARK: Znaczniki i procedury

    @Test("MPP ustawia P_18A, a procedura marży biur podróży P_106E_2")
    func znaczniki() {
        let sale = makeSale(marginProcedure: "2", splitPayment: true)
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_18A>true</P_18A>"))
        #expect(result.xml.contains("<P_106E_2>true</P_106E_2>"))
        #expect(result.xml.contains("<P_106E_3>false</P_106E_3>"))
        #expect(result.xml.contains("<P_16>false</P_16>"))
        #expect(result.xml.contains("<P_18>false</P_18>"))
    }

    @Test("Procedura marży towarów używanych ustawia P_106E_3 z adnotacją")
    func marzaTowaryUzywane() {
        let sale = makeSale(marginProcedure: "3_1")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_106E_3>true</P_106E_3>"))
        #expect(result.xml.contains("<P_106E_3A>procedura marży - towary używane</P_106E_3A>"))
    }

    @Test("Adnotacje marży dla dzieł sztuki i antyków")
    func marzaEtykiety() {
        #expect(JPKFAGenerator.marginLabel("3_2") == "procedura marży - dzieła sztuki")
        #expect(JPKFAGenerator.marginLabel("3_3") == "procedura marży - przedmioty kolekcjonerskie i antyki")
        #expect(JPKFAGenerator.marginLabel("2") == "")
    }

    // MARK: Rodzaje dokumentów

    @Test("Korekta ma rodzaj KOREKTA z przyczyną i numerem faktury korygowanej")
    func korekta() {
        let sale = makeSale(
            number: "KOR/1", net: -100, vat: -23,
            documentType: "KOR",
            correctionReason: "Zwrot towaru",
            correctedInvoiceNumber: "FV/5/2026"
        )
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<RodzajFaktury>KOREKTA</RodzajFaktury>"))
        #expect(result.xml.contains("<PrzyczynaKorekty>Zwrot towaru</PrzyczynaKorekty>"))
        #expect(result.xml.contains("<NrFaKorygowanej>FV/5/2026</NrFaKorygowanej>"))
        // Kwoty różnicy zachowują znak.
        #expect(result.xml.contains("<P_15>-123.00</P_15>"))
    }

    @Test("Korekta bez numeru faktury korygowanej pomija sekwencję z ostrzeżeniem")
    func korektaBezNumeru() {
        let sale = makeSale(number: "KOR/2", documentType: "KOR")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(!result.xml.contains("<NrFaKorygowanej>"))
        #expect(result.warnings.contains { $0.contains("korekta bez numeru") })
    }

    @Test("Faktura rozliczająca (ROZ) to rodzaj VAT z numerami zaliczkowych")
    func rozliczajaca() {
        let sale = makeSale(
            number: "ROZ/1", documentType: "ROZ",
            advanceInvoiceRefs: ["6511111111-20260601-ABCDEF-01", "6511111111-20260602-ABCDEF-02"]
        )
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<RodzajFaktury>VAT</RodzajFaktury>"))
        #expect(result.xml.contains("<NrFaZaliczkowej>6511111111-20260601-ABCDEF-01, 6511111111-20260602-ABCDEF-02</NrFaZaliczkowej>"))
    }

    @Test("Faktura uproszczona (UPR) jest prezentowana jako rodzaj VAT")
    func uproszczona() {
        let sale = makeSale(number: "UPR/1", buyerName: "", buyerNIP: "", buyerAddress: "", documentType: "UPR")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<RodzajFaktury>VAT</RodzajFaktury>"))
        #expect(!result.xml.contains("<P_3A>"))
        #expect(!result.xml.contains("<P_5B>"))
    }

    // MARK: Faktury zaliczkowe — węzeł Zamowienie

    @Test("Faktura zaliczkowa idzie do węzła Zamowienie bez wierszy FakturaWiersz")
    func zaliczkowa() {
        let sale = makeSale(
            number: "ZAL/1",
            lines: [line("Zamówiony towar", net: 100, rate: "23", vat: 23, quantity: 2, unitPrice: 50)],
            net: 100, vat: 23,
            documentType: "ZAL"
        )
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<RodzajFaktury>ZAL</RodzajFaktury>"))
        #expect(!result.xml.contains("<FakturaWiersz>"))
        #expect(result.xml.contains("<P_2AZ>ZAL/1</P_2AZ>"))
        #expect(result.xml.contains("<WartoscZamowienia>123.00</WartoscZamowienia>"))
        #expect(result.xml.contains("<P_7Z>Zamówiony towar</P_7Z>"))
        #expect(result.xml.contains("<P_8BZ>2</P_8BZ>"))
        #expect(result.xml.contains("<P_9AZ>50.00</P_9AZ>"))
        #expect(result.xml.contains("<P_11NettoZ>100.00</P_11NettoZ>"))
        #expect(result.xml.contains("<P_11VatZ>23.00</P_11VatZ>"))
        #expect(result.xml.contains("<P_12Z>23</P_12Z>"))
        #expect(result.xml.contains("<LiczbaZamowien>1</LiczbaZamowien>"))
        #expect(result.xml.contains("<WartoscZamowien>123.00</WartoscZamowien>"))
        #expect(result.orderCount == 1)
        #expect(result.warnings.contains { $0.contains("wartość zamówienia") })
    }

    @Test("Korekta faktury zaliczkowej też prezentuje pozycje w Zamowieniu")
    func korektaZaliczkowej() {
        let sale = makeSale(
            number: "KOR_ZAL/1",
            lines: [line("Storno", net: -50, rate: "23", vat: -11.5)],
            net: -50, vat: -11.5,
            documentType: "KOR_ZAL",
            correctedInvoiceNumber: "ZAL/1"
        )
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<RodzajFaktury>KOREKTA</RodzajFaktury>"))
        #expect(!result.xml.contains("<FakturaWiersz>"))
        #expect(result.xml.contains("<P_11NettoZ>-50.00</P_11NettoZ>"))
        #expect(result.orderCount == 1)
    }

    @Test("Zaliczkowa bez pozycji dostaje wiersz zamówienia z kwotami łącznymi")
    func zaliczkowaBezPozycji() {
        let sale = makeSale(number: "ZAL/2", documentType: "ZAL")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<ZamowienieWiersz>"))
        #expect(result.xml.contains("<P_11NettoZ>100.00</P_11NettoZ>"))
        #expect(result.warnings.contains { $0.contains("zaliczkowy bez pozycji") })
    }

    @Test("Plik bez FakturaWiersz nie jest gotowy do eksportu zgodnego z XSD")
    func gotowoscSchemy() {
        let onlyAdvance = JPKFAGenerator.generate(
            invoices: [makeSale(number: "ZAL/1", documentType: "ZAL")],
            options: makeOptions()
        )
        #expect(!onlyAdvance.isSchemaReady)

        let regular = JPKFAGenerator.generate(
            invoices: [makeSale(lines: [line("Usługa", net: 100, rate: "23", vat: 23)])],
            options: makeOptions()
        )
        #expect(regular.isSchemaReady)
    }

    @Test("Gotowość opcji wymaga poprawnego NIP i niepustego pełnego adresu")
    func gotowoscOpcji() {
        #expect(makeOptions().isReadyForExport)

        var invalidNIP = makeOptions()
        invalidNIP.sellerNIP = "123"
        #expect(!invalidNIP.isReadyForExport)

        var blankAddress = makeOptions()
        blankAddress.gmina = "   "
        #expect(!blankAddress.isReadyForExport)
    }

    // MARK: Wiersze i sumy kontrolne

    @Test("Wiersze faktur mają numer, nazwę, ilość, cenę i stawkę")
    func wiersze() {
        let sale = makeSale(lines: [
            line("Usługa doradcza", net: 250, rate: "23", vat: 57.5, unit: "godz.", quantity: 2.5, unitPrice: 100),
        ], net: 250, vat: 57.5)
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_2B>FV/6/2026</P_2B>"))
        #expect(result.xml.contains("<P_7>Usługa doradcza</P_7>"))
        #expect(result.xml.contains("<P_8A>godz.</P_8A>"))
        #expect(result.xml.contains("<P_8B>2.5</P_8B>"))
        #expect(result.xml.contains("<P_9A>100.00</P_9A>"))
        #expect(result.xml.contains("<P_11>250.00</P_11>"))
        #expect(result.xml.contains("<P_12>23</P_12>"))
    }

    @Test("Sumy kontrolne liczą faktury (P_15) i wiersze (P_11)")
    func sumyKontrolne() {
        let invoices = [
            makeSale(number: "FV/1", lines: [line("A", net: 100, rate: "23", vat: 23)], net: 100, vat: 23),
            makeSale(number: "FV/2", lines: [
                line("B", net: 200, rate: "8", vat: 16),
                line("C", net: 50, rate: "23", vat: 11.5),
            ], net: 250, vat: 27.5),
        ]
        let result = JPKFAGenerator.generate(invoices: invoices, options: makeOptions())
        #expect(result.invoiceCount == 2)
        #expect(result.xml.contains("<LiczbaFaktur>2</LiczbaFaktur>"))
        #expect(result.xml.contains("<WartoscFaktur>400.50</WartoscFaktur>"))
        #expect(result.lineCount == 3)
        #expect(result.xml.contains("<LiczbaWierszyFaktur>3</LiczbaWierszyFaktur>"))
        #expect(result.xml.contains("<WartoscWierszyFaktur>350.00</WartoscWierszyFaktur>"))
        // Bez zaliczek nie ma sekcji zamówień.
        #expect(!result.xml.contains("<ZamowienieCtrl>"))
    }

    @Test("Stawka spoza słownika P_12 pomija pole stawki z ostrzeżeniem")
    func stawkaSpozaSlownika() {
        let sale = makeSale(lines: [
            line("RR historyczna", net: 100, rate: "6.5", vat: 6.5),
        ], net: 100, vat: 6.5)
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(!result.xml.contains("<P_12>6.5</P_12>"))
        #expect(result.warnings.contains { $0.contains("spoza słownika P_12") })
        // Kwoty trafiają do koszyka stawki obniżonej pierwszej.
        #expect(result.xml.contains("<P_13_2>100.00</P_13_2>"))
        #expect(result.warnings.contains { $0.contains("stawka VAT RR") })
    }

    // MARK: Identyfikatory podatkowe

    @Test("Prefiks UE nabywcy trafia do P_5A, numer bez prefiksu do P_5B")
    func nabywcaUE() {
        let sale = makeSale(buyerNIP: "DE123456789")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_5A>DE</P_5A>"))
        #expect(result.xml.contains("<P_5B>123456789</P_5B>"))
    }

    @Test("Prefiks GR jest normalizowany do EL (Grecja w słowniku UE)")
    func grecja() {
        let sale = makeSale(buyerNIP: "GR123456789")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_5A>EL</P_5A>"))
    }

    @Test("Prefiks PL jest zdejmowany — krajowy numer bez P_5A")
    func prefiksPL() {
        let sale = makeSale(buyerNIP: "PL1111111111")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(!result.xml.contains("<P_5A>"))
        #expect(result.xml.contains("<P_5B>1111111111</P_5B>"))
    }

    @Test("Rozbiór identyfikatora: separatory, prefiks spoza UE i pusty numer")
    func taxIdentifier() {
        let dashed = JPKFAGenerator.taxIdentifier("526-025-02-74")
        #expect(dashed.prefix == nil && dashed.number == "5260250274")
        let unknown = JPKFAGenerator.taxIdentifier("US123456")
        #expect(unknown.prefix == nil && unknown.number == "US123456")
        let empty = JPKFAGenerator.taxIdentifier("  ")
        #expect(empty.prefix == nil && empty.number == nil)
        let bareprefix = JPKFAGenerator.taxIdentifier("DE")
        #expect(bareprefix.prefix == nil && bareprefix.number == nil)
    }

    @Test("Brak adresu sprzedawcy daje BRAK z ostrzeżeniem")
    func brakAdresuSprzedawcy() {
        let sale = makeSale(sellerAddress: "")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_3D>BRAK</P_3D>"))
        #expect(result.warnings.contains { $0.contains("brak adresu sprzedawcy") })
    }

    @Test("Brak nazwy sprzedawcy daje BRAK z ostrzeżeniem")
    func brakNazwySprzedawcy() {
        let sale = makeSale(sellerName: "")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_3C>BRAK</P_3C>"))
        #expect(result.warnings.contains { $0.contains("brak nazwy sprzedawcy") })
    }

    // MARK: Formatowanie i znaki specjalne

    @Test("Ilości i stawki procentowe są przycinane bez zbędnych zer")
    func formatowanie() {
        #expect(JPKFAGenerator.quantity(2.5) == "2.5")
        #expect(JPKFAGenerator.quantity(1) == "1")
        #expect(JPKFAGenerator.quantity(0.123456) == "0.123456")
        #expect(JPKFAGenerator.percent(19) == "19")
        #expect(JPKFAGenerator.percent(21.5) == "21.5")
    }

    @Test("Znaki specjalne XML w danych są poprawnie kodowane")
    func escapowanie() {
        let sale = makeSale(buyerName: "Firma \"A&B\" <Sp. j.>")
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_3A>Firma &quot;A&amp;B&quot; &lt;Sp. j.&gt;</P_3A>"))
    }

    @Test("Pola znakowe są przycinane do limitu 256 znaków")
    func przyciecie() {
        let longName = String(repeating: "x", count: 300)
        let sale = makeSale(buyerName: longName)
        let result = JPKFAGenerator.generate(invoices: [sale], options: makeOptions())
        #expect(result.xml.contains("<P_3A>\(String(repeating: "x", count: 256))</P_3A>"))
        #expect(!result.xml.contains(longName))
    }

    @Test("Faktury są sortowane po dacie wystawienia, a przy równej po numerze")
    func sortowanie() {
        let invoices = [
            makeSale(number: "FV/B", issue: "2026-06-20"),
            makeSale(number: "FV/A", issue: "2026-06-20"),
            makeSale(number: "FV/C", issue: "2026-06-01"),
        ]
        let result = JPKFAGenerator.generate(invoices: invoices, options: makeOptions())
        let posC = result.xml.range(of: "<P_2A>FV/C</P_2A>")!.lowerBound
        let posA = result.xml.range(of: "<P_2A>FV/A</P_2A>")!.lowerBound
        let posB = result.xml.range(of: "<P_2A>FV/B</P_2A>")!.lowerBound
        #expect(posC < posA && posA < posB)
    }
}
