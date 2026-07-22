import Foundation

/// Polityka form płatności — konfigurowalna w Ustawieniach.
///
/// Formy „opłacone z góry” (np. gotówka, karta) powodują, że faktura
/// jest od razu traktowana jako opłacona; formy odroczone (np. przelew)
/// pozostawiają fakturę jako „do opłacenia”.
public enum PaymentFormPolicy {

    /// Domyślny zestaw form opłaconych z góry:
    /// gotówka, karta, bon i płatność mobilna.
    public static let defaultPrepaidForms: Set<String> = [
        PaymentForm.cash.rawValue,
        PaymentForm.card.rawValue,
        PaymentForm.voucher.rawValue,
        PaymentForm.mobile.rawValue,
    ]

    /// Serializacja zestawu do wartości @AppStorage (kody rozdzielone przecinkami).
    public static func encode(_ forms: Set<String>) -> String {
        forms.sorted().joined(separator: ",")
    }

    /// Deserializacja z wartości @AppStorage.
    public static func decode(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").compactMap {
            let value = String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        })
    }

    /// Czy dana forma płatności jest opłacona z góry według konfiguracji.
    public static func isPrepaid(_ form: PaymentForm?, prepaidForms: Set<String>) -> Bool {
        guard let form else { return false }
        return prepaidForms.contains(form.rawValue)
    }

    /// Stosuje politykę do faktury: forma opłacona z góry może tylko
    /// USTAWIĆ status „opłacona” — nigdy go nie cofa (ręczne oznaczenia
    /// i znacznik „Zaplacono” mają pierwszeństwo).
    public static func apply(to invoice: Invoice, prepaidForms: Set<String>) {
        if !invoice.isPaid, isPrepaid(invoice.paymentForm, prepaidForms: prepaidForms) {
            invoice.isPaid = true
        }
    }
}
