import Foundation

/// Wspólna normalizacja kodów walut pochodzących z formularzy, importów
/// i starszych kopii zapasowych. W modelach docelowo przechowujemy kod ISO
/// wielkimi literami bez otaczających białych znaków.
public enum CurrencyCode {
    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func normalizedOrPLN(_ value: String) -> String {
        let code = normalized(value)
        return code.isEmpty ? "PLN" : code
    }

    public static func isPLN(_ value: String) -> Bool {
        normalized(value) == "PLN"
    }
}
