import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Klasyfikacja statusu VAT

@Suite("VATRegistrationStatus — klasyfikacja z wykazu")
struct VATRegistrationStatusTests {

    @Test("Rozpoznaje czynny, zwolniony i niezarejestrowany")
    func classifiesKnownStatuses() {
        #expect(VATRegistrationStatus(rawStatus: "Czynny") == .active)
        #expect(VATRegistrationStatus(rawStatus: "czynny") == .active)
        #expect(VATRegistrationStatus(rawStatus: "Zwolniony") == .exempt)
        #expect(VATRegistrationStatus(rawStatus: "Niezarejestrowany") == .notRegistered)
    }

    @Test("Pusty i nieznany status dają unknown")
    func classifiesUnknown() {
        #expect(VATRegistrationStatus(rawStatus: "") == .unknown)
        #expect(VATRegistrationStatus(rawStatus: "cokolwiek") == .unknown)
    }

    @Test("Etykiety po polsku")
    func displayNames() {
        #expect(VATRegistrationStatus.active.displayName == "Czynny podatnik VAT")
        #expect(VATRegistrationStatus.exempt.displayName == "Zwolniony z VAT")
        #expect(VATRegistrationStatus.notRegistered.displayName == "Niezarejestrowany do VAT")
        #expect(VATRegistrationStatus.unknown.displayName == "Status VAT nieustalony")
    }
}

// MARK: - Budowanie wyniku weryfikacji (czysta logika)

@Suite("ContractorVerification.build — składanie werdyktu")
struct ContractorVerificationBuildTests {

    private let validNIP = "5260250274"

    @Test("Nieprawidłowy NIP: werdykt krytyczny, jedno ustalenie, brak sprawdzeń")
    func invalidNIP() {
        let result = ContractorVerification.build(
            nip: "1234567890",
            whiteList: .found(statusRaw: "Czynny", name: "X"),
            ksef: .authorizations([])
        )
        #expect(!result.isNIPValid)
        #expect(result.overallSeverity == .critical)
        #expect(result.headline == "Nieprawidłowy NIP")
        // Tylko ustalenie o NIP — dalsze sprawdzenia pominięte niezależnie od argumentów.
        #expect(result.findings.count == 1)
        #expect(result.findings.first?.id == "nip")
        #expect(!result.ksefChecked)
    }

    @Test("NIP normalizowany do samych cyfr")
    func normalizesNIP() {
        let result = ContractorVerification.build(
            nip: "526-025-02-74",
            whiteList: .found(statusRaw: "Czynny", name: "ACME"),
            ksef: .notChecked
        )
        #expect(result.nip == "5260250274")
        #expect(result.isNIPValid)
    }

    @Test("Czynny podatnik VAT bez KSeF: werdykt OK, bez ustalenia KSeF")
    func activeNoKSeF() {
        let result = ContractorVerification.build(
            nip: validNIP,
            whiteList: .found(statusRaw: "Czynny", name: "ACME Sp. z o.o."),
            ksef: .notChecked
        )
        #expect(result.vatStatus == .active)
        #expect(result.overallSeverity == .info) // najcięższe = stała nota informacyjna
        #expect(result.headline == "Czynny podatnik VAT")
        #expect(!result.ksefChecked)
        #expect(result.findings.contains { $0.id == "vat" && $0.severity == .ok })
        #expect(!result.findings.contains { $0.id == "ksef" })
        // Stała, uczciwa nota o naturze KSeF zawsze obecna.
        #expect(result.findings.contains { $0.id == "ksef-note" })
    }

    @Test("Podmiot niezarejestrowany: ostrzeżenie")
    func notRegistered() {
        let result = ContractorVerification.build(
            nip: validNIP,
            whiteList: .notRegistered,
            ksef: .notChecked
        )
        #expect(result.vatStatus == .notRegistered)
        #expect(result.overallSeverity == .warning)
        #expect(result.headline == "Podmiot niezarejestrowany do VAT")
        #expect(result.findings.contains { $0.id == "vat" && $0.severity == .warning })
    }

