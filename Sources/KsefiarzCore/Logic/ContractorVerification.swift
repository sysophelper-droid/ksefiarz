import Foundation

// MARK: - Status rejestracji VAT (Wykaz podatników — „Biała lista”)

/// Status podmiotu w Wykazie podatników VAT (rozpoznany z pola `statusVat`
/// zwracanego przez `wl-api.mf.gov.pl` albo z braku podmiotu w wykazie).
public enum VATRegistrationStatus: String, Sendable, Equatable {
    /// Czynny podatnik VAT.
    case active
    /// Zwolniony z VAT (podmiotowo lub przedmiotowo).
    case exempt
    /// Nie figuruje w wykazie jako zarejestrowany podatnik VAT.
    case notRegistered
    /// Statusu nie udało się ustalić (błąd usługi, pusty status).
    case unknown

    /// Rozpoznaje status z surowego napisu `statusVat` wykazu.
    /// Wykaz zwraca m.in. „Czynny”, „Zwolniony”, „Niezarejestrowany”.
    public init(rawStatus: String) {
        let normalized = rawStatus
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
            .lowercased()
        if normalized.isEmpty {
            self = .unknown
        } else if normalized.contains("czynny") {
            self = .active
        } else if normalized.contains("zwolniony") {
            self = .exempt
        } else if normalized.contains("niezarejestrowany") || normalized.contains("nie figuruje") {
            self = .notRegistered
        } else {
            self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .active: return "Czynny podatnik VAT"
        case .exempt: return "Zwolniony z VAT"
        case .notRegistered: return "Niezarejestrowany do VAT"
        case .unknown: return "Status VAT nieustalony"
        }
    }
}

// MARK: - Uprawnienie podmiotowe nadane nam przez kontrahenta (KSeF)

/// Uprawnienie podmiotowe, które kontrahent nadał NASZEMU podmiotowi w KSeF
/// (wynik zapytania `authorizations/grants` z `queryType=Received`,
/// filtrowanego po NIP kontrahenta jako nadającego).
public struct ContractorKSeFAuthorization: Identifiable, Sendable, Equatable {
    public let id: String
    /// Surowy zakres uprawnienia podmiotowego (np. „SelfInvoicing”).
    public let scopeRaw: String
    /// Data początku obowiązywania, jeśli KSeF ją zwrócił.
    public let startDate: Date?

    public init(id: String, scopeRaw: String, startDate: Date?) {
        self.id = id
        self.scopeRaw = scopeRaw
        self.startDate = startDate
    }

    /// Polska etykieta zakresu (reużywa słownika `PermissionsEngine`).
    public var scopeLabel: String { PermissionsEngine.scopeLabel(scopeRaw) }
}

// MARK: - Waga (severity) pozycji werdyktu

/// Waga pojedynczego ustalenia w karcie weryfikacji — steruje ikoną i kolorem
/// w UI oraz wyliczeniem ogólnego werdyktu.
public enum ContractorVerificationSeverity: Int, Sendable, Equatable, Comparable {
    case ok = 0
    case info = 1
    case warning = 2
    case critical = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Wynik weryfikacji kontrahenta

/// Złożony wynik weryfikacji kontrahenta: walidacja NIP, status z Wykazu
/// podatników VAT (Biała lista) oraz relacja uprawnień podmiotowych w KSeF.
/// Czysta struktura danych — budowana przez `ContractorVerification.build`,
/// prezentowana przez `ContractorVerificationView`.
public struct ContractorVerificationResult: Sendable, Equatable {

    /// Znormalizowany NIP (same cyfry), o który pytano.
    public let nip: String
    /// Poprawność NIP (10 cyfr, prawidłowa suma kontrolna).
    public let isNIPValid: Bool

    /// Status rejestracji VAT ustalony z wykazu (albo `.unknown` przy błędzie).
    public let vatStatus: VATRegistrationStatus
    /// Nazwa podmiotu zwrócona przez wykaz podatników VAT.
    public let whiteListName: String?
    /// Komunikat błędu usługi wykazu, jeśli zapytanie się nie powiodło.
    public let whiteListError: String?

    /// Czy w ogóle odpytano KSeF (wymaga poświadczeń — NIP + token/certyfikat).
    public let ksefChecked: Bool
    /// Uprawnienia podmiotowe nadane nam przez kontrahenta w KSeF.
    public let ksefAuthorizations: [ContractorKSeFAuthorization]
    /// Komunikat błędu zapytania KSeF, jeśli się nie powiodło.
    public let ksefError: String?

