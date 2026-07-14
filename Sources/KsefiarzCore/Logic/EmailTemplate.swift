import Foundation

/// Rodzaj wiadomości e-mail z konfigurowalnym szablonem (F5).
public enum EmailTemplateKind: String, CaseIterable, Identifiable, Sendable {
    /// Wysyłka faktury e-mailem (arkusz „Wyślij fakturę e-mailem”).
    case invoice
    /// Wysyłka faktury proforma.
    case proforma
    /// Automatyczne przypomnienie PRZED terminem płatności (C4).
    case reminderBefore
    /// Automatyczne ponaglenie PO terminie płatności (C4).
    case reminderOverdue

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .invoice: return "Faktura (wysyłka e-mailem)"
        case .proforma: return "Faktura proforma"
        case .reminderBefore: return "Przypomnienie przed terminem"
        case .reminderOverdue: return "Ponaglenie po terminie"
        }
    }
}

/// Czysty silnik szablonów e-mail: podstawianie symboli `{nazwa}`
/// i wartości dokumentu oraz wbudowane szablony domyślne (dotychczas
/// zaszyte w kodzie — teraz jeden punkt prawdy, edytowalny w Ustawieniach).
///
/// Reguła wierszy warunkowych: wiersz, który zawiera co najmniej jeden
/// ZNANY symbol i wszystkie znane symbole w nim rozwiązują się do pustej
/// wartości, jest pomijany w całości (np. „Termin płatności: {termin}.”
/// znika dla faktury bez terminu — jak w dotychczasowych szablonach).
/// Nieznany symbol (literówka) zostaje w treści dosłownie — jawnie
/// pokazuje błąd zamiast cicho go połykać.
public enum EmailTemplate {

    // MARK: Renderowanie

