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

        /// Sufiks kluczy ustawień szablonów e-mail (`EmailTemplate`).
        public var keySuffix: String {
            switch self {
            case .polish: return "pl"
            case .english: return "en"
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

    /// Domyślny temat wiadomości w wybranym języku (wbudowany szablon).
    public static func defaultSubject(for invoice: Invoice, language: Language = .polish) -> String {
        subject(for: invoice, language: language, templates: EmailTemplates())
    }

    /// Domyślna treść wiadomości w wybranym języku (wbudowany szablon;
    /// edytowalna przed wysyłką).
    public static func defaultBody(for invoice: Invoice, language: Language = .polish) -> String {
        body(for: invoice, language: language, templates: EmailTemplates())
    }

    /// Temat wiadomości według obowiązujących szablonów (własne wzory
    /// z Ustawień z fail-backiem do wbudowanych — patrz `EmailTemplates`).
    public static func subject(
        for invoice: Invoice,
        language: Language,
        templates: EmailTemplates
    ) -> String {
        templates.subject(kind: .invoice, for: invoice, language: language)
    }

    /// Treść wiadomości według obowiązujących szablonów.
    public static func body(
        for invoice: Invoice,
        language: Language,
        templates: EmailTemplates
    ) -> String {
        templates.body(kind: .invoice, for: invoice, language: language)
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
