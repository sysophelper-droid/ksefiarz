import Foundation

/// Przygotowanie wiadomości e-mail z fakturą: adresat ze słownika
/// kontrahentów (adres fakturowy ma pierwszeństwo), domyślny temat i treść.
/// Czysta logika — wysyłką zajmuje się `InvoiceEmailService`.
public enum InvoiceEmailComposer {

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

    /// Domyślny temat wiadomości.
    public static func defaultSubject(for invoice: Invoice) -> String {
        "Faktura \(invoice.invoiceNumber) — \(invoice.sellerName)"
    }

    /// Domyślna treść wiadomości (edytowalna przed wysyłką).
    public static func defaultBody(for invoice: Invoice) -> String {
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
