import Foundation
import Security
import Testing
@testable import KsefiarzCore

// MARK: - Pomocnicze (dedykowane temu plikowi, sufiks _ksef by uniknąć kolizji)

/// Magazyn sekretów w pamięci — atrapa pęku kluczy dla testów magazynu
/// certyfikatów. Nie dotyka realnego pęku kluczy użytkownika.
private final class InMemorySecretStorage_ksef: SecretStorage {
    var values: [String: String] = [:]
    func read(account: String) -> String? { values[account] }
    func save(_ value: String, account: String) { values[account] = value }
    func delete(account: String) { values[account] = nil }
}

/// Buduje usługę z zerowym odstępem odpytywania i testowym kluczem publicznym
/// (podmieniony resolver — bez zależności od prawdziwych certyfikatów MF).
private func makeService_ksef(
    transport: MockTransport,
    keys: TestRSAKeyPair = TestRSAKeyPair(),
    nip: String = "1111111111",
    token: String = "tok-abc"
) -> KSeFService {
    let service = KSeFService(
        environment: .test,
        nip: nip,
        authToken: token,
        transport: transport,
        publicKeyResolver: { _ in keys.publicKey }
    )
    service.pollInterval = 0
    return service
}

/// Rejestruje komplet tras potrzebnych do pomyślnego uwierzytelnienia tokenem.
private func routeAuthSuccess_ksef(on transport: MockTransport) {
    transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
    transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
    transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
    transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
    transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)
}

/// Poprawny szkic faktury (przechodzi walidację przed wysyłką).
private func makeValidDraft_ksef() -> InvoiceDraft {
    InvoiceDraft(
        invoiceNumber: "FV/2026/07/777",
        issueDate: FA2Format.dateFormatter.date(from: "2026-07-01")!,
        sellerName: "ACME Sp. z o.o.",
        sellerNIP: "5260250274",
        sellerAddress: "ul. Przykładowa 1, 00-001 Warszawa",
        buyerName: "Kontrahent S.A.",
        buyerNIP: "1111111111",
        netAmount: 100.0,
        vatAmount: 23.0
    )
}

/// Certyfikat self-signed (RSA-2048) do magazynu certyfikatów.
private func makeStoreCertificate_ksef(nip: String = "5265877635") throws -> KSeFCertificate {
    let key = try X509Builder.generateRSAKeyPair()
    let der = try X509Builder.makeSelfSignedCertificate(
        subject: [.commonName("Ksefiarz Test"), .countryName("PL"), .organizationIdentifier("VATPL-\(nip)")],
        privateKey: key
    )
    return KSeFCertificate(certificateDER: der, privateKeyDER: try X509Builder.exportPrivateKey(key))
}

/// Certyfikat „wystawiony przez KSeF" (self-signed) do odpowiedzi retrieve.
private func makeIssuedCertificateDER_ksef() throws -> Data {
    let key = try X509Builder.generateRSAKeyPair()
    return try X509Builder.makeSelfSignedCertificate(
        subject: [.commonName("Firma Kowalski Certyfikat"), .countryName("PL")],
        privateKey: key,
        validTo: .now.addingTimeInterval(2 * 365 * 86_400)
    )
}

/// Klucz prywatny RSA-512 (PKCS#1 DER, base64) — celowo za słaby na RSASSA-PSS
/// SHA-256 (moduł 64 B < 66 B). Importuje się poprawnie, ale podpis PSS zawodzi,
/// co pozwala pokryć gałąź błędu podpisu KODU II. Klucz jednorazowy, nie sekret.
private let weakRSA512PrivateKeyDER = Data(base64Encoded:
    "MIIBPQIBAAJBAL7p/ftXwMP4tYWYR1mI7QEyA+mTbuOG4tpKpPRr6T5qeRb6eIdrTWSRgP5HVNQkXDNe" +
    "DH3991ap9NzK74X7GOsCAwEAAQJBAKILpMvROUpd8V162pzxrxHDrTR2MronRKg6kXbxnWGesHuqtbkb" +
    "dy+XqS2goFEcGyM0BBd8bxUfOnH2cugUn6ECIQDn/mT5uCl/E61PPfOVwdMG1RG6LN1t8e6tsIIw7O7N" +
    "MQIhANKrYVoary6n2418453ttyTpX1FNWKuWyEkWKZWdJpDbAiEAqnhvgGQH8f3mguz1+ZxUUZftj815" +
    "5Fk7Vlv2PrdLfnECIQCKi6LuevYSnNnK5wNabWcwoznIYjGaRwNY7XZTqpIeWQIhANLAQGqaNSgBq5el" +
    "DOq+EMOa24sTQujPKrdBY6AfpWLy"
)!

