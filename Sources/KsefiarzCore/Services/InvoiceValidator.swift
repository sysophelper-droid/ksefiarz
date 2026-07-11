import Foundation

/// Błędy walidacji szkicu faktury.
public enum InvoiceValidationError: LocalizedError, Equatable, Hashable, Sendable {
    case emptyInvoiceNumber
    case emptySellerName
    case emptySellerAddress
    case emptyBuyerName
    case invalidSellerNIP
    case invalidBuyerNIP
    case nonPositiveNetAmount
    case negativeVatAmount
    case amountsMismatch
    case emptyLineName(Int)
    case nonPositiveLineQuantity(Int)
    case negativeLinePrice(Int)
    case emptyCorrectedInvoiceNumber
    case missingExchangeRate
    case missingAdvanceInvoiceRefs
    case duplicateInvoiceNumber(String)
    case invalidLineOSSRate(Int)
    case attachmentMissingMetadata(Int)
    case attachmentTooManyParagraphs(Int)
    case attachmentInvalidTable(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyInvoiceNumber: return "Numer faktury nie może być pusty."
        case .emptySellerName: return "Nazwa sprzedawcy nie może być pusta."
        case .emptySellerAddress: return "Adres sprzedawcy jest wymagany przez schemę FA(2) — uzupełnij go w Ustawieniach."
        case .emptyBuyerName: return "Nazwa nabywcy nie może być pusta."
        case .invalidSellerNIP: return "NIP sprzedawcy jest nieprawidłowy."
        case .invalidBuyerNIP: return "NIP nabywcy jest nieprawidłowy."
        case .nonPositiveNetAmount: return "Kwota netto musi być większa od zera."
        case .negativeVatAmount: return "Kwota VAT nie może być ujemna."
        case .amountsMismatch: return "Kwota brutto musi być sumą netto i VAT."
        case .emptyLineName(let index): return "Pozycja \(index): nazwa towaru lub usługi nie może być pusta."
        case .nonPositiveLineQuantity(let index): return "Pozycja \(index): ilość musi być większa od zera."
        case .negativeLinePrice(let index): return "Pozycja \(index): cena nie może być ujemna."
        case .emptyCorrectedInvoiceNumber: return "Korekta musi wskazywać numer faktury korygowanej."
        case .missingExchangeRate: return "Faktura w walucie obcej z kwotą VAT wymaga kursu PLN (przeliczenie VAT — art. 106e ust. 11 ustawy o VAT)."
        case .missingAdvanceInvoiceRefs: return "Faktura rozliczeniowa (ROZ) musi wskazywać numery KSeF faktur zaliczkowych."
        case .duplicateInvoiceNumber(let number): return "Faktura o numerze „\(number)” już istnieje w bazie — zmień numer, aby nie zaburzyć numeracji."
        case .invalidLineOSSRate(let index): return "Pozycja \(index): stawka OSS musi mieścić się w zakresie 0–100%."
        case .attachmentMissingMetadata(let index): return "Załącznik, blok \(index): wymagana jest co najmniej jedna para metadanych (klucz i wartość) — wymóg schematu FA(3)."
        case .attachmentTooManyParagraphs(let index): return "Załącznik, blok \(index): część tekstowa może mieć najwyżej 10 akapitów."
        case .attachmentInvalidTable(let index): return "Załącznik, blok \(index): tabela musi mieć od 1 do 20 kolumn i co najmniej jeden wiersz."
        }
    }
}

/// Walidator danych faktury — w tym poprawności polskiego numeru NIP.
public enum InvoiceValidator {

