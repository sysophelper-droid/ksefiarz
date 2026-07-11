import Foundation
import Security

/// Magazyn sekretów — abstrakcja nad pękiem kluczy, podmienialna w testach.
public protocol SecretStorage {
    func read(account: String) -> String?
    func save(_ value: String, account: String)
    func delete(account: String)
}

/// Implementacja `SecretStorage` na systemowym pęku kluczy
/// (generic password, usługa `pl.itkrak.ksefiarz`).
public struct KeychainSecretStorage: SecretStorage {

    private let service = "pl.itkrak.ksefiarz"

    public init() {}

    public func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ value: String, account: String) {
        guard !value.isEmpty else { return delete(account: account) }
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            update as CFDictionary
        )
        if status == errSecItemNotFound {
            var add = baseQuery(account: account)
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Pojedyncze źródło prawdy o tokenie autoryzacyjnym KSeF.
///
/// Token żyje w pęku kluczy, NIE w UserDefaults — plik preferencji jest
/// czytelny dla każdego procesu użytkownika i trafia do kopii Time Machine.
/// Uwaga eksploatacyjna: bundle podpisany ad-hoc zmienia sygnaturę przy
/// każdym wydaniu, więc po aktualizacji macOS może jednorazowo poprosić
/// o zgodę na dostęp do pęku kluczy („Zezwól”).
public final class TokenStore: ObservableObject {

    public static let shared = TokenStore()

    /// Bieżący token; każda zmiana jest utrwalana w magazynie sekretów
    /// (pusty token usuwa wpis).
    @Published public var token: String {
        didSet {
            guard token != oldValue else { return }
            if token.isEmpty {
                storage.delete(account: account)
            } else {
                storage.save(token, account: account)
            }
        }
    }

    private let storage: SecretStorage
    private var account: String

    public init(
        storage: SecretStorage = KeychainSecretStorage(),
        defaults: UserDefaults = .standard
    ) {
        let environmentRaw = defaults.string(forKey: AppSettingsKeys.environment) ?? ""
        let account = Self.account(forEnvironment: environmentRaw)
        self.storage = storage
        self.account = account
        Self.migrateFromDefaults(defaults, into: storage, account: account)
        self.token = storage.read(account: account) ?? ""
    }

    /// Konto pęku kluczy dla środowiska KSeF. Każde środowisko ma własny
    /// token — przełączenie na `test` nie może nadpisać tokenu produkcyjnego.
    /// Produkcja zachowuje historyczne konto `ksef.token` (zgodność z już
    /// zmigrowanymi instalacjami), pozostałe środowiska dostają sufiks.
    public static func account(forEnvironment environmentRaw: String) -> String {
        if environmentRaw.isEmpty || environmentRaw == KSeFEnvironment.production.rawValue {
            return AppSettingsKeys.token
        }
        return "\(AppSettingsKeys.token).\(environmentRaw)"
    }

    /// Przełącza magazyn na token wskazanego środowiska — wczytuje jego
    /// token (lub pusty, jeśli środowisko nie ma jeszcze tokenu).
    public func switchEnvironment(_ environmentRaw: String) {
        let newAccount = Self.account(forEnvironment: environmentRaw)
        guard newAccount != account else { return }
        account = newAccount
        token = storage.read(account: newAccount) ?? ""
    }

    /// Jednorazowo przenosi token z UserDefaults do magazynu sekretów
    /// i usuwa go z pliku preferencji. Token już obecny w magazynie ma
    /// pierwszeństwo — nie jest nadpisywany (ręczna konfiguracja w pęku
    /// kluczy jest nowsza niż zapomniany wpis w preferencjach).
    /// Zwraca `true`, gdy w UserDefaults był token do przeniesienia.
    @discardableResult
    public static func migrateFromDefaults(
        _ defaults: UserDefaults,
        into storage: SecretStorage,
        account: String = AppSettingsKeys.token
    ) -> Bool {
        guard let legacy = defaults.string(forKey: account), !legacy.isEmpty else {
            return false
        }
        if (storage.read(account: account) ?? "").isEmpty {
            storage.save(legacy, account: account)
        }
        defaults.removeObject(forKey: account)
        return true
    }
}
