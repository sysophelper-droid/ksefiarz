import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Pomocnicze

private func makeOptions(
    variant: JPKV7Variant = .monthly,
    year: Int = 2026,
    month: Int = 6,
    includeDeclaration: Bool = true,
    previousExcess: Int = 0
) -> JPKV7Options {
    JPKV7Options(
        variant: variant,
        year: year, month: month,
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
        #expect(result.xml.contains(#"kodSystemowy="JPK_V7M (3)""#))
        #expect(result.xml.contains("http://crd.gov.pl/wzor/2025/12/19/14090/"))
        #expect(result.xml.contains("<WariantFormularza>3</WariantFormularza>"))
        #expect(result.xml.contains("<KodUrzedu>1219</KodUrzedu>"))
        #expect(result.xml.contains("<Rok>2026</Rok>"))
        #expect(result.xml.contains("<Miesiac>6</Miesiac>"))
        #expect(result.xml.contains("<NIP>5260250274</NIP>"))
        #expect(result.xml.contains(#"kodSystemowy="VAT-7 (23)""#))
        #expect(result.xml.contains("<WariantFormularzaDekl>23</WariantFormularzaDekl>"))
        #expect(result.xml.contains("<BFK>1</BFK>"))
        #expect((try? XMLDocument(data: Data(result.xml.utf8), options: [])) != nil)
    }

    @Test("Okres do stycznia 2026 zachowuje historyczną schemę JPK_V7M(2)")
    func historicalMonthlySchema() {
        let invoice = makeSale(number: "FV/1/2026", issue: "2026-01-10")
        let result = JPKV7Generator.generate(
            invoices: [invoice], options: makeOptions(year: 2026, month: 1)
        )
        #expect(result.xml.contains(#"kodSystemowy="JPK_V7M (2)""#))
        #expect(result.xml.contains("http://crd.gov.pl/wzor/2021/12/27/11148/"))
        #expect(result.xml.contains(#"kodSystemowy="VAT-7 (22)""#))
        #expect(!result.xml.contains("<BFK>"))
    }

    @Test("Schemat (3) wskazuje numer KSeF albo właściwy znacznik dokumentu")
    func ksefMarkers() {
        let accepted = makeSale(number: "KSEF", issue: "2026-06-01")
        accepted.ksefId = "5260250274-20260601-ABCDEF-ABCDEF-12"
        let offline24 = makeSale(number: "OFFLINE24", issue: "2026-06-02")
        offline24.isOfflineMode = true
        offline24.offlineReason = .offline24
        let failure = makeSale(number: "AWARIA", issue: "2026-06-03")
        failure.isOfflineMode = true
        failure.offlineReason = .failure
        let regular = makePurchase(number: "PAPIER", issue: "2026-06-04")

        let result = JPKV7Generator.generate(
            invoices: [accepted, offline24, failure, regular], options: makeOptions()
        )

        #expect(result.xml.contains("<NrKSeF>5260250274-20260601-ABCDEF-ABCDEF-12</NrKSeF>"))
        #expect(result.xml.contains("<DI>1</DI>"))
        #expect(result.xml.contains("<OFF>1</OFF>"))
        #expect(result.xml.contains("<BFK>1</BFK>"))
    }

    @Test("Korekta samej ewidencji — bez części deklaracyjnej")
    func withoutDeclaration() {
        let result = JPKV7Generator.generate(
            invoices: [makeSale()], options: makeOptions(includeDeclaration: false)
        )
        #expect(!result.xml.contains("<Deklaracja>"))
        #expect(result.xml.contains("<Ewidencja>"))
        #expect(result.hasDeclaration == false)
    }

    @Test("Wariant miesięczny: pola deklaracji równe podatkowi miesiąca")
    func monthlyDeclarationTotals() {
        let sale = makeSale(lines: [line("Usługa", net: 1000, rate: "23", vat: 230)])
        let purchase = makePurchase(net: 500, vat: 115)
        let result = JPKV7Generator.generate(invoices: [sale, purchase], options: makeOptions())
        #expect(result.hasDeclaration)
        #expect(result.declarationOutputVAT == 230)
        #expect(result.declarationInputVAT == 115)
    }
}