/// Atrapa `URLProtocol` — pozwala pokryć rozszerzenie `URLSession: HTTPTransport`
/// bez realnego ruchu sieciowego (żądania są przechwytywane lokalnie).
final class StubHTTPURLProtocol_ksef: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.status,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Środowiska KSeF

@Suite("KSeFEnvironment — identyfikatory i nazwy prezentacyjne")
struct KSeFEnvironmentEdgeTests {

    @Test("id równa się rawValue dla każdego środowiska")
    func identifiers() {
        #expect(KSeFEnvironment.test.id == "test")
        #expect(KSeFEnvironment.demo.id == "demo")
        #expect(KSeFEnvironment.production.id == "production")
    }

    @Test("displayName ma polską etykietę dla każdego środowiska")
    func displayNames() {
        #expect(KSeFEnvironment.test.displayName == "Testowe")
        #expect(KSeFEnvironment.demo.displayName == "Demo (przedprodukcyjne)")
        #expect(KSeFEnvironment.production.displayName == "Produkcyjne")
    }
}

// MARK: - Opisy błędów KSeFError

@Suite("KSeFError — czytelne opisy wszystkich wariantów")
struct KSeFErrorDescriptionTests {

    @Test("Każdy wariant KSeFError ma niepusty, poprawny errorDescription")
    func allDescriptions() {
        #expect(KSeFError.missingCredentials.errorDescription?.hasPrefix("Brak danych uwierzytelniających") == true)
        #expect(KSeFError.notAuthorized.errorDescription == "Brak aktywnej autoryzacji w KSeF.")
        #expect(KSeFError.badStatus(code: 409, message: "Konflikt").errorDescription
            == "Serwer KSeF zwrócił błąd (HTTP 409). Konflikt")
        #expect(KSeFError.invalidResponse.errorDescription == "Nieprawidłowa odpowiedź serwera KSeF.")
        #expect(KSeFError.xmlParsingFailed("brak węzła").errorDescription
            == "Błąd parsowania dokumentu e-Faktury: brak węzła")

        let validation = KSeFError.validationFailed([.emptyInvoiceNumber])
        #expect(validation.errorDescription?.hasPrefix("Faktura zawiera błędy:") == true)

        #expect(KSeFError.encryptionFailed("szczegóły").errorDescription
            == "Błąd kryptograficzny: szczegóły")
        #expect(KSeFError.noPublicKey.errorDescription
            == "KSeF nie udostępnił certyfikatu klucza publicznego wymaganego do szyfrowania.")
        #expect(KSeFError.authenticationFailed("odmowa").errorDescription
            == "Uwierzytelnienie w KSeF nie powiodło się: odmowa")
        #expect(KSeFError.authenticationTimeout.errorDescription
            == "Przekroczono czas oczekiwania na uwierzytelnienie w KSeF.")
        #expect(KSeFError.invoiceRejected("semantyka").errorDescription
            == "KSeF odrzucił fakturę: semantyka")
        #expect(KSeFError.certificateEnrollmentFailed("limit").errorDescription
            == "Wniosek o certyfikat KSeF nie powiódł się: limit")
        #expect(KSeFError.permissionOperationFailed("brak roli").errorDescription
            == "Operacja na uprawnieniach KSeF nie powiodła się: brak roli")
    }
}

// MARK: - Rozszerzenie URLSession jako transport HTTP

@Suite("URLSession — konformancja HTTPTransport (bez sieci)")
struct URLSessionTransportTests {

