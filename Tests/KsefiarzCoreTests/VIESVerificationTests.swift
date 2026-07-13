import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Status VAT-UE

@Suite("VIESRegistrationStatus — etykiety")
struct VIESRegistrationStatusTests {

    @Test("Polskie etykiety statusów")
    func displayNames() {
        #expect(VIESRegistrationStatus.active.displayName == "Aktywny numer VAT-UE")
        #expect(VIESRegistrationStatus.inactive.displayName == "Numer VAT-UE nieaktywny")
        #expect(VIESRegistrationStatus.unknown.displayName == "Status VAT-UE nieustalony")
    }
}

// MARK: - Rozpoznawanie kontrahenta UE (routing)

@Suite("VIESVerification.euIdentity — routing UE vs krajowy")
struct VIESEUIdentityTests {

    @Test("Jawny prefiks UE + numer bez prefiksu")
    func explicitPrefix() {
        let id = VIESVerification.euIdentity(uePrefix: "DE", identifier: "123456789")
        #expect(id?.countryCode == "DE")
        #expect(id?.vatNumber == "123456789")
    }

    @Test("Zdublowany prefiks w identyfikatorze jest usuwany")
    func stripsDuplicatePrefix() {
        let id = VIESVerification.euIdentity(uePrefix: "DE", identifier: "DE123456789")
        #expect(id?.countryCode == "DE")
        #expect(id?.vatNumber == "123456789")
    }

    @Test("Prefiks wyłącznie w identyfikatorze (puste pole prefiksu)")
    func prefixOnlyInIdentifier() {
        let id = VIESVerification.euIdentity(uePrefix: "", identifier: "FR12345678901")
        #expect(id?.countryCode == "FR")
        #expect(id?.vatNumber == "12345678901")
    }

    @Test("Numery z literami (np. Irlandia) są zachowane")
    func keepsAlphanumericVAT() {
        let id = VIESVerification.euIdentity(uePrefix: "IE", identifier: "6388047V")
        #expect(id?.countryCode == "IE")
        #expect(id?.vatNumber == "6388047V")
    }

    @Test("Grecki prefiks GR normalizowany do EL")
    func greekPrefixNormalized() {
        #expect(VIESVerification.euIdentity(uePrefix: "GR", identifier: "123456789")?.countryCode == "EL")
        #expect(VIESVerification.euIdentity(uePrefix: "", identifier: "GR123456789")?.countryCode == "EL")
        // Numer z prefiksem GR w identyfikatorze też jest oczyszczony.
        #expect(VIESVerification.euIdentity(uePrefix: "EL", identifier: "GR123456789")?.vatNumber == "123456789")
    }

    @Test("Irlandia Północna XI jest kontrahentem UE (VIES)")
    func northernIreland() {
        #expect(VIESVerification.euIdentity(uePrefix: "XI", identifier: "123456789")?.countryCode == "XI")
    }

    @Test("Krajowy NIP (same cyfry) nie jest kontrahentem UE")
    func domesticNIPIsNotEU() {
        #expect(VIESVerification.euIdentity(uePrefix: "", identifier: "5260250274") == nil)
    }

    @Test("Prefiks PL jest traktowany jako krajowy (użyj Białej listy)")
    func polishPrefixExcluded() {
        #expect(VIESVerification.euIdentity(uePrefix: "PL", identifier: "5260250274") == nil)
        #expect(VIESVerification.euIdentity(uePrefix: "", identifier: "PL5260250274") == nil)
    }

    @Test("Nieznany kod kraju odrzucony")
    func unknownCountryRejected() {
        #expect(VIESVerification.euIdentity(uePrefix: "US", identifier: "123456789") == nil)
        #expect(VIESVerification.euIdentity(uePrefix: "DE", identifier: "DE") == nil) // brak numeru po prefiksie
    }
}

// MARK: - Budowanie werdyktu (czysta logika)

@Suite("VIESVerification.build — składanie werdyktu")
struct VIESVerificationBuildTests {