// MARK: - JPK_V7K (wariant kwartalny)

@Suite("JPK_V7K — wariant kwartalny (ewidencja co miesiąc, deklaracja za kwartał)")
struct JPKV7KGeneratorTests {

    @Test("Ostatni miesiąc kwartału: nagłówek V7K(3), deklaracja VAT-7K(17) z elementem Kwartal")
    func quarterEndHeader() {
        // Czerwiec = ostatni miesiąc II kwartału.
        let result = JPKV7Generator.generate(
            invoices: [makeSale(lines: [line("Usługa", net: 1000, rate: "23", vat: 230)])],
            options: makeOptions(variant: .quarterly, month: 6)
        )
        #expect(result.xml.contains(#"kodSystemowy="JPK_V7K (3)""#))
        #expect(result.xml.contains("http://crd.gov.pl/wzor/2025/12/19/14089/"))
        #expect(result.xml.contains(#"kodSystemowy="VAT-7K (17)""#))
        #expect(result.xml.contains(">VAT-7K</KodFormularzaDekl>"))
        #expect(result.xml.contains("<WariantFormularzaDekl>17</WariantFormularzaDekl>"))
        #expect(result.xml.contains("<Kwartal>2</Kwartal>"))
        #expect(result.xml.contains("<Miesiac>6</Miesiac>"))
        #expect(result.hasDeclaration)
        #expect((try? XMLDocument(data: Data(result.xml.utf8), options: [])) != nil)
    }

    @Test("Pierwszy/drugi miesiąc kwartału: sama ewidencja, bez deklaracji, z ostrzeżeniem")
    func nonQuarterEndRecordsOnly() {
        // Maj = drugi miesiąc II kwartału.
        let result = JPKV7Generator.generate(
            invoices: [makeSale(number: "FV/5", issue: "2026-05-10",
                                lines: [line("Usługa", net: 100, rate: "23", vat: 23)])],
            options: makeOptions(variant: .quarterly, month: 5)
        )
        #expect(result.salesCount == 1)
        #expect(result.xml.contains("<Ewidencja>"))
        #expect(!result.xml.contains("<Deklaracja>"))
        #expect(!result.xml.contains("<Kwartal>"))
        #expect(result.hasDeclaration == false)
        #expect(result.xml.contains(#"kodSystemowy="JPK_V7K (3)""#))
        #expect(result.warnings.contains { $0.contains("ostatniego miesiąca kwartału") })
    }

    @Test("Deklaracja obejmuje cały kwartał, ewidencja tylko ostatni miesiąc")
    func declarationCoversQuarterEvidenceCoversMonth() {
        // II kwartał: kwiecień, maj, czerwiec — plik czerwcowy.
        let april = makeSale(number: "FV/4", issue: "2026-04-10",
                             lines: [line("Usługa", net: 1000, rate: "23", vat: 230)])
        let may = makeSale(number: "FV/5", issue: "2026-05-10",
                           lines: [line("Usługa", net: 2000, rate: "23", vat: 460)])
        let june = makeSale(number: "FV/6", issue: "2026-06-10",
                            lines: [line("Usługa", net: 3000, rate: "23", vat: 690)])
        let result = JPKV7Generator.generate(
            invoices: [april, may, june],
            options: makeOptions(variant: .quarterly, month: 6)
        )
        // Ewidencja: tylko czerwiec.
        #expect(result.salesCount == 1)
        #expect(result.xml.contains("<DowodSprzedazy>FV/6</DowodSprzedazy>"))
        #expect(!result.xml.contains("<DowodSprzedazy>FV/4</DowodSprzedazy>"))
        #expect(result.xml.contains("<K_19>3000.00</K_19>")) // wiersz ewidencji = czerwiec
        // SprzedazCtrl liczy podatek miesiąca (czerwiec).
        #expect(result.outputVAT == 690)
        // Deklaracja: suma całego kwartału (230+460+690 = 1380).
        #expect(result.declarationOutputVAT == 1380)
        #expect(result.xml.contains("<P_19>6000</P_19>")) // 1000+2000+3000
        #expect(result.xml.contains("<P_38>1380</P_38>"))
        #expect(result.xml.contains("<P_51>1380</P_51>"))
        #expect(result.amountDue == 1380)
    }

