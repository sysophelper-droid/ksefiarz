import Foundation

/// Stan prezentowany przy ikonie w pasku menu: kolejka dosłań offline
/// (oczekujące i po terminie) oraz opis ostatniej synchronizacji.
/// Czysta logika — widok paska menu tylko ją renderuje.
public struct MenuBarStatus: Equatable, Sendable {

    /// Dokumenty offline oczekujące na dosłanie do KSeF.
    public let pendingOfflineCount: Int
    /// Dokumenty offline PO terminie dosłania — wymagają uwagi.
    public let overdueOfflineCount: Int
    /// Wysyłki w toku (przetwarzane przez KSeF).
    public let processingCount: Int

    public init(invoices: [Invoice], now: Date = .now) {
        let visible = invoices.filter { !$0.isArchivedOrHidden }
        let pending = visible.filter { $0.ksefSubmissionStatus == .offlinePending }
        pendingOfflineCount = pending.count
        overdueOfflineCount = pending.filter { invoice in
            guard let deadline = invoice.offlineSendDeadline else { return false }
            return deadline < now
        }.count
        processingCount = visible.filter { $0.ksefSubmissionStatus == .processing }.count
    }

    /// Symbol SF ikony w pasku menu — czerwony trójkąt sygnalizuje
    /// przekroczony termin dosłania.
    public var systemImageName: String {
        if overdueOfflineCount > 0 { return "exclamationmark.triangle.fill" }
        if pendingOfflineCount > 0 { return "tray.full" }
        return "doc.text"
    }

    /// Jednozdaniowy opis kolejki dosłań do menu.
    public var offlineQueueDescription: String {
        if pendingOfflineCount == 0 {
            return "Brak dokumentów w kolejce dosłań"
        }
        var text = "Oczekujące dosłania: \(pendingOfflineCount)"
        if overdueOfflineCount > 0 {
            text += " (po terminie: \(overdueOfflineCount))"
        }
        return text
    }

    /// Opis ostatniej synchronizacji do menu.
    /// - Parameters:
    ///   - lastSyncAt: `timeIntervalSince1970` ostatniej synchronizacji
    ///     (0 = jeszcze nie synchronizowano),
    ///   - isSyncing: czy synchronizacja właśnie trwa.
    public static func syncDescription(
        lastSyncAt: TimeInterval,
        isSyncing: Bool,
        now: Date = .now
    ) -> String {
        if isSyncing { return "Synchronizacja w toku…" }
        guard lastSyncAt > 0 else { return "Nie synchronizowano jeszcze" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(
            for: Date(timeIntervalSince1970: lastSyncAt), relativeTo: now
        )
        return "Ostatnia synchronizacja: \(relative)"
    }
}