    @Test("Odpowiedź HTTP jest zwracana wraz z danymi (atrapa URLProtocol)")
    func returnsHTTPResponse() async throws {
        StubHTTPURLProtocol_ksef.status = 201
        StubHTTPURLProtocol_ksef.body = Data("OK".utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubHTTPURLProtocol_ksef.self]
        let session = URLSession(configuration: config)

        let (data, http) = try await session.send(
            URLRequest(url: URL(string: "https://przyklad.testowy.invalid/zasob")!)
        )
        #expect(http.statusCode == 201)
        #expect(String(decoding: data, as: UTF8.self) == "OK")
    }

    @Test("Odpowiedź inna niż HTTP (schemat data:) zgłasza invalidResponse")
    func nonHTTPResponseThrows() async {
        let request = URLRequest(url: URL(string: "data:text/plain;base64,aGVsbG8=")!)
        await #expect(throws: KSeFError.invalidResponse) {
            _ = try await URLSession.shared.send(request)
        }
    }
}

// MARK: - Przypadki brzegowe usługi KSeF

@Suite("KSeFService — przypadki brzegowe pętli i inicjalizatora")
struct KSeFServiceEdgeCasesTests {

    @Test("Inicjalizator korzysta z domyślnego resolvera klucza publicznego")
    func defaultPublicKeyResolver() {
        // Wywołanie inicjalizatora z pominięciem transportu i resolvera pokrywa
        // ich wartości domyślne (m.in. KSeFCrypto.publicKey(fromDERCertificate:)).
        // Sam obiekt nie wykonuje żadnego żądania sieciowego.
        let service = KSeFService(nip: "1111111111", authToken: "tok-abc")
        #expect(service.environment == .test)
        #expect(service.accessToken == nil)
        #expect(service.lastAuthenticationMethod == nil)
    }

    @Test("Uwierzytelnienie z odstępem odpytywania: przekroczenie czasu (timeout)")
    func authenticationTimeoutWithDelay() async {
        let transport = MockTransport()
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
        // Status uwierzytelnienia nigdy nie osiąga kodu 200 — polling się kończy.
        transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authPending)

        let service = makeService_ksef(transport: transport)
        service.pollInterval = 0.0005   // > 0 uruchamia gałąź uśpienia
        service.maxPollAttempts = 2

