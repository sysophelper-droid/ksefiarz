import Foundation

// MARK: - Status rejestracji VAT-UE w VIES

/// Status numeru VAT-UE kontrahenta w systemie VIES (odpowiednik
/// `VATRegistrationStatus` z Wykazu podatników VAT, ale dla kontrahentów
/// unijnych).
public enum VIESRegistrationStatus: String, Sendable, Equatable {
    /// Aktywny numer VAT-UE (VIES: `isValid == true`).
    case active
    /// Numer nieaktywny albo nieznany w VIES (`isValid == false`).
    case inactive
    /// Statusu nie udało się ustalić (awaria usługi/rejestru albo błędne dane).
    case unknown

    public var displayName: String {
        switch self {
        case .active: return "Aktywny numer VAT-UE"
        case .inactive: return "Numer VAT-UE nieaktywny"
        case .unknown: return "Status VAT-UE nieustalony"
        }
    }
}

// MARK: - Wynik weryfikacji VIES

/// Złożony wynik sprawdzenia kontrahenta unijnego w VIES. Czysta struktura
/// danych — budowana przez `VIESVerification.build`, prezentowana przez
/// `VIESVerificationView`. Reużywa wag i wierszy ustaleń z karty weryfikacji
/// krajowej (`ContractorVerificationSeverity`, `ContractorVerificationResult.Finding`).
public struct VIESVerificationResult: Sendable, Equatable {

    /// Kod kraju (prefiks VAT), znormalizowany (Grecja = „EL”).
    public let countryCode: String
    /// Numer VAT bez prefiksu kraju.
    public let vatNumber: String
    /// Czy dane wejściowe są sensowne (kod kraju UE + niepusty numer).
    public let isInputValid: Bool

    /// Status ustalony z VIES.
    public let status: VIESRegistrationStatus
    /// Nazwa podmiotu z VIES (jeśli kraj udostępnia).
    public let name: String?
    /// Adres podmiotu z VIES (jeśli kraj udostępnia).
    public let address: String?
    /// Numer potwierdzenia zapytania (dowód sprawdzenia), jeśli VIES go zwrócił.
    public let consultationNumber: String?
    /// Data zapytania w VIES (napis z odpowiedzi).
    public let requestDate: String?
    /// Komunikat błędu usługi VIES, jeśli zapytanie się nie powiodło.
    public let error: String?

    public init(
        countryCode: String,
        vatNumber: String,
        isInputValid: Bool,
        status: VIESRegistrationStatus,
        name: String?,
        address: String?,
        consultationNumber: String?,
        requestDate: String?,
        error: String?
    ) {
        self.countryCode = countryCode
        self.vatNumber = vatNumber
        self.isInputValid = isInputValid
        self.status = status
        self.name = name
        self.address = address
        self.consultationNumber = consultationNumber
        self.requestDate = requestDate
        self.error = error
    }

    /// Pełny numer VAT-UE z prefiksem kraju („DE123456789”).
    public var fullVATNumber: String { countryCode + vatNumber }

    /// Ogólna waga werdyktu — najcięższe pojedyncze ustalenie.
    public var overallSeverity: ContractorVerificationSeverity {
        findings.map(\.severity).max() ?? .ok
    }

    /// Nagłówek werdyktu do wyróżnienia na karcie.
    public var headline: String {
        guard isInputValid else { return "Nieprawidłowy numer VAT-UE" }
        switch status {
        case .active: return "Aktywny podatnik VAT-UE"
        case .inactive: return "Numer VAT-UE nieaktywny w VIES"
        case .unknown: return "Nie udało się zweryfikować w VIES"
        }
    }