    /// Waliduje szkic faktury i zwraca listę wszystkich znalezionych błędów.
    /// `existingNumbers` to numery dokumentów już zapisanych w bazie
    /// (znormalizowane przez `normalizedNumber`, BEZ dokumentu właśnie
    /// edytowanego) — duplikat numeru blokuje zapis i wysyłkę.
    public static func validate(
        _ draft: InvoiceDraft,
        existingNumbers: Set<String> = []
    ) -> [InvoiceValidationError] {
        var errors: [InvoiceValidationError] = []
        if existingNumbers.contains(normalizedNumber(draft.invoiceNumber)) {
            errors.append(.duplicateInvoiceNumber(draft.invoiceNumber))
        }

        if draft.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyInvoiceNumber)
        }
        if draft.sellerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptySellerName)
        }
        if draft.buyerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyBuyerName)
        }
        if !isValidNIP(draft.sellerNIP) {
            errors.append(.invalidSellerNIP)
        }
        if !isValidNIP(draft.buyerNIP) {
            errors.append(.invalidBuyerNIP)
        }
        if draft.sellerAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptySellerAddress)
        }
        // Korekta wyraża różnicę — kwoty mogą być ujemne; zwykła faktura nie.
        let isCorrection = draft.correction != nil
        if !isCorrection, draft.netAmount <= 0 {
            errors.append(.nonPositiveNetAmount)
        }
        if !isCorrection, draft.vatAmount < 0 {
            errors.append(.negativeVatAmount)
        }
        if abs(draft.netAmount + draft.vatAmount - draft.grossAmount) > 0.01 {
            errors.append(.amountsMismatch)
        }
        if let correction = draft.correction,
           correction.originalNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyCorrectedInvoiceNumber)
        }
        // Waluta obca: VAT musi mieć przeliczenie na PLN (P_14_xW).
        if draft.currency != "PLN", draft.vatAmount > 0, draft.exchangeRate <= 0 {
            errors.append(.missingExchangeRate)
        }
        // Faktura rozliczeniowa musi wskazywać rozliczane zaliczki.
        if draft.documentType == "ROZ",
           draft.advanceInvoiceRefs.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            errors.append(.missingAdvanceInvoiceRefs)
        }
        // Walidacja pozycji faktury.
        for (offset, line) in draft.lines.enumerated() {
            let number = offset + 1
            if line.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.emptyLineName(number))
            }
            if line.quantity <= 0 {
                errors.append(.nonPositiveLineQuantity(number))
            }
            if !isCorrection, line.unitNetPrice < 0 {
                errors.append(.negativeLinePrice(number))
            }
            if let ossRate = line.ossRate, !(0...100).contains(ossRate) {
                errors.append(.invalidLineOSSRate(number))
            }
        }
        // Walidacja załącznika FA(3) — ograniczenia z XSD.
        for (offset, block) in draft.attachments.enumerated() {
            let number = offset + 1
            let metadata = block.metadata.filter {
                !$0.key.trimmingCharacters(in: .whitespaces).isEmpty
                    && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
            }
            if metadata.isEmpty {
                errors.append(.attachmentMissingMetadata(number))
            }
            let paragraphs = block.paragraphs.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if paragraphs.count > 10 {
                errors.append(.attachmentTooManyParagraphs(number))
            }
            for table in block.tables {
                if table.columns.isEmpty || table.columns.count > 20 || table.rows.isEmpty {
                    errors.append(.attachmentInvalidTable(number))
                    break
                }
            }
        }
        return errors
    }

    /// Numer dokumentu w postaci porównywalnej: bez otaczających spacji,
    /// bez rozróżniania wielkości liter („fv/1/2026” = „FV/1/2026”).
    public static func normalizedNumber(_ number: String) -> String {
        number.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Sprawdza poprawność polskiego numeru NIP (10 cyfr + suma kontrolna).
    /// Akceptuje NIP z myślnikami i spacjami, np. "526-025-02-74".
    public static func isValidNIP(_ nip: String) -> Bool {
        let digits = nip.filter(\.isNumber).compactMap { $0.wholeNumberValue }
        // NIP musi mieć dokładnie 10 cyfr (po odrzuceniu separatorów nie może być innych znaków).
        let stripped = nip.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard stripped.count == 10, digits.count == 10 else { return false }

        // Wagi sumy kontrolnej NIP.
        let weights = [6, 5, 7, 2, 3, 4, 5, 6, 7]
        let checksum = zip(digits, weights).reduce(0) { $0 + $1.0 * $1.1 } % 11
        // Suma kontrolna równa 10 jest zawsze nieprawidłowa.
        guard checksum != 10 else { return false }
        return checksum == digits[9]
    }
}
