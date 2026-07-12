import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Etykiety i właściwości prezentacyjne enumów uprawnień
//
// Domyka pokrycie właściwości `id` / `displayName` / `help` wszystkich enumów
// uprawnień (czysta logika prezentacji) oraz gałęzi walidacji uprawnienia
// podmiotowego (`.authorization`). Wszystkie testy są w pełni offline.

@Suite("PermissionsEngine — etykiety enumów i walidacja uprawnienia podmiotowego")
struct PermissionsEnumLabelsTests {

    @Test("KSeFGrantSubjectKind: id, displayName i help mają sensowne wartości dla wszystkich przypadków")
    func grantSubjectKindLabels() {
        // Iteracja po allCases pokrywa wszystkie gałęzie switchy.
        for kind in KSeFGrantSubjectKind.allCases {
            #expect(kind.id == kind.rawValue)
            #expect(!kind.displayName.isEmpty)
            #expect(!kind.help.isEmpty)
        }
        // Punktowe utrwalenie treści polskich etykiet.
        #expect(KSeFGrantSubjectKind.entity.displayName == "Podmiot (np. biuro rachunkowe)")
        #expect(KSeFGrantSubjectKind.person.displayName == "Osoba fizyczna")
        #expect(KSeFGrantSubjectKind.authorization.displayName == "Uprawnienie podmiotowe")
        #expect(KSeFGrantSubjectKind.entity.help.contains("NIP"))
        #expect(KSeFGrantSubjectKind.person.help.contains("osobie fizycznej"))
        #expect(KSeFGrantSubjectKind.authorization.help.contains("przedstawiciela podatkowego"))
    }

    @Test("KSeFInvoiceScope: id i displayName po polsku dla wszystkich zakresów")
    func invoiceScopeLabels() {
        for scope in KSeFInvoiceScope.allCases {
            #expect(scope.id == scope.rawValue)
            #expect(!scope.displayName.isEmpty)
        }
        #expect(KSeFInvoiceScope.invoiceRead.displayName == "Przeglądanie faktur")
        #expect(KSeFInvoiceScope.invoiceWrite.displayName == "Wystawianie faktur")
    }

    @Test("KSeFPersonScope: id i displayName (delegowane do scopeLabel) dla wszystkich zakresów")
    func personScopeLabels() {
        for scope in KSeFPersonScope.allCases {
            #expect(scope.id == scope.rawValue)
            #expect(!scope.displayName.isEmpty)
            // displayName == PermissionsEngine.scopeLabel(rawValue).
            #expect(scope.displayName == PermissionsEngine.scopeLabel(scope.rawValue))
        }
        #expect(KSeFPersonScope.credentialsManage.displayName == "Zarządzanie uprawnieniami")
        #expect(KSeFPersonScope.enforcementOperations.displayName == "Operacje egzekucyjne")
    }

    @Test("KSeFAuthorizationScope: id i displayName (delegowane do scopeLabel) dla wszystkich zakresów")
    func authorizationScopeLabels() {
        for scope in KSeFAuthorizationScope.allCases {
            #expect(scope.id == scope.rawValue)
            #expect(!scope.displayName.isEmpty)
            #expect(scope.displayName == PermissionsEngine.scopeLabel(scope.rawValue))
        }
        #expect(KSeFAuthorizationScope.selfInvoicing.displayName == "Samofakturowanie")
        #expect(KSeFAuthorizationScope.taxRepresentative.displayName == "Przedstawiciel podatkowy")
        #expect(KSeFAuthorizationScope.rrInvoicing.displayName == "Wystawianie faktur RR")
        #expect(KSeFAuthorizationScope.pefInvoicing.displayName == "Wystawianie faktur PEF")
    }

    @Test("KSeFPermissionIdentifierType: id i displayName dla NIP i PESEL")
    func identifierTypeLabels() {
        for type in KSeFPermissionIdentifierType.allCases {
            #expect(type.id == type.rawValue)
            #expect(!type.displayName.isEmpty)
        }
        #expect(KSeFPermissionIdentifierType.nip.displayName == "NIP")
        #expect(KSeFPermissionIdentifierType.pesel.displayName == "PESEL")
    }

