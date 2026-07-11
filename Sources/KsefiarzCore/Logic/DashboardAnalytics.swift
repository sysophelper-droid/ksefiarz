import Foundation

/// Rozszerzona analityka Kokpitu: przepływy pieniężne, VAT należny
/// i naliczony, struktura wiekowa należności/zobowiązań oraz porównanie
/// bieżącego i poprzedniego miesiąca. Czysta logika liczona z widocznych
/// faktur (ukryte pomija wywołujący — jak w `DashboardMetrics`).
public struct DashboardAnalytics {

    /// Punkt przepływów pieniężnych jednego miesiąca (kwoty w PLN).
    public struct MonthCashFlow: Equatable, Sendable {
        /// Pierwszy dzień miesiąca.
        public let month: Date
        /// Wpływy — wpłaty zaksięgowane na fakturach sprzedażowych.
        public let inflow: Double
        /// Wydatki — zapłaty zaksięgowane na fakturach zakupowych.
        public let outflow: Double

        public var balance: Double { inflow - outflow }
    }

    /// Przedział struktury wiekowej nieopłaconych faktur (kwoty w PLN).
    public struct AgingBucket: Equatable, Sendable {
        public let label: String
        /// Należności — nieopłacona sprzedaż (saldo).
        public let receivables: Double
        /// Zobowiązania — nieopłacone zakupy (saldo).
        public let payables: Double
    }

    /// Sumy jednego miesiąca do porównania miesięcznego (kwoty w PLN).
    public struct MonthSummary: Equatable, Sendable {
        public let month: Date
        public let salesGross: Double
        public let purchasesGross: Double
        /// VAT należny z faktur sprzedażowych wystawionych w miesiącu.
        public let vatDue: Double

        /// Zmiana procentowa względem innego miesiąca (nil, gdy brak bazy).
        public static func change(from previous: Double, to current: Double) -> Double? {
            guard previous != 0 else { return nil }
            return (current - previous) / abs(previous) * 100
        }
    }

    /// VAT należny (sprzedaż) w analizowanym okresie Kokpitu.
    public let vatDue: Double
    /// VAT naliczony (zakupy) w analizowanym okresie Kokpitu.
    public let vatInput: Double
    /// Saldo VAT (należny − naliczony).
    public var vatBalance: Double { vatDue - vatInput }

    /// Przepływy pieniężne z ewidencji wpłat — ostatnie miesiące
    /// (najstarszy pierwszy).
    public let cashFlow: [MonthCashFlow]

    /// Struktura wiekowa nieopłaconych faktur (kolejność od „przed terminem”).
    public let aging: [AgingBucket]

    /// Bieżący i poprzedni miesiąc do porównania.
    public let currentMonth: MonthSummary
    public let previousMonth: MonthSummary

    /// Kwota w PLN — faktury walutowe po kursie z faktury (bez kursu
    /// nominalnie, spójnie z `DashboardMetrics.grossInPLN`).
    static func inPLN(_ amount: Double, invoice: Invoice) -> Double {
        guard invoice.currency != "PLN", invoice.exchangeRate > 0 else { return amount }
        return amount * invoice.exchangeRate
    }

    /// - Parameters:
    ///   - invoices: wszystkie WIDOCZNE faktury (przepływy, wiekowanie,
    ///     porównania miesięczne liczą się niezależnie od filtra okresu),
    ///   - periodInvoices: faktury z analizowanego okresu Kokpitu (VAT),
    ///   - now: chwila odniesienia (testy),
    ///   - months: liczba miesięcy przepływów pieniężnych.
    public init(
        invoices: [Invoice],
        periodInvoices: [Invoice],
        now: Date = .now,
        months: Int = 6
    ) {
        let calendar = Calendar.current

        // VAT w analizowanym okresie.
        self.vatDue = periodInvoices
            .filter { $0.kind == .sales }
            .reduce(0) { $0 + Self.inPLN($1.vatAmount, invoice: $1) }
        self.vatInput = periodInvoices
            .filter { $0.kind == .purchase }
            .reduce(0) { $0 + Self.inPLN($1.vatAmount, invoice: $1) }

        // Przepływy pieniężne: wpłaty (PaymentRecord) pogrupowane po miesiącu.
        let monthStarts: [Date] = (0..<max(1, months)).reversed().compactMap { offset in
            guard let shifted = calendar.date(byAdding: .month, value: -offset, to: now) else {
                return nil
            }
            return calendar.date(from: calendar.dateComponents([.year, .month], from: shifted))
        }
        var flows: [Date: (inflow: Double, outflow: Double)] = Dictionary(
            uniqueKeysWithValues: monthStarts.map { ($0, (0, 0)) }
        )
        for invoice in invoices {
            for payment in invoice.payments {
                guard let monthStart = calendar.date(
                    from: calendar.dateComponents([.year, .month], from: payment.date)
                ), flows[monthStart] != nil else { continue }
                let amount = Self.inPLN(payment.amount, invoice: invoice)
                if invoice.kind == .sales {
                    flows[monthStart]?.inflow += amount
                } else {
                    flows[monthStart]?.outflow += amount
                }
            }
        }
        self.cashFlow = monthStarts.map {
            MonthCashFlow(month: $0, inflow: flows[$0]?.inflow ?? 0, outflow: flows[$0]?.outflow ?? 0)
        }

        // Struktura wiekowa nieopłaconych faktur po saldzie (uwzględnia
        // płatności częściowe).
        let unpaid = invoices.filter { !$0.isPaid }
        var buckets = [
            ("Przed terminem", 0.0, 0.0),
            ("1–30 dni", 0.0, 0.0),
            ("31–60 dni", 0.0, 0.0),
            ("61–90 dni", 0.0, 0.0),
            ("Ponad 90 dni", 0.0, 0.0),
        ]
        for invoice in unpaid {
            let outstanding = Self.inPLN(invoice.outstandingAmount, invoice: invoice)
            guard outstanding > 0 else { continue }
            let index: Int
            if let due = invoice.paymentDueDate, due < now {
                let days = calendar.dateComponents([.day], from: due, to: now).day ?? 0
                switch days {
                case ...30: index = 1
                case 31...60: index = 2
                case 61...90: index = 3
                default: index = 4
                }
            } else {
                index = 0 // przed terminem albo bez terminu płatności
            }
            if invoice.kind == .sales {
                buckets[index].1 += outstanding
            } else {
                buckets[index].2 += outstanding
            }
        }
        self.aging = buckets.map { AgingBucket(label: $0.0, receivables: $0.1, payables: $0.2) }

        // Porównanie miesięczne (po dacie wystawienia).
        func summary(monthOf reference: Date) -> MonthSummary {
            let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: reference)
            ) ?? reference
            let inMonth = invoices.filter {
                calendar.isDate($0.issueDate, equalTo: monthStart, toGranularity: .month)
            }
            let sales = inMonth.filter { $0.kind == .sales }
            let purchases = inMonth.filter { $0.kind == .purchase }
            return MonthSummary(
                month: monthStart,
                salesGross: sales.reduce(0) { $0 + Self.inPLN($1.grossAmount, invoice: $1) },
                purchasesGross: purchases.reduce(0) { $0 + Self.inPLN($1.grossAmount, invoice: $1) },
                vatDue: sales.reduce(0) { $0 + Self.inPLN($1.vatAmount, invoice: $1) }
            )
        }
        self.currentMonth = summary(monthOf: now)
        let previousReference = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        self.previousMonth = summary(monthOf: previousReference)
    }
}