    /// Renderuje szablon treści: podstawia symbole i stosuje regułę
    /// wierszy warunkowych.
    public static func render(_ template: String, values: [String: String]) -> String {
        template
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                renderLine(String(line), values: values)
            }
            .joined(separator: "\n")
    }

    /// Renderuje szablon TEMATU: jak `render`, ale wynik jest jednym
    /// wierszem (znaki nowej linii zamieniane na spację).
    public static func renderSubject(_ template: String, values: [String: String]) -> String {
        render(template, values: values)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Jeden wiersz szablonu: `nil` = wiersz pominięty (wszystkie znane
    /// symbole puste). Symbol to `{male_litery_i_podkreslenia}` — ręczny
    /// skaner zamiast regexa (tryb języka Swift 5, zero zależności).
    private static func renderLine(_ line: String, values: [String: String]) -> String? {
        var knownCount = 0
        var nonEmptyCount = 0
        var result = ""
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "{") {
            result += rest[rest.startIndex..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else {
                // Niedomknięty nawias — reszta wiersza dosłownie.
                result += rest[open...]
                rest = rest[rest.endIndex...]
                break
            }
            let name = String(rest[afterOpen..<close])
            let isValidName = !name.isEmpty && name.allSatisfy { $0 == "_" || ("a"..."z").contains($0) }
            if isValidName, let value = values[name] {
                knownCount += 1
                if !value.isEmpty { nonEmptyCount += 1 }
                result += value
            } else {
                // Nieznany symbol (literówka) — zostaje dosłownie.
                result += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        if knownCount > 0 && nonEmptyCount == 0 { return nil }
        return result
    }

    // MARK: Wartości symboli

    /// Wartości symboli dla dokumentu (faktura albo przejściowa faktura
    /// proformy). Daty w formacie „długim” zgodnym z językiem szablonu.
    public static func values(
        for invoice: Invoice,
        language: InvoiceEmailComposer.Language,
        asOf: Date = .now
    ) -> [String: String] {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = Locale(identifier: language == .polish ? "pl_PL" : "en_GB")

        var overdueDays = ""
        if let due = invoice.paymentDueDate {
            let days = PaymentDemandEngine.daysOverdue(dueDate: due, asOf: asOf)
            overdueDays = String(max(0, days))
        }

        return [
            "numer": invoice.invoiceNumber,
            "data": formatter.string(from: invoice.issueDate),
            "kwota": "\(FA2Format.amount(invoice.grossAmount)) \(invoice.currency)",
            "saldo": "\(FA2Format.amount(invoice.outstandingAmount)) \(invoice.currency)",
            "termin": invoice.paymentDueDate.map { formatter.string(from: $0) } ?? "",
            "rachunek": invoice.paymentBankAccount ?? "",
            "ksef": invoice.ksefId ?? "",
            "sprzedawca": invoice.sellerName,
            "nabywca": invoice.buyerName,
            "dni_po_terminie": overdueDays,
        ]
    }

    /// Legenda symboli do UI Ustawień (kolejność prezentacji).
    public static let placeholderLegend: [(symbol: String, description: String)] = [
        ("{numer}", "numer dokumentu"),
        ("{data}", "data wystawienia"),
        ("{kwota}", "kwota brutto z walutą"),
        ("{saldo}", "kwota pozostała do zapłaty z walutą"),
        ("{termin}", "termin płatności (pusty pomija wiersz)"),
        ("{rachunek}", "rachunek do wpłaty (pusty pomija wiersz)"),
        ("{ksef}", "numer KSeF (pusty pomija wiersz)"),
        ("{sprzedawca}", "nazwa sprzedawcy"),
        ("{nabywca}", "nazwa nabywcy"),
        ("{dni_po_terminie}", "liczba dni po terminie"),
    ]

    // MARK: Klucze ustawień

    /// Klucz UserDefaults własnego szablonu; pusta wartość = szablon
    /// domyślny. Pola: "subject" / "body".
    public static func storageKey(
        kind: EmailTemplateKind,
        field: String,
        language: InvoiceEmailComposer.Language
    ) -> String {
        "email.template.\(kind.rawValue).\(field).\(language.keySuffix)"
    }

    /// Wszystkie klucze szablonów — do kopii zapasowej.
    public static var allStorageKeys: [String] {
        EmailTemplateKind.allCases.flatMap { kind in
            InvoiceEmailComposer.Language.allCases.flatMap { language in
                ["subject", "body"].map { storageKey(kind: kind, field: $0, language: language) }
            }
        }
    }

    // MARK: Szablony domyślne

    /// Wbudowany domyślny szablon tematu.
    public static func defaultSubjectTemplate(
        kind: EmailTemplateKind,
        language: InvoiceEmailComposer.Language
    ) -> String {
        switch (kind, language) {
        case (.invoice, .polish): return "Faktura {numer} — {sprzedawca}"
        case (.invoice, .english): return "Invoice {numer} — {sprzedawca}"
        case (.proforma, .polish): return "Proforma {numer} — {sprzedawca}"
        case (.proforma, .english): return "Proforma invoice {numer} — {sprzedawca}"
        case (.reminderBefore, .polish):
            return "Przypomnienie: zbliża się termin płatności faktury {numer}"
        case (.reminderBefore, .english):
            return "Reminder: invoice {numer} payment due soon"
        case (.reminderOverdue, .polish):
            return "Przypomnienie o płatności — faktura {numer} po terminie"
        case (.reminderOverdue, .english):
            return "Payment reminder — invoice {numer} overdue"
        }
    }

    /// Wbudowany domyślny szablon treści. Struktura i brzmienie 1:1
    /// z dotychczasowymi tekstami zaszytymi w kodzie.
    public static func defaultBodyTemplate(
        kind: EmailTemplateKind,
        language: InvoiceEmailComposer.Language
    ) -> String {
        switch (kind, language) {
        case (.invoice, .polish):
            return """
            Dzień dobry,

            w załączeniu przesyłamy fakturę {numer} z dnia {data} na kwotę {kwota} brutto.
            Termin płatności: {termin}.
            Numer rachunku do wpłaty: {rachunek}.
            Faktura znajduje się w KSeF pod numerem: {ksef}.

            Pozdrawiamy
            {sprzedawca}
            """
        case (.invoice, .english):
            return """
            Dear Sirs,

            please find attached invoice {numer} dated {data} for the total (gross) amount of {kwota}.
            Payment due date: {termin}.
            Bank account for payment: {rachunek}.
            The invoice is registered in KSeF (Polish National e-Invoicing System) under number: {ksef}.

            Kind regards
            {sprzedawca}
            """
        case (.proforma, .polish):
            return """
            Dzień dobry,

            w załączeniu przesyłamy fakturę proforma {numer} z dnia {data} na kwotę {kwota} brutto.
            Termin płatności: {termin}.
            Numer rachunku do wpłaty: {rachunek}.

            Proforma jest dokumentem handlowym — nie stanowi faktury VAT. Fakturę VAT wystawimy po zaksięgowaniu wpłaty.

            Pozdrawiamy
            {sprzedawca}
            """
        case (.proforma, .english):
            return """
            Dear Sirs,

            please find attached proforma invoice {numer} dated {data} for the total (gross) amount of {kwota}.
            Payment due date: {termin}.
            Bank account for payment: {rachunek}.

            A proforma is a commercial document — it is not a VAT invoice. The VAT invoice will be issued once the payment is received.

            Kind regards
            {sprzedawca}
            """
        case (.reminderBefore, .polish):
            return """
            Dzień dobry,

            uprzejmie przypominamy, że {termin} upływa termin płatności faktury {numer}. Do zapłaty pozostaje {saldo}.
            Numer rachunku do wpłaty: {rachunek}.

            Jeżeli płatność została już zrealizowana, prosimy zignorować tę wiadomość.

            Pozdrawiamy
            {sprzedawca}
            """
        case (.reminderBefore, .english):
            return """
            Dear Sirs,

            this is a friendly reminder that invoice {numer} is due for payment on {termin}. The outstanding amount is {saldo}.
            Bank account for payment: {rachunek}.

            If the payment has already been made, please disregard this message.

            Kind regards
            {sprzedawca}
            """
        case (.reminderOverdue, .polish):
            return """
            Dzień dobry,

            uprzejmie przypominamy, że termin płatności faktury {numer} upłynął {termin} ({dni_po_terminie} dni temu). Do zapłaty pozostaje {saldo}.

            Prosimy o uregulowanie należności albo kontakt w sprawie płatności.
            Numer rachunku do wpłaty: {rachunek}.

            Jeżeli płatność została już zrealizowana, prosimy zignorować tę wiadomość.

            Pozdrawiamy
            {sprzedawca}
            """
        case (.reminderOverdue, .english):
            return """
            Dear Sirs,

            this is a friendly reminder that invoice {numer} was due for payment on {termin} ({dni_po_terminie} days ago). The outstanding amount is {saldo}.

            Please arrange the payment or contact us regarding the invoice.
            Bank account for payment: {rachunek}.

            If the payment has already been made, please disregard this message.

            Kind regards
            {sprzedawca}
            """
        }
    }
}

/// Zestaw szablonów obowiązujących w danej chwili: własne wzory
/// z Ustawień z fail-backiem do wbudowanych domyślnych. Wartościowy
/// i porównywalny — nadaje się do wstrzykiwania do czystej logiki
/// (silnik przypomnień) bez sięgania do UserDefaults.
public struct EmailTemplates: Equatable, Hashable, Sendable {

    /// Własne szablony: klucz UserDefaults → tekst. Puste/nieobecne =
    /// szablon domyślny.
    private var custom: [String: String]

    /// Zestaw bez żadnych zmian — same szablony domyślne.
    public init() {
        self.custom = [:]
    }

    public init(custom: [String: String]) {
        self.custom = custom.filter { !$0.value.isEmpty }
    }

    /// Wczytuje własne szablony z UserDefaults (Ustawienia → E-mail).
    public static func fromDefaults(_ defaults: UserDefaults = .standard) -> EmailTemplates {
        var custom: [String: String] = [:]
        for key in EmailTemplate.allStorageKeys {
            if let value = defaults.string(forKey: key), !value.isEmpty {
                custom[key] = value
            }
        }
        return EmailTemplates(custom: custom)
    }

    /// Szablon tematu: własny, a przy braku — domyślny.
    public func subjectTemplate(
        kind: EmailTemplateKind,
        language: InvoiceEmailComposer.Language
    ) -> String {
        let key = EmailTemplate.storageKey(kind: kind, field: "subject", language: language)
        if let value = custom[key], !value.trimmingCharacters(in: .whitespaces).isEmpty {
            return value
        }
        return EmailTemplate.defaultSubjectTemplate(kind: kind, language: language)
    }

    /// Szablon treści: własny, a przy braku — domyślny.
    public func bodyTemplate(
        kind: EmailTemplateKind,
        language: InvoiceEmailComposer.Language
    ) -> String {
        let key = EmailTemplate.storageKey(kind: kind, field: "body", language: language)
        if let value = custom[key], !value.trimmingCharacters(in: .whitespaces).isEmpty {
            return value
        }
        return EmailTemplate.defaultBodyTemplate(kind: kind, language: language)
    }

    /// Gotowy temat dla dokumentu (render szablonu).
    public func subject(
        kind: EmailTemplateKind,
        for invoice: Invoice,
        language: InvoiceEmailComposer.Language,
        asOf: Date = .now
    ) -> String {
        EmailTemplate.renderSubject(
            subjectTemplate(kind: kind, language: language),
            values: EmailTemplate.values(for: invoice, language: language, asOf: asOf)
        )
    }

    /// Gotowa treść dla dokumentu (render szablonu).
    public func body(
        kind: EmailTemplateKind,
        for invoice: Invoice,
        language: InvoiceEmailComposer.Language,
        asOf: Date = .now
    ) -> String {
        EmailTemplate.render(
            bodyTemplate(kind: kind, language: language),
            values: EmailTemplate.values(for: invoice, language: language, asOf: asOf)
        )
    }
}