    @Test("Aktywny numer z nazwą i adresem: werdykt OK")
    func activeWithData() {
        let result = VIESVerification.build(
            countryCode: "DE",
            vatNumber: "123456789",
            outcome: .active(name: "ACME GmbH", address: "Hauptstr. 1\n10115 Berlin", consultationNumber: "", requestDate: "2026-07-13T10:00:00Z")
        )
        #expect(result.isInputValid)
        #expect(result.status == .active)
        #expect(result.fullVATNumber == "DE123456789")
        #expect(result.headline == "Aktywny podatnik VAT-UE")
        #expect(result.name == "ACME GmbH")
        let viesFinding = result.findings.first { $0.id == "vies" }
        #expect(viesFinding?.severity == .ok)
        #expect(viesFinding?.detail?.contains("ACME GmbH") == true)
        // Stała nota zawsze obecna.
        #expect(result.findings.contains { $0.id == "vies-note" })
        // Najcięższe ustalenie to nota informacyjna.
        #expect(result.overallSeverity == .info)
    }

    @Test("Aktywny numer bez danych podmiotu (kraj nie udostępnia)")
    func activeWithoutData() {
        let result = VIESVerification.build(
            countryCode: "ES",
            vatNumber: "A12345678",
            outcome: .active(name: "", address: "", consultationNumber: "", requestDate: "")
        )
        #expect(result.status == .active)
        let viesFinding = result.findings.first { $0.id == "vies" }
        #expect(viesFinding?.severity == .ok)
        #expect(viesFinding?.detail?.contains("nie udostępnia") == true)
    }

    @Test("Numer nieaktywny: ostrzeżenie o WDT")
    func inactive() {
        let result = VIESVerification.build(
            countryCode: "DE",
            vatNumber: "000000000",
            outcome: .inactive(consultationNumber: "CN-INACTIVE", requestDate: "2026-07-13T10:00:00Z")
        )
        #expect(result.status == .inactive)
        #expect(result.headline == "Numer VAT-UE nieaktywny w VIES")
        let viesFinding = result.findings.first { $0.id == "vies" }
        #expect(viesFinding?.severity == .warning)
        #expect(viesFinding?.detail?.contains("0%") == true)
        #expect(result.overallSeverity == .warning)
        #expect(result.consultationNumber == "CN-INACTIVE")
        #expect(result.findings.contains { $0.id == "consultation" })
    }

    @Test("Błąd usługi: status unknown, komunikat zapisany")
    func serviceError() {
        let result = VIESVerification.build(
            countryCode: "DE",
            vatNumber: "123456789",
            outcome: .error("Rejestr niedostępny.")
        )
        #expect(result.status == .unknown)
        #expect(result.error == "Rejestr niedostępny.")
        #expect(result.headline == "Nie udało się zweryfikować w VIES")
        let viesFinding = result.findings.first { $0.id == "vies" }
        #expect(viesFinding?.severity == .warning)
        #expect(viesFinding?.detail == "Rejestr niedostępny.")
    }

    @Test("Numer potwierdzenia zapytania jako ustalenie informacyjne")
    func consultationNumber() {
        let result = VIESVerification.build(
            countryCode: "DE",
            vatNumber: "123456789",
            outcome: .active(name: "ACME", address: "", consultationNumber: "WAPIAAAAZ9cWmQXG", requestDate: "2026-07-13T10:00:00Z")
        )
        #expect(result.consultationNumber == "WAPIAAAAZ9cWmQXG")
        let finding = result.findings.first { $0.id == "consultation" }
        #expect(finding?.severity == .info)
        #expect(finding?.title.contains("WAPIAAAAZ9cWmQXG") == true)
        #expect(finding?.detail?.contains("2026-07-13") == true)
    }

    @Test("Brak numeru potwierdzenia: bez ustalenia consultation")
    func noConsultationNumber() {
        let result = VIESVerification.build(
            countryCode: "DE",
            vatNumber: "123456789",
            outcome: .active(name: "ACME", address: "", consultationNumber: "", requestDate: "")
        )
        #expect(result.consultationNumber == nil)
        #expect(!result.findings.contains { $0.id == "consultation" })
    }

