import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Pomocnicze

private func makeOptions(year: Int = 2026, month: Int = 6) -> VATUEOptions {
    VATUEOptions(
        year: year, month: month,
        sellerNIP: "526-025-02-74",
        sellerName: "ACME Sp. z o.o.",
        taxOfficeCode: "1219"
    )
}

/// Pozycja: same cyfry (CN) → towar; kod z kropkami (PKWiU) → usługa.
private func line(_ idx: Int, net: Double, code: String, oss: Double? = nil) -> InvoiceLine {
    InvoiceLine(
        index: idx, name: "Pozycja \(idx)", netAmount: net,
        vatRate: "0", vatAmount: 0, cnPkwiu: code, ossRate: oss
    )
}

private func goods(_ idx: Int, net: Double) -> InvoiceLine { line(idx, net: net, code: "85234910") }
private func service(_ idx: Int, net: Double) -> InvoiceLine { line(idx, net: net, code: "62.01.11.0") }

private func euSale(
    number: String = "FV/6/2026",
    buyerNIP: String = "DE123456789",
    lines: [InvoiceLine] = [],
    issue: String = "2026-06-10",
    saleDate: String? = nil,
    net: Double = 100,
    currency: String = "PLN",
    exchangeRate: Double = 0,
    documentType: String = "VAT",
    hidden: Bool = false
) -> Invoice {
    let invoice = Invoice(
        invoiceNumber: number,
        issueDate: FA2Format.dateFormatter.date(from: issue)!,
        sellerName: "ACME Sp. z o.o.", sellerNIP: "5260250274",
        buyerName: "Kontrahent GmbH", buyerNIP: buyerNIP,
        netAmount: net, vatAmount: 0, grossAmount: net,
        isArchivedOrHidden: hidden,
        documentType: documentType,
        currency: currency,
        exchangeRate: exchangeRate,
        saleDate: saleDate.flatMap { FA2Format.dateFormatter.date(from: $0) },
        kind: .sales
    )
    invoice.lines = lines
    return invoice
}

private func euPurchase(
    number: String = "Z/6/2026",
    sellerNIP: String = "CZ1234567890",
    lines: [InvoiceLine] = [],
    issue: String = "2026-06-15",
    net: Double = 200,
    documentType: String = "VAT"
) -> Invoice {
    let invoice = Invoice(
        invoiceNumber: number,
        issueDate: FA2Format.dateFormatter.date(from: issue)!,
        sellerName: "Dodavatel s.r.o.", sellerNIP: sellerNIP,
        buyerName: "ACME", buyerNIP: "5260250274",
        netAmount: net, vatAmount: 0, grossAmount: net,
        documentType: documentType,
        kind: .purchase
    )
    invoice.lines = lines
    return invoice
}

// MARK: - Testy

@Suite("VAT-UE — informacja podsumowująca")
struct VATUEGeneratorTests {

    @Test("WDT: sprzedaż towarów do UE → Grupa1 z krajem, numerem VAT i kwotą; P_Dd=1")
    func wdtGoods() {
        let invoice = euSale(buyerNIP: "DE123456789", lines: [goods(1, net: 10000)])
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())