        await #expect(throws: KSeFError.authenticationTimeout) {
            try await service.authenticate()
        }
    }

    @Test("Stronicowanie: druga strona jest pobierana, gdy hasMore = true")
    func pagesUntilHasMoreIsFalse() async throws {
        func metadata(hasMore: Bool) -> Data {
            Data("""
            {"hasMore": \(hasMore), "invoices": [
              {"ksefNumber": "5260250274-20260701-AAAAAA-AAAAAA-AA",
               "invoiceNumber": "FV/1", "issueDate": "2026-07-01",
               "seller": {"nip": "5260250274", "name": "ACME"},
               "buyer": {"identifier": {"type": "Nip", "value": "1111111111"}, "name": "Nabywca"},
               "netAmount": 10.0, "vatAmount": 2.3, "grossAmount": 12.3}
            ]}
            """.utf8)
        }
        let transport = MockTransport()
        routeAuthSuccess_ksef(on: transport)
        transport.route("invoices/query/metadata") { request in
            let url = request.url?.absoluteString ?? ""
            // Pierwsza strona zapowiada kolejną (hasMore=true → pageOffset += 1),
            // druga strona kończy stronicowanie.
            return (200, metadata(hasMore: url.contains("pageOffset=0")))
        }

        let service = makeService_ksef(transport: transport)
        let invoices = try await service.fetchInvoices(
            role: .buyer,
            from: .distantPast,
            to: .now,
            skipDocumentsFor: ["5260250274-20260701-AAAAAA-AAAAAA-AA"]
        )
        // Po jednej fakturze z każdej z dwóch stron.
        #expect(invoices.count == 2)
        // pageOffset jest w query stringu (nie w ścieżce) — szukamy w pełnym URL.
        #expect(transport.requests.contains { ($0.url?.absoluteString ?? "").contains("pageOffset=1") })
    }

    @Test("Odpytywanie o wynik wysyłki z odstępem: gałąź uśpienia przy przetwarzaniu")
    func invoiceResultPollingDelay() async throws {
        let transport = MockTransport()
        routeAuthSuccess_ksef(on: transport)
        transport.routeOK("sessions/online/SESS-1/invoices", data: Data(#"{"referenceNumber":"INV-1"}"#.utf8))
        transport.routeOK("sessions/online/SESS-1/close", data: Data("{}".utf8))
        // Status pozostaje „w przetwarzaniu" (kod 150) — pętla dochodzi do końca.
        transport.routeOK(
            "sessions/SESS-1/invoices/INV-1",
            data: Data(#"{"status":{"code":150,"description":"Trwa przetwarzanie"}}"#.utf8)
        )
        transport.routeOK("sessions/online", data: Data(#"{"referenceNumber":"SESS-1"}"#.utf8))

        let service = makeService_ksef(transport: transport)
        service.pollInterval = 0.0005   // > 0 uruchamia gałąź uśpienia (743)
        service.maxPollAttempts = 2

        let result = try await service.sendInvoice(makeValidDraft_ksef())
        #expect(result.ksefNumber == nil)
        #expect(result.processingResult.status == .processing)
    }

    @Test("Limit żądań (429) z niezerowym opóźnieniem: backoff i ponowienie")
    func rateLimitWithBackoffDelay() async throws {
        let transport = MockTransport()
        transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
        transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
        transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)

        var challengeCalls = 0
        transport.route("auth/challenge") { _ in
            challengeCalls += 1
            if challengeCalls == 1 {
                return (429, Data(#"{"status":{"code":429,"description":"Too Many Requests"}}"#.utf8))
            }
            return (200, AuthFixtures.challenge)
        }

        let service = makeService_ksef(transport: transport)
        service.rateLimitRetryDelay = 0.0005   // > 0 uruchamia obliczenie i uśpienie backoffu

        let token = try await service.authenticate()
        #expect(token == "ACCESS-JWT")
        #expect(challengeCalls == 2)
    }
}

// MARK: - Podpis KODU II (gałąź błędu)

@Suite("KSeFVerificationLink — błąd podpisu RSASSA-PSS")
struct KSeFVerificationLinkErrorTests {

    @Test("Za słaby klucz RSA-512 kończy podpis KODU II błędem encryptionFailed")
    func pssSignatureFailure() throws {
        // Certyfikat z celowo za słabym kluczem RSA-512 — podpis RSASSA-PSS
        // SHA-256 jest z nim niekompatybilny, więc gałąź błędu musi się uruchomić.
        let certificate = KSeFCertificate(
            certificateDER: Data([0x30, 0x00]),
            privateKeyDER: weakRSA512PrivateKeyDER,
            keyType: .rsa,
            serialNumberHex: "0AB12"
        )
        #expect(throws: KSeFError.self) {
            _ = try KSeFVerificationLink.sign(Data("faktura".utf8), with: certificate)
        }
        // Komunikat pochodzi z gałęzi błędu podpisu PSS.
        do {
            _ = try KSeFVerificationLink.sign(Data("faktura".utf8), with: certificate)
            Issue.record("Podpis nie powinien się powieść dla klucza RSA-512")
        } catch let error as KSeFError {
            #expect(error.errorDescription?.contains("Podpis RSASSA-PSS nie powiódł się") == true)
        }
    }
}

// MARK: - Usługa certyfikatów (przypadki brzegowe)

@Suite("KSeFService — certyfikaty, przypadki brzegowe wniosku")
struct KSeFCertificateServiceEdgeTests {

    private let enrollmentDataJSON = Data("""
    {
      "commonName": "Firma Kowalski Certyfikat",
      "countryName": "PL",
      "organizationName": "Firma Kowalski Sp. z o.o.",
      "organizationIdentifier": "7762811692"
    }
    """.utf8)

    private func routeAuth(on transport: MockTransport) {
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
        transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
        transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)
    }

    @Test("Dane podmiotu z kompletem pól budują wszystkie atrybuty DN (w tym 2.5.4.45)")
    func subjectAttributesWithAllFields() throws {
        let json = Data("""
        {
          "commonName": "Jan Kowalski",
          "countryName": "PL",
          "givenName": "Jan",
          "surname": "Kowalski",
          "serialNumber": "PNOPL-12345678901",
          "uniqueIdentifier": "UID-123",
          "organizationName": "Firma",
          "organizationIdentifier": "VATPL-7762811692"
        }
        """.utf8)
        let data = try JSONDecoder().decode(KSeFEnrollmentData.self, from: json)
        let attributes = data.subjectAttributes

        // CN, GN, SN, serialNumber, O, orgIdentifier, uniqueIdentifier (2.5.4.45), C.
        #expect(attributes.count == 8)
        #expect(attributes.contains { $0.oid == "2.5.4.45" && $0.value == "UID-123" })
        #expect(attributes.last?.oid == "2.5.4.6")   // countryName zawsze na końcu
    }

    @Test("Standardowa nazwa certyfikatu zależy od typu")
    func certificateNameByType() {
        #expect(KSeFService.certificateName(for: .authentication) == "Ksefiarz uwierzytelniający")
        #expect(KSeFService.certificateName(for: .offline) == "Ksefiarz offline")
    }

    @Test("Odnowienie certyfikatu (renew) składa nowy wniosek pod standardową nazwą")
    func renewCertificateFlow() async throws {
        let issuedDER = try makeIssuedCertificateDER_ksef()
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("certificates/enrollments/data", data: enrollmentDataJSON)
        transport.routeOK("certificates/enrollments/ENROLL-1", data: Data(
            #"{"status":{"code":200,"description":"OK"},"certificateSerialNumber":"0321C82DA41B4362"}"#.utf8
        ))
        transport.routeOK("certificates/enrollments", data: Data(#"{"referenceNumber":"ENROLL-1"}"#.utf8))
        transport.routeOK("certificates/retrieve", data: Data("""
        {"certificates":[{"certificate":"\(issuedDER.base64EncodedString())","certificateName":"K","certificateSerialNumber":"0321C82DA41B4362","certificateType":"Offline"}]}
        """.utf8))

        let service = makeService_ksef(transport: transport, nip: "7762811692")
        let certificate = try await service.renewCertificate(type: .offline)
        #expect(certificate.serialNumberHex == "0321C82DA41B4362")

        // Wniosek został złożony pod nazwą „Ksefiarz offline".
        let enrollRequest = try #require(transport.requests.first {
            ($0.url?.path ?? "").hasSuffix("certificates/enrollments") && $0.httpMethod == "POST"
        })
        let body = String(decoding: try #require(enrollRequest.httpBody), as: UTF8.self)
        #expect(body.contains("Ksefiarz offline"))
    }

    @Test("Status 200 bez numeru seryjnego kończy wniosek błędem")
    func enrollmentMissingSerialNumber() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("certificates/enrollments/data", data: enrollmentDataJSON)
        transport.routeOK("certificates/enrollments/ENROLL-1", data: Data(
            #"{"status":{"code":200,"description":"Wniosek obsłużony"}}"#.utf8
        ))
        transport.routeOK("certificates/enrollments", data: Data(#"{"referenceNumber":"ENROLL-1"}"#.utf8))

        let service = makeService_ksef(transport: transport, nip: "7762811692")
        await #expect(throws: KSeFError.certificateEnrollmentFailed(
            "Wniosek obsłużony, ale brak numeru seryjnego certyfikatu."
        )) {
            _ = try await service.requestCertificate(name: "Ksefiarz auth", type: .authentication)
        }
    }

    @Test("Odpytywanie wniosku z odstępem: gałąź uśpienia przy kodzie 100")
    func enrollmentPollingDelay() async throws {
        let issuedDER = try makeIssuedCertificateDER_ksef()
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("certificates/enrollments/data", data: enrollmentDataJSON)
        var statusCalls = 0
        transport.route("certificates/enrollments/ENROLL-1") { _ in
            statusCalls += 1
            if statusCalls == 1 {
                return (200, Data(#"{"status":{"code":100,"description":"Przyjęty"}}"#.utf8))
            }
            return (200, Data(#"{"status":{"code":200,"description":"OK"},"certificateSerialNumber":"0321C82DA41B4362"}"#.utf8))
        }
        transport.routeOK("certificates/enrollments", data: Data(#"{"referenceNumber":"ENROLL-1"}"#.utf8))
        transport.routeOK("certificates/retrieve", data: Data("""
        {"certificates":[{"certificate":"\(issuedDER.base64EncodedString())","certificateName":"K","certificateSerialNumber":"0321C82DA41B4362","certificateType":"Authentication"}]}
        """.utf8))

        let service = makeService_ksef(transport: transport, nip: "7762811692")
        service.pollInterval = 0.0005   // > 0 uruchamia gałąź uśpienia (195)
        let certificate = try await service.requestCertificate(name: "Ksefiarz auth", type: .authentication)
        #expect(statusCalls == 2)
        #expect(certificate.serialNumberHex == "0321C82DA41B4362")
    }

    @Test("Przekroczenie czasu oczekiwania na wystawienie certyfikatu")
    func enrollmentTimeout() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("certificates/enrollments/data", data: enrollmentDataJSON)
        // Status nigdy nie osiąga kodu 200 — pętla odpytywania się wyczerpuje.
        transport.routeOK("certificates/enrollments/ENROLL-1", data: Data(
            #"{"status":{"code":100,"description":"Przyjęty"}}"#.utf8
        ))
        transport.routeOK("certificates/enrollments", data: Data(#"{"referenceNumber":"ENROLL-1"}"#.utf8))

        let service = makeService_ksef(transport: transport, nip: "7762811692")
        service.maxPollAttempts = 2

        await #expect(throws: KSeFError.certificateEnrollmentFailed(
            "Przekroczono czas oczekiwania na wystawienie certyfikatu."
        )) {
            _ = try await service.requestCertificate(name: "Ksefiarz auth", type: .authentication)
        }
    }

    @Test("Nieprawidłowa treść certyfikatu w retrieve kończy wniosek błędem")
    func retrieveInvalidCertificateContent() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("certificates/enrollments/data", data: enrollmentDataJSON)
        transport.routeOK("certificates/enrollments/ENROLL-1", data: Data(
            #"{"status":{"code":200,"description":"OK"},"certificateSerialNumber":"0321C82DA41B4362"}"#.utf8
        ))
        transport.routeOK("certificates/enrollments", data: Data(#"{"referenceNumber":"ENROLL-1"}"#.utf8))
        // Element istnieje, ale treść nie jest poprawnym base64 (guard na Data(base64Encoded:)).
        transport.routeOK("certificates/retrieve", data: Data(
            #"{"certificates":[{"certificate":"@@@niepoprawny@@@","certificateName":"K","certificateSerialNumber":"0321C82DA41B4362","certificateType":"Authentication"}]}"#.utf8
        ))

        let service = makeService_ksef(transport: transport, nip: "7762811692")
        await #expect(throws: KSeFError.certificateEnrollmentFailed("KSeF nie zwrócił treści certyfikatu.")) {
            _ = try await service.requestCertificate(name: "Ksefiarz auth", type: .authentication)
        }
    }
}

// MARK: - Magazyn certyfikatów (akcesor)

@Suite("KSeFCertificateStore — akcesor certyfikatu po typie")
struct KSeFCertificateStoreAccessorTests {

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "test.coverage.certstore.\(UUID().uuidString)")!
        defaults.set("test", forKey: AppSettingsKeys.environment)
        return defaults
    }

    @Test("certificate(type:) zwraca zapisany certyfikat albo nil zależnie od typu")
    func certificateByType() throws {
        let storage = InMemorySecretStorage_ksef()
        let store = KSeFCertificateStore(storage: storage, defaults: makeDefaults())
        let certificate = try makeStoreCertificate_ksef()

        // Bez zapisu — oba typy są puste.
        #expect(store.certificate(type: .authentication) == nil)
        #expect(store.certificate(type: .offline) == nil)

        store.save(certificate, type: .authentication)
        // Oba warianty switcha zostają odwiedzone.
        #expect(store.certificate(type: .authentication) == certificate)
        #expect(store.certificate(type: .offline) == nil)
    }
}
