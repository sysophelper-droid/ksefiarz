import Foundation

/// Automatyczne odnowienie certyfikatów KSeF: decyduje, które certyfikaty
/// (typ 1 — uwierzytelniający, typ 2 — offline) należy odnowić PRZED
/// wygaśnięciem, żeby stary nie przestał działać. Czysta logika — sam wniosek
/// do KSeF, zapis w pęku kluczy i powiadomienia realizuje warstwa widoku
/// (`CertificateRenewalCoordinator`).
///
/// Odnowienie wymaga zalogowania podpisem XAdES WAŻNYM certyfikatem typu 1
/// (enrollment API — tokenem się nie da, błąd 25002). Stąd zasady:
/// - typ 1 odnawiamy, DOPÓKI jest jeszcze ważny (logujemy się nim samym);
/// - typ 2 odnawiamy, o ile istnieje ważny certyfikat typu 1 (nim się
///   logujemy) — certyfikat typu 2 może być nawet już przeterminowany.
/// Gdy certyfikat typu 1 wygasł, automat nic nie zrobi — użytkownik musi
/// zaimportować nowy typ 1 z pliku (Aplikacja Podatnika KSeF 2.0).
public enum CertificateRenewalEngine {

    /// Domyślny próg: odnawiaj, gdy do wygaśnięcia zostało tyle dni lub mniej
    /// (spójnie z ostrzeżeniem „<30 dni” w Ustawieniach).
    public static let defaultThresholdDays = 30

    /// Po ilu dniach klucze prób odnowienia są zapominane (przycinanie pamięci
    /// deduplikacji — analogicznie do `DeadlineNotificationEngine`).
    static let attemptRetentionDays = 14

    /// Powód zaplanowania odnowienia certyfikatu.
    public enum Reason: Equatable, Sendable {
        /// Certyfikat wciąż ważny, ale wygasa za `days` dni (≤ próg).
        case expiringSoon(days: Int)
        /// Certyfikat wygasł `days` dni temu (odnawialny tylko dla typu 2,
        /// dopóki certyfikat typu 1 jest wciąż ważny).
        case expired(days: Int)
    }

    /// Certyfikat zaplanowany do odnowienia.
    public struct Candidate: Equatable, Sendable {
        public let type: KSeFCertificateType
        public let reason: Reason
        /// Klucz deduplikacji: `renew|typ|seryjny|RRRR-MM-DD` — jedna próba
        /// danego certyfikatu na dobę (ochrona przed limitami wniosków API
        /// i przed powtórnym wnioskiem przy każdym starcie/tiku timera).
        public let dedupKey: String
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let expiryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "pl_PL")
        return formatter
    }()

    /// Zwraca certyfikaty wymagające odnowienia. `authentication`/`offline` to
    /// pola aktualnych certyfikatów danego środowiska (nil = brak certyfikatu
    /// danego typu — nie ma czego odnawiać). Pomija próby już podjęte dziś
    /// (`alreadyAttempted`).
    public static func candidates(
        authentication: KSeFCertificate.CertificateInfo?,
        offline: KSeFCertificate.CertificateInfo?,
        thresholdDays: Int = defaultThresholdDays,
        now: Date = .now,
        alreadyAttempted: Set<String> = []
    ) -> [Candidate] {
        // Warunek konieczny KAŻDEGO odnowienia: ważny certyfikat typu 1 jako
        // podpisujący wniosek. Bez niego enrollment API odrzuci żądanie.
        guard let authentication, authentication.isValid(at: now) else { return [] }

        var result: [Candidate] = []

        // Typ 1 — odnawiamy, dopóki ważny i mieści się w progu. (Po wygaśnięciu
        // nie da się nim zalogować, więc warunek wyżej i tak by nas zatrzymał.)
        let authDays = authentication.daysToExpiry(from: now)
        if authDays <= thresholdDays,
           let candidate = makeCandidate(
               type: .authentication,
               serial: authentication.serialNumberHex,
               reason: .expiringSoon(days: authDays),
               now: now,
               alreadyAttempted: alreadyAttempted
           ) {
            result.append(candidate)
        }

        // Typ 2 — odnawiamy w progu LUB po wygaśnięciu (logujemy się typem 1).
        if let offline {
            let offlineDays = offline.daysToExpiry(from: now)
            if offlineDays <= thresholdDays {
                let reason: Reason = offline.isValid(at: now)
                    ? .expiringSoon(days: offlineDays)
                    : .expired(days: -offlineDays)
                if let candidate = makeCandidate(
                    type: .offline,
                    serial: offline.serialNumberHex,
                    reason: reason,
                    now: now,
                    alreadyAttempted: alreadyAttempted
                ) {
                    result.append(candidate)
                }
            }
        }
        return result
    }

    private static func makeCandidate(
        type: KSeFCertificateType,
        serial: String,
        reason: Reason,
        now: Date,
        alreadyAttempted: Set<String>
    ) -> Candidate? {
        let key = dedupKey(type: type, serial: serial, now: now)
        guard !alreadyAttempted.contains(key) else { return nil }
        return Candidate(type: type, reason: reason, dedupKey: key)
    }

    /// Klucz deduplikacji próby odnowienia (jedna próba na certyfikat na dobę).
    public static func dedupKey(
        type: KSeFCertificateType,
        serial: String,
        now: Date = .now
    ) -> String {
        "renew|\(type.rawValue)|\(serial)|\(dayFormatter.string(from: now))"
    }

    /// Przycina pamięć prób: zostają klucze z ostatnich `attemptRetentionDays`
    /// dni (dzień jest ostatnią częścią klucza).
    public static func prune(attempted: Set<String>, now: Date = .now) -> Set<String> {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(
            byAdding: .day, value: -attemptRetentionDays, to: calendar.startOfDay(for: now)
        ) else { return attempted }
        return attempted.filter { key in
            guard let dayPart = key.split(separator: "|").last,
                  let day = dayFormatter.date(from: String(dayPart)) else { return false }
            return day >= cutoff
        }
    }

    // MARK: Treści powiadomień

    /// Powiadomienie o udanym odnowieniu certyfikatu.
    public static func successMessage(
        type: KSeFCertificateType,
        validTo: Date
    ) -> (title: String, body: String) {
        (
            "Odnowiono certyfikat KSeF",
            "Certyfikat „\(type.displayName)” został automatycznie odnowiony. "
                + "Nowy jest ważny do \(expiryDateFormatter.string(from: validTo))."
        )
    }

    /// Powiadomienie o nieudanej próbie odnowienia — stary certyfikat pozostaje
    /// nietknięty (odnowienie nie kasuje działającego certyfikatu).
    public static func failureMessage(
        type: KSeFCertificateType,
        error: String
    ) -> (title: String, body: String) {
        (
            "Nie udało się odnowić certyfikatu KSeF",
            "Automatyczne odnowienie certyfikatu „\(type.displayName)” nie powiodło się: "
                + "\(error) Dotychczasowy certyfikat działa nadal — odnów go ręcznie "
                + "w Ustawieniach → KSeF."
        )
    }
}

