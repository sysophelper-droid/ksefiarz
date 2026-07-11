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

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return result }

        return result.filter { invoice in
            invoice.sellerName.lowercased().contains(query)
                || invoice.buyerName.lowercased().contains(query)
                || invoice.sellerNIP.contains(query)
                || invoice.buyerNIP.contains(query)
                || invoice.invoiceNumber.lowercased().contains(query)
        }
    }
}
