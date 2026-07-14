import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Miesięczny raport e-mail — okresy, agregaty i treść (F4)")
struct MonthlyReportEngineTests {

    private func date(_ text: String) -> Date {
        FA2Format.dateFormatter.date(from: text)!
    }

    private func makeInvoice(
        number: String,
        issued: String,
        kind: Invoice.Kind,
        net: Double = 100,
        vat: Double = 23,
        gross: Double = 123,
        isPaid: Bool = true,
        due: String? = nil,
        hidden: Bool = false,
        currency: String = "PLN",
        exchangeRate: Double = 0
    ) -> Invoice {
        Invoice(
            invoiceNumber: number,
            issueDate: date(issued),
            sellerName: "ACME Sp. z o.o.",
            sellerNIP: "5260250274",
            buyerName: "Kontrahent S.A.",
            buyerNIP: "1111111111",
            netAmount: net,
            vatAmount: vat,
            grossAmount: gross,
            isPaid: isPaid,
            paymentDueDate: due.map(date),
            isArchivedOrHidden: hidden,
            currency: currency,
            exchangeRate: exchangeRate,
            kind: kind
        )
    }

    // MARK: Okresy i deduplikacja

    @Test("Okres raportu to poprzedni miesiąc; klucz w formacie RRRR-MM")
    func periodResolution() {
        let period = MonthlyReportEngine.previousMonthStart(asOf: date("2026-07-14"))
        #expect(period == date("2026-06-01"))
        #expect(MonthlyReportEngine.periodKey(for: period!) == "2026-06")
    }

    @Test("Na przełomie roku raport dotyczy grudnia poprzedniego roku")
    func periodAcrossYearBoundary() {
        let period = MonthlyReportEngine.previousMonthStart(asOf: date("2026-01-02"))
        #expect(period == date("2025-12-01"))
        #expect(MonthlyReportEngine.periodKey(for: period!) == "2025-12")
    }

    @Test("Zaraportowany okres nie jest zwracany ponownie")
    func duePeriodDeduplicated() {
        let asOf = date("2026-07-14")
        #expect(MonthlyReportEngine.duePeriod(asOf: asOf, alreadySent: []) == date("2026-06-01"))
        #expect(MonthlyReportEngine.duePeriod(asOf: asOf, alreadySent: ["2026-06"]) == nil)
        // Stary wpis nie blokuje nowego okresu.
        #expect(MonthlyReportEngine.duePeriod(asOf: asOf, alreadySent: ["2026-05"]) == date("2026-06-01"))
    }

    @Test("Pamięć wysłanych raportów jest przycinana do najnowszych okresów")
    func pruneKeepsNewest() {
        let sent: Set<String> = ["2024-01", "2024-02", "2026-05", "2026-06"]
        let pruned = MonthlyReportEngine.prune(sent: sent, keep: 2)
        #expect(pruned == ["2026-05", "2026-06"])
    }

    // MARK: Agregaty

    @Test("Podsumowanie liczy sprzedaż i zakupy miesiąca oraz należności na dzień raportu")
    func summaryAggregates() {
        let invoices = [
            // Sprzedaż w okresie (czerwiec).
            makeInvoice(number: "S1", issued: "2026-06-05", kind: .sales),
            makeInvoice(number: "S2", issued: "2026-06-20", kind: .sales,
                        net: 200, vat: 46, gross: 246, isPaid: false, due: "2026-07-30"),
            // Zakup w okresie.
            makeInvoice(number: "Z1", issued: "2026-06-10", kind: .purchase,
                        net: 50, vat: 11.5, gross: 61.5),
            // Sprzedaż spoza okresu — nie wchodzi do sum miesiąca,
            // ale jako nieopłacona i po terminie zasila należności.
            makeInvoice(number: "S0", issued: "2026-05-02", kind: .sales,
                        net: 300, vat: 69, gross: 369, isPaid: false, due: "2026-05-16"),
            // Ukryta — całkowicie poza raportem.
            makeInvoice(number: "H1", issued: "2026-06-15", kind: .sales,
                        net: 999, vat: 0, gross: 999, hidden: true),
        ]
        let summary = MonthlyReportEngine.summary(
            invoices: invoices,
            periodStart: date("2026-06-01"),
            asOf: date("2026-07-14")
        )
        #expect(summary.salesCount == 2)
        #expect(summary.salesNet == 300)
        #expect(summary.salesVAT == 69)
        #expect(summary.salesGross == 369)
        #expect(summary.purchasesCount == 1)
        #expect(summary.purchasesVAT == 11.5)
        #expect(summary.purchasesGross == 61.5)
        #expect(summary.vatBalance == 57.5)
        // Należności: S2 (246, przed terminem) + S0 (369, po terminie).
        #expect(summary.receivablesCount == 2)
        #expect(summary.receivablesTotal == 615)
        #expect(summary.overdueCount == 1)
        #expect(summary.overdueTotal == 369)
        #expect(summary.missingRateCount == 0)
    }