// MARK: - Wykonanie planu odnowień

/// Wynik pojedynczego odnowienia — do powiadomień i zapamiętania próby.
public struct CertificateRenewalOutcome: Equatable, Sendable {
    public let type: KSeFCertificateType
    public let success: Bool
    public let notificationTitle: String
    public let notificationBody: String
    /// Klucz deduplikacji z kandydata — zapamiętywany NIEZALEŻNIE od wyniku
    /// (jedna próba na dobę, także po niepowodzeniu).
    public let dedupKey: String
}

/// Wykonuje plan odnowień: dla każdego kandydata składa wniosek (`renew`)
/// i — WYŁĄCZNIE przy powodzeniu — zapisuje nowy certyfikat (`save`).
/// Niepowodzenie NIE narusza dotychczasowego certyfikatu w pęku kluczy.
///
/// @MainActor, bo `save` publikuje zmianę w `KSeFCertificateStore`
/// (ObservableObject) — mutacja @Published musi iść z głównego wątku.
/// Sieciowe `renew` i tak zwalnia wątek na punktach `await`.
public enum CertificateRenewalCoordinator {

    @MainActor
    public static func run(
        candidates: [CertificateRenewalEngine.Candidate],
        renew: (KSeFCertificateType) async throws -> KSeFCertificate,
        save: (KSeFCertificate, KSeFCertificateType) -> Void
    ) async -> [CertificateRenewalOutcome] {
        var outcomes: [CertificateRenewalOutcome] = []
        for candidate in candidates {
            do {
                let certificate = try await renew(candidate.type)
                save(certificate, candidate.type)
                let validTo = certificate.info?.validTo ?? .now
                let message = CertificateRenewalEngine.successMessage(
                    type: candidate.type, validTo: validTo
                )
                outcomes.append(CertificateRenewalOutcome(
                    type: candidate.type,
                    success: true,
                    notificationTitle: message.title,
                    notificationBody: message.body,
                    dedupKey: candidate.dedupKey
                ))
            } catch {
                let message = CertificateRenewalEngine.failureMessage(
                    type: candidate.type, error: error.localizedDescription
                )
                outcomes.append(CertificateRenewalOutcome(
                    type: candidate.type,
                    success: false,
                    notificationTitle: message.title,
                    notificationBody: message.body,
                    dedupKey: candidate.dedupKey
                ))
            }
        }
        return outcomes
    }
}