    public init(
        nip: String,
        isNIPValid: Bool,
        vatStatus: VATRegistrationStatus,
        whiteListName: String?,
        whiteListError: String?,
        ksefChecked: Bool,
        ksefAuthorizations: [ContractorKSeFAuthorization],
        ksefError: String?
    ) {
        self.nip = nip
        self.isNIPValid = isNIPValid
        self.vatStatus = vatStatus
        self.whiteListName = whiteListName
        self.whiteListError = whiteListError
        self.ksefChecked = ksefChecked
        self.ksefAuthorizations = ksefAuthorizations
        self.ksefError = ksefError
    }

    /// Ogólna waga werdyktu — najcięższe pojedyncze ustalenie.
    public var overallSeverity: ContractorVerificationSeverity {
        findings.map(\.severity).max() ?? .ok
    }

    /// Nagłówek werdyktu do wyróżnienia na karcie.
    public var headline: String {
        guard isNIPValid else { return "Nieprawidłowy NIP" }
        switch vatStatus {
        case .active: return "Czynny podatnik VAT"
        case .exempt: return "Podatnik zwolniony z VAT"
        case .notRegistered: return "Podmiot niezarejestrowany do VAT"
        case .unknown:
            return whiteListError == nil
                ? "Weryfikacja częściowa"
                : "Nie udało się w pełni zweryfikować"
        }
    }

    /// Pojedyncze ustalenie karty weryfikacji (linia z ikoną i opisem).
    public struct Finding: Identifiable, Sendable, Equatable {
        public let id: String
        public let severity: ContractorVerificationSeverity
        public let title: String
        public let detail: String?

        public init(id: String, severity: ContractorVerificationSeverity, title: String, detail: String? = nil) {
            self.id = id
            self.severity = severity
            self.title = title
            self.detail = detail
        }
    }

    /// Uporządkowana lista ustaleń: NIP → status VAT → relacja KSeF → nota.
    public var findings: [Finding] {
        var result: [Finding] = []

        // 1. Poprawność NIP.
        if isNIPValid {
            result.append(.init(
                id: "nip",
                severity: .ok,
                title: "NIP poprawny (suma kontrolna zgodna)."
            ))
        } else {
            result.append(.init(
                id: "nip",
                severity: .critical,
                title: "Nieprawidłowy NIP.",
                detail: "Wymagane 10 cyfr z poprawną sumą kontrolną. Dalsze sprawdzenia pominięto."
            ))
            // Przy błędnym NIP nie było sensu pytać usług — kończymy tu.
            return result
        }

        // 2. Status VAT z wykazu.
        if let whiteListError {
            result.append(.init(
                id: "vat",
                severity: .warning,
                title: "Nie udało się pobrać statusu VAT z wykazu podatników.",
                detail: whiteListError
            ))
        } else {
            switch vatStatus {
            case .active:
                result.append(.init(
                    id: "vat",
                    severity: .ok,
                    title: "Czynny podatnik VAT (Wykaz podatników VAT).",
                    detail: whiteListName
                ))
            case .exempt:
                result.append(.init(
                    id: "vat",
                    severity: .info,
                    title: "Podatnik zwolniony z VAT (Wykaz podatników VAT).",
                    detail: whiteListName
                ))
            case .notRegistered:
                result.append(.init(
                    id: "vat",
                    severity: .warning,
                    title: "Podmiot nie figuruje w wykazie jako zarejestrowany podatnik VAT.",
                    detail: "Sprawdź, czy to oczekiwane (np. podatnik zwolniony poza wykazem lub błędny NIP)."
                ))
            case .unknown:
                result.append(.init(
                    id: "vat",
                    severity: .warning,
                    title: "Statusu VAT nie udało się jednoznacznie ustalić.",
                    detail: whiteListName
                ))
            }
        }

        // 3. Relacja uprawnień w KSeF (tylko gdy odpytano).
        if ksefChecked {
            if let ksefError {
                result.append(.init(
                    id: "ksef",
                    severity: .warning,
                    title: "Nie udało się sprawdzić uprawnień KSeF.",
                    detail: ksefError
                ))
            } else if ksefAuthorizations.isEmpty {
                result.append(.init(
                    id: "ksef",
                    severity: .info,
                    title: "Kontrahent nie nadał Twojej firmie żadnych uprawnień podmiotowych w KSeF."
                ))
            } else {
                let scopes = ksefAuthorizations.map(\.scopeLabel).joined(separator: ", ")
                result.append(.init(
                    id: "ksef",
                    severity: .ok,
                    title: "Kontrahent nadał Twojej firmie uprawnienia podmiotowe w KSeF.",
                    detail: scopes
                ))
            }
        }

        // 4. Stała, uczciwa nota o naturze KSeF.
        result.append(.init(
            id: "ksef-note",
            severity: .info,
            title: "KSeF nie ma pojęcia „aktywnego konta”.",
            detail: "System jest powszechny — faktura trafia do odbiorcy po jego NIP automatycznie. "
                + "Weryfikacja dotyczy statusu VAT i ewentualnej relacji uprawnień, nie „aktywacji konta”."
        ))

        return result
    }
}

// MARK: - Budowanie wyniku (czysta logika)

/// Czysta logika składania wyniku weryfikacji z danych z poszczególnych źródeł.
/// Bez zależności sieciowych — orkiestracja żądań jest w
/// `ContractorVerificationService`.
public enum ContractorVerification {

