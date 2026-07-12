import Foundation
import Testing
@testable import KsefiarzCore

@Suite("KPiR — ewidencja i eksport")
struct KPiREngineTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func invoice(
        number: String,
        kind: Invoice.Kind,
        date: Date,
        net: Double = 100,
        taxID: String = "5260250274"
    ) -> Invoice {
        let invoice = Invoice(
            invoiceNumber: number,
            issueDate: date,
            sellerName: kind == .purchase ? "Dostawca" : "Moja Firma",
            sellerNIP: kind == .purchase ? taxID : "1111111111",
            sellerAddress: "ul. Sprzedawcy 1",
            buyerName: kind == .sales ? "Odbiorca" : "Moja Firma",
            buyerNIP: kind == .sales ? taxID : "1111111111",
            buyerAddress: "ul. Nabywcy 2",
            netAmount: net,
            vatAmount: net * 0.23,
            grossAmount: net * 1.23,
            kind: kind
        )
        return invoice
    }

    @Test("Domyślna klasyfikacja rozdziela sprzedaż i pozostałe wydatki")
    func defaultClassification() {
        let sale = invoice(number: "S/1", kind: .sales, date: date(2026, 1, 2))
        let purchase = invoice(number: "Z/1", kind: .purchase, date: date(2026, 1, 3))

        #expect(KPiREngine.effectiveColumn(for: sale) == .salesRevenue)
        #expect(KPiREngine.effectiveColumn(for: purchase) == .otherExpenses)

        purchase.kpirColumnRaw = KPiRColumn.goodsAndMaterials.rawValue
        #expect(KPiREngine.effectiveColumn(for: purchase) == .goodsAndMaterials)

        // Kolumna przychodowa zapisana omyłkowo na zakupie jest ignorowana.
        purchase.kpirColumnRaw = KPiRColumn.otherRevenue.rawValue
        #expect(KPiREngine.effectiveColumn(for: purchase) == .otherExpenses)
    }

    @Test("Okres używa daty zdarzenia, sortuje wpisy i pomija ukryte oraz wykluczone")
    func filteringAndSorting() throws {
        let later = invoice(number: "S/2", kind: .sales, date: date(2026, 2, 20))
        later.kpirEventDate = date(2026, 1, 3)
        later.ksefId = "KSEF-2"
        let earlier = invoice(number: "S/1", kind: .sales, date: date(2026, 1, 2), taxID: "")
        let hidden = invoice(number: "UKRYTA", kind: .purchase, date: date(2026, 1, 1))
        hidden.isArchivedOrHidden = true
        let excluded = invoice(number: "WYKLUCZONA", kind: .purchase, date: date(2026, 1, 4))
        excluded.isExcludedFromKPiR = true
        let otherMonth = invoice(number: "LUTY", kind: .sales, date: date(2026, 2, 1))

        let rows = KPiREngine.rows(
            from: [later, hidden, excluded, otherMonth, earlier],
            period: .init(year: 2026, month: 1),
            calendar: calendar
        )

        #expect(rows.map(\.documentNumber) == ["S/1", "S/2"])
        #expect(rows.map(\.ordinal) == [1, 2])
        #expect(rows[1].ksefNumber == "KSEF-2")
        #expect(rows[0].contractorTaxID.isEmpty)
        #expect(rows[0].contractorName == "Odbiorca")
        #expect(rows[0].contractorAddress == "ul. Nabywcy 2")
        #expect(rows[1].contractorTaxID == "5260250274")
        #expect(rows[1].contractorName.isEmpty)

        let withExcluded = KPiREngine.rows(
            from: [excluded], period: .init(year: 2026, month: 1),
            includeExcluded: true, calendar: calendar
        )
        #expect(withExcluded.count == 1)
        #expect(withExcluded[0].isExcluded)
    }

    @Test("Kwoty walutowe przelicza na PLN, a ręczna kwota ma pierwszeństwo")
    func amounts() throws {
        let purchase = invoice(number: "EUR/1", kind: .purchase, date: date(2026, 3, 1), net: 100)
        purchase.currency = "EUR"
        purchase.exchangeRate = 4.25
        var row = try #require(KPiREngine.rows(
            from: [purchase], period: .init(year: 2026), calendar: calendar
        ).first)
        #expect(row.amountPLN == 425)
        #expect(row.warning == nil)

        purchase.kpirAmountOverride = 212.345
        row = try #require(KPiREngine.rows(
            from: [purchase], period: .init(year: 2026), calendar: calendar
        ).first)
        #expect(row.amountPLN == 212.35)

        purchase.kpirAmountOverride = nil
        purchase.exchangeRate = 0
        row = try #require(KPiREngine.rows(
            from: [purchase], period: .init(year: 2026), calendar: calendar
        ).first)
        #expect(row.warning?.contains("Brak kursu PLN") == true)
    }

    @Test("Podsumowanie liczy przychód, wszystkie grupy kosztów i dochód")
    func summary() {
        let sale = invoice(number: "S", kind: .sales, date: date(2026, 4, 1), net: 1000)
        let goods = invoice(number: "T", kind: .purchase, date: date(2026, 4, 2), net: 200)
        goods.kpirColumnRaw = KPiRColumn.goodsAndMaterials.rawValue
        let wages = invoice(number: "W", kind: .purchase, date: date(2026, 4, 3), net: 300)
        wages.kpirColumnRaw = KPiRColumn.wages.rawValue
        let excluded = invoice(number: "X", kind: .purchase, date: date(2026, 4, 4), net: 900)
        excluded.isExcludedFromKPiR = true
        let rows = KPiREngine.rows(from: [sale, goods, wages, excluded],
                                   period: .init(year: 2026), includeExcluded: true,
                                   calendar: calendar)
        let result = KPiREngine.summary(for: rows)

        #expect(result.revenue == 1000)
        #expect(result.goodsAndMaterials == 200)
        #expect(result.wages == 300)
        #expect(result.deductibleCosts == 500)
        #expect(result.income == 500)
    }

    @Test("CSV ma pełne 19 kolumn wzoru 2026, sumy i poprawne cytowanie")
    func csv() throws {
        let sale = invoice(number: "FV;\"1\"", kind: .sales, date: date(2026, 5, 5), net: 123.45)
        sale.kpirDescription = "Usługa; abonament"
        sale.kpirNotes = "pierwsza\nlinia"
        sale.kpirResearchDevelopmentCost = 10
        let excluded = invoice(number: "X", kind: .sales, date: date(2026, 5, 6))
        excluded.isExcludedFromKPiR = true
        let rows = KPiREngine.rows(from: [sale, excluded], period: .init(year: 2026),
                                   includeExcluded: true, calendar: calendar)

        let csv = KPiRCSVExporter.csv(for: rows)
        let logicalLines = csv.components(separatedBy: "\n")
        #expect(logicalLines[0].split(separator: ";", omittingEmptySubsequences: false).count == 19)
        #expect(csv.contains("\"FV;\"\"1\"\"\""))
        #expect(csv.contains("\"Usługa; abonament\""))
        #expect(csv.contains("123,45;;123,45"))
        #expect(csv.contains(";10,00;\"pierwsza\nlinia\""))
        #expect(!csv.contains(";X;"))
        #expect(csv.contains("\n1;2026-05-05;"))
    }
}
