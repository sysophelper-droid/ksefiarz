import Foundation

/// Podsumowanie zamkniętego miesiąca do cyklicznego raportu e-mail (F4).
/// Kwoty w PLN (faktury walutowe po kursie z faktury; brak kursu = kwota
/// nominalna, jawnie policzona w `missingRateCount`).
public struct MonthlyReportSummary: Equatable, Sendable {
    /// Pierwszy dzień raportowanego miesiąca.
    public let periodStart: Date

    /// Sprzedaż wystawiona w miesiącu (po dacie wystawienia).
    public let salesCount: Int
    public let salesNet: Double
    public let salesVAT: Double
    public let salesGross: Double

    /// Zakupy z datą wystawienia w miesiącu.
    public let purchasesCount: Int
    public let purchasesVAT: Double
    public let purchasesGross: Double

    /// Saldo VAT (należny − naliczony) — szacunek poglądowy, nie JPK.
    public var vatBalance: Double { salesVAT - purchasesVAT }

    /// Należności na dzień raportu: nieopłacone faktury sprzedaży
    /// z dodatnim saldem — ze wszystkich okresów, nie tylko z miesiąca.
    public let receivablesCount: Int
    public let receivablesTotal: Double
    /// W tym po terminie płatności.
    public let overdueCount: Int
    public let overdueTotal: Double

    /// Faktury miesiąca w walucie obcej bez kursu (kwoty nominalne).
    public let missingRateCount: Int
}

/// Tożsamość cyklu automatyzacji raportu miesięcznego (SwiftUI `task(id:)`)
/// — zmiana ustawień restartuje pętlę, nowa konfiguracja działa od razu.
/// Pusty własny adresat jest zastępowany adresem podatnika z ustawień JPK.
struct MonthlyReportAutomationConfiguration: Equatable, Hashable, Sendable {
    let isEnabled: Bool
    /// Rozstrzygnięty adresat (własny albo fallback); pusty = raport
    /// nie może powstać.
    let recipient: String
    let deliveryModeRaw: String

    init(
        isEnabled: Bool,
        recipient: String,
        fallbackRecipient: String,
        deliveryModeRaw: String
    ) {
        self.isEnabled = isEnabled
        let own = recipient.trimmingCharacters(in: .whitespaces)
        let fallback = fallbackRecipient.trimmingCharacters(in: .whitespaces)
        self.recipient = own.isEmpty ? fallback : own
        self.deliveryModeRaw = deliveryModeRaw
    }
}

/// Cykliczny raport e-mail „podsumowanie miesiąca” — czysta logika:
/// wyznaczenie zamkniętego okresu, deduplikacja wysłanych raportów,
/// agregaty sprzedaż/VAT/należności i treść wiadomości (PL).
/// Dostarczaniem zajmuje się `MailAutomationService` (cykl
/// w `MainContentView`), pamięcią wysłanych — UserDefaults
/// (`AppSettingsKeys.monthlyReportSentPeriods`).
public enum MonthlyReportEngine {

