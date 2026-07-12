import Foundation

/// Przygotowanie wiadomości e-mail z fakturą: adresat ze słownika
/// kontrahentów (adres fakturowy ma pierwszeństwo), domyślny temat i treść
/// (szablon polski albo angielski dla kontrahentów zagranicznych).
/// Czysta logika — wysyłką zajmuje się `InvoiceEmailService`.
public enum InvoiceEmailComposer {

    /// Język szablonu wiadomości.
    public enum Language: String, CaseIterable, Identifiable, Sendable {
        case polish
        case english

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .polish: return "Polski"
            case .english: return "Angielski"
            }
        }
    }

    /// Język podpowiadany dla faktury: angielski, gdy kontrahent
    /// (dopasowany po NIP nabywcy) ma w słowniku włączone dokumenty
    /// dwujęzyczne; w pozostałych przypadkach polski.
    public static func preferredLanguage(
        for invoice: Invoice,
        contractors: [Contractor]
    ) -> Language {
        let buyerNIP = normalizedNIP(invoice.buyerNIP)
        guard !buyerNIP.isEmpty else { return .polish }
        let prefersBilingual = contractors.contains {
            normalizedNIP($0.nip) == buyerNIP && $0.prefersBilingualDocuments
        }
        return prefersBilingual ? .english : .polish
    }

    /// Adres e-mail odbiorcy faktury: kontrahent ze słownika dopasowany po
    /// NIP nabywcy; preferowany dedykowany adres fakturowy (`invoiceEmail`),
    /// w drugiej kolejności adres ogólny. Brak dopasowania → pusty String.
    public static func recipient(for invoice: Invoice, contractors: [Contractor]) -> String {
        let buyerNIP = normalizedNIP(invoice.buyerNIP)
        guard !buyerNIP.isEmpty else { return "" }
        let matching = contractors.filter { normalizedNIP($0.nip) == buyerNIP }
        if let dedicated = matching.first(where: { !$0.invoiceEmail.trimmed.isEmpty }) {
            return dedicated.invoiceEmail.trimmed
        }
        return matching.first(where: { !$0.email.trimmed.isEmpty })?.email.trimmed ?? ""
    }

    /// Domyślny temat wiadomości w wybranym języku.
    public static func defaultSubject(for invoice: Invoice, language: Language = .polish) -> String {
        switch language {
        case .polish:
            return "Faktura \(invoice.invoiceNumber) — \(invoice.sellerName)"
        case .english:
            return "Invoice \(invoice.invoiceNumber) — \(invoice.sellerName)"
        }
    }

    /// Domyślna treść wiadomości w wybranym języku (edytowalna przed wysyłką).
    public static func defaultBody(for invoice: Invoice, language: Language = .polish) -> String {
        switch language {
        case .polish: return polishBody(for: invoice)
        case .english: return englishBody(for: invoice)
        }
    }

    private static func polishBody(for invoice: Invoice) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.locale = Locale(identifier: "pl_PL")

        var body = """
        Dzień dobry,

        w załączeniu przesyłamy fakturę \(invoice.invoiceNumber) \
        z dnia \(dateFormatter.string(from: invoice.issueDate)) \
        na kwotę \(FA2Format.amount(invoice.grossAmount)) \(invoice.currency) brutto.
        """
        if let due = invoice.paymentDueDate {
            body += "\nTermin płatności: \(dateFormatter.string(from: due))."
        }
        if let account = invoice.paymentBankAccount, !account.isEmpty {
            body += "\nNumer rachunku do wpłaty: \(account)."
        }
        if let ksefId = invoice.ksefId {
            body += "\nFaktura znajduje się w KSeF pod numerem: \(ksefId)."
        }
        body += "\n\nPozdrawiamy\n\(invoice.sellerName)"
        return body
    }

    private static func englishBody(for invoice: Invoice) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.locale = Locale(identifier: "en_GB")

        var body = """
        Dear Sirs,

        please find attached invoice \(invoice.invoiceNumber) \
        dated \(dateFormatter.string(from: invoice.issueDate)) \
        for the total (gross) amount of \(FA2Format.amount(invoice.grossAmount)) \(invoice.currency).
        """
        if let due = invoice.paymentDueDate {
            body += "\nPayment due date: \(dateFormatter.string(from: due))."
        }
        if let account = invoice.paymentBankAccount, !account.isEmpty {
            body += "\nBank account for payment: \(account)."
        }
        if let ksefId = invoice.ksefId {
            body += "\nThe invoice is registered in KSeF (Polish National e-Invoicing System) under number: \(ksefId)."
        }
        body += "\n\nKind regards\n\(invoice.sellerName)"
        return body
    }

    /// Nazwa pliku załącznika — numer faktury bez znaków niedozwolonych
    /// w nazwach plików.
    public static func attachmentBaseName(for invoice: Invoice) -> String {
        let sanitized = invoice.invoiceNumber
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        return "Faktura-\(sanitized)"
    }

    /// NIP w postaci porównywalnej — same cyfry (bez myślników i spacji).
    static func normalizedNIP(_ nip: String) -> String {
        nip.filter(\.isNumber)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
