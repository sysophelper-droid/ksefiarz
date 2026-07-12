import Foundation

// MARK: - Rodzaj podmiotu i zakresy uprawnień KSeF

/// Rodzaj podmiotu, któremu nadajemy uprawnienie — decyduje o użytym
/// endpoincie API permissions.
public enum KSeFGrantSubjectKind: String, CaseIterable, Identifiable, Sendable {
    /// Podmiot (np. biuro rachunkowe) identyfikowany NIP-em —
    /// `/permissions/entities/grants`.
    case entity
    /// Osoba fizyczna (NIP/PESEL) — `/permissions/persons/grants`.
    case person
    /// Uprawnienie podmiotowe (np. przedstawiciel podatkowy, samofakturowanie) —
    /// `/permissions/authorizations/grants`.
    case authorization

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .entity: return "Podmiot (np. biuro rachunkowe)"
        case .person: return "Osoba fizyczna"
        case .authorization: return "Uprawnienie podmiotowe"
        }
    }

    public var help: String {
        switch self {
        case .entity:
            return "Nadaje innej firmie (po NIP) dostęp do wystawiania i/lub przeglądania Twoich faktur."
        case .person:
            return "Nadaje osobie fizycznej (po NIP lub PESEL) wybrane uprawnienia do pracy w KSeF."
        case .authorization:
            return "Nadaje uprawnienie podmiotowe, np. przedstawiciela podatkowego lub samofakturowanie."
        }
    }
}

/// Zakres uprawnień do obsługi faktur (nadanie podmiotowi/biuru rachunkowemu).
public enum KSeFInvoiceScope: String, CaseIterable, Identifiable, Sendable {
    case invoiceRead = "InvoiceRead"
    case invoiceWrite = "InvoiceWrite"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .invoiceRead: return "Przeglądanie faktur"
        case .invoiceWrite: return "Wystawianie faktur"
        }
    }
}

/// Pełny zestaw zakresów uprawnień osoby fizycznej do pracy w KSeF.
public enum KSeFPersonScope: String, CaseIterable, Identifiable, Sendable {
    case credentialsManage = "CredentialsManage"
    case credentialsRead = "CredentialsRead"
    case invoiceWrite = "InvoiceWrite"
    case invoiceRead = "InvoiceRead"
    case introspection = "Introspection"
    case subunitManage = "SubunitManage"
    case enforcementOperations = "EnforcementOperations"

    public var id: String { rawValue }

    public var displayName: String { PermissionsEngine.scopeLabel(rawValue) }
}

/// Uprawnienie podmiotowe (jedno na nadanie).
public enum KSeFAuthorizationScope: String, CaseIterable, Identifiable, Sendable {
    case selfInvoicing = "SelfInvoicing"
    case taxRepresentative = "TaxRepresentative"
    case rrInvoicing = "RRInvoicing"
    case pefInvoicing = "PefInvoicing"

    public var id: String { rawValue }

    public var displayName: String { PermissionsEngine.scopeLabel(rawValue) }
}

/// Typ identyfikatora podmiotu, któremu nadajemy uprawnienie.
public enum KSeFPermissionIdentifierType: String, CaseIterable, Identifiable, Sendable {
    case nip = "Nip"
    case pesel = "Pesel"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nip: return "NIP"
        case .pesel: return "PESEL"
        }
    }
}

// MARK: - Szkic nadania uprawnienia (formularz)

/// Dane z formularza nadania uprawnienia — walidowane przed wysłaniem do KSeF.
public struct PermissionGrantDraft: Sendable, Equatable {
    public var subjectKind: KSeFGrantSubjectKind
    /// Typ identyfikatora — istotny tylko dla osoby fizycznej; podmiot
    /// i uprawnienie podmiotowe zawsze używają NIP.
    public var identifierType: KSeFPermissionIdentifierType
    public var identifierValue: String
    /// Pełna nazwa podmiotu (dla `entity`/`authorization`).
    public var subjectName: String
    /// Imię i nazwisko osoby (dla `person`).
    public var firstName: String
    public var lastName: String
    /// Opis nadania (wymagany przez API — np. „Biuro rachunkowe Kowalski”).
    public var description: String
    /// Wybrane zakresy dla nadania podmiotowi.
    public var invoiceScopes: Set<KSeFInvoiceScope>
    /// Wybrane zakresy dla osoby fizycznej.
    public var personScopes: Set<KSeFPersonScope>
    /// Uprawnienie podmiotowe (dla `authorization`).
    public var authorizationScope: KSeFAuthorizationScope
    /// Możliwość dalszego delegowania (przekazywania uprawnienia).
    public var canDelegate: Bool