    @Test("Kwartał uwzględnia zakupy z całego kwartału (P_42/P_43)")
    func declarationQuarterPurchases() {
        let apr = makePurchase(number: "Z/4", issue: "2026-04-05", net: 1000, vat: 230)
        let jun = makePurchase(number: "Z/6", issue: "2026-06-05", net: 2000, vat: 460)
        let junSale = makeSale(number: "FV/6", issue: "2026-06-10",
                              lines: [line("Usługa", net: 5000, rate: "23", vat: 1150)])
        let result = JPKV7Generator.generate(
            invoices: [apr, jun, junSale],
            options: makeOptions(variant: .quarterly, month: 6)
        )
        // Ewidencja zakupów: tylko czerwiec.
        #expect(result.purchaseCount == 1)
        #expect(result.declarationInputVAT == 690) // 230+460 z całego kwartału
        #expect(result.xml.contains("<P_43>690</P_43>"))
        #expect(result.xml.contains("<P_42>3000</P_42>"))
        #expect(result.amountDue == 460) // 1150 należny − 690 naliczony
    }

    @Test("Numer kwartału i wykrycie ostatniego miesiąca")
    func quarterMath() {
        #expect(JPKV7Generator.quarter(of: 1) == 1)
        #expect(JPKV7Generator.quarter(of: 3) == 1)
        #expect(JPKV7Generator.quarter(of: 4) == 2)
        #expect(JPKV7Generator.quarter(of: 9) == 3)
        #expect(JPKV7Generator.quarter(of: 12) == 4)
        #expect(JPKV7Generator.quarterMonths(5) == [4, 5, 6])
        #expect(JPKV7Generator.quarterMonths(12) == [10, 11, 12])
        #expect(JPKV7Generator.isQuarterEnd(3))
        #expect(JPKV7Generator.isQuarterEnd(12))
        #expect(!JPKV7Generator.isQuarterEnd(4))
    }

    @Test("Grudzień → IV kwartał (Kwartal=4)")
    func fourthQuarter() {
        let result = JPKV7Generator.generate(
            invoices: [makeSale(number: "FV/12", issue: "2026-12-10",
                                lines: [line("Usługa", net: 100, rate: "23", vat: 23)])],
            options: makeOptions(variant: .quarterly, month: 12)
        )
        #expect(result.xml.contains("<Kwartal>4</Kwartal>"))
        #expect(result.xml.contains("<Miesiac>12</Miesiac>"))
    }

    @Test("Historyczny kwartał zachowuje schemę JPK_V7K(2)")
    func historicalQuarterlySchema() {
        let invoice = makeSale(number: "FV/12/2025", issue: "2025-12-10")
        let result = JPKV7Generator.generate(
            invoices: [invoice],
            options: makeOptions(variant: .quarterly, year: 2025, month: 12)
        )
        #expect(result.xml.contains(#"kodSystemowy="JPK_V7K (2)""#))
        #expect(result.xml.contains("http://crd.gov.pl/wzor/2021/12/27/11149/"))
        #expect(result.xml.contains(#"kodSystemowy="VAT-7K (16)""#))
        #expect(result.xml.contains("<WariantFormularzaDekl>16</WariantFormularzaDekl>"))
        #expect(!result.xml.contains("<BFK>"))
    }

    @Test("Etykiety wariantu")
    func variantLabels() {
        #expect(JPKV7Variant.monthly.fileTag == "JPK_V7M")
        #expect(JPKV7Variant.quarterly.fileTag == "JPK_V7K")
        #expect(JPKV7Variant.monthly.label.contains("V7M"))
        #expect(JPKV7Variant.quarterly.label.contains("V7K"))
        #expect(JPKV7Variant.monthly.id == "monthly")
        #expect(JPKV7Variant.quarterly.id == "quarterly")
        #expect(JPKV7Variant.allCases.count == 2)
    }
}
