import Foundation

/// Agregaty finansowe prezentowane w Kokpicie.
/// Liczone wyłącznie z faktur widocznych — ukryte (nieuprawnione)
/// są pomijane, aby nie fałszować wyników.
public struct DashboardMetrics {

    /// Suma brutto nieopłaconych faktur zakupowych (zobowiązania).
    public let purchasesToPayGross: Double
    /// Suma brutto nieopłaconych faktur sprzedażowych (należności).
    public let salesAwaitingGross: Double
    /// Liczba faktur zaległych (nieopłaconych, po terminie).
    public let overdueCount: Int
    /// Nieopłacone faktury z terminem płatności w ciągu najbliższych
    /// `dueSoonDays` dni (posortowane rosnąco po terminie).
    public let dueSoonInvoices: [Invoice]
    /// Horyzont (w dniach) listy najbliższych płatności.
    public let dueSoonDays: Int
    /// Liczba wszystkich widocznych, nieopłaconych faktur.
    public let unpaidCount: Int

    /// Równowartość brutto w PLN: faktury walutowe przeliczane po kursie
    /// z faktury; bez kursu kwota wchodzi nominalnie (lepsze przybliżenie
    /// niż pominięcie — kursy walut UE są rzędu jedności).
    static func grossInPLN(_ invoice: Invoice) -> Double {
        guard invoice.currency != "PLN", invoice.exchangeRate > 0 else {
            return invoice.grossAmount
        }
        return invoice.grossAmount * invoice.exchangeRate
    }

    public init(invoices: [Invoice], now: Date = .now, dueSoonDays: Int = 7) {
        // Pomijamy faktury ukryte/nieuprawnione.
        let visible = invoices.filter { !$0.isArchivedOrHidden }
        let unpaid = visible.filter { !$0.isPaid }

        self.purchasesToPayGross = unpaid
            .filter { $0.kind == .purchase }
            .reduce(0) { $0 + Self.grossInPLN($1) }

        self.salesAwaitingGross = unpaid
            .filter { $0.kind == .sales }
            .reduce(0) { $0 + Self.grossInPLN($1) }

        self.overdueCount = unpaid.filter { $0.isOverdue(asOf: now) }.count
        self.unpaidCount = unpaid.count

        self.dueSoonDays = dueSoonDays
        let horizon = Calendar.current.date(byAdding: .day, value: max(1, dueSoonDays), to: now) ?? now
        self.dueSoonInvoices = unpaid
            .filter { invoice in
                guard let due = invoice.paymentDueDate else { return false }
                return due >= now && due <= horizon
            }
            .sorted { ($0.paymentDueDate ?? .distantFuture) < ($1.paymentDueDate ?? .distantFuture) }
    }
}
