import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Pomocnicze

private func makeOptions(includeDeclaration: Bool = true, previousExcess: Int = 0) -> JPKV7Options {
    JPKV7Options(
        year: 2026, month: 6,
        sellerNIP: "526-025-02-74",
        sellerName: "ACME Sp. z o.o.",
        email: "biuro@acme.pl",
        taxOfficeCode: "1219",
        previousExcess: previousExcess,
        includeDeclaration: includeDeclaration
    )
}

private func makeSale(
    number: String = "FV/6/2026",
    issue: String = "2026-06-10",
    saleDate: String? = nil,
    buyerNIP: String = "1111111111",
    lines: [InvoiceLine] = [],
    net: Double = 100,
    vat: Double = 23,
    currency: String = "PLN",
    exchangeRate: Double = 0,
    marginProcedure: String = "",
    hidden: Bool = false
) -> Invoice {
    let invoice = Invoice(
        invoiceNumber: number,
        issueDate: FA2Format.dateFormatter.date(from: issue)!,
        sellerName: "ACME Sp. z o.o.", sellerNIP: "5260250274",
        buyerName: "Kontrahent S.A.", buyerNIP: buyerNIP,
        netAmount: net, vatAmount: vat, grossAmount: net + vat,
        isArchivedOrHidden: hidden,
        currency: currency,
        exchangeRate: exchangeRate,
        saleDate: saleDate.flatMap { FA2Format.dateFormatter.date(from: $0) },
        marginProcedure: marginProcedure,
        kind: .sales
    )
    invoice.lines = lines
    return invoice
}

private func makePurchase(
    number: String = "Z/6/2026",
    issue: String = "2026-06-15",
    net: Double = 200,
    vat: Double = 46
) -> Invoice {
    Invoice(
        invoiceNumber: number,
        issueDate: FA2Format.dateFormatter.date(from: issue)!,
        sellerName: "Dostawca", sellerNIP: "9999999999",
        buyerName: "ACME", buyerNIP: "5260250274",
        netAmount: net, vatAmount: vat, grossAmount: net + vat,
        kind: .purchase
    )
}

private func line(
    _ name: String, net: Double, rate: String, vat: Double,
    gtu: String = "", procedure: String = "", ossRate: Double? = nil
) -> InvoiceLine {
    InvoiceLine(
        index: 1, name: name, netAmount: net, vatRate: rate, vatAmount: vat,
        gtu: gtu, procedure: procedure, ossRate: ossRate
    )
}

// MARK: - Testy

@Suite("JPK_V7M — ewidencja VAT i deklaracja")
struct JPKV7GeneratorTests {

    @Test("Wiersz sprzedaży: stawki trafiają do właściwych pól K, GTU i procedury jako znaczniki")
    func salesRowMapping() {
        let invoice = makeSale(lines: [
            line("Usługa 23%", net: 100, rate: "23", vat: 23, gtu: "GTU_12"),
            line("Towar 8%", net: 50, rate: "8", vat: 4, gtu: "06"),
            line("Towar 5%", net: 20, rate: "5", vat: 1),
            line("Towar 0%", net: 10, rate: "0", vat: 0),
            line("Usługa zw.", net: 5, rate: "zw", vat: 0, procedure: "TT_D"),
        ])
        let result = JPKV7Generator.generate(invoices: [invoice], options: makeOptions())

        #expect(result.salesCount == 1)
        #expect(result.xml.contains("<K_19>100.00</K_19>"))
        #expect(result.xml.contains("<K_20>23.00</K_20>"))
        #expect(result.xml.contains("<K_17>50.00</K_17>"))
        #expect(result.xml.contains("<K_18>4.00</K_18>"))
        #expect(result.xml.contains("<K_15>20.00</K_15>"))
        #expect(result.xml.contains("<K_16>1.00</K_16>"))
        #expect(result.xml.contains("<K_13>10.00</K_13>"))
        #expect(result.xml.contains("<K_10>5.00</K_10>"))
        #expect(result.xml.contains("<GTU_12>1</GTU_12>"))
        #expect(result.xml.contains("<GTU_06>1</GTU_06>")) // znormalizowane z "06"
        #expect(result.xml.contains("<TT_D>1</TT_D>"))
        #expect(result.xml.contains("<NrKontrahenta>1111111111</NrKontrahenta>"))
        #expect(result.xml.contains("<PodatekNalezny>28.00</PodatekNalezny>"))
        #expect(result.outputVAT == 28.00)
    }

    @Test("Zakupy w całości jako pozostałe nabycia (K_42/K_43)")
    func purchaseRow() {
        let result = JPKV7Generator.generate(
            invoices: [makePurchase()], options: makeOptions()
        )
        #expect(result.purchaseCount == 1)
        #expect(result.xml.contains("<K_42>200.00</K_42>"))
        #expect(result.xml.contains("<K_43>46.00</K_43>"))
        #expect(result.xml.contains("<NrDostawcy>9999999999</NrDostawcy>"))
        #expect(result.xml.contains("<PodatekNaliczony>46.00</PodatekNaliczony>"))
    }

