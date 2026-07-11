import Foundation

/// Kwota słownie po polsku — standardowy element polskiej faktury
/// (np. „sto dwadzieścia trzy złote 45/100”).
public enum AmountInWords {

    private static let units = [
        "", "jeden", "dwa", "trzy", "cztery", "pięć", "sześć", "siedem", "osiem", "dziewięć",
    ]
    private static let teens = [
        "dziesięć", "jedenaście", "dwanaście", "trzynaście", "czternaście",
        "piętnaście", "szesnaście", "siedemnaście", "osiemnaście", "dziewiętnaście",
    ]
    private static let tens = [
        "", "dziesięć", "dwadzieścia", "trzydzieści", "czterdzieści",
        "pięćdziesiąt", "sześćdziesiąt", "siedemdziesiąt", "osiemdziesiąt", "dziewięćdziesiąt",
    ]
    private static let hundreds = [
        "", "sto", "dwieście", "trzysta", "czterysta",
        "pięćset", "sześćset", "siedemset", "osiemset", "dziewięćset",
    ]

    /// Formy liczebników wielkich: (pojedyncza, 2–4, pozostałe).
    private static let scales: [(String, String, String)] = [
        ("tysiąc", "tysiące", "tysięcy"),
        ("milion", "miliony", "milionów"),
        ("miliard", "miliardy", "miliardów"),
    ]

    /// Zwraca kwotę słownie z groszami w formacie „NN/100”.
    /// Przykład: 123.45 → „sto dwadzieścia trzy złote 45/100”.
    public static func polishCurrency(_ amount: Double) -> String {
        let totalGrosze = Int((abs(amount) * 100).rounded())
        let zlote = totalGrosze / 100
        let grosze = totalGrosze % 100

        let words = zlote == 0 ? "zero" : numberInWords(zlote)
        let currency = currencyForm(for: zlote)
        let sign = amount < 0 ? "minus " : ""
        return "\(sign)\(words) \(currency) \(String(format: "%02d", grosze))/100"
    }

    /// Liczba całkowita słownie (do miliardów).
    static func numberInWords(_ number: Int) -> String {
        guard number != 0 else { return "zero" }
        var parts: [String] = []
        var remainder = number
        var groups: [Int] = []

        while remainder > 0 {
            groups.append(remainder % 1000)
            remainder /= 1000
        }

        // Grupy od najwyższej (miliardy → setki).
        for groupIndex in stride(from: groups.count - 1, through: 0, by: -1) {
            let group = groups[groupIndex]
            guard group > 0 else { continue }

            // „jeden tysiąc” mówimy jako „tysiąc”.
            if !(groupIndex >= 1 && group == 1) {
                parts.append(groupInWords(group))
            }
            if groupIndex >= 1 {
                parts.append(scaleForm(for: group, scale: scales[groupIndex - 1]))
            }
        }
        return parts.joined(separator: " ")
    }

    /// Grupa 1–999 słownie.
    private static func groupInWords(_ group: Int) -> String {
        var parts: [String] = []
        let h = group / 100
        let rest = group % 100

        if h > 0 { parts.append(hundreds[h]) }
        if rest >= 10 && rest <= 19 {
            parts.append(teens[rest - 10])
        } else {
            let t = rest / 10
            let u = rest % 10
            if t > 0 { parts.append(tens[t]) }
            if u > 0 { parts.append(units[u]) }
        }
        return parts.joined(separator: " ")
    }

    /// Polska odmiana liczebników wielkich: 1 tysiąc, 2–4 tysiące, 5+ tysięcy
    /// (z wyjątkiem nastek: 12–14 tysięcy).
    private static func scaleForm(for count: Int, scale: (String, String, String)) -> String {
        if count == 1 { return scale.0 }
        let lastTwo = count % 100
        let last = count % 10
        if (2...4).contains(last) && !(12...14).contains(lastTwo) {
            return scale.1
        }
        return scale.2
    }

    /// Odmiana „złoty”: 1 złoty, 2–4 złote (poza 12–14), inaczej złotych.
    private static func currencyForm(for zlote: Int) -> String {
        if zlote == 1 { return "złoty" }
        let lastTwo = zlote % 100
        let last = zlote % 10
        if (2...4).contains(last) && !(12...14).contains(lastTwo) {
            return "złote"
        }
        return "złotych"
    }
}