    @Test("Nieprawidłowe dane wejściowe: jedno ustalenie krytyczne, brak innych")
    func invalidInput() {
        let result = VIESVerification.build(
            countryCode: "US",
            vatNumber: "123",
            outcome: .active(name: "X", address: "Y", consultationNumber: "Z", requestDate: "D")
        )
        #expect(!result.isInputValid)
        #expect(result.overallSeverity == .critical)
        #expect(result.headline == "Nieprawidłowy numer VAT-UE")
        #expect(result.findings.count == 1)
        #expect(result.findings.first?.id == "input")
    }

    @Test("Pusty numer po prefiksie: dane wejściowe niepoprawne")
    func emptyNumber() {
        let result = VIESVerification.build(countryCode: "DE", vatNumber: "", outcome: .notChecked)
        #expect(!result.isInputValid)
    }

    @Test("Kod kraju i numer są normalizowane (GR→EL, litery/cyfry)")
    func normalizesInput() {
        let result = VIESVerification.build(
            countryCode: "gr",
            vatNumber: "12 34 56",
            outcome: .active(name: "", address: "", consultationNumber: "", requestDate: "")
        )
        #expect(result.countryCode == "EL")
        #expect(result.vatNumber == "123456")
        #expect(result.isInputValid)
    }
}

// MARK: - VIESLookupService (atrapa transportu)

@Suite("VIESLookupService — klient REST VIES")
struct VIESLookupServiceTests {

    private func makeService(transport: MockTransport) -> VIESLookupService {
        VIESLookupService(transport: transport, baseURL: URL(string: "https://vies.example")!)
    }

    @Test("Numer aktywny: mapuje isValid, nazwę, adres i normalizuje pola")
    func validNumber() async throws {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data("""
        {
          "isValid": true,
          "requestDate": "2026-07-13T10:00:00.000Z",
          "userError": "VALID",
          "name": "ACME GmbH",
          "address": "Hauptstr. 1\\n10115 Berlin",
          "requestIdentifier": "",
          "vatNumber": "123456789"
        }
        """.utf8))