    public init(
        subjectKind: KSeFGrantSubjectKind = .entity,
        identifierType: KSeFPermissionIdentifierType = .nip,
        identifierValue: String = "",
        subjectName: String = "",
        firstName: String = "",
        lastName: String = "",
        description: String = "",
        invoiceScopes: Set<KSeFInvoiceScope> = [.invoiceRead, .invoiceWrite],
        personScopes: Set<KSeFPersonScope> = [.invoiceRead],
        authorizationScope: KSeFAuthorizationScope = .taxRepresentative,
        canDelegate: Bool = false
    ) {
        self.subjectKind = subjectKind
        self.identifierType = identifierType
        self.identifierValue = identifierValue
        self.subjectName = subjectName
        self.firstName = firstName
        self.lastName = lastName
        self.description = description
        self.invoiceScopes = invoiceScopes
        self.personScopes = personScopes
        self.authorizationScope = authorizationScope
        self.canDelegate = canDelegate
    }

    /// Efektywny typ identyfikatora — podmiot i uprawnienie podmiotowe zawsze
    /// używają NIP, niezależnie od wyboru w formularzu.
    public var effectiveIdentifierType: KSeFPermissionIdentifierType {
        subjectKind == .person ? identifierType : .nip
    }

    /// Identyfikator bez separatorów (spacje, myślniki).
    public var normalizedIdentifier: String {
        identifierValue
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lista błędów walidacji (pusta = szkic gotowy do wysłania).
    public func validationErrors() -> [String] {
        var errors: [String] = []
        let identifier = normalizedIdentifier

        switch effectiveIdentifierType {
        case .nip:
            if !InvoiceValidator.isValidNIP(identifier) {
                errors.append("Podaj poprawny NIP (10 cyfr, prawidłowa suma kontrolna).")
            }
        case .pesel:
            if !InvoiceValidator.isValidPESEL(identifier) {
                errors.append("Podaj poprawny PESEL (11 cyfr, prawidłowa suma kontrolna).")
            }
        }

        // Opis nadania — API wymaga 5–256 znaków (lustrzane ograniczenia,
        // by dać czytelny błąd w formularzu zamiast surowego 400 z serwera).
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDescription.isEmpty {
            errors.append("Opis nadania jest wymagany.")
        } else if trimmedDescription.count < 5 {
            errors.append("Opis nadania musi mieć co najmniej 5 znaków.")
        } else if trimmedDescription.count > 256 {
            errors.append("Opis nadania może mieć najwyżej 256 znaków.")
        }

        // Nazwa podmiotu (fullName) — API wymaga 5–90 znaków.
        func validateEntityName() {
            let name = subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                errors.append("Podaj nazwę podmiotu.")
            } else if name.count < 5 {
                errors.append("Nazwa podmiotu musi mieć co najmniej 5 znaków.")
            } else if name.count > 90 {
                errors.append("Nazwa podmiotu może mieć najwyżej 90 znaków.")
            }
        }

        switch subjectKind {
        case .entity:
            validateEntityName()
            if invoiceScopes.isEmpty {
                errors.append("Wybierz co najmniej jedno uprawnienie do faktur.")
            }
        case .person:
            // Imię 2–30, nazwisko 2–81 znaków (limity schematu PersonDetails).
            let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            if first.isEmpty {
                errors.append("Podaj imię osoby.")
            } else if first.count < 2 || first.count > 30 {
                errors.append("Imię musi mieć od 2 do 30 znaków.")
            }
            if last.isEmpty {
                errors.append("Podaj nazwisko osoby.")
            } else if last.count < 2 || last.count > 81 {
                errors.append("Nazwisko musi mieć od 2 do 81 znaków.")
            }
            if personScopes.isEmpty {
                errors.append("Wybierz co najmniej jedno uprawnienie.")
            }
        case .authorization:
            validateEntityName()
        }
        return errors
    }

    public var isValid: Bool { validationErrors().isEmpty }
}

// MARK: - Uprawnienia do prezentacji (wyniki zapytań)

/// Uprawnienie do obsługi faktur nadane osobie lub podmiotowi
/// (znormalizowany wiersz z zapytania `query/persons/grants`).
public struct KSeFPermissionGrant: Identifiable, Sendable, Equatable {
    public let id: String
    public let authorizedIdentifierType: String
    public let authorizedIdentifierValue: String
    public let scopeRaw: String
    public let description: String
    /// Nazwa podmiotu/osoby ze szczegółów, jeśli KSeF ją zwrócił.
    public let subjectName: String?
    public let isActive: Bool
    public let canDelegate: Bool
    public let startDate: Date?

