import Foundation

/// Ustawienia automatycznych przypomnień e-mail o płatnościach.
public struct PaymentReminderSettings: Equatable, Hashable, Sendable {
    /// Ile dni przed terminem wysłać uprzedzające przypomnienie
    /// (okno obejmuje też dzień terminu). 0 = tylko w dniu terminu.
    public var daysBeforeDue: Int
    /// Co ile dni ponawiać miękkie ponaglenie po terminie.
    public var repeatAfterDays: Int

    public init(daysBeforeDue: Int = 3, repeatAfterDays: Int = 7) {
        // Wartości spoza zakresu (ręczna edycja UserDefaults) nie mogą
        // zapętlić przypomnień ani cofnąć okna przed datę wystawienia.
        self.daysBeforeDue = min(30, max(0, daysBeforeDue))
        self.repeatAfterDays = min(60, max(1, repeatAfterDays))
    }
}

/// Tożsamość cyklu automatyzacji SwiftUI. Zmiana dowolnego ustawienia
/// istotnego dla przebiegu restartuje task, dzięki czemu nowa konfiguracja
/// obowiązuje od razu, bez oczekiwania do kolejnego uruchomienia aplikacji.
struct PaymentReminderAutomationConfiguration: Equatable, Hashable, Sendable {
    let isEnabled: Bool
    let settings: PaymentReminderSettings
    let deliveryModeRaw: String

    init(
        isEnabled: Bool,
        daysBeforeDue: Int,
        repeatAfterDays: Int,
        deliveryModeRaw: String
    ) {
        self.isEnabled = isEnabled
        self.settings = PaymentReminderSettings(
            daysBeforeDue: daysBeforeDue,
            repeatAfterDays: repeatAfterDays
        )
        self.deliveryModeRaw = deliveryModeRaw
    }
}

/// Kandydat do przypomnienia — gotowa wiadomość dla jednej faktury.
public struct PaymentReminderCandidate {
    /// Faza przypomnienia względem terminu płatności.
    public enum Phase: Equatable, Sendable {
        /// Termin dopiero nadchodzi (miękkie uprzedzenie).
        case beforeDue
        /// Termin minął (cykliczne ponaglenie).
        case overdue
    }

    public let invoice: Invoice
    public let phase: Phase
    public let recipient: String
    public let language: InvoiceEmailComposer.Language
    public let subject: String
    public let body: String
}

/// Faktura pominięta przez silnik przypomnień — z jawnym powodem
/// (transparentność zamiast cichego pomijania).
public struct PaymentReminderOmission: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Miękkie przypomnienie celowo wstrzymane po formalnym wezwaniu.
        case formalCollection
        /// Brak adresu, który użytkownik powinien uzupełnić w słowniku.
        case missingRecipient
    }

    public let invoiceNumber: String
    public let kind: Kind
    public let reason: String
}

/// Automatyczne przypomnienia e-mail o płatnościach: przed terminem
/// (uprzedzenie) i cyklicznie po terminie (miękkie ponaglenia).
/// Czysta logika — dostarczaniem zajmuje się `MailAutomationService`,
/// a pamięcią wysłanych `Invoice.collectionReminderAt` (wspólną ze ścieżką
/// windykacji C3: formalne wezwanie wstrzymuje miękkie przypomnienia).
public enum PaymentReminderEngine {

    /// Buduje listę przypomnień do wysłania teraz oraz jawne pominięcia.
    /// Obejmuje wyłącznie widoczne, nieopłacone faktury sprzedażowe
    /// z terminem płatności i dodatnim saldem.
    public static func candidates(
        invoices: [Invoice],
        contractors: [Contractor],
        settings: PaymentReminderSettings,
        asOf: Date = .now,
        templates: EmailTemplates = EmailTemplates()
    ) -> (candidates: [PaymentReminderCandidate], omissions: [PaymentReminderOmission]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: asOf)
        var candidates: [PaymentReminderCandidate] = []
        var omissions: [PaymentReminderOmission] = []

