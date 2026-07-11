import Foundation

/// Propozycja dopasowania operacji bankowej do faktury — do zatwierdzenia
/// przez użytkownika (aplikacja sama niczego nie księguje).
public struct PaymentMatchProposal: Identifiable, Sendable {
    public enum Confidence: Int, Comparable, Sendable {
        /// Numer faktury odnaleziony w tytule przelewu.
        case invoiceNumber = 2
        /// Kwota operacji równa saldu dokładnie jednej faktury.
        case uniqueAmount = 1
        /// Brak dopasowania.
        case none = 0

        public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var displayName: String {
            switch self {
            case .invoiceNumber: return "numer faktury w tytule"
            case .uniqueAmount: return "zgodna kwota salda"
            case .none: return "brak dopasowania"
            }
        }
    }

    public let id = UUID()
    public let transaction: BankTransaction
    /// Identyfikator dopasowanej faktury (nil = operacja bez dopasowania).
    public let invoiceID: UUID?
    public let confidence: Confidence
}

/// Dopasowywanie operacji z wyciągu do nieopłaconych faktur.
/// Wpływy (kwoty dodatnie) są zestawiane z fakturami sprzedażowymi,
/// wypływy — z zakupowymi. Porównania kwot dotyczą salda pozostałego
/// do zapłaty, więc płatności częściowe zawężają kolejne dopasowania.
@MainActor
public enum PaymentMatcher {

    /// Normalizacja do porównań „numer w tytule”: tylko litery i cyfry,
    /// wielkość liter bez znaczenia (FV/2026/06/001 ≡ „fv 2026 06 001”).
    static func normalized(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
            .lowercased()
    }

    /// Buduje propozycje dopasowań dla wszystkich operacji wyciągu.
    public static func proposals(
        transactions: [BankTransaction],
        invoices: [Invoice]
    ) -> [PaymentMatchProposal] {
        // Kandydaci: faktury z niedomkniętym saldem, bez ukrytych.
        let candidates = invoices.filter { !$0.isPaid && !$0.isArchivedOrHidden && $0.outstandingAmount > PaymentLedger.tolerance }
        let sales = candidates.filter { $0.kind == .sales }
        let purchases = candidates.filter { $0.kind == .purchase }

        return transactions.map { transaction in
            let pool = transaction.amount >= 0 ? sales : purchases
            return proposal(for: transaction, in: pool)
        }
    }

    /// Dopasowanie pojedynczej operacji w podanej puli faktur.
    static func proposal(
        for transaction: BankTransaction,
        in pool: [Invoice]
    ) -> PaymentMatchProposal {
        let haystack = normalized(transaction.title + " " + transaction.counterparty)
        let amount = abs(transaction.amount)

        // 1. Numer faktury w tytule przelewu (najdłuższe numery najpierw —
        // „FV/2026/06/0012” nie może dopasować się do „FV/2026/06/001”).
        let byNumber = pool
            .map { (invoice: $0, number: normalized($0.invoiceNumber)) }
            .filter { !$0.number.isEmpty && haystack.contains($0.number) }
            .sorted { $0.number.count > $1.number.count }
        if let hit = byNumber.first {
            // Przy kilku trafieniach preferujemy zgodność kwoty z saldem.
            let best = byNumber.first {
                abs($0.invoice.outstandingAmount - amount) < PaymentLedger.tolerance
            } ?? hit
            return PaymentMatchProposal(
                transaction: transaction,
                invoiceID: best.invoice.id,
                confidence: .invoiceNumber
            )
        }

        // 2. Kwota równa saldu dokładnie jednej faktury.
        let byAmount = pool.filter {
            abs($0.outstandingAmount - amount) < PaymentLedger.tolerance
        }
        if byAmount.count == 1, let match = byAmount.first {
            return PaymentMatchProposal(
                transaction: transaction,
                invoiceID: match.id,
                confidence: .uniqueAmount
            )
        }

        return PaymentMatchProposal(transaction: transaction, invoiceID: nil, confidence: .none)
    }

    /// Księguje zatwierdzone propozycje. Zwraca liczbę zapisanych wpłat.
    @discardableResult
    public static func apply(
        _ proposals: [PaymentMatchProposal],
        invoices: [Invoice]
    ) -> Int {
        var applied = 0
        for proposal in proposals {
            guard let invoiceID = proposal.invoiceID,
                  let invoice = invoices.first(where: { $0.id == invoiceID }) else { continue }
            let note = [proposal.transaction.title, proposal.transaction.counterparty]
                .filter { !$0.isEmpty }
                .joined(separator: " — ")
            PaymentLedger.register(
                amount: abs(proposal.transaction.amount),
                date: proposal.transaction.date,
                note: note,
                source: .bankImport,
                on: invoice
            )
            applied += 1
        }
        return applied
    }
}
