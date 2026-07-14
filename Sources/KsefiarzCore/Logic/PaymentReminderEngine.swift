import Foundation

/// Ustawienia automatycznych przypomnień e-mail o płatnościach.
public struct PaymentReminderSettings: Equatable, Sendable {
    /// Ile dni przed terminem wysłać uprzedzające przypomnienie
    /// (okno obejmuje też dzień terminu). 0 = tylko w dniu terminu.
    public var daysBeforeDue: Int
    /// Co ile dni ponawiać miękkie ponaglenie po terminie.
    public var repeatAfterDays: Int

    public init(daysBeforeDue: Int = 3, repeatAfterDays: Int = 7) {
        // Wartości spoza zakresu (ręczna edycja UserDefaults) nie mogą
        // zapętlić przypomnień ani cofnąć okna przed datę wystawienia.
        self.daysBeforeDue = max(0, daysBeforeDue)
        self.repeatAfterDays = max(1, repeatAfterDays)
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
    public let invoiceNumber: String
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
        asOf: Date = .now
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
                subject: subject(for: invoice, phase: phase, language: language),
                body: body(for: invoice, phase: phase, language: language, asOf: asOf)
            ))
        }

        // Deterministyczna kolejność: najpierw najdawniej wymagalne.
        candidates.sort {
            ($0.invoice.paymentDueDate ?? .distantPast)
                < ($1.invoice.paymentDueDate ?? .distantPast)
        }
        return (candidates, omissions)
    }

    // MARK: Treść wiadomości

    /// Temat przypomnienia w wybranym języku.
    public static func subject(
        for invoice: Invoice,
        phase: PaymentReminderCandidate.Phase,
        language: InvoiceEmailComposer.Language
    ) -> String {
        switch (language, phase) {
        case (.polish, .beforeDue):
            return "Przypomnienie: zbliża się termin płatności faktury \(invoice.invoiceNumber)"
        case (.polish, .overdue):
            return "Przypomnienie o płatności — faktura \(invoice.invoiceNumber) po terminie"
        case (.english, .beforeDue):
            return "Reminder: invoice \(invoice.invoiceNumber) payment due soon"
        case (.english, .overdue):
            return "Payment reminder — invoice \(invoice.invoiceNumber) overdue"
        }
    }

    /// Treść przypomnienia w wybranym języku — miękki ton, saldo (nie
    /// brutto), rachunek do wpłaty i prośba o zignorowanie po zapłacie.
    public static func body(
        for invoice: Invoice,
        phase: PaymentReminderCandidate.Phase,
        language: InvoiceEmailComposer.Language,
        asOf: Date = .now
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.locale = Locale(identifier: language == .polish ? "pl_PL" : "en_GB")
        let due = invoice.paymentDueDate ?? asOf
        let amount = "\(FA2Format.amount(invoice.outstandingAmount)) \(invoice.currency)"
        let overdueDays = PaymentDemandEngine.daysOverdue(dueDate: due, asOf: asOf)

        var body: String
        switch (language, phase) {
        case (.polish, .beforeDue):
            body = """
            Dzień dobry,

            uprzejmie przypominamy, że \(dateFormatter.string(from: due)) upływa termin \
            płatności faktury \(invoice.invoiceNumber). Do zapłaty pozostaje \(amount).
            """
        case (.polish, .overdue):
            body = """
            Dzień dobry,

            uprzejmie przypominamy, że termin płatności faktury \(invoice.invoiceNumber) \
            upłynął \(dateFormatter.string(from: due)) (\(overdueDays) dni temu). \
            Do zapłaty pozostaje \(amount).

            Prosimy o uregulowanie należności albo kontakt w sprawie płatności.
            """
        case (.english, .beforeDue):
            body = """
            Dear Sirs,

            this is a friendly reminder that invoice \(invoice.invoiceNumber) is due \
            for payment on \(dateFormatter.string(from: due)). \
            The outstanding amount is \(amount).
            """
        case (.english, .overdue):
            body = """
            Dear Sirs,

            this is a friendly reminder that invoice \(invoice.invoiceNumber) was due \
            for payment on \(dateFormatter.string(from: due)) (\(overdueDays) days ago). \
            The outstanding amount is \(amount).

            Please arrange the payment or contact us regarding the invoice.
            """
        }

        if let account = invoice.paymentBankAccount, !account.isEmpty {
            body += language == .polish
                ? "\nNumer rachunku do wpłaty: \(account)."
                : "\nBank account for payment: \(account)."
        }
        body += language == .polish
            ? "\n\nJeżeli płatność została już zrealizowana, prosimy zignorować tę wiadomość."
            : "\n\nIf the payment has already been made, please disregard this message."
        body += language == .polish
            ? "\n\nPozdrawiamy\n\(invoice.sellerName)"
            : "\n\nKind regards\n\(invoice.sellerName)"
        return body
    }
}
