import Foundation

/// Tryb zakresu dat dla importu z KSeF oraz analiz (Kokpit, listy).
public enum DateRangeMode: String, CaseIterable, Identifiable, Sendable {
    case currentMonth
    case lastMonth
    case last3Months
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .currentMonth: return "Bieżący miesiąc"
        case .lastMonth: return "Poprzedni miesiąc"
        case .last3Months: return "Ostatnie 3 miesiące"
        case .custom: return "Własny zakres"
        }
    }
}

/// Wylicza konkretny przedział dat na podstawie trybu z Ustawień.
public enum DateRangeResolver {

    /// Zwraca przedział `[from, to]` dla danego trybu.
    /// - Parameters:
    ///   - mode: tryb zakresu,
    ///   - customFrom/customTo: granice dla trybu własnego,
    ///   - now: punkt odniesienia (parametr ułatwia testowanie).
    public static func range(
        mode: DateRangeMode,
        customFrom: Date,
        customTo: Date,
        now: Date = .now
    ) -> (from: Date, to: Date) {
        let calendar = Calendar.current
        switch mode {
        case .currentMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (start, now)
        case .lastMonth:
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? now
            // Koniec poprzedniego miesiąca = chwila przed początkiem bieżącego.
            let lastMonthEnd = thisMonthStart.addingTimeInterval(-1)
            return (lastMonthStart, lastMonthEnd)
        case .last3Months:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return (start, now)
        case .custom:
            // Zabezpieczenie przed odwróconym zakresem.
            let from = min(customFrom, customTo)
            let to = max(customFrom, customTo)
            // Koniec dnia daty końcowej, aby objąć cały dzień.
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: to) ?? to
            return (calendar.startOfDay(for: from), endOfDay)
        }
    }

    /// Czy data mieści się w przedziale (włącznie).
    public static func contains(_ date: Date, in range: (from: Date, to: Date)) -> Bool {
        date >= range.from && date <= range.to
    }
}