    @Test("Błąd wykazu: status unknown i komunikat błędu")
    func whiteListError() {
        let result = ContractorVerification.build(
            nip: validNIP,
            whiteList: .error("Serwer zwrócił błąd."),
            ksef: .notChecked
        )
        #expect(result.vatStatus == .unknown)
        #expect(result.whiteListError == "Serwer zwrócił błąd.")
        #expect(result.overallSeverity == .warning)
        #expect(result.headline == "Nie udało się w pełni zweryfikować")
    }

    @Test("Uprawnienia KSeF nadane przez kontrahenta: ustalenie OK ze zakresami")
    func ksefAuthorizations() {
        let grants = [
            ContractorKSeFAuthorization(id: "a1", scopeRaw: "SelfInvoicing", startDate: nil),
            ContractorKSeFAuthorization(id: "a2", scopeRaw: "TaxRepresentative", startDate: nil),
        ]
        let result = ContractorVerification.build(
            nip: validNIP,
            whiteList: .found(statusRaw: "Czynny", name: "ACME"),
            ksef: .authorizations(grants)
        )
        #expect(result.ksefChecked)
        let ksefFinding = result.findings.first { $0.id == "ksef" }
        #expect(ksefFinding?.severity == .ok)
        #expect(ksefFinding?.detail == "Samofakturowanie, Przedstawiciel podatkowy")
    }

    @Test("Brak uprawnień KSeF: ustalenie informacyjne")
    func ksefNoAuthorizations() {
        let result = ContractorVerification.build(
            nip: validNIP,
            whiteList: .found(statusRaw: "Czynny", name: "ACME"),
            ksef: .authorizations([])
        )
        #expect(result.ksefChecked)
        let ksefFinding = result.findings.first { $0.id == "ksef" }
        #expect(ksefFinding?.severity == .info)
    }

    @Test("Błąd zapytania KSeF: ustalenie ostrzegawcze")
    func ksefError() {
        let result = ContractorVerification.build(
            nip: validNIP,
            whiteList: .found(statusRaw: "Czynny", name: "ACME"),
            ksef: .error("Brak autoryzacji.")
        )
        #expect(result.ksefChecked)
        let ksefFinding = result.findings.first { $0.id == "ksef" }
        #expect(ksefFinding?.severity == .warning)
        #expect(ksefFinding?.detail == "Brak autoryzacji.")
    }

    @Test("Zwolniony z VAT: werdykt informacyjny")
    func exempt() {
        let result = ContractorVerification.build(
            nip: validNIP,
            whiteList: .found(statusRaw: "Zwolniony", name: "Mały Podatnik"),
            ksef: .notChecked
        )
        #expect(result.vatStatus == .exempt)
        #expect(result.headline == "Podatnik zwolniony z VAT")
        #expect(result.findings.contains { $0.id == "vat" && $0.severity == .info })
    }

    @Test("Etykieta zakresu uprawnienia KSeF")
    func authorizationScopeLabel() {
        let grant = ContractorKSeFAuthorization(id: "x", scopeRaw: "RRInvoicing", startDate: nil)
        #expect(grant.scopeLabel == "Wystawianie faktur RR")
    }
}

// MARK: - KSeFService.receivedAuthorizations (atrapa transportu)

@Suite("KSeFService — uprawnienia otrzymane od kontrahenta (Received)")
struct ReceivedAuthorizationsTests {

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

