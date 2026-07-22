import Foundation

/// Rodzaj dokumentu windykacyjnego. Kolejność przypadków odpowiada
/// ścieżce eskalacji: przypomnienie → wezwanie → nota → dane do EPU.
public enum PaymentDemandKind: String, CaseIterable, Identifiable, Sendable {
    /// Miękkie przypomnienie o płatności: same salda, bez odsetek
    /// i bez zapowiedzi drogi sądowej.
    case reminder = "przypomnienie"
    /// Wezwanie do zapłaty: kwoty główne (salda) + odsetki do dnia wezwania.
    case demand = "wezwanie"
    /// Nota odsetkowa: same odsetki naliczone od zaległych faktur.
    case interestNote = "nota"
    /// Dane do pozwu EPU (e-sąd) — nie jest pismem do dłużnika, lecz
    /// kompletem danych do formularza na e-sad.gov.pl (bez PDF).
    case epu = "epu"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .reminder: return "Przypomnienie o płatności"
        case .demand: return "Wezwanie do zapłaty"
        case .interestNote: return "Nota odsetkowa"
        case .epu: return "Dane do pozwu EPU (e-sąd)"
        }
    }

    /// Czy dokument nalicza odsetki (przypomnienie ich nie zawiera; dane
    /// EPU wskazują odsetki opisowo — „do dnia zapłaty” — bez kwoty).
    public var includesInterest: Bool {
        switch self {
        case .demand, .interestNote: return true
        case .reminder, .epu: return false
        }
    }

    /// Działanie windykacyjne odnotowywane na fakturach po utworzeniu
    /// dokumentu tego rodzaju.
    public var collectionAction: DebtCollectionAction {
        switch self {
        case .reminder: return .reminder
        case .demand: return .demand
        case .interestNote: return .interestNote
        case .epu: return .epu
        }
    }
}

/// Pozycja wezwania/noty — jedna zaległa faktura z naliczonymi odsetkami.
public struct PaymentDemandItem: Equatable, Sendable {
    public let invoiceNumber: String
    public let issueDate: Date
    public let dueDate: Date
    /// Saldo pozostałe do zapłaty (w walucie faktury).
    public let outstanding: Double
    /// Dni opóźnienia (od dnia po terminie do dnia dokumentu).
    public let daysOverdue: Int
    /// Odsetki naliczone od salda (w walucie faktury).
    public let interest: Double
    public let currency: String
}

/// Naliczanie odsetek za opóźnienie i budowa pozycji wezwania do zapłaty.
/// Stopa roczna jest konfigurowalna — domyślnie odsetki ustawowe za
/// opóźnienie w transakcjach handlowych (stopa referencyjna NBP + 8 p.p.,
/// ogłaszane w obwieszczeniach MF co pół roku).
public enum PaymentDemandEngine {

    /// Odsetki proste: saldo × stopa% × dni/365, zaokrąglone do groszy.
    public static func interest(
        amount: Double,
        from dueDate: Date,
        to asOf: Date,
        annualRatePercent: Double
    ) -> Double {
        let days = daysOverdue(dueDate: dueDate, asOf: asOf)
        guard days > 0, amount > 0, annualRatePercent > 0 else { return 0 }
        let value = amount * (annualRatePercent / 100) * Double(days) / 365
        return (value * 100).rounded() / 100
    }

    /// Liczba dni opóźnienia — od dnia następującego po terminie płatności
    /// do wskazanego dnia (pełne dni kalendarzowe).
    public static func daysOverdue(dueDate: Date, asOf: Date) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: dueDate)
        let to = calendar.startOfDay(for: asOf)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// Pozycje dokumentu dla wskazanych faktur: tylko zaległe (po terminie),
    /// nieopłacone i widoczne; saldo uwzględnia wpłaty częściowe.
    public static func items(
        for invoices: [Invoice],
        annualRatePercent: Double,
        asOf: Date = .now
    ) -> [PaymentDemandItem] {
        invoices.compactMap { invoice in
            guard !invoice.isArchivedOrHidden, !invoice.isPaid,
                  let due = invoice.paymentDueDate, due < asOf,
                  invoice.outstandingAmount > 0 else { return nil }
            return PaymentDemandItem(
                invoiceNumber: invoice.invoiceNumber,
                issueDate: invoice.issueDate,
                dueDate: due,
                outstanding: invoice.outstandingAmount,
                daysOverdue: daysOverdue(dueDate: due, asOf: asOf),
                interest: interest(
                    amount: invoice.outstandingAmount,
                    from: due,
                    to: asOf,
                    annualRatePercent: annualRatePercent
                ),
                currency: CurrencyCode.normalizedOrPLN(invoice.currency)
            )
        }
        .sorted { $0.dueDate < $1.dueDate }
    }

    /// Sumy per waluta (pozycje mogą mieć różne waluty faktur).
    public static func totals(
        of items: [PaymentDemandItem]
    ) -> [(currency: String, outstanding: Double, interest: Double)] {
        var byCurrency: [String: (outstanding: Double, interest: Double)] = [:]
        for item in items {
            byCurrency[item.currency, default: (0, 0)].outstanding += item.outstanding
            byCurrency[item.currency, default: (0, 0)].interest += item.interest
        }
        return byCurrency
            .map { (currency: $0.key, outstanding: $0.value.outstanding, interest: $0.value.interest) }
            .sorted { $0.currency < $1.currency }
    }
}
