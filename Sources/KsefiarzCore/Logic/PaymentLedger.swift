import Foundation

/// Księgowanie wpłat na fakturze — jedyne miejsce zmieniające historię
/// płatności. Pilnuje niezmiennika: znacznik „opłacona” może zostać
/// USTAWIONY automatycznie (pełne pokrycie salda), ale nigdy nie jest
/// automatycznie cofany; wyjątkiem jest usunięcie wpłaty, która sama
/// domknęła saldo (cofnięcie skutku własnej operacji użytkownika).
@MainActor
public enum PaymentLedger {

    /// Tolerancja groszowa porównań kwot.
    public static let tolerance = 0.005

    /// Rejestruje wpłatę i zwraca utworzony wpis. Gdy suma wpłat pokryje
    /// kwotę brutto, faktura zostaje oznaczona jako opłacona.
    @discardableResult
    public static func register(
        amount: Double,
        date: Date = .now,
        note: String = "",
        source: PaymentRecord.Source = .manual,
        on invoice: Invoice
    ) -> PaymentRecord {
        let payment = PaymentRecord(amount: amount, date: date, note: note, source: source)
        invoice.payments.append(payment)
        if invoice.paidAmount >= invoice.grossAmount - tolerance {
            invoice.isPaid = true
        }
        return payment
    }

    /// Usuwa wpłatę. Znacznik „opłacona” jest cofany WYŁĄCZNIE wtedy,
    /// gdy przed usunięciem wpłaty pokrywały pełną kwotę, a po usunięciu
    /// już nie — ręczne oznaczenia i formy płatne z góry (bez kompletu
    /// wpłat) pozostają nietknięte.
    public static func remove(_ payment: PaymentRecord, from invoice: Invoice) {
        let coveredBefore = invoice.paidAmount >= invoice.grossAmount - tolerance
        invoice.payments.removeAll { $0.id == payment.id }
        let coveredAfter = invoice.paidAmount >= invoice.grossAmount - tolerance
        if coveredBefore && !coveredAfter {
            invoice.isPaid = false
        }
    }
}
