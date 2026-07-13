import Foundation

// MARK: - Modele API uprawnień KSeF (permissions)

/// Identyfikator podmiotu w żądaniach nadania uprawnień.
struct PermissionSubjectIdentifierDTO: Encodable {
    let type: String
    let value: String
}

/// Nazwa podmiotu w szczegółach nadania (podmiot / uprawnienie podmiotowe).
struct PermissionEntityDetailsDTO: Encodable {
    let fullName: String
}

/// Pojedyncze uprawnienie podmiotu do obsługi faktur (z flagą delegacji).
struct EntityPermissionDTO: Encodable {
    let type: String
    let canDelegate: Bool
}

struct EntityPermissionsGrantRequestDTO: Encodable {
    let subjectIdentifier: PermissionSubjectIdentifierDTO
    let permissions: [EntityPermissionDTO]
    let description: String
    let subjectDetails: PermissionEntityDetailsDTO
}

/// Szczegóły osoby fizycznej (wariant „PersonByIdentifier”).
struct PersonByIdentifierDTO: Encodable {
    let firstName: String
    let lastName: String
}

struct PersonPermissionSubjectDetailsDTO: Encodable {
    let subjectDetailsType: String
    let personById: PersonByIdentifierDTO
}

struct PersonPermissionsGrantRequestDTO: Encodable {
    let subjectIdentifier: PermissionSubjectIdentifierDTO
    let permissions: [String]
    let description: String
    let subjectDetails: PersonPermissionSubjectDetailsDTO
}

struct AuthorizationPermissionGrantRequestDTO: Encodable {
    let subjectIdentifier: PermissionSubjectIdentifierDTO
    let permission: String
    let description: String
    let subjectDetails: PermissionEntityDetailsDTO
}

/// Odpowiedź na nadanie/odebranie — numer referencyjny operacji asynchronicznej.
struct PermissionsOperationResponseDTO: Decodable {
    let referenceNumber: String
}

/// Status operacji na uprawnieniach (te same pola co inne operacje KSeF).
struct PermissionsOperationStatusDTO: Decodable {
    let status: StatusInfoDTO
}

// Zapytania o listę uprawnień.

struct PersonPermissionsQueryRequestDTO: Encodable {
    let queryType: String
}

struct AuthorizationPermissionsQueryRequestDTO: Encodable {
    let queryType: String
}

/// Zapytanie o uprawnienia podmiotowe OTRZYMANE od wskazanego podmiotu
/// (`queryType=Received`) — z filtrem po podmiocie nadającym (kontrahencie).
struct ReceivedAuthorizationsQueryRequestDTO: Encodable {
    let queryType: String
    /// Podmiot nadający uprawnienie (kontrahent, po NIP) — zawęża wynik.
    let authorizingIdentifier: PermissionSubjectIdentifierDTO?
}

/// Identyfikator w odpowiedziach zapytań (typ + wartość mogą być puste).
struct PermissionIdentifierDTO: Decodable {
    let type: String?
    let value: String?
}

struct PermissionSubjectPersonDetailsDTO: Decodable {
    let firstName: String?
    let lastName: String?
}

struct PermissionSubjectEntityDetailsDTO: Decodable {
    let fullName: String?
}

struct PersonPermissionDTO: Decodable {
    let id: String
    let authorizedIdentifier: PermissionIdentifierDTO
    let permissionScope: String
    let description: String?
    let subjectPersonDetails: PermissionSubjectPersonDetailsDTO?
    let subjectEntityDetails: PermissionSubjectEntityDetailsDTO?
    let permissionState: String
    let startDate: String?
    let canDelegate: Bool
}

struct QueryPersonPermissionsResponseDTO: Decodable {
    let permissions: [PersonPermissionDTO]
    let hasMore: Bool
}

struct EntityAuthorizationGrantDTO: Decodable {
    let id: String
    let authorizedEntityIdentifier: PermissionIdentifierDTO
    /// Podmiot nadający uprawnienie — obecny w wyniku `queryType=Received`
    /// (przy `Granted` nadającym jesteśmy my; pole opcjonalne).
    let authorizingEntityIdentifier: PermissionIdentifierDTO?
    let authorizationScope: String
    let description: String?
    let subjectEntityDetails: PermissionSubjectEntityDetailsDTO?
    let startDate: String?
}

