import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Logika uprawnień (czyste funkcje)

@Suite("PermissionsEngine — walidacja i etykiety")
struct PermissionsEngineTests {

    @Test("Poprawny szkic nadania podmiotowi nie ma błędów")
    func validEntityDraft() {
        let draft = PermissionGrantDraft(
            subjectKind: .entity,
            identifierValue: "526-025-02-74",
            subjectName: "Biuro Rachunkowe Kowalski",
            description: "Biuro rachunkowe",
            invoiceScopes: [.invoiceRead, .invoiceWrite]
        )
        #expect(draft.validationErrors().isEmpty)
        #expect(draft.isValid)
        #expect(draft.normalizedIdentifier == "5260250274")
    }

    @Test("Błędny NIP zwraca błąd walidacji")
    func invalidNIP() {
        let draft = PermissionGrantDraft(
            subjectKind: .entity,
            identifierValue: "1234567890",
            subjectName: "Firma",
            description: "Opis testowy"
        )
        #expect(draft.validationErrors().contains { $0.contains("NIP") })
        #expect(!draft.isValid)
    }

    @Test("Pusty i za krótki opis są odrzucane")
    func descriptionRules() {
        var draft = PermissionGrantDraft(
            subjectKind: .entity,
            identifierValue: "5260250274",
            subjectName: "Firma",
            description: ""
        )
        #expect(draft.validationErrors().contains { $0.contains("Opis") })

        draft.description = "abc"
        #expect(draft.validationErrors().contains { $0.contains("co najmniej 5") })

        draft.description = "abcde"
        #expect(!draft.validationErrors().contains { $0.contains("Opis") })
    }

    @Test("Podmiot bez wybranych zakresów jest niepoprawny")
    func entityRequiresScope() {
        let draft = PermissionGrantDraft(
            subjectKind: .entity,
            identifierValue: "5260250274",
            subjectName: "Firma",
            description: "Opis nadania",
            invoiceScopes: []
        )
        #expect(draft.validationErrors().contains { $0.contains("uprawnienie do faktur") })
    }

    @Test("Osoba wymaga imienia, nazwiska i zakresu")
    func personRequiresNameAndScope() {
        let draft = PermissionGrantDraft(
            subjectKind: .person,
            identifierType: .pesel,
            identifierValue: "44051401359",
            description: "Księgowa",
            personScopes: []
        )
        let errors = draft.validationErrors()
        #expect(errors.contains { $0.contains("imię") })
        #expect(errors.contains { $0.contains("nazwisko") })
        #expect(errors.contains { $0.contains("uprawnienie") })
    }

    @Test("Poprawna osoba po PESEL przechodzi walidację")
    func validPersonByPesel() {
        let draft = PermissionGrantDraft(
            subjectKind: .person,
            identifierType: .pesel,
            identifierValue: "44051401359",
            firstName: "Anna",
            lastName: "Nowak",
            description: "Księgowa biura",
            personScopes: [.invoiceRead]
        )
        #expect(draft.isValid)
    }

    @Test("Błędny PESEL jest odrzucany")
    func invalidPesel() {
        let draft = PermissionGrantDraft(
            subjectKind: .person,
            identifierType: .pesel,
            identifierValue: "44051401358",
            firstName: "Anna",
            lastName: "Nowak",
            description: "Księgowa biura",
            personScopes: [.invoiceRead]
        )
        #expect(draft.validationErrors().contains { $0.contains("PESEL") })
    }

    @Test("Podmiot i uprawnienie podmiotowe zawsze używają NIP")
    func effectiveIdentifierAlwaysNipForEntity() {
        var draft = PermissionGrantDraft(subjectKind: .entity, identifierType: .pesel)
        #expect(draft.effectiveIdentifierType == .nip)
        draft.subjectKind = .authorization
        #expect(draft.effectiveIdentifierType == .nip)
        draft.subjectKind = .person
        #expect(draft.effectiveIdentifierType == .pesel)
    }

