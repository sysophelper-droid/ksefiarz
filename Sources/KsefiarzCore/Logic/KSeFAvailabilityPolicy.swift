import Foundation

/// Podpowiedź trybu wystawienia wynikająca z aktywnego komunikatu MF.
public struct KSeFOfflineSuggestion: Equatable, Sendable {
    public let reason: Invoice.OfflineReason
    public let eventId: Int
    public let eventStart: Date
    public let eventEnd: Date?
    public let title: String
    public let text: String

    public var deadline: Date? {
        guard let eventEnd else { return nil }
        switch reason {
        case .offline24:
            return nil
        case .unavailability:
            return PolishBusinessCalendar.endOfNextBusinessDay(after: eventEnd)
        case .failure:
            return PolishBusinessCalendar.endOfBusinessDay(after: eventEnd, businessDays: 7)
        }
    }
}

/// Czysta logika mapująca status Latarni na tryb aplikacji i aktualizująca
/// terminy dokumentów powiązanych z konkretnym zdarzeniem MF.
public enum KSeFAvailabilityPolicy {

    /// Zwraca podpowiedź wyłącznie dla aktualnie trwającej niedostępności
    /// albo zwykłej awarii. Awaria całkowita celowo nie jest mapowana na
    /// `Invoice.OfflineReason`, bo dokumentów z tego okresu nie dosyła się.
    public static func currentSuggestion(
        from snapshot: KSeFAvailabilitySnapshot
    ) -> KSeFOfflineSuggestion? {
        let category: KSeFAvailabilityCategory
        let reason: Invoice.OfflineReason
        let type: KSeFAvailabilityMessageType
        switch snapshot.status {
        case .maintenance:
            category = .maintenance
            reason = .unavailability
            type = .maintenanceAnnouncement
        case .failure:
            category = .failure
            reason = .failure
            type = .failureStart
        case .available, .totalFailure, .unknown:
            return nil
        }
        guard let message = snapshot.activeMessages.first(where: {
            $0.category == category && $0.type == type
        }) else { return nil }
        return KSeFOfflineSuggestion(
            reason: reason,
            eventId: message.eventId,
            eventStart: message.start,
            eventEnd: message.end,
            title: message.title,
            text: message.text
        )
    }

    public static func isTotalFailure(_ snapshot: KSeFAvailabilitySnapshot) -> Bool {
        snapshot.status == .totalFailure
    }

    /// Najbliższa przyszła przerwa serwisowa, którą warto pokazać z wyprzedzeniem.
    public static func upcomingMaintenance(
        from snapshot: KSeFAvailabilitySnapshot,
        now: Date = .now,
        horizon: TimeInterval = 7 * 86_400
    ) -> KSeFAvailabilityMessage? {
        snapshot.messages
            .filter {
                $0.category == .maintenance
                    && $0.type == .maintenanceAnnouncement
                    && $0.start > now
                    && $0.start <= now.addingTimeInterval(horizon)
            }
            .min { $0.start < $1.start }
    }

    /// Wiąże nową fakturę z komunikatem MF. Dzięki `eventId` późniejszy
    /// komunikat kończący uzupełni termin bez zgadywania po samych datach.
    public static func apply(_ suggestion: KSeFOfflineSuggestion, to invoice: Invoice) {
        guard invoice.isOfflineMode,
              invoice.ksefSubmissionStatus == .offlinePending,
              invoice.offlineReason == suggestion.reason
        else { return }
        invoice.offlineEventId = suggestion.eventId
        invoice.offlineEventEndedAt = suggestion.eventEnd
    }

    /// Aktualizuje daty końca wyłącznie w automatycznie powiązanych,
    /// oczekujących dokumentach bieżącego środowiska. Ręczny wpis użytkownika
    /// (brak `offlineEventId`) pozostaje nadrzędny.
    @discardableResult
    public static func reconcile(
        invoices: [Invoice],
        messages: [KSeFAvailabilityMessage],
        environmentRaw: String
    ) -> Int {
        var completedEvents: [Int: (category: KSeFAvailabilityCategory, end: Date)] = [:]
        for message in messages
        where message.type == .failureEnd || message.type == .maintenanceAnnouncement {
            guard let end = message.end else { continue }
            if completedEvents[message.eventId]?.end ?? .distantPast < end {
                completedEvents[message.eventId] = (message.category, end)
            }
        }
        var changed = 0
        for invoice in invoices {
            guard invoice.isOfflineMode,
                  invoice.ksefSubmissionStatus == .offlinePending,
                  invoice.ksefEnvironmentRaw == environmentRaw,
                  let eventId = invoice.offlineEventId,
                  let completed = completedEvents[eventId],
                  (invoice.offlineReason == .failure && completed.category == .failure
                    || invoice.offlineReason == .unavailability && completed.category == .maintenance),
                  invoice.offlineEventEndedAt != completed.end
            else { continue }
            invoice.offlineEventEndedAt = completed.end
            changed += 1
        }
        return changed
    }
}
