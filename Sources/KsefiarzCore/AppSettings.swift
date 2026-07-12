import Foundation

/// Klucze ustawień aplikacji (UserDefaults / @AppStorage).
///
/// Wyjątek: token autoryzacyjny KSeF NIE leży w UserDefaults — żyje w pęku
/// kluczy (patrz `TokenStore`); jego klucz służy tu jako nazwa konta
/// w Keychain i do migracji starych instalacji.
public enum AppSettingsKeys {
    /// Nazwa firmy użytkownika (sprzedawca przy wystawianiu faktur).
    public static let sellerName = "ksef.sellerName"
    /// Adres firmy użytkownika (wymagany przez FA(2) przy wystawianiu).
    public static let sellerAddress = "ksef.sellerAddress"
    /// NIP firmy użytkownika.
    public static let nip = "ksef.nip"
    /// Numer rachunku bankowego do płatności (na wystawianych fakturach).
    public static let bankAccount = "ksef.bankAccount"
    /// Token autoryzacyjny KSeF.
    public static let token = "ksef.token"
    /// Wybrane środowisko KSeF (rawValue `KSeFEnvironment`).
    public static let environment = "ksef.environment"
    /// Tryb zakresu dat dla importu i analiz (rawValue `DateRangeMode`).
    public static let rangeMode = "ksef.rangeMode"
    /// Granice własnego zakresu dat (timeIntervalSince1970).
    public static let rangeFrom = "ksef.rangeFrom"
    public static let rangeTo = "ksef.rangeTo"
    /// Wzorzec automatycznej numeracji faktur VAT (symbole {RRRR},{MM},{DD},{N…}).
    public static let numberPattern = "ksef.numberPattern"
    /// Wzorce numeracji pozostałych rodzajów dokumentów — pusty wzorzec
    /// oznacza dziedziczenie wzorca faktur VAT.
    public static let numberPatternZAL = "ksef.numberPattern.ZAL"
    public static let numberPatternROZ = "ksef.numberPattern.ROZ"
    public static let numberPatternUPR = "ksef.numberPattern.UPR"
    public static let numberPatternKOR = "ksef.numberPattern.KOR"
    /// Formy płatności traktowane jako opłacone z góry (kody rozdzielone przecinkami).
    public static let prepaidForms = "ksef.prepaidForms"
    /// Horyzont (w dniach) widgetu „Płatności w najbliższych dniach” na Kokpicie.
    public static let dueSoonDays = "ksef.dueSoonDays"
    /// Automatyczne pobranie faktur (sprzedaż + zakup) przy starcie aplikacji.
    public static let syncOnLaunch = "ksef.syncOnLaunch"
    /// Cykliczne pobieranie faktur, gdy aplikacja jest uruchomiona.
    public static let autoSync = "ksef.autoSync"
    /// Interwał automatycznego pobierania w minutach.
    public static let autoSyncIntervalMinutes = "ksef.autoSyncIntervalMinutes"
    /// Czas ostatniej udanej synchronizacji (timeIntervalSince1970) —
    /// zapisywany przez InvoiceSyncEngine, prezentowany w pasku bocznym.
    public static let lastSyncAt = "ksef.lastSyncAt"
    /// Automatyczna kopia zapasowa przy starcie (domyślnie włączona).
    public static let autoBackup = "backup.auto"
    /// Tryb rotacji kopii (rawValue `AutoBackupService.RotationMode`).
    public static let autoBackupRotationMode = "backup.rotationMode"
    /// Liczba przechowywanych kopii (tryb „liczba kopii”).
    public static let autoBackupKeepCount = "backup.keepCount"
    /// Liczba dni wstecz (tryb „dni wstecz”).
    public static let autoBackupKeepDays = "backup.keepDays"
    /// Powiadomienia systemowe o nowych fakturach zakupowych z synchronizacji.
    public static let notifyNewPurchases = "ksef.notifyNewPurchases"
    /// Powiadomienia o terminach: płatności (dziś/jutro) i dosłań offline.
    public static let notifyDeadlines = "ksef.notifyDeadlines"
    /// Pamięć doręczonych powiadomień o terminach (klucze z datą — dedup).
    public static let deadlineNotifiedKeys = "ksef.deadlineNotifiedKeys"
}