    public init(
        id: String,
        authorizedIdentifierType: String,
        authorizedIdentifierValue: String,
        scopeRaw: String,
        description: String,
        subjectName: String?,
        isActive: Bool,
        canDelegate: Bool,
        startDate: Date?
    ) {
        self.id = id
        self.authorizedIdentifierType = authorizedIdentifierType
        self.authorizedIdentifierValue = authorizedIdentifierValue
        self.scopeRaw = scopeRaw
        self.description = description
        self.subjectName = subjectName
        self.isActive = isActive
        self.canDelegate = canDelegate
        self.startDate = startDate
    }

    public var scopeLabel: String { PermissionsEngine.scopeLabel(scopeRaw) }

    public var subjectLabel: String {
        PermissionsEngine.subjectLabel(
            name: subjectName,
            identifierType: authorizedIdentifierType,
            identifierValue: authorizedIdentifierValue
        )
    }
}

/// Uprawnienie podmiotowe nadane innemu podmiotowi
/// (znormalizowany wiersz z zapytania `query/authorizations/grants`).
public struct KSeFAuthorizationGrant: Identifiable, Sendable, Equatable {
    public let id: String
    public let authorizedIdentifierType: String
    public let authorizedIdentifierValue: String
    public let scopeRaw: String
    public let description: String
    public let subjectName: String?
    public let startDate: Date?

    public init(
        id: String,
        authorizedIdentifierType: String,
        authorizedIdentifierValue: String,
        scopeRaw: String,
        description: String,
        subjectName: String?,
        startDate: Date?
    ) {
        self.id = id
        self.authorizedIdentifierType = authorizedIdentifierType
        self.authorizedIdentifierValue = authorizedIdentifierValue
        self.scopeRaw = scopeRaw
        self.description = description
        self.subjectName = subjectName
        self.startDate = startDate
    }

    public var scopeLabel: String { PermissionsEngine.scopeLabel(scopeRaw) }

    public var subjectLabel: String {
        PermissionsEngine.subjectLabel(
            name: subjectName,
            identifierType: authorizedIdentifierType,
            identifierValue: authorizedIdentifierValue
        )
    }
}

// MARK: - Silnik uprawnień (czyste funkcje pomocnicze)

/// Czysta logika uprawnień KSeF: polskie etykiety zakresów, formatowanie
/// podmiotu i parsowanie dat. Bez zależności sieciowych — w pełni testowalne.
public enum PermissionsEngine {

    /// Polska etykieta zakresu uprawnienia (rozpoznaje wartości z API
    /// permissions — zakresy osób/podmiotów i uprawnienia podmiotowe).
    public static func scopeLabel(_ raw: String) -> String {
        switch raw {
        case "InvoiceRead": return "Przeglądanie faktur"
        case "InvoiceWrite": return "Wystawianie faktur"
        case "CredentialsManage": return "Zarządzanie uprawnieniami"
        case "CredentialsRead": return "Przeglądanie uprawnień"
        case "Introspection": return "Przeglądanie historii (introspekcja)"
        case "SubunitManage": return "Zarządzanie podmiotami podrzędnymi"
        case "EnforcementOperations": return "Operacje egzekucyjne"
        case "VatUeManage": return "Zarządzanie VAT UE"
        case "SelfInvoicing": return "Samofakturowanie"
        case "TaxRepresentative": return "Przedstawiciel podatkowy"
        case "RRInvoicing": return "Wystawianie faktur RR"
        case "PefInvoicing": return "Wystawianie faktur PEF"
        default: return raw
        }
    }

    /// Etykieta podmiotu: nazwa (jeśli znana) plus identyfikator z typem.
    public static func subjectLabel(name: String?, identifierType: String, identifierValue: String) -> String {
        let typeLabel: String
        switch identifierType {
        case "Nip": typeLabel = "NIP"
        case "Pesel": typeLabel = "PESEL"
        case "Fingerprint": typeLabel = "odcisk certyfikatu"
        case "PeppolId": typeLabel = "Peppol ID"
        default: typeLabel = identifierType
        }
        let identifier = "\(typeLabel) \(identifierValue)"
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(name) (\(identifier))"
        }
        return identifier
    }

    /// Parsuje datę ISO 8601 (z ułamkami sekund lub bez).
    public static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
