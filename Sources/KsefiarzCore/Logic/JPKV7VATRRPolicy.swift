import Foundation

/// Specyfikacja podatkowa ujęcia faktury VAT RR po stronie nabywcy.
///
/// Art. 116 ust. 6 ustawy o VAT pozwala zwiększyć podatek naliczony dopiero
/// w okresie zapłaty należności (razem ze zryczałtowanym zwrotem) na rachunek
/// rolnika, przy związku nabycia ze sprzedażą opodatkowaną i prawidłowym
/// opisaniu dowodu zapłaty. JPK oznacza taki dowód jako `VAT_RR`, a kwoty
/// pozostałego nabycia wykazuje w K_42/K_43.
///
/// Aplikacja potrafi potwierdzić datę i pełną kwotę rozliczenia oraz kanał
/// bankowy. Związek ze sprzedażą opodatkowaną i treść dowodu przelewu pozostają
/// do weryfikacji podatnika i są przypominane ostrzeżeniem generatora.
public enum JPKV7VATRRPolicy {

    /// Tolerancja groszowa niezależna od izolowanego `PaymentLedger`.
    static let tolerance = 0.005

    public struct Recognition: Equatable, Sendable {
        /// Data zapłaty nabywcy albo data zwrotu przy korekcie zmniejszającej.
        public var date: Date
        /// Dodatkowa kontrola, której nie da się wyprowadzić z modelu faktury.
        public var advisory: String
    }

    public enum Decision: Equatable, Sendable {
        case recognize(Recognition)
        /// Pominięcie wymagające ostrzeżenia — warunki art. 116 niespełnione.
        case omit(reason: String)
        /// Pominięcie oczywiste (dokument nie wpływa na K_42/K_43, np. korekta
        /// bez zmiany kwot) — bez wiersza ewidencji i bez ostrzeżenia.
        case omitSilently
    }

    /// Klasyfikuje wyłącznie zakupową fakturę VAT RR / VAT RR KOREKTA.
    /// Zwykłe zakupy nie podlegają tej polityce.
    public static func decision(for invoice: Invoice) -> Decision {
        guard invoice.kind == .purchase, invoice.isRR else {
            return .omitSilently
        }

        // Korekta bez zmiany kwot nie wpływa na K_42/K_43 i nie tworzy
        // samodzielnego wiersza kwotowego ewidencji.
        if invoice.isCorrection,
           abs(invoice.netAmount) < tolerance,
           abs(invoice.vatAmount) < tolerance {
            return .omitSilently
        }

        guard let paymentEvidence = bankPaymentEvidence(invoice) else {
            return .omit(
                reason: "brak potwierdzenia rozliczenia bankowego na rachunek rolnika (forma przelew i numer rachunku albo pełna płatność z importu wyciągu)"
            )
        }

        // Wyróżnikiem korekty zmniejszającej jest saldo brutto — to jego zwrot
        // przez rolnika warunkuje ujęcie (art. 116 ust. 6c); ten sam predykat
        // steruje komunikatem o brakującej dacie i treścią przypomnienia.
        let isRefundCorrection = invoice.isCorrection && invoice.grossAmount < 0

        guard let date = settlementDate(invoice, evidence: paymentEvidence) else {
            let action = isRefundCorrection
                ? "zwrotu kwoty przez rolnika"
                : "pełnej zapłaty wraz ze zryczałtowanym zwrotem"
            return .omit(reason: "brak daty \(action)")
        }

        let advisory: String
        if isRefundCorrection {
            advisory = "VAT RR ujęty według daty zwrotu przez rolnika; zweryfikuj bankowy dowód zwrotu i dane faktury VAT RR KOREKTA (art. 116 ust. 6a i 6c)."
        } else {
            advisory = "VAT RR ujęty według daty zapłaty; zweryfikuj związek nabycia ze sprzedażą opodatkowaną oraz numer/data faktury lub numer KSeF na dowodzie zapłaty (art. 116 ust. 6)."
        }
        return .recognize(Recognition(date: date, advisory: advisory))
    }

    /// Data rozliczenia z pola faktury albo dzień, w którym suma zapisanych
    /// płatności po raz pierwszy pokryła pełną (bezwzględną) kwotę brutto.
    /// Częściowa zapłata nie uruchamia automatycznego odliczenia — generator
    /// czeka na pełne pokrycie, aby nie zawyżyć podatku naliczonego.
    static func settlementDate(_ invoice: Invoice, evidence: PaymentEvidence) -> Date? {
        if evidence == .invoiceTransfer, let paymentDate = invoice.paymentDate {
            return paymentDate
        }

        let required = abs(invoice.grossAmount)
        guard required >= tolerance else { return nil }
        var total = 0.0
        let payments = evidence == .bankImport
            ? invoice.payments.filter { $0.source == .bankImport }
            : invoice.payments
        for payment in payments.sorted(by: { $0.date < $1.date }) {
            total += max(0, payment.amount)
            if total >= required - tolerance {
                return payment.date
            }
        }
        return nil
    }

    /// Dane faktury potwierdzają przelew na rachunek rolnika. Alternatywnie
    /// komplet płatności może pochodzić z importu wyciągu bankowego.
    enum PaymentEvidence: Equatable {
        case invoiceTransfer
        case bankImport
    }

    static func bankPaymentEvidence(_ invoice: Invoice) -> PaymentEvidence? {
        if invoice.paymentForm == .transfer,
           !(invoice.paymentBankAccount ?? "").filter(\.isNumber).isEmpty {
            return .invoiceTransfer
        }

        let required = abs(invoice.grossAmount)
        guard required >= tolerance else { return nil }
        let imported = invoice.payments
            .filter { $0.source == .bankImport }
            .reduce(0) { $0 + max(0, $1.amount) }
        return imported >= required - tolerance ? .bankImport : nil
    }
}