    @Test("Deklaracja: P_38 z należnego, P_51 do wpłaty (pełne złote, nieujemna)")
    func declarationDue() {
        let sale = makeSale(lines: [line("Usługa", net: 1000.49, rate: "23", vat: 230.11)])
        let purchase = makePurchase(net: 100, vat: 23)
        let result = JPKV7Generator.generate(
            invoices: [sale, purchase], options: makeOptions()
        )
        #expect(result.xml.contains("<P_19>1000</P_19>")) // zaokrąglenie do zł
        #expect(result.xml.contains("<P_20>230</P_20>"))
        #expect(result.xml.contains("<P_38>230</P_38>"))
        #expect(result.xml.contains("<P_43>23</P_43>"))
        #expect(result.xml.contains("<P_48>23</P_48>"))
        #expect(result.xml.contains("<P_51>207</P_51>"))
        #expect(result.amountDue == 207)
        #expect(result.xml.contains("<Pouczenia>1</Pouczenia>"))
    }

    @Test("Nadwyżka naliczonego: P_51 = 0, kwota przechodzi do P_53/P_62")
    func declarationExcess() {
        let sale = makeSale(lines: [line("Usługa", net: 100, rate: "23", vat: 23)])
        let purchase = makePurchase(net: 1000, vat: 230)
        let result = JPKV7Generator.generate(
            invoices: [sale, purchase], options: makeOptions(previousExcess: 10)
        )
        #expect(result.xml.contains("<P_39>10</P_39>"))
        #expect(result.xml.contains("<P_51>0</P_51>"))
        #expect(result.xml.contains("<P_53>217</P_53>")) // 230+10−23
        #expect(result.xml.contains("<P_62>217</P_62>"))
        #expect(result.excessCarried == 217)
    }

    @Test("Pozycje OSS pominięte z ostrzeżeniem; brak NIP nabywcy → „BRAK”")
    func ossAndMissingNIP() {
        let invoice = makeSale(buyerNIP: "", lines: [
            line("Krajowa", net: 100, rate: "23", vat: 23),
            line("OSS DE", net: 50, rate: "23", vat: 9.5, ossRate: 19),
        ])
        let result = JPKV7Generator.generate(invoices: [invoice], options: makeOptions())

        #expect(result.xml.contains("<K_19>100.00</K_19>")) // bez pozycji OSS
        #expect(result.xml.contains("<NrKontrahenta>BRAK</NrKontrahenta>"))
        #expect(result.warnings.contains { $0.contains("OSS") })
        #expect(result.warnings.contains { $0.contains("BRAK") })
    }

    @Test("Okres: decyduje data sprzedaży (P_6), inaczej data wystawienia; ukryte pomijane")
    func periodFiltering() {
        let inPeriodBySale = makeSale(number: "A", issue: "2026-07-01", saleDate: "2026-06-30")
        let outOfPeriod = makeSale(number: "B", issue: "2026-05-31")
        let hidden = makeSale(number: "C", issue: "2026-06-10", hidden: true)
        let result = JPKV7Generator.generate(
            invoices: [inPeriodBySale, outOfPeriod, hidden], options: makeOptions()
        )
        #expect(result.salesCount == 1)
        #expect(result.xml.contains("<DowodSprzedazy>A</DowodSprzedazy>"))
        #expect(result.xml.contains("<DataSprzedazy>2026-06-30</DataSprzedazy>"))
    }

    @Test("Faktura walutowa przeliczana po kursie z faktury")
    func currencyConversion() {
        let invoice = makeSale(
            lines: [line("Usługa EUR", net: 100, rate: "23", vat: 23)],
            currency: "EUR", exchangeRate: 4.0
        )
        let result = JPKV7Generator.generate(invoices: [invoice], options: makeOptions())
        #expect(result.xml.contains("<K_19>400.00</K_19>"))
        #expect(result.xml.contains("<K_20>92.00</K_20>"))
    }

    @Test("Dokument jest poprawnym XML i zawiera wymagane elementy nagłówka")
    func headerAndWellFormed() {
        let result = JPKV7Generator.generate(
            invoices: [makeSale(), makePurchase()], options: makeOptions()
        )
        #expect(result.xml.contains(#"kodSystemowy="JPK_V7M (2)""#))
        #expect(result.xml.contains("<WariantFormularza>2</WariantFormularza>"))
        #expect(result.xml.contains("<KodUrzedu>1219</KodUrzedu>"))
        #expect(result.xml.contains("<Rok>2026</Rok>"))
        #expect(result.xml.contains("<Miesiac>6</Miesiac>"))
        #expect(result.xml.contains("<NIP>5260250274</NIP>"))
        #expect(result.xml.contains(#"kodSystemowy="VAT-7 (22)""#))
        #expect((try? XMLDocument(data: Data(result.xml.utf8), options: [])) != nil)
    }

    @Test("Korekta samej ewidencji — bez części deklaracyjnej")
    func withoutDeclaration() {
        let result = JPKV7Generator.generate(
            invoices: [makeSale()], options: makeOptions(includeDeclaration: false)
        )
        #expect(!result.xml.contains("<Deklaracja>"))
        #expect(result.xml.contains("<Ewidencja>"))
    }
}
