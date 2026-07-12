import Foundation

/// Pojedyncze powiadomienie o terminie (płatności albo dosłania offline).
public struct DeadlineNotification: Equatable, Sendable {
    /// Unikalny klucz: rodzaj|id faktury|dzień powiadomienia — służy
    /// deduplikacji (jedno powiadomienie danego rodzaju na dobę).
    public let key: String
    public let title: String
    public let body: String
}

/// Powiadomienia o terminach: płatności (dziś/jutro/zaległe pierwszy raz)
/// oraz dosłania dokumentów offline do KSeF (dziś lub po terminie).
/// Czysta logika — dostarczanie i pamięć doręczeń zapewnia widok.
public enum DeadlineNotificationEngine {

    /// Po ilu dniach klucze doręczeń są zapominane (przycinanie pamięci).
    static let deliveredRetentionDays = 14

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Buduje listę powiadomień do doręczenia teraz. Pomija faktury ukryte,
    /// opłacone oraz powiadomienia już doręczone (`alreadyDelivered`).
    public static func pending(
        invoices: [Invoice],
        now: Date = .now,
        alreadyDelivered: Set<String> = []
    ) -> [DeadlineNotification] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let todayKeyPart = dayFormatter.string(from: today)
        var notifications: [DeadlineNotification] = []

        for invoice in invoices where !invoice.isArchivedOrHidden {
            // Terminy płatności: dziś i jutro (nieopłacone, z terminem).
            if !invoice.isPaid, let due = invoice.paymentDueDate {
                let dueDay = calendar.startOfDay(for: due)
                let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
                if days == 0 || days == 1 {
                    let key = "due|\(invoice.id.uuidString)|\(todayKeyPart)"
                    if !alreadyDelivered.contains(key) {
                        let role = invoice.kind == .sales ? "Należność" : "Zobowiązanie"
                        let contractor = invoice.kind == .sales ? invoice.buyerName : invoice.sellerName
                        notifications.append(DeadlineNotification(
                            key: key,
                            title: days == 0
                                ? "Termin płatności dziś"
                                : "Termin płatności jutro",
                            body: "\(role): \(invoice.invoiceNumber) — \(contractor), "
                                + "do zapłaty \(amountText(invoice.outstandingAmount, currency: invoice.currency))."
                        ))
                    }
                }
            }

            // Terminy dosłania offline: dziś albo już po terminie.
            if invoice.ksefSubmissionStatus == .offlinePending,
               let deadline = invoice.offlineSendDeadline {
                let deadlineDay = calendar.startOfDay(for: deadline)
                let overdue = deadline < now
                if overdue || deadlineDay == today {
                    let key = "offline|\(invoice.id.uuidString)|\(todayKeyPart)"
                    if !alreadyDelivered.contains(key) {
                        notifications.append(DeadlineNotification(
                            key: key,
                            title: overdue
                                ? "Po terminie dosłania do KSeF!"
                                : "Dziś mija termin dosłania do KSeF",
                            body: "Dokument \(invoice.invoiceNumber) "
                                + "(\(invoice.offlineReason.displayName)) czeka w kolejce — "
                                + "sprawdź połączenie i doślij go do KSeF."
                        ))
                    }
                }
            }
        }
        return notifications
    }

    /// Przycina pamięć doręczeń: zostają klucze z ostatnich
    /// `deliveredRetentionDays` dni (dzień jest częścią klucza).
    public static func prune(delivered: Set<String>, now: Date = .now) -> Set<String> {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(
            byAdding: .day, value: -deliveredRetentionDays, to: calendar.startOfDay(for: now)
        ) else { return delivered }
        return delivered.filter { key in
            guard let dayPart = key.split(separator: "|").last,
                  let day = dayFormatter.date(from: String(dayPart)) else { return false }
            return day >= cutoff
        }
    }

    /// Kwota z walutą w polskim formacie (do treści powiadomienia).
    static func amountText(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: "pl_PL")
        return formatter.string(from: NSNumber(value: amount))
            ?? "\(FA2Format.amount(amount)) \(currency)"
    }
}