        let service = makeService(transport: transport)
        let result = try await service.lookup(countryCode: "DE", vatNumber: "123456789")
        #expect(result.isValid)
        #expect(result.countryCode == "DE")
        #expect(result.name == "ACME GmbH")
        #expect(result.address == "Hauptstr. 1\n10115 Berlin")
        #expect(result.consultationNumber == "")
    }

    @Test("Numer nieaktywny (INVALID): isValid false, brak błędu")
    func invalidNumber() async throws {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/000000000", data: Data("""
        {"isValid": false, "userError": "INVALID", "name": "---", "address": "---", "requestDate": "2026-07-13T10:00:00Z"}
        """.utf8))

        let service = makeService(transport: transport)
        let result = try await service.lookup(countryCode: "DE", vatNumber: "000000000")
        #expect(!result.isValid)
        // Placeholder „---” jest normalizowany do pustego napisu.
        #expect(result.name == "")
        #expect(result.address == "")
    }

    @Test("Numer potwierdzenia z parametrami pytającego")
    func consultationNumberWithRequester() async throws {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data("""
        {"isValid": true, "userError": "VALID", "name": "ACME", "address": "", "requestIdentifier": "WAPIAAAAZ9cWmQXG", "requestDate": "2026-07-13T10:00:00Z"}
        """.utf8))

        let service = makeService(transport: transport)
        let result = try await service.lookup(countryCode: "DE", vatNumber: "123456789", requesterNIP: "526-025-02-74")
        #expect(result.consultationNumber == "WAPIAAAAZ9cWmQXG")

        // Ścieżka zawiera parametry pytającego (PL + cyfry NIP).
        let request = try #require(transport.request(matching: "/ms/DE/vat/123456789"))
        let query = request.url?.query ?? ""
        #expect(query.contains("requesterMemberStateCode=PL"))
        #expect(query.contains("requesterNumber=5260250274"))
    }

    @Test("Zapytanie anonimowe nie wysyła parametrów pytającego")
    func noRequesterParams() async throws {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data(#"{"isValid": true, "userError": "VALID"}"#.utf8))

        let service = makeService(transport: transport)
        _ = try await service.lookup(countryCode: "DE", vatNumber: "123456789")
        let request = try #require(transport.request(matching: "/ms/DE/vat/123456789"))
        #expect(request.url?.query == nil)
    }

    @Test("Niepoprawny NIP pytającego nie blokuje anonimowej weryfikacji")
    func invalidRequesterIsOmitted() async throws {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data(#"{"isValid": true, "userError": "VALID"}"#.utf8))

        let service = makeService(transport: transport)
        let result = try await service.lookup(
            countryCode: "DE",
            vatNumber: "123456789",
            requesterNIP: "123"
        )

        #expect(result.isValid)
        let request = try #require(transport.request(matching: "/ms/DE/vat/123456789"))
        #expect(request.url?.query == nil)
    }

    @Test("Odrzucone dane pytającego powodują ponowienie zapytania anonimowo")
    func rejectedRequesterFallsBackToAnonymousLookup() async throws {
        let transport = MockTransport()
        transport.route("/ms/DE/vat/123456789") { request in
            if request.url?.query != nil {
                return (200, Data(#"{"isValid": false, "userError": "INVALID_REQUESTER_INFO"}"#.utf8))
            }
            return (200, Data(#"{"isValid": true, "userError": "VALID"}"#.utf8))
        }

        let service = makeService(transport: transport)
        let result = try await service.lookup(
            countryCode: "DE",
            vatNumber: "123456789",
            requesterNIP: "5260250274"
        )

        #expect(result.isValid)
        #expect(transport.requests.count == 2)
        #expect(transport.requests.first?.url?.query != nil)
        #expect(transport.requests.last?.url?.query == nil)
    }

    @Test("Grecki kod GR trafia do ścieżki jako EL")
    func greekMappedToEL() async throws {
        let transport = MockTransport()
        transport.routeOK("/ms/EL/vat/123456789", data: Data(#"{"isValid": true, "userError": "VALID"}"#.utf8))

        let service = makeService(transport: transport)
        let result = try await service.lookup(countryCode: "GR", vatNumber: "123456789")
        #expect(result.countryCode == "EL")
        #expect(transport.request(matching: "/ms/EL/vat/") != nil)
    }

    @Test("MS_UNAVAILABLE: błąd niedostępności rejestru (nie mylony z nieaktywnym)")
    func memberStateUnavailable() async {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data(#"{"isValid": false, "userError": "MS_UNAVAILABLE"}"#.utf8))

        let service = makeService(transport: transport)
        await #expect(throws: VIESLookupService.LookupError.memberStateUnavailable) {
            _ = try await service.lookup(countryCode: "DE", vatNumber: "123456789")
        }
    }

    @Test("INVALID_INPUT z usługi: błąd danych wejściowych")
    func invalidInputFromService() async {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data(#"{"isValid": false, "userError": "INVALID_INPUT"}"#.utf8))

        let service = makeService(transport: transport)
        await #expect(throws: VIESLookupService.LookupError.invalidInput) {
            _ = try await service.lookup(countryCode: "DE", vatNumber: "123456789")
        }
    }

    @Test("Nieznany userError: ogólny błąd usługi")
    func unknownUserError() async {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data(#"{"isValid": false, "userError": "VAT_BLOCKED"}"#.utf8))

        let service = makeService(transport: transport)
        await #expect(throws: VIESLookupService.LookupError.serviceError("VAT_BLOCKED")) {
            _ = try await service.lookup(countryCode: "DE", vatNumber: "123456789")
        }
    }

    @Test("Brak userError nie jest mylony z nieaktywnym numerem")
    func missingUserError() async {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data(#"{"isValid": false}"#.utf8))

        let service = makeService(transport: transport)
        await #expect(throws: VIESLookupService.LookupError.invalidResponse) {
            _ = try await service.lookup(countryCode: "DE", vatNumber: "123456789")
        }
    }

    @Test("Brak isValid nie jest mylony z nieaktywnym numerem")
    func missingValidityFlag() async {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data(#"{"userError": "INVALID"}"#.utf8))

        let service = makeService(transport: transport)
        await #expect(throws: VIESLookupService.LookupError.invalidResponse) {
            _ = try await service.lookup(countryCode: "DE", vatNumber: "123456789")
        }
    }

    @Test("Sprzeczne isValid i userError są błędem odpowiedzi")
    func inconsistentValidity() async {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data(#"{"isValid": false, "userError": "VALID"}"#.utf8))

        let service = makeService(transport: transport)
        await #expect(throws: VIESLookupService.LookupError.invalidResponse) {
            _ = try await service.lookup(countryCode: "DE", vatNumber: "123456789")
        }
    }

    @Test("Błąd HTTP: serviceError z kodem")
    func httpError() async {
        let transport = MockTransport()
        transport.route("/ms/DE/vat/123456789") { _ in (503, Data()) }

        let service = makeService(transport: transport)
        await #expect(throws: VIESLookupService.LookupError.serviceError("HTTP 503")) {
            _ = try await service.lookup(countryCode: "DE", vatNumber: "123456789")
        }
    }

    @Test("Błędne dane wejściowe: brak żądania sieciowego")
    func invalidInputSkipsNetwork() async {
        let transport = MockTransport()
        let service = makeService(transport: transport)
        await #expect(throws: VIESLookupService.LookupError.invalidInput) {
            _ = try await service.lookup(countryCode: "D", vatNumber: "123")
        }
        await #expect(throws: VIESLookupService.LookupError.invalidInput) {
            _ = try await service.lookup(countryCode: "DE", vatNumber: "")
        }
    }
}

// MARK: - Koordynator VIESVerificationService

@Suite("VIESVerificationService — orkiestracja VIES")
struct VIESVerificationServiceTests {

    private func viesService(transport: MockTransport) -> VIESLookupService {
        VIESLookupService(transport: transport, baseURL: URL(string: "https://vies.example")!)
    }

    @Test("Numer aktywny: werdykt OK z danymi podmiotu")
    func active() async {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data("""
        {"isValid": true, "userError": "VALID", "name": "ACME GmbH", "address": "Berlin", "requestDate": "2026-07-13T10:00:00Z"}
        """.utf8))

        let service = VIESVerificationService(vies: viesService(transport: transport))
        let result = await service.verify(countryCode: "DE", vatNumber: "123456789")
        #expect(result.status == .active)
        #expect(result.name == "ACME GmbH")
        #expect(result.isInputValid)
    }

    @Test("Numer nieaktywny: status inactive")
    func inactive() async {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/000000000", data: Data(#"{"isValid": false, "userError": "INVALID", "requestIdentifier": "CN-NEGATIVE"}"#.utf8))

        let service = VIESVerificationService(vies: viesService(transport: transport))
        let result = await service.verify(countryCode: "DE", vatNumber: "000000000")
        #expect(result.status == .inactive)
        #expect(result.consultationNumber == "CN-NEGATIVE")
    }

    @Test("Błąd usługi nie rzuca — zapisany w wyniku")
    func serviceErrorIsolated() async {
        let transport = MockTransport()
        transport.route("/ms/DE/vat/123456789") { _ in (500, Data(#"{"message":"awaria"}"#.utf8)) }

        let service = VIESVerificationService(vies: viesService(transport: transport))
        let result = await service.verify(countryCode: "DE", vatNumber: "123456789")
        #expect(result.status == .unknown)
        #expect(result.error != nil)
    }

    @Test("Błędne dane wejściowe: brak żądania sieciowego")
    func invalidInputSkipsNetwork() async {
        let transport = MockTransport()
        let service = VIESVerificationService(vies: viesService(transport: transport))
        let result = await service.verify(countryCode: "US", vatNumber: "123")
        #expect(!result.isInputValid)
        #expect(transport.requests.isEmpty)
    }

    @Test("Przekazuje NIP pytającego do VIES")
    func passesRequesterNIP() async throws {
        let transport = MockTransport()
        transport.routeOK("/ms/DE/vat/123456789", data: Data("""
        {"isValid": true, "userError": "VALID", "requestIdentifier": "CN-1", "requestDate": "2026-07-13T10:00:00Z"}
        """.utf8))

        let service = VIESVerificationService(vies: viesService(transport: transport))
        let result = await service.verify(countryCode: "DE", vatNumber: "123456789", requesterNIP: "5260250274")
        #expect(result.consultationNumber == "CN-1")
        let request = try #require(transport.request(matching: "/ms/DE/vat/123456789"))
        #expect(request.url?.query?.contains("requesterNumber=5260250274") == true)
    }
}
