import AppKit
import SwiftUI
import SwiftData

/// Ikona Ksefiarza w pasku menu — zmienia symbol, gdy w kolejce dosłań
/// czekają dokumenty (czerwony trójkąt = po terminie), a liczniki pokazuje
/// z ostatniego przebiegu synchronizacji (`SyncActivity`).
public struct MenuBarExtraLabel: View {

    @ObservedObject private var activity = SyncActivity.shared

    public init() {}

    public var body: some View {
        let status = activity.menuBarStatus
        HStack(spacing: 2) {
            Image(systemName: status?.systemImageName ?? "doc.text")
            if let status, status.pendingOfflineCount > 0 {
                Text("\(status.pendingOfflineCount)")
            }
        }
    }
}

/// Zawartość menu przy ikonie w pasku menu: status synchronizacji,
/// kolejka dosłań offline, szybkie „Pobierz z KSeF” i powrót do okna
/// aplikacji. Działa również przy zamkniętym oknie głównym.
public struct MenuBarExtraView: View {

    @Query private var invoices: [Invoice]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var activity = SyncActivity.shared
    @AppStorage(AppSettingsKeys.lastSyncAt) private var lastSyncAt = 0.0

    public init() {}

    public var body: some View {
        let status = MenuBarStatus(invoices: invoices)

        Text(MenuBarStatus.syncDescription(lastSyncAt: lastSyncAt, isSyncing: activity.isSyncing))
        Text(status.offlineQueueDescription)
        if status.processingCount > 0 {
            Text("Wysyłki przetwarzane przez KSeF: \(status.processingCount)")
        }
        if let error = activity.lastError {
            Text("Błąd synchronizacji: \(error)")
        }

        Divider()

        Button("Pobierz z KSeF") {
            Task { await QuickSyncRunner.syncAll(context: modelContext) }
        }
        .disabled(activity.isSyncing)

        Button("Otwórz Ksefiarza") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Divider()

        Button("Zakończ Ksefiarza") {
            NSApp.terminate(nil)
        }

        // Otwarcie menu odświeża liczniki ikony (poza cyklem synchronizacji).
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { activity.refreshMenuBarStatus(invoices: invoices) }
    }
}
