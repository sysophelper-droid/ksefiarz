import Foundation

/// Błędy walidacji szkicu proformy.
public enum ProformaValidationError: LocalizedError, Equatable, Hashable, Sendable {
    case emptyProformaNumber
    case emptySellerName
    case invalidSellerNIP
    case emptyBuyerName
    case invalidBuyerNIP
    case nonPositiveNetAmount
    case negativeVatAmount
    case emptyLineName(Int)
    case nonPositiveLineQuantity(Int)
    case negativeLinePrice(Int)
    case missingExchangeRate
    case validUntilBeforeIssue
    case duplicateProformaNumber(String)

    public var errorDescription: String? {
        switch self {
        case .emptyProformaNumber: return "Numer proformy nie może być pusty."
        case .emptySellerName: return "Nazwa sprzedawcy nie może być pusta."
        case .invalidSellerNIP: return "NIP sprzedawcy jest nieprawidłowy."
        case .emptyBuyerName: return "Nazwa nabywcy nie może być pusta."
        case .invalidBuyerNIP: return "NIP nabywcy jest nieprawidłowy (możesz zostawić puste — proforma dla konsumenta nie wymaga NIP)."
        case .nonPositiveNetAmount: return "Kwota netto musi być większa od zera."
        case .negativeVatAmount: return "Kwota VAT nie może być ujemna."
        case .emptyLineName(let index): return "Pozycja \(index): nazwa towaru lub usługi nie może być pusta."
        case .nonPositiveLineQuantity(let index): return "Pozycja \(index): ilość musi być większa od zera."
        case .negativeLinePrice(let index): return "Pozycja \(index): cena nie może być ujemna."
        case .missingExchangeRate: return "Proforma w walucie obcej z kwotą VAT wymaga kursu PLN."
        case .validUntilBeforeIssue: return "Data ważności („ważna do”) nie może być wcześniejsza niż data wystawienia."
        case .duplicateProformaNumber(let number): return "Proforma o numerze „\(number)” już istnieje — zmień numer."
        }
    }
}

/// Walidator danych proformy. W odróżnieniu od faktury VAT: **NIP nabywcy jest
/// opcjonalny** (proforma bywa wystawiana konsumentowi lub kontrahentowi
/// zagranicznemu) — sprawdzany wyłącznie, gdy został podany. Suma kontrolna
/// NIP i normalizacja numeru pochodzą z `InvoiceValidator`.
public enum ProformaValidator {

    /// Waliduje szkic proformy i zwraca listę wszystkich znalezionych błędów.
    /// `existingNumbers` to znormalizowane (`InvoiceValidator.normalizedNumber`)
    /// numery proform już zapisanych w bazie, BEZ dokumentu właśnie edytowanego.
    public static func validate(
        _ draft: ProformaDraft,
        existingNumbers: Set<String> = []
    ) -> [ProformaValidationError] {
        var errors: [ProformaValidationError] = []

        if existingNumbers.contains(InvoiceValidator.normalizedNumber(draft.proformaNumber)) {
            errors.append(.duplicateProformaNumber(draft.proformaNumber))
        }
        if draft.proformaNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyProformaNumber)
        }
        if draft.sellerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptySellerName)
        }
        if !InvoiceValidator.isValidNIP(draft.sellerNIP) {
            errors.append(.invalidSellerNIP)
        }
        if draft.buyerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyBuyerName)
        }
        // NIP nabywcy opcjonalny — sprawdzany tylko, gdy podany.
        let buyerNIP = draft.buyerNIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if !buyerNIP.isEmpty, !InvoiceValidator.isValidNIP(buyerNIP) {
            errors.append(.invalidBuyerNIP)
        }
        if draft.netAmount <= 0 {
            errors.append(.nonPositiveNetAmount)
        }
        if draft.vatAmount < 0 {
            errors.append(.negativeVatAmount)
        }
        if !CurrencyCode.isPLN(draft.currency), draft.vatAmount > 0, draft.exchangeRate <= 0 {
            errors.append(.missingExchangeRate)
        }
        if let validUntil = draft.validUntil,
           validUntil < Calendar.current.startOfDay(for: draft.issueDate) {
            errors.append(.validUntilBeforeIssue)
        }
        for (offset, line) in draft.lines.enumerated() {
            let number = offset + 1
            if line.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.emptyLineName(number))
            }
            if line.quantity <= 0 {
                errors.append(.nonPositiveLineQuantity(number))
            }
            if line.unitNetPrice < 0 {
                errors.append(.negativeLinePrice(number))
            }
        }
        return errors
    }
}