struct QueryEntityAuthorizationPermissionsResponseDTO: Decodable {
    let authorizationGrants: [EntityAuthorizationGrantDTO]
    let hasMore: Bool
}

// MARK: - Operacje na uprawnieniach

public extension KSeFService {

    /// Nadaje uprawnienie zgodnie ze szkicem z formularza — dobiera właściwy
    /// endpoint na podstawie rodzaju podmiotu. Czeka na zakończenie operacji
    /// asynchronicznej (rzuca `permissionOperationFailed` przy odrzuceniu).
    /// Zwraca numer referencyjny operacji.
    @discardableResult
    func grantPermission(_ draft: PermissionGrantDraft) async throws -> String {
        let errors = draft.validationErrors()
        guard errors.isEmpty else {
            throw KSeFError.permissionOperationFailed(errors.joined(separator: " "))
        }
        switch draft.subjectKind {
        case .entity:
            return try await grantEntityPermissions(
                nip: draft.normalizedIdentifier,
                fullName: draft.subjectName,
                scopes: Array(draft.invoiceScopes),
                canDelegate: draft.canDelegate,
                description: draft.description
            )
        case .person:
            return try await grantPersonPermissions(
                identifierType: draft.effectiveIdentifierType,
                identifierValue: draft.normalizedIdentifier,
                firstName: draft.firstName,
                lastName: draft.lastName,
                scopes: Array(draft.personScopes),
                description: draft.description
            )
        case .authorization:
            return try await grantAuthorizationPermission(
                nip: draft.normalizedIdentifier,
                fullName: draft.subjectName,
                scope: draft.authorizationScope,
                description: draft.description
            )
        }
    }

    /// Nadaje podmiotowi (np. biuru rachunkowemu, po NIP) uprawnienia
    /// do obsługi faktur — `/permissions/entities/grants`.
    @discardableResult
    func grantEntityPermissions(
        nip: String,
        fullName: String,
        scopes: [KSeFInvoiceScope],
        canDelegate: Bool,
        description: String
    ) async throws -> String {
        try await ensureAuthenticated()
        let request = EntityPermissionsGrantRequestDTO(
            subjectIdentifier: .init(type: "Nip", value: nip),
            permissions: scopes.map { EntityPermissionDTO(type: $0.rawValue, canDelegate: canDelegate) },
            description: description,
            subjectDetails: .init(fullName: fullName)
        )
        return try await submitGrant(path: "permissions/entities/grants", body: request)
    }

    /// Nadaje osobie fizycznej (po NIP lub PESEL) uprawnienia do pracy w KSeF —
    /// `/permissions/persons/grants`.
    @discardableResult
    func grantPersonPermissions(
        identifierType: KSeFPermissionIdentifierType,
        identifierValue: String,
        firstName: String,
        lastName: String,
        scopes: [KSeFPersonScope],
        description: String
    ) async throws -> String {
        try await ensureAuthenticated()
        let request = PersonPermissionsGrantRequestDTO(
            subjectIdentifier: .init(type: identifierType.rawValue, value: identifierValue),
            permissions: scopes.map(\.rawValue),
            description: description,
            subjectDetails: .init(
                subjectDetailsType: "PersonByIdentifier",
                personById: .init(firstName: firstName, lastName: lastName)
            )
        )
        return try await submitGrant(path: "permissions/persons/grants", body: request)
    }

    /// Nadaje uprawnienie podmiotowe (np. przedstawiciel podatkowy) innemu
    /// podmiotowi po NIP — `/permissions/authorizations/grants`.
    @discardableResult
    func grantAuthorizationPermission(
        nip: String,
        fullName: String,
        scope: KSeFAuthorizationScope,
        description: String
    ) async throws -> String {
        try await ensureAuthenticated()
        let request = AuthorizationPermissionGrantRequestDTO(
            subjectIdentifier: .init(type: "Nip", value: nip),
            permission: scope.rawValue,
            description: description,
            subjectDetails: .init(fullName: fullName)
        )
        return try await submitGrant(path: "permissions/authorizations/grants", body: request)
    }

    /// Odbiera uprawnienie do pracy w KSeF (nadane osobie lub podmiotowi) —
    /// `DELETE /permissions/common/grants/{permissionId}`.
    @discardableResult
    func revokePermission(id: String) async throws -> String {
        try await ensureAuthenticated()
        return try await submitRevoke(path: "permissions/common/grants/\(id)")
    }