    /// Początek poprzedniego (zamkniętego) miesiąca względem `asOf`.
    public static func previousMonthStart(
        asOf: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let currentStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: asOf)
        ) else { return nil }
        return calendar.date(byAdding: .month, value: -1, to: currentStart)
    }

    /// Klucz deduplikacji okresu, np. „2026-06”.
    public static func periodKey(
        for periodStart: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month], from: periodStart)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    /// Okres, za który raport powinien teraz powstać: poprzedni miesiąc,
    /// o ile nie został już zaraportowany. `nil` = nic do zrobienia.
    public static func duePeriod(
        asOf: Date,
        alreadySent: Set<String>,
        calendar: Calendar = .current
    ) -> Date? {
        guard let period = previousMonthStart(asOf: asOf, calendar: calendar) else { return nil }
        return alreadySent.contains(periodKey(for: period, calendar: calendar)) ? nil : period
    }

    /// Przycina pamięć wysłanych raportów do najnowszych `keep` okresów
    /// (klucze „RRRR-MM” sortują się leksykograficznie chronologicznie).
    public static func prune(sent: Set<String>, keep: Int = 24) -> Set<String> {
        Set(sent.sorted().suffix(keep))
    }

    /// Agreguje podsumowanie miesiąca. Faktury ukryte są pomijane
    /// (jak w statystykach Kokpitu); korekty wchodzą kwotami ze znakiem.
    public static func summary(
        invoices: [Invoice],
        periodStart: Date,
        asOf: Date = .now,
        calendar: Calendar = .current
    ) -> MonthlyReportSummary {
        let visible = invoices.filter { !$0.isArchivedOrHidden }
        let inPeriod = visible.filter {
            calendar.isDate($0.issueDate, equalTo: periodStart, toGranularity: .month)
        }
        let sales = inPeriod.filter { $0.kind == .sales }
        let purchases = inPeriod.filter { $0.kind == .purchase }

        func plnSum(_ invoices: [Invoice], _ amount: (Invoice) -> Double) -> Double {
            invoices.reduce(0) { $0 + DashboardAnalytics.inPLN(amount($1), invoice: $1) }
        }

        // Należności liczone ze WSZYSTKICH widocznych faktur sprzedaży —
        // zaległość z maja jest nadal należnością w raporcie za czerwiec.
        let today = calendar.startOfDay(for: asOf)
        var receivablesCount = 0
        var receivablesTotal = 0.0
        var overdueCount = 0
        var overdueTotal = 0.0
        for invoice in visible where invoice.kind == .sales && !invoice.isPaid {
            let outstanding = DashboardAnalytics.inPLN(
                invoice.outstandingAmount, invoice: invoice
            )
            guard outstanding > 0.005 else { continue }
            receivablesCount += 1
            receivablesTotal += outstanding
            if let due = invoice.paymentDueDate, calendar.startOfDay(for: due) < today {
                overdueCount += 1
                overdueTotal += outstanding
            }
        }

        return MonthlyReportSummary(
            periodStart: periodStart,
            salesCount: sales.count,
            salesNet: plnSum(sales, \.netAmount),
            salesVAT: plnSum(sales, \.vatAmount),
            salesGross: plnSum(sales, \.grossAmount),
            purchasesCount: purchases.count,
            purchasesVAT: plnSum(purchases, \.vatAmount),
            purchasesGross: plnSum(purchases, \.grossAmount),
            receivablesCount: receivablesCount,
            receivablesTotal: receivablesTotal,
            overdueCount: overdueCount,
            overdueTotal: overdueTotal,
            missingRateCount: inPeriod.filter { $0.currency != "PLN" && $0.exchangeRate <= 0 }.count
        )
    }

    /// Nazwa miesiąca do tematu i treści, np. „czerwiec 2026”.
    public static func monthDisplayName(for periodStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: periodStart)
    }

    /// Temat wiadomości raportu.
    public static func subject(for summary: MonthlyReportSummary) -> String {
        "Ksefiarz — podsumowanie miesiąca: \(monthDisplayName(for: summary.periodStart))"
    }

    /// Treść wiadomości raportu (PL — raport dla właściciela firmy).
    public static func body(for summary: MonthlyReportSummary) -> String {
        func pln(_ amount: Double) -> String { "\(FA2Format.amount(amount)) PLN" }

        var body = """
        Podsumowanie miesiąca \(monthDisplayName(for: summary.periodStart)) (Ksefiarz).

        SPRZEDAŻ
        • Wystawione faktury: \(summary.salesCount)
        • Sprzedaż netto: \(pln(summary.salesNet))
        • VAT należny: \(pln(summary.salesVAT))
        • Sprzedaż brutto: \(pln(summary.salesGross))

        ZAKUPY
        • Faktury zakupu: \(summary.purchasesCount)
        • Zakupy brutto: \(pln(summary.purchasesGross))
        • VAT naliczony: \(pln(summary.purchasesVAT))

        VAT
        • Saldo VAT (należny − naliczony): \(pln(summary.vatBalance))

        NALEŻNOŚCI (stan na dzień raportu)
        • Nieopłacone faktury sprzedaży: \(summary.receivablesCount) na kwotę \(pln(summary.receivablesTotal))
        • W tym po terminie: \(summary.overdueCount) na kwotę \(pln(summary.overdueTotal))
        """
        if summary.missingRateCount > 0 {
            body += "\n\nUwaga: \(summary.missingRateCount) "
            body += summary.missingRateCount == 1
                ? "faktura walutowa bez kursu została ujęta w kwocie nominalnej."
                : "faktury walutowe bez kursu zostały ujęte w kwotach nominalnych."
        }
        body += "\n\nRaport ma charakter poglądowy — saldo VAT nie uwzględnia reguł "
        body += "JPK (m.in. VAT RR, marża, proporcja odliczenia) i nie zastępuje "
        body += "ewidencji księgowej."
        return body
    }
}