    @Test("Etykiety zakresów po polsku; nieznane przechodzą bez zmian")
    func scopeLabels() {
        #expect(PermissionsEngine.scopeLabel("InvoiceWrite") == "Wystawianie faktur")
        #expect(PermissionsEngine.scopeLabel("CredentialsManage") == "Zarządzanie uprawnieniami")
        #expect(PermissionsEngine.scopeLabel("TaxRepresentative") == "Przedstawiciel podatkowy")
        #expect(PermissionsEngine.scopeLabel("Nieznane") == "Nieznane")
    }

    @Test("Etykieta podmiotu łączy nazwę z identyfikatorem")
    func subjectLabels() {
        #expect(PermissionsEngine.subjectLabel(name: "Biuro XYZ", identifierType: "Nip", identifierValue: "1111111111")
            == "Biuro XYZ (NIP 1111111111)")
        #expect(PermissionsEngine.subjectLabel(name: nil, identifierType: "Pesel", identifierValue: "44051401359")
            == "PESEL 44051401359")
        #expect(PermissionsEngine.subjectLabel(name: "  ", identifierType: "Fingerprint", identifierValue: "AB12")
            == "odcisk certyfikatu AB12")
    }

    @Test("Parsowanie daty ISO 8601 z ułamkami sekund i bez")
    func parsesDates() {
        #expect(PermissionsEngine.parseDate("2026-07-01T10:00:00.000Z") != nil)
        #expect(PermissionsEngine.parseDate("2026-06-15T08:30:00Z") != nil)
        #expect(PermissionsEngine.parseDate(nil) == nil)
        #expect(PermissionsEngine.parseDate("") == nil)
    }

    @Test("Walidacja PESEL: poprawny i błędny")
    func peselValidator() {
        #expect(InvoiceValidator.isValidPESEL("44051401359"))
        #expect(!InvoiceValidator.isValidPESEL("44051401358"))
        #expect(!InvoiceValidator.isValidPESEL("123"))
    }

    @Test("Osoba fizyczna po NIP: poprawny przechodzi, błędny odrzucany")
    func personByNip() {
        var draft = PermissionGrantDraft(
            subjectKind: .person,
            identifierType: .nip,
            identifierValue: "526-025-02-74",
            firstName: "Jan",
            lastName: "Kowalski",
            description: "Księgowy jednoosobowy",
            personScopes: [.invoiceRead]
        )
        #expect(draft.effectiveIdentifierType == .nip)
        #expect(draft.isValid)

        draft.identifierValue = "1234567890"
        #expect(draft.validationErrors().contains { $0.contains("NIP") })
    }

    @Test("Nazwa podmiotu musi mieć 5–90 znaków")
    func entityNameLengthBounds() {
        var draft = PermissionGrantDraft(
            subjectKind: .entity,
            identifierValue: "5260250274",
            subjectName: "PZU",
            description: "Opis nadania",
            invoiceScopes: [.invoiceRead]
        )
        #expect(draft.validationErrors().contains { $0.contains("co najmniej 5 znaków") })

        draft.subjectName = String(repeating: "a", count: 91)
        #expect(draft.validationErrors().contains { $0.contains("najwyżej 90 znaków") })

        draft.subjectName = "Biuro Rachunkowe"
        #expect(!draft.validationErrors().contains { $0.contains("Nazwa podmiotu") })
    }

    @Test("Imię 2–30 i nazwisko 2–81 znaków")
    func personNameLengthBounds() {
        var draft = PermissionGrantDraft(
            subjectKind: .person,
            identifierType: .pesel,
            identifierValue: "44051401359",
            firstName: "A",
            lastName: "Nowak",
            description: "Księgowa biura",
            personScopes: [.invoiceRead]
        )
        #expect(draft.validationErrors().contains { $0.contains("Imię musi mieć") })

        draft.firstName = "Anna"
        draft.lastName = String(repeating: "x", count: 82)
        #expect(draft.validationErrors().contains { $0.contains("Nazwisko musi mieć") })
    }

    @Test("Opis nadania może mieć najwyżej 256 znaków")
    func descriptionMaxLength() {
        let draft = PermissionGrantDraft(
            subjectKind: .entity,
            identifierValue: "5260250274",
            subjectName: "Biuro Rachunkowe",
            description: String(repeating: "x", count: 257),
            invoiceScopes: [.invoiceRead]
        )
        #expect(draft.validationErrors().contains { $0.contains("najwyżej 256 znaków") })
    }
}