    /// Odbiera uprawnienie podmiotowe —
    /// `DELETE /permissions/authorizations/grants/{permissionId}`.
    @discardableResult
    func revokeAuthorizationPermission(id: String) async throws -> String {
        try await ensureAuthenticated()
        return try await submitRevoke(path: "permissions/authorizations/grants/\(id)")
    }

    /// Pobiera uprawnienia do pracy w KSeF nadane w bieżącym kontekście
    /// (osobom fizycznym i podmiotom) — `/permissions/query/persons/grants`.
    func queryGrantedPermissions() async throws -> [KSeFPermissionGrant] {
        try await ensureAuthenticated()
        let request = PersonPermissionsQueryRequestDTO(queryType: "PermissionsGrantedInCurrentContext")
        var result: [KSeFPermissionGrant] = []
        var pageOffset = 0
        // Pętla kończy się na hasMore == false; wysoki limit to tylko
        // bezpiecznik przed nieskończonym stronicowaniem (100 × 100 = 10 000).
        while pageOffset < 100 {
            let data = try await perform(
                path: "permissions/query/persons/grants?pageOffset=\(pageOffset)&pageSize=100",
                method: "POST",
                body: try JSONEncoder().encode(request),
                bearer: try requireAccessToken()
            )
            let page: QueryPersonPermissionsResponseDTO = try decode(data)
            result.append(contentsOf: page.permissions.map(Self.grant(from:)))
            guard page.hasMore else { break }
            pageOffset += 1
        }
        return result
    }

    /// Pobiera uprawnienia podmiotowe nadane innym podmiotom —
    /// `/permissions/query/authorizations/grants` (queryType `Granted`).
    func queryAuthorizationGrants() async throws -> [KSeFAuthorizationGrant] {
        try await ensureAuthenticated()
        let request = AuthorizationPermissionsQueryRequestDTO(queryType: "Granted")
        var result: [KSeFAuthorizationGrant] = []
        var pageOffset = 0
        // Bezpiecznik jak wyżej — realnie kończy hasMore == false.
        while pageOffset < 100 {
            let data = try await perform(
                path: "permissions/query/authorizations/grants?pageOffset=\(pageOffset)&pageSize=100",
                method: "POST",
                body: try JSONEncoder().encode(request),
                bearer: try requireAccessToken()
            )
            let page: QueryEntityAuthorizationPermissionsResponseDTO = try decode(data)
            result.append(contentsOf: page.authorizationGrants.map(Self.grant(from:)))
            guard page.hasMore else { break }
            pageOffset += 1
        }
        return result
    }

    /// Sprawdza, jakie uprawnienia podmiotowe NADAŁ NAM wskazany kontrahent
    /// (po NIP) — `/permissions/query/authorizations/grants` z
    /// `queryType=Received`. To jedyna KSeF-natywna „weryfikacja relacji”
    /// z kontrahentem: KSeF nie zna pojęcia „aktywnego konta”, a każdy NIP
    /// odbiera faktury automatycznie. Wynik filtrujemy dodatkowo po stronie
    /// klienta na wypadek, gdyby serwer zignorował filtr nadającego.
    func receivedAuthorizations(fromNIP nip: String) async throws -> [ContractorKSeFAuthorization] {
        try await ensureAuthenticated()
        let normalizedNIP = nip.filter(\.isNumber)
        let request = ReceivedAuthorizationsQueryRequestDTO(
            queryType: "Received",
            authorizingIdentifier: .init(type: "Nip", value: normalizedNIP)
        )
        var result: [ContractorKSeFAuthorization] = []
        var pageOffset = 0
        // Bezpiecznik jak w pozostałych zapytaniach — realnie kończy hasMore.
        while pageOffset < 100 {
            let data = try await perform(
                path: "permissions/query/authorizations/grants?pageOffset=\(pageOffset)&pageSize=100",
                method: "POST",
                body: try JSONEncoder().encode(request),
                bearer: try requireAccessToken()
            )
            let page: QueryEntityAuthorizationPermissionsResponseDTO = try decode(data)
            for grant in page.authorizationGrants {
                // Zawężamy do uprawnień nadanych właśnie przez tego kontrahenta.
                // OpenAPI wymaga identyfikatora nadającego w odpowiedzi. Wpis
                // bez niego albo z innym typem pomijamy, żeby niespójna
                // odpowiedź nie dała fałszywego potwierdzenia relacji.
                guard let granter = grant.authorizingEntityIdentifier,
                      granter.type?.caseInsensitiveCompare("Nip") == .orderedSame,
                      let granterNIP = granter.value,
                      granterNIP.filter(\.isNumber) == normalizedNIP else {
                    continue
                }
                result.append(ContractorKSeFAuthorization(
                    id: grant.id,
                    scopeRaw: grant.authorizationScope,
                    startDate: PermissionsEngine.parseDate(grant.startDate)
                ))
            }
            guard page.hasMore else { break }
            pageOffset += 1
        }
        return result
    }

