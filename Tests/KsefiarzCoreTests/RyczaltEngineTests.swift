import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Ryczałt — ewidencja przychodów i eksport")
struct RyczaltEngineTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func sale(
        number: String,
        date: Date,
        net: Double = 100,
        buyerNIP: String = "5260250274"
    ) -> Invoice {
        Invoice(
            invoiceNumber: number,
            issueDate: date,
            sellerName: "Moja Firma",
            sellerNIP: "1111111111",
            sellerAddress: "ul. Sprzedawcy 1",
            buyerName: "Odbiorca",
            buyerNIP: buyerNIP,
            buyerAddress: "ul. Nabywcy 2",
            netAmount: net,
            vatAmount: net * 0.23,
            grossAmount: net * 1.23,
            kind: .sales
        )
    }

    // MARK: Stawki

    @Test("Stawki mają właściwe kolumny, ułamki i polskie etykiety")
    func rateMetadata() {
        #expect(RyczaltRate.allCases.map(\.rawValue) == ["17", "15", "14", "12.5", "12", "10", "8.5", "5.5", "3"])
        #expect(RyczaltRate.r17.columnNumber == 7)
        #expect(RyczaltRate.r3.columnNumber == 15)
        #expect(RyczaltRate.r8_5.fraction == 0.085)
        #expect(RyczaltRate.r12_5.displayName == "12,5%")
        #expect(RyczaltRate.r8_5.displayName == "8,5%")
    }

    @Test("Forma opodatkowania domyślnie KPiR, a nieznana wartość też")
    func taxFormResolution() {
        #expect(TaxForm.resolve("kpir") == .kpir)
        #expect(TaxForm.resolve("ryczalt") == .ryczalt)
        #expect(TaxForm.resolve("") == .kpir)
        #expect(TaxForm.resolve("cokolwiek") == .kpir)
    }

    @Test("Efektywna stawka: pusta = domyślna, ustawiona = własna")
    func effectiveRate() {
        let invoice = sale(number: "S/1", date: date(2026, 1, 2))
        #expect(RyczaltEngine.effectiveRate(for: invoice, default: .r8_5) == .r8_5)
        invoice.ryczaltRateRaw = RyczaltRate.r12.rawValue
        #expect(RyczaltEngine.effectiveRate(for: invoice, default: .r8_5) == .r12)
        // Nieznana wartość wraca do stawki domyślnej.
        invoice.ryczaltRateRaw = "99"
        #expect(RyczaltEngine.effectiveRate(for: invoice, default: .r15) == .r15)
    }

    @Test("Domyślna stawka z ustawień z fallbackiem 8,5%")
    func defaultRateFromSetting() {
        #expect(RyczaltEngine.defaultRate(fromSetting: "12") == .r12)
        #expect(RyczaltEngine.defaultRate(fromSetting: "") == .r8_5)
        #expect(RyczaltEngine.defaultRate(fromSetting: "brak") == .r8_5)
    }

    // MARK: Wiersze

    @Test("Ewidencja obejmuje tylko sprzedaż, pomija zakupy i ukryte")
    func salesOnly() {
        let saleDoc = sale(number: "S/1", date: date(2026, 1, 2))
        let purchase = Invoice(
            invoiceNumber: "Z/1", issueDate: date(2026, 1, 3),
            sellerName: "Dostawca", sellerNIP: "5260250274", sellerAddress: "ul. 1",
            buyerName: "Moja Firma", buyerNIP: "1111111111", buyerAddress: "ul. 2",
            netAmount: 200, vatAmount: 46, grossAmount: 246, kind: .purchase
        )
        let hidden = sale(number: "S/2", date: date(2026, 1, 4))
        hidden.isArchivedOrHidden = true

        let rows = RyczaltEngine.rows(
            from: [saleDoc, purchase, hidden],
            period: .init(year: 2026), defaultRate: .r8_5
        )
        #expect(rows.count == 1)
        #expect(rows.first?.documentNumber == "S/1")
    }

    @Test("Okres używa daty przychodu, sortuje wpisy i pomija wykluczone")
    func filteringAndSorting() throws {
        let later = sale(number: "S/2", date: date(2026, 2, 20))
        later.ryczaltEventDate = date(2026, 1, 3)
        let earlier = sale(number: "S/1", date: date(2026, 1, 2))
        let excluded = sale(number: "S/3", date: date(2026, 1, 5))
        excluded.isExcludedFromRyczalt = true
        let otherMonth = sale(number: "S/4", date: date(2026, 3, 10))

        let january = RyczaltEngine.rows(
            from: [later, earlier, excluded, otherMonth],
            period: .init(year: 2026, month: 1), defaultRate: .r8_5
        )
        // Bez wykluczonych i spoza okresu; posortowane po dacie przychodu.
        #expect(january.map(\.documentNumber) == ["S/1", "S/2"])
        #expect(january.map(\.ordinal) == [1, 2])

        let withExcluded = RyczaltEngine.rows(
            from: [later, earlier, excluded, otherMonth],
            period: .init(year: 2026, month: 1), defaultRate: .r8_5, includeExcluded: true
        )
        #expect(withExcluded.contains { $0.documentNumber == "S/3" && $0.isExcluded })
    }

    @Test("Kwota przychodu: nadpisanie ma pierwszeństwo, inaczej netto w PLN")
    func effectiveAmount() {
        let invoice = sale(number: "S/1", date: date(2026, 1, 2), net: 100)
        #expect(RyczaltEngine.effectiveAmount(for: invoice) == 100)
        invoice.ryczaltAmountOverride = 40
        #expect(RyczaltEngine.effectiveAmount(for: invoice) == 40)
    }

    @Test("Data przychodu: nadpisanie, potem data sprzedaży, potem wystawienia")
    func effectiveDate() {
        let invoice = sale(number: "S/1", date: date(2026, 1, 2))
        #expect(RyczaltEngine.effectiveDate(for: invoice) == date(2026, 1, 2))
        invoice.saleDate = date(2026, 1, 5)
        #expect(RyczaltEngine.effectiveDate(for: invoice) == date(2026, 1, 5))
        invoice.ryczaltEventDate = date(2026, 1, 9)
        #expect(RyczaltEngine.effectiveDate(for: invoice) == date(2026, 1, 9))
    }

    // MARK: Podsumowanie

    @Test("Podsumowanie sumuje przychód i szacuje ryczałt per stawka")
    func summary() {
        let a = sale(number: "S/1", date: date(2026, 1, 2), net: 1000)
        a.ryczaltRateRaw = RyczaltRate.r12.rawValue
        let b = sale(number: "S/2", date: date(2026, 1, 3), net: 2000)
        b.ryczaltRateRaw = RyczaltRate.r8_5.rawValue
        let c = sale(number: "S/3", date: date(2026, 1, 4), net: 500)
        c.ryczaltRateRaw = RyczaltRate.r12.rawValue

        let rows = RyczaltEngine.rows(from: [a, b, c], period: .init(year: 2026), defaultRate: .r8_5)
        let summary = RyczaltEngine.summary(for: rows)

        #expect(summary.totalRevenue == 3500)
        #expect(summary.revenueByRate[.r12] == 1500)
        #expect(summary.revenueByRate[.r8_5] == 2000)
        // 1500 × 12% = 180; 2000 × 8,5% = 170.
        #expect(summary.taxByRate[.r12] == 180)
        #expect(summary.taxByRate[.r8_5] == 170)
        #expect(summary.estimatedTax == 350)
        // Kolejność stawek jak w kolumnach wzoru (12% przed 8,5%).
        #expect(summary.usedRates == [.r12, .r8_5])
    }

    @Test("Wykluczone wpisy nie wchodzą do podsumowania")
    func summaryIgnoresExcluded() {
        let a = sale(number: "S/1", date: date(2026, 1, 2), net: 1000)
        a.ryczaltRateRaw = RyczaltRate.r15.rawValue
        let excluded = sale(number: "S/2", date: date(2026, 1, 3), net: 9999)
        excluded.ryczaltRateRaw = RyczaltRate.r15.rawValue
        excluded.isExcludedFromRyczalt = true

        let rows = RyczaltEngine.rows(
            from: [a, excluded], period: .init(year: 2026), defaultRate: .r8_5, includeExcluded: true
        )
        let summary = RyczaltEngine.summary(for: rows)
        #expect(summary.totalRevenue == 1000)
        #expect(summary.revenueByRate[.r15] == 1000)
    }

    @Test("Brak kursu waluty obcej daje ostrzeżenie")
    func missingExchangeRateWarning() {
        let invoice = sale(number: "S/1", date: date(2026, 1, 2))
        invoice.currency = "EUR"
        invoice.exchangeRate = 0
        let rows = RyczaltEngine.rows(from: [invoice], period: .init(year: 2026), defaultRate: .r8_5)
        #expect(rows.first?.warning != nil)

        // Nadpisana kwota gasi ostrzeżenie.
        invoice.ryczaltAmountOverride = 123
        let fixed = RyczaltEngine.rows(from: [invoice], period: .init(year: 2026), defaultRate: .r8_5)
        #expect(fixed.first?.warning == nil)
    }

    // MARK: CSV

    @Test("CSV ma 17 kolumn, wstawia kwotę w kolumnie stawki i sumę na końcu")
    func csvLayout() throws {
        let a = sale(number: "S/1", date: date(2026, 1, 2), net: 100)
        a.ryczaltRateRaw = RyczaltRate.r12.rawValue
        let rows = RyczaltEngine.rows(from: [a], period: .init(year: 2026), defaultRate: .r8_5)
        let csv = RyczaltCSVExporter.csv(for: rows)
        let lines = csv.split(separator: "\n").map(String.init)

        // Nagłówek + wiersz + suma.
        #expect(lines.count == 3)
        let header = lines[0].components(separatedBy: ";")
        #expect(header.count == 17)
        #expect(header[9] == "10 Przychody 12,5%")

        let row = lines[1].components(separatedBy: ";")
        #expect(row.count == 17)
        // Kolumna 12% to indeks 10 (kol. 11 wzoru); pozostałe stawki puste.
        #expect(row[10] == "100,00")
        #expect(row[6] == "") // 17%
        #expect(row[15] == "100,00") // ogółem
        #expect(row[5] == "5260250274") // identyfikator kontrahenta (buyerNIP)

        let totals = lines[2].components(separatedBy: ";")
        #expect(totals[5] == "Suma przychodów")
        #expect(totals[10] == "100,00")
        #expect(totals[15] == "100,00")
    }

    @Test("CSV pomija wpisy wykluczone")
    func csvSkipsExcluded() {
        let a = sale(number: "S/1", date: date(2026, 1, 2), net: 100)
        a.ryczaltRateRaw = RyczaltRate.r3.rawValue
        let excluded = sale(number: "S/2", date: date(2026, 1, 3), net: 500)
        excluded.isExcludedFromRyczalt = true

        let rows = RyczaltEngine.rows(
            from: [a, excluded], period: .init(year: 2026), defaultRate: .r8_5, includeExcluded: true
        )
        let lines = RyczaltCSVExporter.csv(for: rows).split(separator: "\n").map(String.init)
        // Nagłówek + jeden wiersz + suma (wykluczony pominięty).
        #expect(lines.count == 3)
        #expect(lines[1].contains("S/1"))
        #expect(!lines[1].contains("S/2"))
    }
}