    /// Uporządkowana lista ustaleń: dane wejściowe → status VIES →
    /// numer potwierdzenia → stała nota.
    public var findings: [ContractorVerificationResult.Finding] {
        typealias Finding = ContractorVerificationResult.Finding
        var result: [Finding] = []

        // 1. Poprawność danych wejściowych.
        guard isInputValid else {
            result.append(.init(
                id: "input",
                severity: .critical,
                title: "Nieprawidłowe dane do sprawdzenia VAT-UE.",
                detail: "Wymagany dwuliterowy kod kraju UE (np. DE) oraz numer VAT. "
                    + "Dla kontrahentów krajowych użyj weryfikacji w Wykazie podatników VAT."
            ))
            return result
        }

        // 2. Status z VIES.
        if let error {
            result.append(.init(
                id: "vies",
                severity: .warning,
                title: "Nie udało się sprawdzić numeru \(fullVATNumber) w VIES.",
                detail: error
            ))
        } else {
            switch status {
            case .active:
                let details = [name, address]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                result.append(.init(
                    id: "vies",
                    severity: .ok,
                    title: "Aktywny numer VAT-UE \(fullVATNumber) (VIES).",
                    detail: details.isEmpty
                        ? "Kraj rejestracji nie udostępnia nazwy ani adresu podmiotu."
                        : details
                ))
            case .inactive:
                result.append(.init(
                    id: "vies",
                    severity: .warning,
                    title: "Numer VAT-UE \(fullVATNumber) jest nieaktywny w VIES.",
                    detail: "Numer nie figuruje jako aktywny do transakcji wewnątrzwspólnotowych. "
                        + "Bez aktywnego numeru nabywcy nie zastosujesz stawki 0% do WDT — zweryfikuj numer u kontrahenta."
                ))
            case .unknown:
                result.append(.init(
                    id: "vies",
                    severity: .warning,
                    title: "Statusu VAT-UE nie udało się jednoznacznie ustalić."
                ))
            }
        }

        // 3. Numer potwierdzenia zapytania (dowód należytej staranności).
        if let consultationNumber, !consultationNumber.isEmpty {
            let detail = requestDate.map { "Data zapytania: \($0)." }
            result.append(.init(
                id: "consultation",
                severity: .info,
                title: "Numer potwierdzenia VIES: \(consultationNumber).",
                detail: detail
            ))
        }

        // 4. Stała nota o znaczeniu sprawdzenia VIES.
        result.append(.init(
            id: "vies-note",
            severity: .info,
            title: "VIES potwierdza jedynie aktywność numeru VAT-UE.",
            detail: "Nie zastępuje weryfikacji tożsamości kontrahenta ani rachunku bankowego. "
                + "Do celów dowodowych zachowaj numer potwierdzenia zapytania."
        ))

        return result
    }
}

// MARK: - Budowanie wyniku (czysta logika)

/// Czysta logika składania wyniku weryfikacji VIES. Bez zależności sieciowych —
/// orkiestracja żądania jest w `VIESVerificationService`.
public enum VIESVerification {

    /// Kody krajów obsługiwane przez VIES: 27 państw UE (Grecja jako „EL”)
    /// oraz „XI” (Irlandia Północna po Brexicie). „PL” jest technicznie
    /// obsługiwane, ale dla kontrahentów krajowych używamy Wykazu podatników
    /// VAT — dlatego `euIdentity` je pomija.
    public static let viesCountryCodes: Set<String> = [
        "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "EL", "ES", "FI", "FR",
        "HR", "HU", "IE", "IT", "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO",
        "SE", "SI", "SK", "XI",
    ]

    /// Wynik zapytania VIES przekazywany do budowniczego.
    public enum Outcome: Sendable, Equatable {
        /// Aktywny numer — opcjonalna nazwa/adres, numer potwierdzenia i data.
        case active(name: String, address: String, consultationNumber: String, requestDate: String)
        /// Nieaktywny numer (`isValid == false`) z datą zapytania.
        case inactive(requestDate: String)
        /// Błąd usługi — komunikat do pokazania.
        case error(String)
        /// Nie odpytano (błędne dane wejściowe — nie było sensu wołać VIES).
        case notChecked
    }