    // MARK: Pomocnicze

    /// Wysyła żądanie nadania i czeka na zakończenie operacji asynchronicznej.
    private func submitGrant<T: Encodable>(path: String, body: T) async throws -> String {
        let data = try await perform(
            path: path,
            method: "POST",
            body: try JSONEncoder().encode(body),
            bearer: try requireAccessToken()
        )
        let response: PermissionsOperationResponseDTO = try decode(data)
        try await waitForPermissionOperation(referenceNumber: response.referenceNumber)
        return response.referenceNumber
    }

    /// Wysyła żądanie odebrania (DELETE) i czeka na zakończenie operacji.
    private func submitRevoke(path: String) async throws -> String {
        let data = try await perform(
            path: path,
            method: "DELETE",
            body: nil,
            bearer: try requireAccessToken()
        )
        let response: PermissionsOperationResponseDTO = try decode(data)
        try await waitForPermissionOperation(referenceNumber: response.referenceNumber)
        return response.referenceNumber
    }

    /// Odpytuje o status operacji na uprawnieniach do skutku (kod 200) lub błędu.
    private func waitForPermissionOperation(referenceNumber: String) async throws {
        for attempt in 0..<maxPollAttempts {
            let data = try await perform(
                path: "permissions/operations/\(referenceNumber)",
                method: "GET",
                body: nil,
                bearer: try requireAccessToken()
            )
            let response: PermissionsOperationStatusDTO = try decode(data)
            switch response.status.code {
            case 200:
                return
            case 400...:
                let details = ([response.status.description] + (response.status.details ?? []))
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                throw KSeFError.permissionOperationFailed(details)
            default:
                if attempt < maxPollAttempts - 1, pollInterval > 0 {
                    try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                }
            }
        }
        throw KSeFError.permissionOperationFailed(
            "Przekroczono czas oczekiwania na potwierdzenie operacji."
        )
    }

    /// Mapuje uprawnienie do pracy w KSeF na strukturę prezentacji.
    private static func grant(from dto: PersonPermissionDTO) -> KSeFPermissionGrant {
        let personName = [dto.subjectPersonDetails?.firstName, dto.subjectPersonDetails?.lastName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let name = !personName.isEmpty ? personName : dto.subjectEntityDetails?.fullName
        return KSeFPermissionGrant(
            id: dto.id,
            authorizedIdentifierType: dto.authorizedIdentifier.type ?? "",
            authorizedIdentifierValue: dto.authorizedIdentifier.value ?? "",
            scopeRaw: dto.permissionScope,
            description: dto.description ?? "",
            subjectName: name?.isEmpty == false ? name : nil,
            isActive: dto.permissionState == "Active",
            canDelegate: dto.canDelegate,
            startDate: PermissionsEngine.parseDate(dto.startDate)
        )
    }

    /// Mapuje uprawnienie podmiotowe na strukturę prezentacji.
    private static func grant(from dto: EntityAuthorizationGrantDTO) -> KSeFAuthorizationGrant {
        KSeFAuthorizationGrant(
            id: dto.id,
            authorizedIdentifierType: dto.authorizedEntityIdentifier.type ?? "",
            authorizedIdentifierValue: dto.authorizedEntityIdentifier.value ?? "",
            scopeRaw: dto.authorizationScope,
            description: dto.description ?? "",
            subjectName: dto.subjectEntityDetails?.fullName,
            startDate: PermissionsEngine.parseDate(dto.startDate)
        )
    }
}