    @Test("Kwoty walutowe są przeliczane po kursie z faktury; brak kursu jest policzony")
    func summaryCurrencyConversion() {
        let invoices = [
            makeInvoice(number: "E1", issued: "2026-06-05", kind: .sales,
                        net: 100, vat: 0, gross: 100, currency: "EUR", exchangeRate: 4.5),
            makeInvoice(number: "E2", issued: "2026-06-06", kind: .sales,
                        net: 10, vat: 0, gross: 10, currency: "USD", exchangeRate: 0),
        ]
        let summary = MonthlyReportEngine.summary(
            invoices: invoices,
            periodStart: date("2026-06-01"),
            asOf: date("2026-07-01")
        )
        // 100 EUR × 4.5 + 10 USD nominalnie (bez kursu).
        #expect(summary.salesGross == 460)
        #expect(summary.missingRateCount == 1)
    }

    // MARK: Treść wiadomości

    @Test("Temat i treść zawierają nazwę miesiąca, kwoty i ostrzeżenie o braku kursu")
    func subjectAndBody() {
        let invoices = [
            makeInvoice(number: "S1", issued: "2026-06-05", kind: .sales),
            makeInvoice(number: "E2", issued: "2026-06-06", kind: .sales,
                        net: 10, vat: 0, gross: 10, currency: "USD", exchangeRate: 0),
        ]
        let summary = MonthlyReportEngine.summary(
            invoices: invoices,
            periodStart: date("2026-06-01"),
            asOf: date("2026-07-14")
        )
        #expect(MonthlyReportEngine.subject(for: summary)
            == "Ksefiarz — podsumowanie miesiąca: czerwiec 2026")
        let body = MonthlyReportEngine.body(for: summary)
        #expect(body.contains("Wystawione faktury: 2"))
        #expect(body.contains("Sprzedaż brutto: 133.00 PLN"))
        #expect(body.contains("VAT należny: 23.00 PLN"))
        #expect(body.contains("Saldo VAT (należny − naliczony): 23.00 PLN"))
        #expect(body.contains("faktura walutowa bez kursu"))
        #expect(body.contains("nie zastępuje"))
    }

    @Test("Raport bez faktur walutowych nie ma ostrzeżenia o kursie")
    func bodyWithoutMissingRateWarning() {
        let summary = MonthlyReportEngine.summary(
            invoices: [makeInvoice(number: "S1", issued: "2026-06-05", kind: .sales)],
            periodStart: date("2026-06-01"),
            asOf: date("2026-07-14")
        )
        #expect(!MonthlyReportEngine.body(for: summary).contains("bez kursu"))
    }

    // MARK: Konfiguracja automatyzacji

    @Test("Pusty adresat raportu dziedziczy adres e-mail podatnika z ustawień JPK")
    func configurationRecipientFallback() {
        let own = MonthlyReportAutomationConfiguration(
            isEnabled: true, recipient: " ja@firma.pl ",
            fallbackRecipient: "jpk@firma.pl", deliveryModeRaw: "draft"
        )
        #expect(own.recipient == "ja@firma.pl")
        let fallback = MonthlyReportAutomationConfiguration(
            isEnabled: true, recipient: "  ",
            fallbackRecipient: " jpk@firma.pl ", deliveryModeRaw: "draft"
        )
        #expect(fallback.recipient == "jpk@firma.pl")
        let none = MonthlyReportAutomationConfiguration(
            isEnabled: true, recipient: "",
            fallbackRecipient: "", deliveryModeRaw: "draft"
        )
        #expect(none.recipient.isEmpty)
    }
}