        for invoice in invoices {
            guard invoice.kind == .sales,
                  !invoice.isArchivedOrHidden,
                  !invoice.isPaid,
                  invoice.outstandingAmount > 0.005,
                  let due = invoice.paymentDueDate else { continue }
            let dueDay = calendar.startOfDay(for: due)
            let daysUntilDue = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0

            let phase: PaymentReminderCandidate.Phase
            if daysUntilDue >= 0 && daysUntilDue <= settings.daysBeforeDue {
                phase = .beforeDue
            } else if daysUntilDue < 0 {
                phase = .overdue
            } else {
                continue // termin daleko — poza oknem przypomnień
            }

            // Formalna windykacja (wezwanie i dalej) wstrzymuje miękkie
            // przypomnienia — sprzeczne tony podważałyby wezwanie.
            if invoice.collectionStage >= .demanded {
                omissions.append(PaymentReminderOmission(
                    invoiceNumber: invoice.invoiceNumber,
                    kind: .formalCollection,
                    reason: "formalna windykacja w toku (\(invoice.collectionStage.displayName))"
                ))
                continue
            }

            // Deduplikacja po dacie ostatniego przypomnienia.
            if let last = invoice.collectionReminderAt {
                let lastDay = calendar.startOfDay(for: last)
                switch phase {
                case .beforeDue:
                    // Jedno uprzedzenie na okno przed terminem.
                    let windowStart = calendar.date(
                        byAdding: .day, value: -settings.daysBeforeDue, to: dueDay
                    ) ?? dueDay
                    if lastDay >= windowStart { continue }
                case .overdue:
                    let sinceLast = calendar.dateComponents(
                        [.day], from: lastDay, to: today
                    ).day ?? 0
                    if sinceLast < settings.repeatAfterDays { continue }
                }
            }

            let recipient = InvoiceEmailComposer.recipient(for: invoice, contractors: contractors)
            guard !recipient.isEmpty else {
                omissions.append(PaymentReminderOmission(
                    invoiceNumber: invoice.invoiceNumber,
                    kind: .missingRecipient,
                    reason: "brak adresu e-mail w słowniku kontrahentów"
                ))
                continue
            }

            let language = InvoiceEmailComposer.preferredLanguage(
                for: invoice, contractors: contractors
            )
            candidates.append(PaymentReminderCandidate(
                invoice: invoice,
                phase: phase,
                recipient: recipient,
                language: language,
                subject: subject(for: invoice, phase: phase, language: language, asOf: asOf, templates: templates),
                body: body(for: invoice, phase: phase, language: language, asOf: asOf, templates: templates)
            ))
        }

        // Deterministyczna kolejność: najpierw najdawniej wymagalne.
        candidates.sort {
            ($0.invoice.paymentDueDate ?? .distantPast)
                < ($1.invoice.paymentDueDate ?? .distantPast)
        }
        return (candidates, omissions)
    }

    /// Treść dziennego podsumowania faktur, dla których automat nie mógł
    /// przygotować wiadomości z powodu braku adresu. Celowe wstrzymanie po
    /// formalnym wezwaniu nie jest błędem i nie trafia do powiadomienia.
    public static func missingRecipientNotificationBody(
        omissions: [PaymentReminderOmission]
    ) -> String? {
        let missing = omissions.filter { $0.kind == .missingRecipient }
        guard !missing.isEmpty else { return nil }
        let listed = missing.prefix(5).map(\.invoiceNumber).joined(separator: ", ")
        let suffix = missing.count > 5 ? "…" : ""
        let noun = missing.count == 1 ? "faktury" : "faktur"
        return "Brak adresu e-mail dla \(missing.count) \(noun): \(listed)\(suffix). "
            + "Uzupełnij dane kontrahentów w słowniku."
    }

    // MARK: Treść wiadomości

    /// Rodzaj szablonu dla fazy przypomnienia.
    static func templateKind(for phase: PaymentReminderCandidate.Phase) -> EmailTemplateKind {
        phase == .beforeDue ? .reminderBefore : .reminderOverdue
    }

    /// Temat przypomnienia w wybranym języku — własny szablon z Ustawień
    /// albo wbudowany domyślny (`EmailTemplate`). `asOf` zasila symbol
    /// {dni_po_terminie}, gdyby użytkownik użył go we wzorze tematu.
    public static func subject(
        for invoice: Invoice,
        phase: PaymentReminderCandidate.Phase,
        language: InvoiceEmailComposer.Language,
        asOf: Date = .now,
        templates: EmailTemplates = EmailTemplates()
    ) -> String {
        templates.subject(kind: templateKind(for: phase), for: invoice, language: language, asOf: asOf)
    }

    /// Treść przypomnienia w wybranym języku — miękki ton, saldo (nie
    /// brutto), rachunek do wpłaty i prośba o zignorowanie po zapłacie.
    /// Własny szablon z Ustawień albo wbudowany domyślny (`EmailTemplate`).
    public static func body(
        for invoice: Invoice,
        phase: PaymentReminderCandidate.Phase,
        language: InvoiceEmailComposer.Language,
        asOf: Date = .now,
        templates: EmailTemplates = EmailTemplates()
    ) -> String {
        templates.body(
            kind: templateKind(for: phase),
            for: invoice,
            language: language,
            asOf: asOf
        )
    }
}
