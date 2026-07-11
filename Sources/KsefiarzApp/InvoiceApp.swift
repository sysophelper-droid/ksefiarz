import AppKit
import SwiftUI
import SwiftData
import KsefiarzCore

/// Delegat aplikacji — wymagany przy uruchamianiu przez `swift run`,
/// gdy binarka nie jest pełnym bundlem .app. Bez jawnej polityki aktywacji
/// macOS traktuje proces jako narzędzie tła i nie pokazuje okna.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyDefaultsIfNeeded()

        // Pierwszy dostęp do TokenStore przenosi token KSeF z UserDefaults
        // do pęku kluczy i usuwa go z pliku preferencji — musi nastąpić
        // PO migracji starej domeny defaults, żeby nie zgubić tokenu.
        _ = TokenStore.shared

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Ikona aplikacji w Docku — ładowana z zasobów pakietu.
        // Przy uruchomieniu z bundla .app ikona pochodzi z Info.plist,
        // ale ustawiamy ją też tutaj, aby działało również `swift run`.
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
    }

    /// Migracja ustawień ze starej domeny UserDefaults.
    ///
    /// Wersje uruchamiane przez `swift run` (bez bundla) zapisywały ustawienia
    /// w domenie procesu „Ksefiarz”. Po przejściu na bundle .app z identyfikatorem
    /// domena się zmienia — przenosimy zapisane klucze, aby nie zgubić
    /// tokenu KSeF, NIP-u i preferencji.
    private func migrateLegacyDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        // Migrujemy tylko, gdy nowa domena nie ma jeszcze konfiguracji.
        let hasConfiguration = !(defaults.string(forKey: "ksef.nip") ?? "").isEmpty
        guard !hasConfiguration,
              let legacy = defaults.persistentDomain(forName: "Ksefiarz") else { return }

        for (key, value) in legacy where key.hasPrefix("ksef.") || key.hasPrefix("filter.") {
            if defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
    }
}

/// Punkt wejścia aplikacji Ksefiarz.
/// Konfiguruje kontener SwiftData i główne okno z `MainContentView`.
@main
struct InvoiceApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Wspólny kontener bazy danych dla całej aplikacji.
    ///
    /// Baza MUSI mieć jawny, dedykowany plik. SwiftData bez podanego URL-a
    /// zapisuje (poza sandboxem) do współdzielonego
    /// `~/Library/Application Support/default.store` — z tego samego pliku
    /// korzysta każdy proces z domyślną konfiguracją, w tym agenci systemowi
    /// Apple, a ich migracja schematu kasuje cudze tabele (12.06.2026
    /// `com.apple.icloudmailagent` usunął w ten sposób wszystkie faktury).
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Invoice.self, PaymentRecord.self, Contractor.self, Product.self,
                             BankAccount.self, InvoiceTemplate.self, RecurringInvoice.self,
                             SyncRun.self])
        let storeDirectory = URL.applicationSupportDirectory
            .appending(path: "Ksefiarz", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: storeDirectory, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(
                schema: schema,
                url: storeDirectory.appending(path: "Ksefiarz.store"))
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Nie udało się utworzyć kontenera SwiftData: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainContentView()
        }
        .modelContainer(sharedModelContainer)

        // Standardowe okno Ustawień macOS (⌘,) — te same ustawienia co w pasku bocznym.
        Settings {
            SettingsView()
                .frame(width: 520, height: 520)
        }
    }
}
