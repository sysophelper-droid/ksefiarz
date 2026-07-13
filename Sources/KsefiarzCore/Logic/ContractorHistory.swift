import Foundation

/// Zbiorcza historia współpracy z kontrahentem. Obejmuje widoczne dokumenty
/// sprzedaży i zakupu, ale zachowanie płatnicze ocenia wyłącznie po sprzedaży
/// (terminowość zakupów opisuje nas, a nie kontrahenta).
public struct ContractorHistory {

    /// Tolerancja groszowa zgodna z ewidencją wpłat. Lokalna stała utrzymuje
    /// czystą logikę niezależną od izolowanego na MainActor koordynatora.
    private static let paymentTolerance = 0.005

    /// Saldo w jednej walucie. Należności i zobowiązania są prezentowane
    /// osobno, bo nie wolno sumować kwot z różnych walut ani zacierać kierunku.
    public struct CurrencyBalance: Equatable, Sendable {
        public let currency: String
        public let receivables: Double
        public let payables: Double

        /// Saldo netto: należności minus zobowiązania.
        public var net: Double { receivables - payables }
    }

    /// Słowna interpretacja wyniku terminowości.
    public enum PaymentScore: Equatable, Sendable {
        case excellent
        case good
        case needsAttention
        case poor
        case unrated

        public var displayName: String {
            switch self {
            case .excellent: return "Bardzo dobra"
            case .good: return "Dobra"
            case .needsAttention: return "Wymaga uwagi"
            case .poor: return "Słaba"
            case .unrated: return "Brak danych"
            }
        }
    }

    /// Wszystkie widoczne dokumenty przypisane do kontrahenta, od najnowszego.
    public let invoices: [Invoice]
    public let salesCount: Int
    public let purchaseCount: Int
    public let balances: [CurrencyBalance]

    /// Średnia liczba dni od wystawienia do pełnej zapłaty. Liczymy tylko
    /// dokumenty sprzedaży z wiarygodną datą zapłaty.
    public let averagePaymentDays: Double?

    /// Liczba sprzedaży użytych do średniej czasu płatności.
    public let paymentTimeSampleCount: Int

    /// Udział terminowych płatności 0...1. Próba obejmuje zapłacone faktury
    /// z terminem i datą zapłaty oraz aktualnie zaległe, niezapłacone faktury.
    public let onTimeRate: Double?
    public let onTimeCount: Int
    public let timelinessSampleCount: Int
    public let score: PaymentScore

    public init(invoices allInvoices: [Invoice], contractorNIP: String, asOf: Date = .now) {
        let normalizedNIP = Self.normalizedTaxID(contractorNIP)
        let matched = allInvoices
            .filter { invoice in
                guard !invoice.isArchivedOrHidden, !normalizedNIP.isEmpty else { return false }
                let invoiceNIP = invoice.kind == .sales ? invoice.buyerNIP : invoice.sellerNIP
                return Self.normalizedTaxID(invoiceNIP) == normalizedNIP
            }
            .sorted {
                if $0.issueDate != $1.issueDate { return $0.issueDate > $1.issueDate }
                return $0.invoiceNumber.localizedStandardCompare($1.invoiceNumber) == .orderedAscending
            }

        invoices = matched
        salesCount = matched.count { $0.kind == .sales }
        purchaseCount = matched.count { $0.kind == .purchase }

        var amounts: [String: (receivables: Double, payables: Double)] = [:]
        for invoice in matched where !invoice.isPaid {
            let currency = Self.normalizedCurrency(invoice.currency)
            let remaining = invoice.grossAmount - invoice.paidAmount
            if invoice.kind == .sales {
                amounts[currency, default: (0, 0)].receivables += remaining
            } else {
                amounts[currency, default: (0, 0)].payables += remaining
            }
        }
        balances = amounts.map { currency, value in
            CurrencyBalance(
                currency: currency,
                receivables: value.receivables,
                payables: value.payables
            )
        }
        .sorted { $0.currency < $1.currency }

        let sales = matched.filter { $0.kind == .sales }
        let paymentDurations = sales.compactMap { invoice -> Int? in
            guard let paidAt = Self.paymentCompletionDate(for: invoice) else { return nil }
            return Self.calendarDays(from: invoice.issueDate, to: paidAt)
        }
        paymentTimeSampleCount = paymentDurations.count
        averagePaymentDays = paymentDurations.isEmpty
            ? nil
            : Double(paymentDurations.reduce(0, +)) / Double(paymentDurations.count)

        var timely = 0
        var scored = 0
        for invoice in sales {
            guard let dueDate = invoice.paymentDueDate else { continue }
            if let paidAt = Self.paymentCompletionDate(for: invoice) {
                scored += 1
                if Self.isSameDayOrEarlier(paidAt, than: dueDate) { timely += 1 }
            } else if !invoice.isPaid && invoice.grossAmount - invoice.paidAmount > Self.paymentTolerance,
                      !Self.isSameDayOrEarlier(asOf, than: dueDate) {
                // Otwarta faktura po terminie jest już zdarzeniem nieterminowym.
                scored += 1
            }
        }
        onTimeCount = timely
        timelinessSampleCount = scored
        onTimeRate = scored == 0 ? nil : Double(timely) / Double(scored)
        score = Self.paymentScore(for: onTimeRate)
    }

    /// Normalizacja pozwala łączyć wpis słownikowy z dokumentami, w których
    /// NIP zapisano z prefiksem kraju, spacjami albo myślnikami.
    public static func normalizedTaxID(_ value: String) -> String {
        let normalized = value.uppercased().filter { $0.isLetter || $0.isNumber }
        if normalized.hasPrefix("PL") {
            let withoutCountry = String(normalized.dropFirst(2))
            if withoutCountry.count == 10, withoutCountry.allSatisfy(\.isNumber) {
                return withoutCountry
            }
        }
        return normalized
    }

    public static func paymentScore(for onTimeRate: Double?) -> PaymentScore {
        guard let onTimeRate else { return .unrated }
        switch onTimeRate {
        case 0.9...: return .excellent
        case 0.75...: return .good
        case 0.5...: return .needsAttention
        default: return .poor
        }
    }

    /// Data pełnej zapłaty: jawna data z dokumentu albo dzień wpłaty, która
    /// domknęła kwotę brutto. Sam ręczny znacznik bez daty nie jest podstawą
    /// do oceny — zapobiega tworzeniu pozornie precyzyjnego scoringu.
    public static func paymentCompletionDate(for invoice: Invoice) -> Date? {
        if let paymentDate = invoice.paymentDate { return paymentDate }
        guard invoice.grossAmount > Self.paymentTolerance else { return nil }

        var accumulated = 0.0
        for payment in invoice.payments.sorted(by: { $0.date < $1.date }) {
            accumulated += payment.amount
            if accumulated >= invoice.grossAmount - Self.paymentTolerance {
                return payment.date
            }
        }
        return nil
    }

    private static func normalizedCurrency(_ value: String) -> String {
        let currency = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return currency.isEmpty ? "PLN" : currency
    }

    private static func calendarDays(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return max(0, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0)
    }

    private static func isSameDayOrEarlier(_ date: Date, than reference: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: reference)
    }
}