// MARK: - Serwis uprawnień (atrapa transportu)

@Suite("KSeFService — uprawnienia (permissions API)")
struct PermissionsServiceTests {

    private func makeService(transport: MockTransport) -> KSeFService {
        let keys = TestRSAKeyPair()
        let service = KSeFService(
            environment: .test,
            nip: "5260250274",
            authToken: "tok-abc",
            transport: transport,
            publicKeyResolver: { _ in keys.publicKey }
        )
        service.pollInterval = 0
        return service
    }

    private func routeAuth(on transport: MockTransport) {
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
        transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
        transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)
    }

    private let operationOK = Data(#"{"status":{"code":200,"description":"Operacja zakończona sukcesem"}}"#.utf8)
    private let grantAccepted = Data(#"{"referenceNumber":"PERM-OP-1"}"#.utf8)

    // MARK: Nadawanie

    @Test("Nadanie podmiotowi: właściwa ścieżka, body i oczekiwanie na operację")
    func grantEntity() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/entities/grants", data: grantAccepted)
        transport.routeOK("permissions/operations/PERM-OP-1", data: operationOK)

        let service = makeService(transport: transport)
        let ref = try await service.grantEntityPermissions(
            nip: "1111111111",
            fullName: "Biuro Rachunkowe XYZ",
            scopes: [.invoiceWrite, .invoiceRead],
            canDelegate: true,
            description: "Biuro rachunkowe"
        )
        #expect(ref == "PERM-OP-1")

        let request = try #require(transport.requests.first {
            ($0.url?.path ?? "").hasSuffix("permissions/entities/grants") && $0.httpMethod == "POST"
        })
        struct Body: Decodable {
            struct Subject: Decodable { let type: String; let value: String }
            struct Perm: Decodable { let type: String; let canDelegate: Bool }
            struct Details: Decodable { let fullName: String }
            let subjectIdentifier: Subject
            let permissions: [Perm]
            let description: String
            let subjectDetails: Details
        }
        let body = try JSONDecoder().decode(Body.self, from: try #require(request.httpBody))
        #expect(body.subjectIdentifier.type == "Nip")
        #expect(body.subjectIdentifier.value == "1111111111")
        #expect(Set(body.permissions.map(\.type)) == ["InvoiceWrite", "InvoiceRead"])
        #expect(body.permissions.allSatisfy { $0.canDelegate })
        #expect(body.description == "Biuro rachunkowe")
        #expect(body.subjectDetails.fullName == "Biuro Rachunkowe XYZ")

        // Operacja jest odpytywana (potwierdzenie asynchroniczne).
        #expect(transport.request(matching: "permissions/operations/PERM-OP-1") != nil)
    }

    @Test("Nadanie osobie: raw permissions i szczegóły PersonByIdentifier")
    func grantPerson() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/persons/grants", data: grantAccepted)
        transport.routeOK("permissions/operations/PERM-OP-1", data: operationOK)

        let service = makeService(transport: transport)
        try await service.grantPersonPermissions(
            identifierType: .pesel,
            identifierValue: "44051401359",
            firstName: "Anna",
            lastName: "Nowak",
            scopes: [.invoiceRead, .credentialsRead],
            description: "Księgowa biura"
        )

        let request = try #require(transport.requests.first {
            ($0.url?.path ?? "").hasSuffix("permissions/persons/grants") && $0.httpMethod == "POST"
        })
        struct Body: Decodable {
            struct Subject: Decodable { let type: String; let value: String }
            struct Details: Decodable {
                struct Person: Decodable { let firstName: String; let lastName: String }
                let subjectDetailsType: String
                let personById: Person
            }
            let subjectIdentifier: Subject
            let permissions: [String]
            let description: String
            let subjectDetails: Details
        }
        let body = try JSONDecoder().decode(Body.self, from: try #require(request.httpBody))
        #expect(body.subjectIdentifier.type == "Pesel")
        #expect(body.subjectIdentifier.value == "44051401359")
        #expect(Set(body.permissions) == ["InvoiceRead", "CredentialsRead"])
        #expect(body.subjectDetails.subjectDetailsType == "PersonByIdentifier")
        #expect(body.subjectDetails.personById.firstName == "Anna")
        #expect(body.subjectDetails.personById.lastName == "Nowak")
    }

    @Test("Nadanie uprawnienia podmiotowego: pojedyncze uprawnienie")
    func grantAuthorization() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/authorizations/grants", data: grantAccepted)
        transport.routeOK("permissions/operations/PERM-OP-1", data: operationOK)

        let service = makeService(transport: transport)
        try await service.grantAuthorizationPermission(
            nip: "1111111111",
            fullName: "Rep Sp. z o.o.",
            scope: .taxRepresentative,
            description: "Przedstawiciel podatkowy"
        )

        let request = try #require(transport.requests.first {
            ($0.url?.path ?? "").hasSuffix("permissions/authorizations/grants") && $0.httpMethod == "POST"
        })
        struct Body: Decodable {
            struct Subject: Decodable { let type: String; let value: String }
            struct Details: Decodable { let fullName: String }
            let subjectIdentifier: Subject
            let permission: String
            let description: String
            let subjectDetails: Details
        }
        let body = try JSONDecoder().decode(Body.self, from: try #require(request.httpBody))
        #expect(body.subjectIdentifier.value == "1111111111")
        #expect(body.permission == "TaxRepresentative")
        #expect(body.subjectDetails.fullName == "Rep Sp. z o.o.")
    }

    @Test("grantPermission dobiera endpoint wg rodzaju podmiotu")
    func grantDispatchesByKind() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/entities/grants", data: grantAccepted)
        transport.routeOK("permissions/operations/PERM-OP-1", data: operationOK)

        let draft = PermissionGrantDraft(
            subjectKind: .entity,
            identifierValue: "1111111111",
            subjectName: "Biuro",
            description: "Biuro rachunkowe",
            invoiceScopes: [.invoiceRead]
        )
        let service = makeService(transport: transport)
        try await service.grantPermission(draft)
        #expect(transport.request(matching: "permissions/entities/grants") != nil)
    }

    @Test("grantPermission odrzuca niepoprawny szkic bez sieci")
    func grantRejectsInvalidDraft() async throws {
        let transport = MockTransport()
        let service = makeService(transport: transport)
        let draft = PermissionGrantDraft(subjectKind: .entity, identifierValue: "1234567890", subjectName: "", description: "")
        await #expect(throws: KSeFError.self) {
            try await service.grantPermission(draft)
        }
        #expect(transport.requests.isEmpty)
    }

    // MARK: Oczekiwanie na operację

    @Test("Operacja czeka na kod 200 (status w toku)")
    func operationPolling() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/entities/grants", data: grantAccepted)
        var calls = 0
        transport.route("permissions/operations/PERM-OP-1") { _ in
            calls += 1
            if calls < 3 {
                return (200, Data(#"{"status":{"code":100,"description":"W toku"}}"#.utf8))
            }
            return (200, Data(#"{"status":{"code":200,"description":"OK"}}"#.utf8))
        }
        let service = makeService(transport: transport)
        try await service.grantEntityPermissions(
            nip: "1111111111", fullName: "Biuro", scopes: [.invoiceRead], canDelegate: false, description: "Biuro rachunkowe"
        )
        #expect(calls == 3)
    }

    @Test("Odrzucenie operacji (kod 400+) zgłasza błąd")
    func operationFailure() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/entities/grants", data: grantAccepted)
        transport.routeOK("permissions/operations/PERM-OP-1", data: Data(
            #"{"status":{"code":400,"description":"Brak uprawnień CredentialsManage","details":["Kontekst nie ma prawa nadawania"]}}"#.utf8
        ))
        let service = makeService(transport: transport)
        await #expect(throws: KSeFError.self) {
            try await service.grantEntityPermissions(
                nip: "1111111111", fullName: "Biuro", scopes: [.invoiceRead], canDelegate: false, description: "Biuro rachunkowe"
            )
        }
    }

    // MARK: Odbieranie

    @Test("Odebranie uprawnienia: DELETE common/grants i oczekiwanie na operację")
    func revokePermission() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/common/grants/", data: grantAccepted)
        transport.routeOK("permissions/operations/PERM-OP-1", data: operationOK)

        let service = makeService(transport: transport)
        try await service.revokePermission(id: "abc-123")

        let request = try #require(transport.request(matching: "permissions/common/grants/abc-123"))
        #expect(request.httpMethod == "DELETE")
        #expect(transport.request(matching: "permissions/operations/PERM-OP-1") != nil)
    }

    @Test("Odebranie uprawnienia podmiotowego: DELETE authorizations/grants")
    func revokeAuthorization() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/authorizations/grants/", data: grantAccepted)
        transport.routeOK("permissions/operations/PERM-OP-1", data: operationOK)

        let service = makeService(transport: transport)
        try await service.revokeAuthorizationPermission(id: "xyz-999")

        let request = try #require(transport.request(matching: "permissions/authorizations/grants/xyz-999"))
        #expect(request.httpMethod == "DELETE")
    }

    // MARK: Przegląd

    @Test("Zapytanie o uprawnienia do pracy w KSeF parsuje osoby i podmioty")
    func queryGrantedPermissions() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/query/persons/grants", data: Data("""
        {
          "permissions": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "authorizedIdentifier": {"type":"Nip","value":"1111111111"},
              "permissionScope": "InvoiceWrite",
              "description": "Biuro rachunkowe",
              "subjectEntityDetails": {"subjectDetailsType":"EntityByIdentifier","fullName":"Biuro Rachunkowe XYZ"},
              "permissionState": "Active",
              "startDate": "2026-07-01T10:00:00.000Z",
              "canDelegate": true
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "authorizedIdentifier": {"type":"Pesel","value":"44051401359"},
              "permissionScope": "InvoiceRead",
              "description": "Księgowa",
              "subjectPersonDetails": {"subjectDetailsType":"PersonByIdentifier","firstName":"Anna","lastName":"Nowak"},
              "permissionState": "Inactive",
              "startDate": "2026-06-15T08:30:00Z",
              "canDelegate": false
            }
          ],
          "hasMore": false
        }
        """.utf8))

        let service = makeService(transport: transport)
        let grants = try await service.queryGrantedPermissions()
        #expect(grants.count == 2)

        let first = try #require(grants.first)
        #expect(first.id == "11111111-1111-1111-1111-111111111111")
        #expect(first.subjectName == "Biuro Rachunkowe XYZ")
        #expect(first.subjectLabel == "Biuro Rachunkowe XYZ (NIP 1111111111)")
        #expect(first.scopeLabel == "Wystawianie faktur")
        #expect(first.isActive)
        #expect(first.canDelegate)
        #expect(first.startDate != nil)

        let second = grants[1]
        #expect(second.subjectName == "Anna Nowak")
        #expect(!second.isActive)
        #expect(second.scopeLabel == "Przeglądanie faktur")
    }

    @Test("Zapytanie o uprawnienia stronicuje po hasMore")
    func queryPaginates() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        var calls = 0
        transport.route("permissions/query/persons/grants") { _ in
            calls += 1
            let hasMore = calls == 1 ? "true" : "false"
            let id = calls == 1 ? "aaaa" : "bbbb"
            return (200, Data("""
            {"permissions":[{"id":"\(id)","authorizedIdentifier":{"type":"Nip","value":"1111111111"},"permissionScope":"InvoiceRead","description":"x","permissionState":"Active","startDate":"2026-07-01T10:00:00Z","canDelegate":false}],"hasMore":\(hasMore)}
            """.utf8))
        }
        let service = makeService(transport: transport)
        let grants = try await service.queryGrantedPermissions()
        #expect(calls == 2)
        #expect(grants.count == 2)
        #expect(grants.map(\.id) == ["aaaa", "bbbb"])
    }

    @Test("Zapytanie o uprawnienia podmiotowe parsuje odpowiedź")
    func queryAuthorizations() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/query/authorizations/grants", data: Data("""
        {
          "authorizationGrants": [
            {
              "id": "33333333-3333-3333-3333-333333333333",
              "authorizedEntityIdentifier": {"type":"Nip","value":"2222222222"},
              "authorizingEntityIdentifier": {"type":"Nip","value":"5260250274"},
              "authorizationScope": "TaxRepresentative",
              "description": "Przedstawiciel",
              "subjectEntityDetails": {"subjectDetailsType":"EntityByIdentifier","fullName":"Rep Sp. z o.o."},
              "startDate": "2026-05-01T00:00:00Z"
            }
          ],
          "hasMore": false
        }
        """.utf8))

        let service = makeService(transport: transport)
        let grants = try await service.queryAuthorizationGrants()
        #expect(grants.count == 1)
        let grant = try #require(grants.first)
        #expect(grant.scopeRaw == "TaxRepresentative")
        #expect(grant.scopeLabel == "Przedstawiciel podatkowy")
        #expect(grant.subjectLabel == "Rep Sp. z o.o. (NIP 2222222222)")
    }

    @Test("Nadanie osobie po NIP wysyła typ identyfikatora Nip")
    func grantPersonByNip() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/persons/grants", data: grantAccepted)
        transport.routeOK("permissions/operations/PERM-OP-1", data: operationOK)

        let service = makeService(transport: transport)
        try await service.grantPersonPermissions(
            identifierType: .nip,
            identifierValue: "5260250274",
            firstName: "Jan",
            lastName: "Kowalski",
            scopes: [.invoiceRead],
            description: "Księgowy jednoosobowy"
        )

        let request = try #require(transport.requests.first {
            ($0.url?.path ?? "").hasSuffix("permissions/persons/grants") && $0.httpMethod == "POST"
        })
        struct Body: Decodable {
            struct Subject: Decodable { let type: String; let value: String }
            let subjectIdentifier: Subject
        }
        let body = try JSONDecoder().decode(Body.self, from: try #require(request.httpBody))
        #expect(body.subjectIdentifier.type == "Nip")
        #expect(body.subjectIdentifier.value == "5260250274")
    }

    @Test("Wyczerpanie prób oczekiwania na operację zgłasza błąd (timeout)")
    func operationTimeout() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/entities/grants", data: grantAccepted)
        var calls = 0
        transport.route("permissions/operations/PERM-OP-1") { _ in
            calls += 1
            return (200, Data(#"{"status":{"code":100,"description":"W toku"}}"#.utf8))
        }
        let service = makeService(transport: transport)
        service.maxPollAttempts = 3
        await #expect(throws: KSeFError.self) {
            try await service.grantEntityPermissions(
                nip: "1111111111", fullName: "Biuro", scopes: [.invoiceRead], canDelegate: false, description: "Biuro rachunkowe"
            )
        }
        #expect(calls == 3)
    }

    @Test("Zapytanie o uprawnienia podmiotowe stronicuje po hasMore")
    func queryAuthorizationsPaginate() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        var calls = 0
        transport.route("permissions/query/authorizations/grants") { _ in
            calls += 1
            let hasMore = calls == 1 ? "true" : "false"
            let id = calls == 1 ? "auth-1" : "auth-2"
            return (200, Data("""
            {"authorizationGrants":[{"id":"\(id)","authorizedEntityIdentifier":{"type":"Nip","value":"2222222222"},"authorizationScope":"SelfInvoicing","description":"x","startDate":"2026-05-01T00:00:00Z"}],"hasMore":\(hasMore)}
            """.utf8))
        }
        let service = makeService(transport: transport)
        let grants = try await service.queryAuthorizationGrants()
        #expect(calls == 2)
        #expect(grants.map(\.id) == ["auth-1", "auth-2"])
    }
}