    /// Składa końcowy wynik. Kod kraju jest normalizowany (Grecja → „EL”),
    /// numer sprowadzony do liter i cyfr. Przy błędnych danych wejściowych
    /// wynik jest minimalny (jedno ustalenie krytyczne), a `outcome` ignorowany.
    public static func build(
        countryCode rawCC: String,
        vatNumber rawNumber: String,
        outcome: Outcome
    ) -> VIESVerificationResult {
        let cc = normalizedCountry(rawCC)
        let number = rawNumber.uppercased().filter { $0.isLetter || $0.isNumber }
        let isInputValid = viesCountryCodes.contains(cc) && !number.isEmpty

        guard isInputValid else {
            return VIESVerificationResult(
                countryCode: cc,
                vatNumber: number,
                isInputValid: false,
                status: .unknown,
                name: nil,
                address: nil,
                consultationNumber: nil,
                requestDate: nil,
                error: nil
            )
        }

        switch outcome {
        case .active(let name, let address, let consultationNumber, let requestDate):
            return VIESVerificationResult(
                countryCode: cc,
                vatNumber: number,
                isInputValid: true,
                status: .active,
                name: name.isEmpty ? nil : name,
                address: address.isEmpty ? nil : address,
                consultationNumber: consultationNumber.isEmpty ? nil : consultationNumber,
                requestDate: requestDate.isEmpty ? nil : requestDate,
                error: nil
            )
        case .inactive(let requestDate):
            return VIESVerificationResult(
                countryCode: cc,
                vatNumber: number,
                isInputValid: true,
                status: .inactive,
                name: nil,
                address: nil,
                consultationNumber: nil,
                requestDate: requestDate.isEmpty ? nil : requestDate,
                error: nil
            )
        case .error(let message):
            return VIESVerificationResult(
                countryCode: cc,
                vatNumber: number,
                isInputValid: true,
                status: .unknown,
                name: nil,
                address: nil,
                consultationNumber: nil,
                requestDate: nil,
                error: message
            )
        case .notChecked:
            return VIESVerificationResult(
                countryCode: cc,
                vatNumber: number,
                isInputValid: true,
                status: .unknown,
                name: nil,
                address: nil,
                consultationNumber: nil,
                requestDate: nil,
                error: nil
            )
        }
    }

    /// Normalizuje kod kraju do postaci VIES: same litery, wielkie, Grecja „EL”.
    public static func normalizedCountry(_ raw: String) -> String {
        let cc = raw.uppercased().filter(\.isLetter)
        return cc == "GR" ? "EL" : cc
    }

    /// Rozstrzyga, czy kontrahent jest unijny (do routingu weryfikacji), i wydobywa
    /// kod kraju oraz numer VAT bez prefiksu z danych słownika kontrahenta.
    ///
    /// Źródłem kodu kraju jest w pierwszej kolejności pole `uePrefix`, a gdy jest
    /// puste — dwuliterowy prefiks wpisany w samym identyfikatorze. Zwraca `nil`
    /// dla kontrahentów krajowych (brak prefiksu albo „PL”) oraz danych bez
    /// rozpoznawalnego kodu kraju UE.
    public static func euIdentity(uePrefix: String, identifier: String) -> (countryCode: String, vatNumber: String)? {
        let idAlnum = identifier.uppercased().filter { $0.isLetter || $0.isNumber }

        // Kod kraju: jawny prefiks UE, inaczej dwie wiodące litery identyfikatora.
        var rawCountry = uePrefix.uppercased().filter(\.isLetter)
        if rawCountry.isEmpty {
            let lead = String(idAlnum.prefix(2))
            if lead.count == 2, lead.allSatisfy(\.isLetter) { rawCountry = lead }
        }
        guard rawCountry.count == 2 else { return nil }
        let country = normalizedCountry(rawCountry)
        guard viesCountryCodes.contains(country), country != "PL" else { return nil }

        // Numer bez zdublowanego prefiksu kraju wpisanego w identyfikatorze.
        var number = idAlnum
        if number.hasPrefix(rawCountry) {
            number = String(number.dropFirst(rawCountry.count))
        } else if country == "EL", number.hasPrefix("GR") {
            number = String(number.dropFirst(2))
        }
        guard !number.isEmpty else { return nil }
        return (country, number)
    }
}
