import Foundation

/// Automatyczna numeracja faktur sprzedażowych według konfigurowalnego
/// wzorca (różne firmy stosują różne schematy numeracji).
///
/// Obsługiwane symbole we wzorcu:
/// - `{RRRR}` — rok czterocyfrowy, `{RR}` — dwucyfrowy,
/// - `{MM}` — miesiąc, `{DD}` — dzień,
/// - `{N}`, `{NN}`, `{NNN}`… — kolejny numer (liczba liter N określa
///   minimalną szerokość z zerami wiodącymi).
public enum InvoiceNumberGenerator {

    /// Domyślny wzorzec numeracji.
    public static let defaultPattern = "FV/{RRRR}/{MM}/{NNN}"

    /// Domyślny wzorzec numeracji faktur proforma (osobna seria „PF").
    public static let defaultProformaPattern = "PF/{RRRR}/{MM}/{NNN}"

    /// Proponuje kolejny numer faktury według wzorca, na podstawie
    /// już istniejących numerów. Licznik rośnie w obrębie numerów
    /// pasujących do wzorca po podstawieniu dat (czyli np. resetuje się
    /// co miesiąc dla wzorca z `{MM}`).
    public static func nextNumber(
        pattern: String = defaultPattern,
        existing: [String],
        date: Date = .now
    ) -> String {
        let template = resolveDatePlaceholders(in: normalized(pattern), date: date)
        guard let token = sequenceToken(in: template) else {
            // Nieosiągalne po normalizacji — bezpieczny fallback.
            return template
        }

        let prefix = String(template[..<token.range.lowerBound])
        let suffix = String(template[token.range.upperBound...])

        let highestUsed = existing.compactMap { number -> Int? in
            guard number.count > prefix.count + suffix.count,
                  number.hasPrefix(prefix),
                  number.hasSuffix(suffix) else { return nil }
            let middle = number.dropFirst(prefix.count).dropLast(suffix.count)
            guard !middle.isEmpty, middle.allSatisfy(\.isNumber) else { return nil }
            return Int(middle)
        }.max() ?? 0

        let next = String(format: "%0\(token.width)d", highestUsed + 1)
        return prefix + next + suffix
    }

    /// Podgląd wzorca — numer, jaki otrzymałaby pierwsza faktura.
    public static func preview(pattern: String, date: Date = .now) -> String {
        nextNumber(pattern: pattern, existing: [], date: date)
    }

    /// Czy wzorzec zawiera licznik `{N…}`. Wzorce bez licznika są
    /// automatycznie uzupełniane, ale Ustawienia mogą o tym ostrzec.
    public static func hasSequenceToken(_ pattern: String) -> Bool {
        sequenceToken(in: pattern) != nil
    }

    // MARK: Wewnętrzne

    /// Pusty wzorzec → domyślny; wzorzec bez licznika → dopisany `/{NNN}`.
    static func normalized(_ pattern: String) -> String {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultPattern }
        return hasSequenceToken(trimmed) ? trimmed : trimmed + "/{NNN}"
    }

    /// Podstawia symbole dat w szablonie.
    private static func resolveDatePlaceholders(in pattern: String, date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return pattern
            .replacingOccurrences(of: "{RRRR}", with: String(format: "%04d", year))
            .replacingOccurrences(of: "{RR}", with: String(format: "%02d", year % 100))
            .replacingOccurrences(of: "{MM}", with: String(format: "%02d", month))
            .replacingOccurrences(of: "{DD}", with: String(format: "%02d", day))
    }

    /// Pierwszy token licznika `{N…}` w szablonie.
    private static func sequenceToken(in template: String) -> (range: Range<String.Index>, width: Int)? {
        guard let range = template.range(of: #"\{N+\}"#, options: .regularExpression) else {
            return nil
        }
        // Szerokość = liczba liter N (bez nawiasów).
        let width = template.distance(from: range.lowerBound, to: range.upperBound) - 2
        return (range, width)
    }
}