    @Test("scopeLabel i subjectLabel pokrywają pozostałe warianty (VatUeManage, PeppolId, nieznany typ)")
    func remainingLabelBranches() {
        // Zakres spoza enumów formularza, ale rozpoznawany przez API.
        #expect(PermissionsEngine.scopeLabel("VatUeManage") == "Zarządzanie VAT UE")
        // Typ identyfikatora Peppol oraz gałąź domyślna (nieznany typ przechodzi wprost).
        #expect(PermissionsEngine.subjectLabel(name: nil, identifierType: "PeppolId", identifierValue: "PL1234567890")
            == "Peppol ID PL1234567890")
        #expect(PermissionsEngine.subjectLabel(name: nil, identifierType: "NieznanyTyp", identifierValue: "X")
            == "NieznanyTyp X")
    }

    @Test("Uprawnienie podmiotowe waliduje nazwę podmiotu (gałąź .authorization)")
    func authorizationDraftValidatesEntityName() {
        // Pusta nazwa podmiotu → błąd „Podaj nazwę podmiotu.” (validateEntityName).
        var draft = PermissionGrantDraft(
            subjectKind: .authorization,
            identifierValue: "5260250274",
            subjectName: "",
            description: "Przedstawiciel podatkowy",
            authorizationScope: .taxRepresentative
        )
        #expect(draft.validationErrors().contains { $0.contains("Podaj nazwę podmiotu") })

        // Za krótka nazwa (< 5 znaków) → błąd długości.
        draft.subjectName = "ABC"
        #expect(draft.validationErrors().contains { $0.contains("co najmniej 5 znaków") })

        // Poprawna nazwa → brak błędów, szkic gotowy do wysłania.
        draft.subjectName = "Rep Sp. z o.o."
        #expect(draft.validationErrors().isEmpty)
        #expect(draft.isValid)
    }
}

// MARK: - Serwis uprawnień: ścieżki dyspozytora i odpytywanie z odstępem

@Suite("KSeFService — dyspozytor grantPermission i odpytywanie operacji")
struct PermissionsServiceEdgeCasesTests {

    private func makeService_perms(transport: MockTransport) -> KSeFService {
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

    private func routeAuth_perms(on transport: MockTransport) {
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
        transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
        transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)
    }

