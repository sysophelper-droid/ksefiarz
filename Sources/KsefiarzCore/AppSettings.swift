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
    /// Forma opodatkowania podatkiem dochodowym (rawValue `TaxForm`) —
    /// decyduje, czy w pasku bocznym jest KPiR czy ewidencja przychodów
    /// (ryczałt). Nie można prowadzić obu równocześnie.
    public static let taxForm = "ksef.taxForm"
    /// Domyślna stawka ryczałtu (rawValue `RyczaltRate`) — używana dla wpisów
    /// ewidencji bez własnej stawki. Można ją nadpisać na każdym wpisie.
    public static let ryczaltDefaultRate = "ksef.ryczaltDefaultRate"
    /// Metoda zaliczki PIT dla KPiR (skala albo podatek liniowy).
    public static let kpirIncomeTaxMethod = "ksef.kpirIncomeTaxMethod"
    /// Częstotliwość zaliczki PIT/ryczałtu oraz rozliczenia VAT.
    public static let incomeTaxSettlementCycle = "ksef.incomeTaxSettlementCycle"
    public static let vatSettlementCycle = "ksef.vatSettlementCycle"
    /// Czy firma jest czynnym podatnikiem VAT (terminy JPK/VAT i prognoza).
    public static let isActiveVATPayer = "ksef.isActiveVATPayer"
    /// Czy wydruki własnych faktur mają używać brandingu firmy.
    public static let pdfBrandingEnabled = "pdf.branding.enabled"
    /// Logo firmy jako znormalizowany PNG zakodowany Base64.
    public static let pdfBrandingLogo = "pdf.branding.logo"
    /// Kolory brandingu zapisane jako RGB w formacie #RRGGBB.
    public static let pdfBrandingPrimaryColor = "pdf.branding.primaryColor"
    public static let pdfBrandingAccentColor = "pdf.branding.accentColor"
    /// Własna stopka umieszczana na każdej stronie wydruku faktury.
    public static let pdfBrandingFooter = "pdf.branding.footer"
    /// Czy na wydruku własnej faktury drukować kod QR płatności (standard 2D
    /// ZBP) — klient skanuje aplikacją banku i płaci. Domyślnie włączony.
    public static let pdfPaymentQR = "pdf.paymentQR"
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
    public static let numberPatternRR = "ksef.numberPattern.RR"
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
    /// JPK_V7M: czterocyfrowy kod urzędu skarbowego (KodUrzedu).
    public static let jpkTaxOfficeCode = "jpk.kodUrzedu"
    /// JPK_V7M: adres e-mail podatnika (Podmiot1/Email).
    public static let jpkEmail = "jpk.email"
    /// Wezwania do zapłaty: roczna stopa odsetek za opóźnienie (%) —
    /// domyślnie odsetki ustawowe za opóźnienie w transakcjach handlowych.
    public static let demandInterestRate = "demand.interestRate"
    /// Wezwania do zapłaty: termin zapłaty z wezwania (dni).
    public static let demandPaymentDays = "demand.paymentDays"
    /// Ikona Ksefiarza w pasku menu (status synchronizacji i dosłań).
    public static let menuBarExtra = "ksef.menuBarExtra"
    /// Automatyczne odnawianie certyfikatów KSeF przed wygaśnięciem
    /// (wniosek o nowy typ 1/typ 2 i podmiana w pęku kluczy).
    public static let autoRenewCertificates = "ksef.autoRenewCertificates"
    /// Pamięć podjętych prób odnowienia certyfikatu (klucze z datą — dedup,
    /// jedna próba na certyfikat na dobę).
    public static let certificateRenewalAttemptedKeys = "ksef.certificateRenewalAttemptedKeys"
}
