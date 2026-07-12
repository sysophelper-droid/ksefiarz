import AppKit
import Combine
import SwiftData

/// Ikona Ksefiarza w pasku menu — zbudowana na AppKit (`NSStatusItem`),
/// a NIE na scenie SwiftUI `MenuBarExtra`. Na macOS 26 współistnienie sceny
/// `MenuBarExtra` z oknem zawierającym `NavigationSplitView` wpada
/// w nieskończoną pętlę renderowania (100% CPU, zawieszenie). NSStatusItem
/// nie dotyka grafu scen SwiftUI, więc jest odporny.
///
/// Kontroler żyje niezależnie od okna (singleton). Uruchamia go
/// `MainContentView.onAppear`, bo tam jest dostęp do `modelContext`
/// (delegat AppKit `applicationDidFinishLaunching` nie jest przy
/// `@NSApplicationDelegateAdaptor` gwarantowany).
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {

    public static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var context: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var observing = false

    private override init() { super.init() }

    /// Uruchamiany z `MainContentView` (ma dostęp do `modelContext`).
    /// Idempotentny — kolejne wywołania tylko odświeżają kontekst i widoczność.
    public func start(context: ModelContext) {
        self.context = context
        syncVisibility()
        guard !observing else { return }
        observing = true

        // Zmiana przełącznika w Ustawieniach dodaje/usuwa ikonę bez restartu.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncVisibility() }
            .store(in: &cancellables)

        // Świeży symbol ikony (np. czerwony trójkąt po terminie dosłania).
        SyncActivity.shared.$menuBarStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.updateButton(status) }
            .store(in: &cancellables)
    }

    /// Czy ikona ma być widoczna. Domyślnie tak, ale można ją wyłączyć
    /// w Ustawieniach → Synchronizacja.
    private var enabled: Bool {
        UserDefaults.standard.object(forKey: AppSettingsKeys.menuBarExtra) == nil
            ? true
            : UserDefaults.standard.bool(forKey: AppSettingsKeys.menuBarExtra)
    }

    private func syncVisibility() {
        if enabled {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
            refresh()
            updateButton(SyncActivity.shared.menuBarStatus)
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Przelicza liczniki z bazy i (przez subskrypcję) odświeża symbol ikony.
    private func refresh() {
        let invoices = (try? context?.fetch(FetchDescriptor<Invoice>())) ?? []
        SyncActivity.shared.refreshMenuBarStatus(invoices: invoices)
    }

    private func updateButton(_ status: MenuBarStatus?) {
        guard let button = statusItem?.button else { return }
        let symbol = status?.systemImageName ?? "doc.text"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Ksefiarz")
        if let status, status.pendingOfflineCount > 0 {
            button.title = " \(status.pendingOfflineCount)"
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    // MARK: - NSMenuDelegate

    /// Buduje zawartość menu przy każdym otwarciu — świeży status i liczniki.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        menu.removeAllItems()

        let status = SyncActivity.shared.menuBarStatus ?? MenuBarStatus(invoices: [])
        let lastSyncAt = UserDefaults.standard.double(forKey: AppSettingsKeys.lastSyncAt)

        menu.addItem(infoItem(MenuBarStatus.syncDescription(
            lastSyncAt: lastSyncAt, isSyncing: SyncActivity.shared.isSyncing)))
        menu.addItem(infoItem(status.offlineQueueDescription))
        if status.processingCount > 0 {
            menu.addItem(infoItem("Wysyłki przetwarzane przez KSeF: \(status.processingCount)"))
        }
        if let error = SyncActivity.shared.lastError {
            menu.addItem(infoItem("Błąd synchronizacji: \(error)"))
        }

        menu.addItem(.separator())

        let sync = NSMenuItem(
            title: "Pobierz z KSeF", action: #selector(quickSync), keyEquivalent: "")
        sync.target = self
        sync.isEnabled = !SyncActivity.shared.isSyncing
        menu.addItem(sync)

        let open = NSMenuItem(
            title: "Otwórz Ksefiarza", action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Zakończ Ksefiarza", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func quickSync() {
        guard let context else { return }
        Task { @MainActor in
            await QuickSyncRunner.syncAll(context: context)
            refresh()
        }
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            MainWindowOpener.open?()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