    @Test("Zapytanie Received z filtrem po NIP nadającego; mapuje zakres i datę")
    func receivedAuthorizationsMapped() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/query/authorizations/grants", data: Data("""
        {
          "authorizationGrants": [
            {
              "id": "auth-1",
              "authorizedEntityIdentifier": {"type":"Nip","value":"5260250274"},
              "authorizingEntityIdentifier": {"type":"Nip","value":"1111111111"},
              "authorizationScope": "SelfInvoicing",
              "description": "Samofakturowanie",
              "startDate": "2026-05-01T00:00:00Z"
            }
          ],
          "hasMore": false
        }
        """.utf8))

        let service = makeService(transport: transport)
        let grants = try await service.receivedAuthorizations(fromNIP: "111-111-11-11")

        #expect(grants.count == 1)
        #expect(grants.first?.scopeRaw == "SelfInvoicing")
        #expect(grants.first?.scopeLabel == "Samofakturowanie")
        #expect(grants.first?.startDate != nil)

        // Body: queryType=Received oraz authorizingIdentifier = NIP kontrahenta.
        let request = try #require(transport.request(matching: "permissions/query/authorizations/grants"))
        struct Body: Decodable {
            struct Ident: Decodable { let type: String; let value: String }
            let queryType: String
            let authorizingIdentifier: Ident?
        }
        let body = try JSONDecoder().decode(Body.self, from: try #require(request.httpBody))
        #expect(body.queryType == "Received")
        #expect(body.authorizingIdentifier?.type == "Nip")
        #expect(body.authorizingIdentifier?.value == "1111111111")
    }

    @Test("Odfiltrowuje uprawnienia nadane przez inny podmiot niż pytany")
    func filtersForeignGranters() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/query/authorizations/grants", data: Data("""
        {
          "authorizationGrants": [
            {
              "id": "auth-1",
              "authorizedEntityIdentifier": {"type":"Nip","value":"5260250274"},
              "authorizingEntityIdentifier": {"type":"Nip","value":"1111111111"},
              "authorizationScope": "SelfInvoicing",
              "startDate": "2026-05-01T00:00:00Z"
            },
            {
              "id": "auth-2",
              "authorizedEntityIdentifier": {"type":"Nip","value":"5260250274"},
              "authorizingEntityIdentifier": {"type":"Nip","value":"9999999999"},
              "authorizationScope": "TaxRepresentative",
              "startDate": "2026-05-01T00:00:00Z"
            }
          ],
          "hasMore": false
        }
        """.utf8))

        let service = makeService(transport: transport)
        let grants = try await service.receivedAuthorizations(fromNIP: "1111111111")
        #expect(grants.map(\.id) == ["auth-1"])
    }

    @Test("Brak pola nadającego: ufamy filtrowi żądania (zachowujemy wpis)")
    func keepsGrantsWithoutGranterField() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("permissions/query/authorizations/grants", data: Data("""
        {
          "authorizationGrants": [
            {
              "id": "auth-1",
              "authorizedEntityIdentifier": {"type":"Nip","value":"5260250274"},
              "authorizationScope": "SelfInvoicing",
              "startDate": "2026-05-01T00:00:00Z"
            }
          ],
          "hasMore": false
        }
        """.utf8))

        let service = makeService(transport: transport)
        let grants = try await service.receivedAuthorizations(fromNIP: "1111111111")
        #expect(grants.count == 1)
    }
}

// MARK: - Koordynator ContractorVerificationService

@Suite("ContractorVerificationService — orkiestracja źródeł")
struct ContractorVerificationServiceTests {

    private func routeAuth(on transport: MockTransport) {
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
        transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
        transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)
    }

    private func makeKSeF(transport: MockTransport) -> KSeFService {
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

    private func whiteListService(transport: MockTransport) -> ContractorLookupService {
        ContractorLookupService(transport: transport, baseURL: URL(string: "https://wl-api.example")!)
    }

    private let activeSubject = Data("""
    {"result":{"subject":{"name":"ACME Sp. z o.o.","statusVat":"Czynny","workingAddress":"ul. Testowa 1, 00-001 Warszawa","accountNumbers":[]}}}
    """.utf8)

    @Test("Biała lista + brak poświadczeń KSeF: czynny, bez sprawdzenia KSeF")
    func whiteListOnly() async {
        let wlTransport = MockTransport()
        wlTransport.routeOK("api/search/nip", data: activeSubject)

        let service = ContractorVerificationService(
            whiteList: whiteListService(transport: wlTransport),
            ksef: nil
        )
        let result = await service.verify(nip: "5260250274")
        #expect(result.isNIPValid)
        #expect(result.vatStatus == .active)
        #expect(result.whiteListName == "ACME Sp. z o.o.")
        #expect(!result.ksefChecked)
    }

    @Test("Podmiot spoza wykazu: notRegistered")
    func notFoundBecomesNotRegistered() async {
        let wlTransport = MockTransport()
        wlTransport.routeOK("api/search/nip", data: Data(#"{"result":{"subject":null}}"#.utf8))

        let service = ContractorVerificationService(
            whiteList: whiteListService(transport: wlTransport),
            ksef: nil
        )
        let result = await service.verify(nip: "5260250274")
        #expect(result.vatStatus == .notRegistered)
    }

    @Test("Błąd usługi wykazu: zapisany komunikat, status unknown")
    func whiteListServiceError() async {
        let wlTransport = MockTransport()
        wlTransport.route("api/search/nip") { _ in (500, Data(#"{"message":"awaria"}"#.utf8)) }

        let service = ContractorVerificationService(
            whiteList: whiteListService(transport: wlTransport),
            ksef: nil
        )
        let result = await service.verify(nip: "5260250274")
        #expect(result.vatStatus == .unknown)
        #expect(result.whiteListError != nil)
    }

    @Test("Oba źródła: czynny + uprawnienie podmiotowe z KSeF")
    func bothSources() async throws {
        let wlTransport = MockTransport()
        wlTransport.routeOK("api/search/nip", data: activeSubject)

        let ksefTransport = MockTransport()
        routeAuth(on: ksefTransport)
        ksefTransport.routeOK("permissions/query/authorizations/grants", data: Data("""
        {"authorizationGrants":[{"id":"auth-1","authorizedEntityIdentifier":{"type":"Nip","value":"5260250274"},"authorizingEntityIdentifier":{"type":"Nip","value":"5260250274"},"authorizationScope":"SelfInvoicing","startDate":"2026-05-01T00:00:00Z"}],"hasMore":false}
        """.utf8))

        let service = ContractorVerificationService(
            whiteList: whiteListService(transport: wlTransport),
            ksef: makeKSeF(transport: ksefTransport)
        )
        let result = await service.verify(nip: "5260250274")
        #expect(result.vatStatus == .active)
        #expect(result.ksefChecked)
        #expect(result.ksefAuthorizations.map(\.scopeRaw) == ["SelfInvoicing"])
    }

    @Test("Błąd KSeF nie przekreśla wyniku z wykazu")
    func ksefErrorIsolated() async {
        let wlTransport = MockTransport()
        wlTransport.routeOK("api/search/nip", data: activeSubject)

        let ksefTransport = MockTransport()
        routeAuth(on: ksefTransport)
        ksefTransport.route("permissions/query/authorizations/grants") { _ in
            (403, Data(#"{"title":"Forbidden"}"#.utf8))
        }

        let service = ContractorVerificationService(
            whiteList: whiteListService(transport: wlTransport),
            ksef: makeKSeF(transport: ksefTransport)
        )
        let result = await service.verify(nip: "5260250274")
        #expect(result.vatStatus == .active)
        #expect(result.ksefChecked)
        #expect(result.ksefError != nil)
    }

    @Test("Nieprawidłowy NIP: brak jakichkolwiek żądań sieciowych")
    func invalidNIPSkipsNetwork() async {
        let wlTransport = MockTransport()
        let service = ContractorVerificationService(
            whiteList: whiteListService(transport: wlTransport),
            ksef: nil
        )
        let result = await service.verify(nip: "123")
        #expect(!result.isNIPValid)
        #expect(wlTransport.requests.isEmpty)
    }
}