    private let operationOK_perms = Data(#"{"status":{"code":200,"description":"OK"}}"#.utf8)
    private let grantAccepted_perms = Data(#"{"referenceNumber":"PERM-OP-1"}"#.utf8)

    @Test("grantPermission dla osoby fizycznej kieruje na endpoint persons/grants")
    func grantDispatchesToPerson() async throws {
        let transport = MockTransport()
        routeAuth_perms(on: transport)
        transport.routeOK("permissions/persons/grants", data: grantAccepted_perms)
        transport.routeOK("permissions/operations/PERM-OP-1", data: operationOK_perms)

        let draft = PermissionGrantDraft(
            subjectKind: .person,
            identifierType: .pesel,
            identifierValue: "44051401359",
            firstName: "Anna",
            lastName: "Nowak",
            description: "Księgowa biura",
            personScopes: [.invoiceRead]
        )
        let service = makeService_perms(transport: transport)
        let ref = try await service.grantPermission(draft)
        #expect(ref == "PERM-OP-1")
        #expect(transport.request(matching: "permissions/persons/grants") != nil)
    }

    @Test("grantPermission dla uprawnienia podmiotowego kieruje na endpoint authorizations/grants")
    func grantDispatchesToAuthorization() async throws {
        let transport = MockTransport()
        routeAuth_perms(on: transport)
        transport.routeOK("permissions/authorizations/grants", data: grantAccepted_perms)
        transport.routeOK("permissions/operations/PERM-OP-1", data: operationOK_perms)

        let draft = PermissionGrantDraft(
            subjectKind: .authorization,
            identifierValue: "1111111111",
            subjectName: "Rep Sp. z o.o.",
            description: "Przedstawiciel podatkowy",
            authorizationScope: .taxRepresentative
        )
        let service = makeService_perms(transport: transport)
        let ref = try await service.grantPermission(draft)
        #expect(ref == "PERM-OP-1")
        #expect(transport.request(matching: "permissions/authorizations/grants") != nil)
    }

    @Test("Odpytywanie operacji z dodatnim odstępem odczekuje między próbami (status w toku)")
    func operationPollingWithInterval() async throws {
        let transport = MockTransport()
        routeAuth_perms(on: transport)
        transport.routeOK("permissions/entities/grants", data: grantAccepted_perms)
        var calls = 0
        transport.route("permissions/operations/PERM-OP-1") { _ in
            calls += 1
            // Pierwsze wywołanie: status „w toku” (kod 100) → wymusza odczekanie
            // (gałąź default z pollInterval > 0). Drugie: sukces (kod 200).
            if calls < 2 {
                return (200, Data(#"{"status":{"code":100,"description":"W toku"}}"#.utf8))
            }
            return (200, Data(#"{"status":{"code":200,"description":"OK"}}"#.utf8))
        }
        let service = makeService_perms(transport: transport)
        // Dodatni, ale minimalny odstęp — aktywuje Task.sleep bez spowalniania testu.
        service.pollInterval = 0.001
        service.maxPollAttempts = 3
        try await service.grantEntityPermissions(
            nip: "1111111111",
            fullName: "Biuro Rachunkowe",
            scopes: [.invoiceRead],
            canDelegate: false,
            description: "Biuro rachunkowe"
        )
        #expect(calls == 2)
    }

    @Test("Odrzucenie operacji bez listy szczegółów używa samego opisu (details == nil)")
    func operationFailureWithoutDetails() async throws {
        let transport = MockTransport()
        routeAuth_perms(on: transport)
        transport.routeOK("permissions/entities/grants", data: grantAccepted_perms)
        // Status 400 bez pola `details` → gałąź `details ?? []` (pusty domyślny).
        transport.routeOK("permissions/operations/PERM-OP-1", data: Data(
            #"{"status":{"code":400,"description":"Odmowa nadania"}}"#.utf8
        ))
        let service = makeService_perms(transport: transport)
        await #expect(throws: KSeFError.self) {
            try await service.grantEntityPermissions(
                nip: "1111111111",
                fullName: "Biuro",
                scopes: [.invoiceRead],
                canDelegate: false,
                description: "Biuro rachunkowe"
            )
        }
    }

    @Test("Uprawnienie osoby z pustymi polami identyfikatora i opisu (domyślne wartości)")
    func personGrantWithNullFields() async throws {
        let transport = MockTransport()
        routeAuth_perms(on: transport)
        // Brak type/value w identyfikatorze, brak description i szczegółów podmiotu
        // → gałęzie `?? ""` oraz brak nazwy (subjectName == nil).
        transport.routeOK("permissions/query/persons/grants", data: Data("""
        {
          "permissions": [
            {
              "id": "nn-1",
              "authorizedIdentifier": {},
              "permissionScope": "InvoiceRead",
              "permissionState": "Active",
              "canDelegate": false
            }
          ],
          "hasMore": false
        }
        """.utf8))
        let service = makeService_perms(transport: transport)
        let grants = try await service.queryGrantedPermissions()
        let grant = try #require(grants.first)
        #expect(grant.authorizedIdentifierType == "")
        #expect(grant.authorizedIdentifierValue == "")
        #expect(grant.description == "")
        #expect(grant.subjectName == nil)
        #expect(grant.startDate == nil)
    }

    @Test("Uprawnienie podmiotowe z pustymi polami identyfikatora i opisu (domyślne wartości)")
    func authorizationGrantWithNullFields() async throws {
        let transport = MockTransport()
        routeAuth_perms(on: transport)
        transport.routeOK("permissions/query/authorizations/grants", data: Data("""
        {
          "authorizationGrants": [
            {
              "id": "aa-1",
              "authorizedEntityIdentifier": {},
              "authorizationScope": "SelfInvoicing"
            }
          ],
          "hasMore": false
        }
        """.utf8))
        let service = makeService_perms(transport: transport)
        let grants = try await service.queryAuthorizationGrants()
        let grant = try #require(grants.first)
        #expect(grant.authorizedIdentifierType == "")
        #expect(grant.authorizedIdentifierValue == "")
        #expect(grant.description == "")
        #expect(grant.subjectName == nil)
        #expect(grant.startDate == nil)
    }
}
