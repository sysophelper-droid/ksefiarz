import Foundation
import Testing
@testable import KsefiarzCore

/// Magazyn sekretów w pamięci — testowy zamiennik pęku kluczy.
private final class InMemorySecretStorage: SecretStorage {
    var values: [String: String] = [:]
    func read(account: String) -> String? { values[account] }
    func save(_ value: String, account: String) { values[account] = value }
    func delete(account: String) { values[account] = nil }
}

/// Świeża, odizolowana domena UserDefaults dla pojedynczego testu.
private func makeDefaults(_ name: String) -> UserDefaults {
    let suite = "test.tokenstore.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Suite("TokenStore — token KSeF w pęku kluczy")
struct TokenStoreTests {

    @Test("Migracja przenosi token z UserDefaults do magazynu i czyści preferencje")
    func migracjaPrzenosiToken() {
        let defaults = makeDefaults("przenosi")
        defaults.set("sekretny-token", forKey: AppSettingsKeys.token)
        let storage = InMemorySecretStorage()

        let migrated = TokenStore.migrateFromDefaults(defaults, into: storage)

        #expect(migrated)
        #expect(storage.read(account: AppSettingsKeys.token) == "sekretny-token")
        #expect(defaults.string(forKey: AppSettingsKeys.token) == nil)
    }

    @Test("Migracja nie nadpisuje tokenu już obecnego w magazynie")
    func migracjaNieNadpisuje() {
        let defaults = makeDefaults("nie-nadpisuje")
        defaults.set("stary-z-defaults", forKey: AppSettingsKeys.token)
        let storage = InMemorySecretStorage()
        storage.save("aktualny-z-keychain", account: AppSettingsKeys.token)

        TokenStore.migrateFromDefaults(defaults, into: storage)

        #expect(storage.read(account: AppSettingsKeys.token) == "aktualny-z-keychain")
        // Wpis w preferencjach i tak znika — sekret nie może tam zostać.
        #expect(defaults.string(forKey: AppSettingsKeys.token) == nil)
    }

    @Test("Migracja bez tokenu w UserDefaults nic nie zmienia")
    func migracjaBezTokenu() {
        let defaults = makeDefaults("pusto")
        let storage = InMemorySecretStorage()

        let migrated = TokenStore.migrateFromDefaults(defaults, into: storage)

        #expect(!migrated)
        #expect(storage.read(account: AppSettingsKeys.token) == nil)
    }

    @Test("Inicjalizacja wczytuje token z magazynu")
    func initWczytujeToken() {
        let storage = InMemorySecretStorage()
        storage.save("zapisany-token", account: AppSettingsKeys.token)

        let store = TokenStore(storage: storage, defaults: makeDefaults("init"))

        #expect(store.token == "zapisany-token")
    }

    @Test("Zmiana tokenu utrwala go w magazynie")
    func zmianaTokenuZapisuje() {
        let storage = InMemorySecretStorage()
        let store = TokenStore(storage: storage, defaults: makeDefaults("zapis"))

        store.token = "nowy-token"

        #expect(storage.read(account: AppSettingsKeys.token) == "nowy-token")
    }

    @Test("Wyczyszczenie tokenu usuwa wpis z magazynu")
    func pustyTokenUsuwaWpis() {
        let storage = InMemorySecretStorage()
        storage.save("do-usuniecia", account: AppSettingsKeys.token)
        let store = TokenStore(storage: storage, defaults: makeDefaults("usun"))

        store.token = ""

        #expect(storage.read(account: AppSettingsKeys.token) == nil)
    }

    @Test("Kopia zapasowa nie obejmuje tokenu KSeF")
    func kopiaBezTokenu() {
        #expect(!BackupService.backedUpSettingsKeys.contains(AppSettingsKeys.token))
    }

    @Test("Produkcja używa historycznego konta, inne środowiska mają sufiks")
    func kontaPerSrodowisko() {
        #expect(TokenStore.account(forEnvironment: KSeFEnvironment.production.rawValue) == AppSettingsKeys.token)
        #expect(TokenStore.account(forEnvironment: "") == AppSettingsKeys.token)
        #expect(TokenStore.account(forEnvironment: KSeFEnvironment.test.rawValue) == "\(AppSettingsKeys.token).\(KSeFEnvironment.test.rawValue)")
    }

    @Test("Przełączenie środowiska wczytuje jego token i nie nadpisuje pozostałych")
    func przelaczenieSrodowiska() {
        let storage = InMemorySecretStorage()
        let defaults = makeDefaults("srodowiska")
        defaults.set(KSeFEnvironment.production.rawValue, forKey: AppSettingsKeys.environment)
        storage.save("token-produkcyjny", account: TokenStore.account(forEnvironment: KSeFEnvironment.production.rawValue))
        storage.save("token-testowy", account: TokenStore.account(forEnvironment: KSeFEnvironment.test.rawValue))
        let store = TokenStore(storage: storage, defaults: defaults)
        #expect(store.token == "token-produkcyjny")

        store.switchEnvironment(KSeFEnvironment.test.rawValue)

        #expect(store.token == "token-testowy")
        #expect(storage.read(account: AppSettingsKeys.token) == "token-produkcyjny")
    }

    @Test("Wpisanie tokenu po przełączeniu środowiska trafia na konto tego środowiska")
    func zapisPoPrzelaczeniu() {
        let storage = InMemorySecretStorage()
        let defaults = makeDefaults("zapis-po-przelaczeniu")
        storage.save("token-produkcyjny", account: AppSettingsKeys.token)
        let store = TokenStore(storage: storage, defaults: defaults)

        store.switchEnvironment(KSeFEnvironment.test.rawValue)
        store.token = "nowy-token-testowy"

        #expect(storage.read(account: TokenStore.account(forEnvironment: KSeFEnvironment.test.rawValue)) == "nowy-token-testowy")
        #expect(storage.read(account: AppSettingsKeys.token) == "token-produkcyjny")
    }
}
