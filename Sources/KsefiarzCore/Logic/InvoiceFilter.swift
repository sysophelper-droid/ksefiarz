import Foundation

/// Filtr statusu płatności używany na listach faktur.
public enum PaymentStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case paid
    case unpaid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "Wszystkie"
        case .paid: return "Opłacone"
        case .unpaid: return "Nieopłacone"
        }
    }
}

/// Filtr statusu wysyłki do KSeF — używany na liście faktur sprzedażowych.
public enum KSeFSyncFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case sent
    case offlinePending
    case processing
    case accepted
    case rejected
    case localOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "Wszystkie"
        case .sent: return "Przekazane do KSeF"
        case .offlinePending: return "Offline24 (do dosłania)"
        case .processing: return "Przetwarzane"
        case .accepted: return "Przyjęte"
        case .rejected: return "Odrzucone"
        case .localOnly: return "Tylko lokalne"
        }
    }

    /// Filtruje faktury po statusie wysyłki.
    public func apply(to invoices: [Invoice]) -> [Invoice] {
        switch self {
        case .all: return invoices
        case .sent: return invoices.filter { !$0.isLocalOnly }
        case .offlinePending: return invoices.filter { $0.ksefSubmissionStatus == .offlinePending }
        case .processing: return invoices.filter { $0.ksefSubmissionStatus == .processing }
        case .accepted: return invoices.filter { $0.ksefSubmissionStatus == .accepted }
        case .rejected: return invoices.filter { $0.ksefSubmissionStatus == .rejected }
        case .localOnly: return invoices.filter { $0.isLocalOnly }
        }
    }
}

/// Czysta logika filtrowania listy faktur — łatwa do przetestowania jednostkowo.
public enum InvoiceFilter {

    /// Tekst do wyszukiwania bez rozróżniania wielkości liter i polskich
    /// znaków. `ł` wymaga jawnej zamiany, bo nie jest znakiem składanym.
    static func normalizedSearchText(_ text: String) -> String {
        text.replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "l")
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "pl_PL")
            )
    }

    /// Token składający się wyłącznie z cyfr i typowych separatorów NIP.
    private static func identifierDigits(from token: String) -> String? {
        let allowed = CharacterSet.decimalDigits.union(
            CharacterSet(charactersIn: "-./")
        )
        guard !token.isEmpty,
              token.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        let digits = token.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    /// Filtruje faktury po statusie płatności i frazie wyszukiwania
    /// (NIP, nazwa kontrahenta lub numer faktury).
    public static func apply(
        _ invoices: [Invoice],
        status: PaymentStatusFilter,
        searchText: String
    ) -> [Invoice] {
        var result = invoices

        switch status {
        case .all:
            break
        case .paid:
            result = result.filter { $0.isPaid }
        case .unpaid:
            result = result.filter { !$0.isPaid }
        }

        let tokens = normalizedSearchText(searchText)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return result }

        return result.filter { invoice in
            let searchableText = normalizedSearchText([
                invoice.sellerName,
                invoice.buyerName,
                invoice.sellerNIP,
                invoice.buyerNIP,
                invoice.invoiceNumber,
            ].joined(separator: " "))
            let taxIdentifiers = [invoice.sellerNIP, invoice.buyerNIP]
                .map { $0.filter(\.isNumber) }

            return tokens.allSatisfy { token in
                if searchableText.contains(token) { return true }
                guard let digits = identifierDigits(from: token) else { return false }
                return taxIdentifiers.contains { $0.contains(digits) }
            }
        }
    }
}