        #expect(result.wdt == [VATUEEntry(countryCode: "DE", vatNumber: "123456789", amountPLN: 10000)])
        #expect(result.wnt.isEmpty)
        #expect(result.services.isEmpty)
        #expect(result.xml.contains("<Grupa1>"))
        #expect(result.xml.contains("<P_Da>DE</P_Da>"))
        #expect(result.xml.contains("<P_Db>123456789</P_Db>"))
        #expect(result.xml.contains("<P_Dc>10000</P_Dc>"))
        #expect(result.xml.contains("<P_Dd>1</P_Dd>"))
        #expect(result.totalWDT == 10000)
    }

    @Test("Usługi UE: sprzedaż usług (PKWiU) → Grupa3 (część E)")
    func services() {
        let invoice = euSale(buyerNIP: "FR12345678901", lines: [service(1, net: 5000)])
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())

        #expect(result.services == [VATUEEntry(countryCode: "FR", vatNumber: "12345678901", amountPLN: 5000)])
        #expect(result.totalServices == 5000)
        #expect(result.wdt.isEmpty)
        #expect(result.xml.contains("<Grupa3>"))
        #expect(result.xml.contains("<P_Ua>FR</P_Ua>"))
        #expect(result.xml.contains("<P_Ub>12345678901</P_Ub>"))
        #expect(result.xml.contains("<P_Uc>5000</P_Uc>"))
        #expect(!result.xml.contains("<P_Ud>")) // usługi bez flagi trójstronnej
    }

    @Test("WNT: zakup towarów z UE → Grupa2 (część D); P_Nd=1")
    func wntGoods() {
        let invoice = euPurchase(sellerNIP: "CZ1234567890", lines: [goods(1, net: 8000)])
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())

        #expect(result.wnt == [VATUEEntry(countryCode: "CZ", vatNumber: "1234567890", amountPLN: 8000)])
        #expect(result.xml.contains("<Grupa2>"))
        #expect(result.xml.contains("<P_Na>CZ</P_Na>"))
        #expect(result.xml.contains("<P_Nb>1234567890</P_Nb>"))
        #expect(result.xml.contains("<P_Nc>8000</P_Nc>"))
        #expect(result.xml.contains("<P_Nd>1</P_Nd>"))
        #expect(result.totalWNT == 8000)
    }

    @Test("Import usług z UE nie jest wykazywany w VAT-UE — pominięty z ostrzeżeniem")
    func importOfServicesSkipped() {
        let invoice = euPurchase(sellerNIP: "DE123456789", lines: [service(1, net: 3000)])
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())

        #expect(result.isEmpty)
        #expect(result.warnings.contains { $0.contains("import usług") })
    }

    @Test("Kontrahent krajowy (same cyfry) i spoza UE (np. CH) są pomijani")
    func domesticAndNonEUExcluded() {
        let domestic = euSale(number: "A", buyerNIP: "1111111111", lines: [goods(1, net: 100)])
        let swiss = euSale(number: "B", buyerNIP: "CHE123456789", lines: [goods(1, net: 200)])
        let result = VATUEGenerator.generate(invoices: [domestic, swiss], options: makeOptions())
        #expect(result.isEmpty)
    }

    @Test("Grecki prefiks GR jest normalizowany do EL")
    func greeceNormalization() {
        let invoice = euSale(buyerNIP: "GR123456789", lines: [goods(1, net: 1000)])
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())
        #expect(result.wdt.first?.countryCode == "EL")
        #expect(result.xml.contains("<P_Da>EL</P_Da>"))
    }

    @Test("Irlandia Płn. (XI): towary → WDT, usługi → pominięte (XI tylko dla towarów)")
    func northernIreland() {
        let goodsSale = euSale(number: "G", buyerNIP: "XI123456789", lines: [goods(1, net: 1000)])
        let serviceSale = euSale(number: "S", buyerNIP: "XI123456789", lines: [service(1, net: 500)])
        let result = VATUEGenerator.generate(invoices: [goodsSale, serviceSale], options: makeOptions())

        #expect(result.wdt == [VATUEEntry(countryCode: "XI", vatNumber: "123456789", amountPLN: 1000)])
        #expect(result.services.isEmpty)
        #expect(result.warnings.contains { $0.contains("XI") && $0.contains("usługi") })
    }

    @Test("Faktura mieszana: towary → WDT, usługi → część E dla tego samego kontrahenta")
    func mixedInvoice() {
        let invoice = euSale(buyerNIP: "DE123456789", lines: [
            goods(1, net: 700),
            service(2, net: 300),
        ])
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())
        #expect(result.wdt.first?.amountPLN == 700)
        #expect(result.services.first?.amountPLN == 300)
    }

    @Test("Agregacja per kontrahent i sortowanie po kraju, potem numerze VAT")
    func aggregationAndSorting() {
        let de1a = euSale(number: "1", buyerNIP: "DE111111111", lines: [goods(1, net: 100)])
        let de1b = euSale(number: "2", buyerNIP: "DE111111111", lines: [goods(1, net: 250)])
        let de2 = euSale(number: "3", buyerNIP: "DE222222222", lines: [goods(1, net: 50)])
        let cz = euSale(number: "4", buyerNIP: "CZ999999999", lines: [goods(1, net: 30)])
        let result = VATUEGenerator.generate(invoices: [de1a, de1b, de2, cz], options: makeOptions())

        // Ten sam kontrahent zsumowany.
        #expect(result.wdt.contains(VATUEEntry(countryCode: "DE", vatNumber: "111111111", amountPLN: 350)))
        // Kolejność: CZ przed DE, w obrębie DE rosnąco po numerze.
        #expect(result.wdt.map(\.countryCode).first == "CZ")
        let deEntries = result.wdt.filter { $0.countryCode == "DE" }
        #expect(deEntries.map(\.vatNumber) == ["111111111", "222222222"])
    }

    @Test("Kwoty zaokrąglane do pełnych złotych (suma, potem zaokrąglenie)")
    func wholeZlotyRounding() {
        let downSale = euSale(number: "D", buyerNIP: "DE111111111", lines: [goods(1, net: 100.49)])
        let upSale = euSale(number: "U", buyerNIP: "DE222222222", lines: [goods(1, net: 100.51)])
        let result = VATUEGenerator.generate(invoices: [downSale, upSale], options: makeOptions())
        #expect(result.wdt.first(where: { $0.vatNumber == "111111111" })?.amountPLN == 100)
        #expect(result.wdt.first(where: { $0.vatNumber == "222222222" })?.amountPLN == 101)
    }

    @Test("Brak pozycji → całość jako towary (WDT) z ostrzeżeniem")
    func noLinesFallback() {
        let invoice = euSale(buyerNIP: "DE123456789", lines: [], net: 4200)
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())
        #expect(result.wdt.first?.amountPLN == 4200)
        #expect(result.warnings.contains { $0.contains("brak pozycji") })
    }

    @Test("Pozycja bez kodu CN/PKWiU → towary z ostrzeżeniem")
    func unknownCodeFallback() {
        let invoice = euSale(buyerNIP: "DE123456789", lines: [line(1, net: 900, code: "")])
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())
        #expect(result.wdt.first?.amountPLN == 900)
        #expect(result.warnings.contains { $0.contains("bez kodu CN/PKWiU") })
    }

    @Test("Pozycje OSS pominięte z ostrzeżeniem (procedura OSS poza VAT-UE)")
    func ossSkipped() {
        let invoice = euSale(buyerNIP: "DE123456789", lines: [
            goods(1, net: 500),
            line(2, net: 200, code: "85234910", oss: 19),
        ])
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())
        #expect(result.wdt.first?.amountPLN == 500) // bez pozycji OSS
        #expect(result.warnings.contains { $0.contains("OSS") })
    }

    @Test("Faktura walutowa przeliczana po kursie z faktury")
    func currencyConversion() {
        let invoice = euSale(
            buyerNIP: "DE123456789", lines: [goods(1, net: 1000)],
            currency: "EUR", exchangeRate: 4.0
        )
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())
        #expect(result.wdt.first?.amountPLN == 4000)
    }

    @Test("Okres: decyduje data sprzedaży, inaczej wystawienia; ukryte pomijane")
    func periodFiltering() {
        let inBySale = euSale(number: "A", buyerNIP: "DE111111111", lines: [goods(1, net: 100)], issue: "2026-07-01", saleDate: "2026-06-30")
        let outOfPeriod = euSale(number: "B", buyerNIP: "DE222222222", lines: [goods(1, net: 200)], issue: "2026-05-31")
        let hidden = euSale(number: "C", buyerNIP: "DE333333333", lines: [goods(1, net: 300)], issue: "2026-06-10", hidden: true)
        let result = VATUEGenerator.generate(invoices: [inBySale, outOfPeriod, hidden], options: makeOptions())
        #expect(result.wdt == [VATUEEntry(countryCode: "DE", vatNumber: "111111111", amountPLN: 100)])
    }

    @Test("Korekta: ostrzeżenie o korektach oraz o wartości ujemnej")
    func corrections() {
        let kor = euSale(
            number: "KOR/1", buyerNIP: "DE123456789",
            lines: [goods(1, net: -500)], documentType: "KOR"
        )
        let result = VATUEGenerator.generate(invoices: [kor], options: makeOptions())
        #expect(result.wdt.first?.amountPLN == -500)
        #expect(result.xml.contains("<P_Dc>-500</P_Dc>"))
        #expect(result.warnings.contains { $0.contains("korygując") })
        #expect(result.warnings.contains { $0.contains("ujemn") })
    }

    @Test("Zerowa suma per kontrahent → wiersz pomijany")
    func zeroSumOmitted() {
        let plus = euSale(number: "P", buyerNIP: "DE123456789", lines: [goods(1, net: 500)])
        let minus = euSale(number: "M", buyerNIP: "DE123456789", lines: [goods(1, net: -500)], documentType: "KOR")
        let result = VATUEGenerator.generate(invoices: [plus, minus], options: makeOptions())
        #expect(result.wdt.isEmpty)
        #expect(!result.xml.contains("<Grupa1>"))
    }

    @Test("Numer VAT dłuższy niż 12 znaków → ostrzeżenie")
    func tooLongVATNumber() {
        let invoice = euSale(buyerNIP: "DE1234567890123", lines: [goods(1, net: 100)])
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())
        #expect(result.warnings.contains { $0.contains("12 znaków") })
    }

    @Test("Dokument jest poprawnym XML z wymaganymi elementami nagłówka i podmiotu")
    func headerAndWellFormed() {
        let invoice = euSale(buyerNIP: "DE123456789", lines: [goods(1, net: 1000)])
        let result = VATUEGenerator.generate(invoices: [invoice], options: makeOptions())

        #expect(result.xml.contains(#"kodSystemowy="VAT-UE (5)""#))
        #expect(result.xml.contains(#"wersjaSchemy="2-0E""#))
        #expect(result.xml.contains("<WariantFormularza>5</WariantFormularza>"))
        #expect(result.xml.contains("<CelZlozenia>1</CelZlozenia>"))
        #expect(result.xml.contains("<KodUrzedu>1219</KodUrzedu>"))
        #expect(result.xml.contains("<Rok>2026</Rok>"))
        #expect(result.xml.contains("<Miesiac>6</Miesiac>"))
        #expect(result.xml.contains("<etd:NIP>5260250274</etd:NIP>"))
        #expect(result.xml.contains("<etd:PelnaNazwa>ACME Sp. z o.o.</etd:PelnaNazwa>"))
        #expect(result.xml.contains("<Pouczenie>1</Pouczenie>"))
        #expect(result.xml.contains(#"xmlns="http://crd.gov.pl/wzor/2021/01/12/10293/""#))
        #expect((try? XMLDocument(data: Data(result.xml.utf8), options: [])) != nil)
    }

    @Test("Brak transakcji UE → dokument pusty, ale nadal poprawny XML")
    func emptyButWellFormed() {
        let domestic = euSale(buyerNIP: "1111111111", lines: [goods(1, net: 100)])
        let result = VATUEGenerator.generate(invoices: [domestic], options: makeOptions())
        #expect(result.isEmpty)
        #expect(!result.xml.contains("<Grupa1>"))
        #expect(result.xml.contains("<PozycjeSzczegolowe>"))
        #expect((try? XMLDocument(data: Data(result.xml.utf8), options: [])) != nil)
    }

    // MARK: Funkcje pomocnicze generatora

    @Test("parseCounterparty: prefiks kraju, normalizacja separatorów, odrzucanie krajowych")
    func parseCounterpartyCases() {
        #expect(VATUEGenerator.parseCounterparty("5260250274") == nil)          // krajowy
        #expect(VATUEGenerator.parseCounterparty("DE") == nil)                   // za krótki
        #expect(VATUEGenerator.parseCounterparty("D1234") == nil)               // prefiks nie-literowy
        let de = VATUEGenerator.parseCounterparty("de 123-456-789")
        #expect(de?.country == "DE")
        #expect(de?.vat == "123456789")
    }

    @Test("classify: CN → towar, PKWiU (z kropkami) → usługa, pusty → nierozstrzygnięty")
    func classifyCases() {
        #expect(VATUEGenerator.classify("85234910") == .goods)
        #expect(VATUEGenerator.classify("62.01.11.0") == .service)
        #expect(VATUEGenerator.classify("") == .unknown)
        #expect(VATUEGenerator.classify("   ") == .unknown)
        #expect(VATUEGenerator.classify("USLUGA") == .unknown) // bez kropki i bez cyfr
    }
}
