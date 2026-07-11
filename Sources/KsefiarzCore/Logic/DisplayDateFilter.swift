import Foundation

/// Filtr wyświetlania faktur — niezależny dla Kokpitu i każdej listy.
/// W odróżnieniu od zakresu importu (Ustawienia) działa wyłącznie lokalnie
/// na danych już pobranych.
public enum DisplayDateFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case currentMonth
    case lastMonth
    case last3Months
    case currentYear

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "Wszystkie"
        case .currentMonth: return "Bieżący miesiąc"
        case .lastMonth: return "Poprzedni miesiąc"
        case .last3Months: return "Ostatnie 3 miesiące"
        case .currentYear: return "Bieżący rok"
        }
    }

    /// Przedział dat dla filtra; `nil` oznacza brak ograniczenia (Wszystkie).
    public func range(now: Date = .now) -> (from: Date, to: Date)? {
        let calendar = Calendar.current
        switch self {
        case .all:
            return nil
        case .currentMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (start, now)
        case .lastMonth:
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? now
            return (start, thisMonthStart.addingTimeInterval(-1))
        case .last3Months:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return (start, now)
        case .currentYear:
            let start = calendar.dateInterval(of: .year, for: now)?.start ?? now
            return (start, now)
        }
    }

    /// Filtruje faktury po dacie wystawienia.
    public func apply(to invoices: [Invoice], now: Date = .now) -> [Invoice] {
        guard let range = range(now: now) else { return invoices }
        return invoices.filter { $0.issueDate >= range.from && $0.issueDate <= range.to }
    }
}
