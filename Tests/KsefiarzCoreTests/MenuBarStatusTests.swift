import Foundation
import Testing
@testable import KsefiarzCore

@Suite("Pasek menu — liczniki dosłań i opisy statusu")
struct MenuBarStatusTests {

    /// Punkt odniesienia: środa 15 lipca 2026, południe.
    private let now = FA2Format.dateFormatter.date(from: "2026-07-15")!.addingTimeInterval(12 * 3600)

    private func makeInvoice(
        number: String,
        issue: String,
        status: KSeFSubmissionStatus? = nil,
        offline: Bool = false,
        hidden: Bool = false
    ) -> Invoice {
        let invoice = Invoice(
            invoiceNumber: number,
            issueDate: FA2Format.dateFormatter.date(from: issue)!,
            sellerName: "S", sellerNIP: "9999999999",
            buyerName: "N", buyerNIP: "1111111111",
            netAmount: 100, vatAmount: 23, grossAmount: 123,
            isArchivedOrHidden: hidden,
            ksefSubmissionStatus: status,
            kind: .sales
        )
        invoice.isOfflineMode = offline
        return invoice
    }

    @Test("Liczniki: oczekujące i po terminie dosłania; ukryte pomijane")
    func counters() {
        let invoices = [
            // Offline24 wystawiona 13.07 (poniedziałek) — termin minął 14.07.
            makeInvoice(number: "S/1", issue: "2026-07-13", status: .offlinePending, offline: true),
            // Offline24 wystawiona dziś — termin jutro (jeszcze nie minął).
            makeInvoice(number: "S/2", issue: "2026-07-15", status: .offlinePending, offline: true),
            // Ukryta nie wchodzi do liczników.
            makeInvoice(number: "S/3", issue: "2026-07-13", status: .offlinePending, offline: true, hidden: true),
            // Wysyłka w toku.
            makeInvoice(number: "S/4", issue: "2026-07-15", status: .processing),
            // Zwykła przyjęta.
            makeInvoice(number: "S/5", issue: "2026-07-15", status: .accepted),
        ]
        let status = MenuBarStatus(invoices: invoices, now: now)

        #expect(status.pendingOfflineCount == 2)
        #expect(status.overdueOfflineCount == 1)
        #expect(status.processingCount == 1)
        #expect(status.systemImageName == "exclamationmark.triangle.fill")
        #expect(status.offlineQueueDescription == "Oczekujące dosłania: 2 (po terminie: 1)")
    }

    @Test("Pusta kolejka: neutralna ikona i komunikat o braku dokumentów")
    func emptyQueue() {
        let status = MenuBarStatus(
            invoices: [makeInvoice(number: "S/1", issue: "2026-07-15", status: .accepted)],
            now: now
        )
        #expect(status.pendingOfflineCount == 0)
        #expect(status.overdueOfflineCount == 0)
        #expect(status.systemImageName == "doc.text")
        #expect(status.offlineQueueDescription == "Brak dokumentów w kolejce dosłań")
    }

    @Test("Kolejka bez zaległości pokazuje ikonę pełnej tacki")
    func pendingWithoutOverdue() {
        let status = MenuBarStatus(
            invoices: [makeInvoice(number: "S/1", issue: "2026-07-15", status: .offlinePending, offline: true)],
            now: now
        )
        #expect(status.systemImageName == "tray.full")
        #expect(status.offlineQueueDescription == "Oczekujące dosłania: 1")
    }

    @Test("Opis synchronizacji: w toku, brak historii, czas względny")
    func syncDescriptions() {
        #expect(MenuBarStatus.syncDescription(lastSyncAt: 0, isSyncing: true) == "Synchronizacja w toku…")
        #expect(MenuBarStatus.syncDescription(lastSyncAt: 0, isSyncing: false) == "Nie synchronizowano jeszcze")

        let fiveMinutesAgo = now.addingTimeInterval(-5 * 60).timeIntervalSince1970
        let description = MenuBarStatus.syncDescription(
            lastSyncAt: fiveMinutesAgo, isSyncing: false, now: now
        )
        #expect(description.hasPrefix("Ostatnia synchronizacja:"))
        #expect(description.contains("5"))
    }
}