    /// Wynik zapytania do Wykazu podatników VAT przekazywany do budowniczego.
    public enum WhiteListOutcome: Sendable, Equatable {
        /// Podmiot znaleziony — surowy status VAT i nazwa.
        case found(statusRaw: String, name: String)
        /// Podmiot nie figuruje w wykazie (odpowiednik `.notFound`).
        case notRegistered
        /// Błąd usługi — komunikat do pokazania.
        case error(String)
    }

    /// Wynik zapytania KSeF o uprawnienia otrzymane od kontrahenta.
    public enum KSeFOutcome: Sendable, Equatable {
        /// Nie odpytano (brak poświadczeń KSeF).
        case notChecked
        /// Odpytano — lista uprawnień podmiotowych nadanych nam przez kontrahenta.
        case authorizations([ContractorKSeFAuthorization])
        /// Błąd zapytania — komunikat do pokazania.
        case error(String)
    }

    /// Składa końcowy wynik. `nip` jest normalizowany do samych cyfr.
    public static func build(
        nip rawNIP: String,
        whiteList: WhiteListOutcome,
        ksef: KSeFOutcome
    ) -> ContractorVerificationResult {
        let nip = rawNIP.filter(\.isNumber)
        let isValid = InvoiceValidator.isValidNIP(nip)

        // Przy błędnym NIP źródła i tak nie były odpytywane — wynik minimalny.
        guard isValid else {
            return ContractorVerificationResult(
                nip: nip,
                isNIPValid: false,
                vatStatus: .unknown,
                whiteListName: nil,
                whiteListError: nil,
                ksefChecked: false,
                ksefAuthorizations: [],
                ksefError: nil
            )
        }

        let vatStatus: VATRegistrationStatus
        let whiteListName: String?
        let whiteListError: String?
        switch whiteList {
        case .found(let statusRaw, let name):
            vatStatus = VATRegistrationStatus(rawStatus: statusRaw)
            whiteListName = name.isEmpty ? nil : name
            whiteListError = nil
        case .notRegistered:
            vatStatus = .notRegistered
            whiteListName = nil
            whiteListError = nil
        case .error(let message):
            vatStatus = .unknown
            whiteListName = nil
            whiteListError = message
        }

        let ksefChecked: Bool
        let ksefAuthorizations: [ContractorKSeFAuthorization]
        let ksefError: String?
        switch ksef {
        case .notChecked:
            ksefChecked = false
            ksefAuthorizations = []
            ksefError = nil
        case .authorizations(let grants):
            ksefChecked = true
            ksefAuthorizations = grants
            ksefError = nil
        case .error(let message):
            ksefChecked = true
            ksefAuthorizations = []
            ksefError = message
        }

        return ContractorVerificationResult(
            nip: nip,
            isNIPValid: true,
            vatStatus: vatStatus,
            whiteListName: whiteListName,
            whiteListError: whiteListError,
            ksefChecked: ksefChecked,
            ksefAuthorizations: ksefAuthorizations,
            ksefError: ksefError
        )
    }
}
