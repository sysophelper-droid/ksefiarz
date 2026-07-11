import Foundation
import Security
import Testing
@testable import KsefiarzCore

// MARK: - Atrapa transportu HTTP

/// Atrapa transportu HTTP — rejestruje żądania i zwraca przygotowane odpowiedzi
/// dopasowane po fragmencie ścieżki URL (pierwsza pasująca trasa wygrywa).
final class MockTransport: HTTPTransport {
    typealias Handler = (URLRequest) throws -> (statusCode: Int, data: Data)

    private var routes: [(pathContains: String, handler: Handler)] = []
    private(set) var requests: [URLRequest] = []

    func route(_ pathContains: String, handler: @escaping Handler) {
        routes.append((pathContains, handler))
    }

    /// Skrót: trasa zwracająca status 200 i podane dane.
    func routeOK(_ pathContains: String, data: Data) {
        route(pathContains) { _ in (200, data) }
    }

    /// Pierwsze zarejestrowane żądanie, którego ścieżka zawiera podany fragment.
    func request(matching pathContains: String) -> URLRequest? {
        requests.first { ($0.url?.path ?? "").contains(pathContains) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        guard let matched = routes.first(where: { path.contains($0.pathContains) }) else {
            Issue.record("Brak trasy dla ścieżki: \(path)")
            throw KSeFError.invalidResponse
        }
        let (status, data) = try matched.handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

// MARK: - Klucze testowe i dane pomocnicze

/// Para kluczy RSA generowana w pamięci — testy odszyfrowują nią dane,
/// które usługa zaszyfrowała "kluczem publicznym MF".
struct TestRSAKeyPair {
    let privateKey: SecKey
    let publicKey: SecKey

    init() {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)!
        self.privateKey = key
        self.publicKey = SecKeyCopyPublicKey(key)!
    }

    func decryptOAEPSHA256(_ data: Data) -> Data? {
        var error: Unmanaged<CFError>?
        return SecKeyCreateDecryptedData(privateKey, .rsaEncryptionOAEPSHA256, data as CFData, &error)
            .map { $0 as Data }
    }
}

/// Odpowiedzi JSON wspólne dla testów przepływu uwierzytelnienia.
enum AuthFixtures {
    static let challenge = Data(
        #"{"challenge":"20260611-CR-TEST","timestamp":"2026-06-11T18:00:00Z","timestampMs":1781202877958}"#.utf8
    )
    /// Certyfikat jest atrapą — testy podmieniają resolver klucza publicznego.
    static let certificates = Data(
        #"[{"certificate":"RkFLRQ==","certificateId":"AQ==","publicKeyId":"AQ==","usage":["KsefTokenEncryption","SymmetricKeyEncryption"],"validFrom":"2026-01-01T00:00:00Z","validTo":"2030-01-01T00:00:00Z"}]"#.utf8
    )
    static let authInit = Data(
        #"{"referenceNumber":"AUTH-REF-1","authenticationToken":{"token":"temp-jwt","validUntil":"2026-12-31T00:00:00Z"}}"#.utf8
    )
    static let authOK = Data(#"{"status":{"code":200,"description":"Uwierzytelnianie zakończone sukcesem"}}"#.utf8)
    static let authPending = Data(#"{"status":{"code":100,"description":"Uwierzytelnianie w toku"}}"#.utf8)
    static let tokens = Data(
        #"{"accessToken":{"token":"ACCESS-JWT","validUntil":"2026-06-12T00:00:00Z"},"refreshToken":{"token":"REFRESH-JWT","validUntil":"2026-06-18T00:00:00Z"}}"#.utf8
    )
}

/// Rejestruje komplet tras potrzebnych do pomyślnego uwierzytelnienia.
private func routeSuccessfulAuth(on transport: MockTransport) {
    transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
    transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
    transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
    transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
    transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)
}

/// Buduje usługę z zerowym odstępem odpytywania i testowym kluczem publicznym.
private func makeService(
    transport: MockTransport,
    keys: TestRSAKeyPair,
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

private func makeValidDraft() -> InvoiceDraft {
    InvoiceDraft(
        invoiceNumber: "FV/2026/06/001",
        issueDate: FA2Format.dateFormatter.date(from: "2026-06-01")!,
        sellerName: "ACME Sp. z o.o.",
        sellerNIP: "5260250274",
        sellerAddress: "ul. Przykładowa 1, 00-001 Warszawa",
        buyerName: "Kontrahent S.A.",
        buyerNIP: "1111111111",
        netAmount: 100.0,
        vatAmount: 23.0
    )
}

private let testKsefNumber = "5260250274-20260611-ABCDEF-ABCDEF-AB"

// MARK: - Testy uwierzytelnienia

@Suite("KSeFService — uwierzytelnienie (KSeF 2.0)")
struct KSeFServiceAuthTests {

    @Test("Pełny przepływ: challenge → szyfrowanie tokenu → polling → redeem")
    func authenticateSuccess() async throws {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)

        let service = makeService(transport: transport, keys: keys)
        let token = try await service.authenticate()

        #expect(token == "ACCESS-JWT")
        #expect(service.accessToken == "ACCESS-JWT")

        // Zaszyfrowany token musi odszyfrować się do "token|timestampMs".
        let initRequest = try #require(transport.request(matching: "auth/ksef-token"))
        let body = try JSONDecoder().decode(
            CapturedTokenAuthRequest.self,
            from: try #require(initRequest.httpBody)
        )
        #expect(body.challenge == "20260611-CR-TEST")
        #expect(body.contextIdentifier.type == "Nip")
        #expect(body.contextIdentifier.value == "1111111111")
        let encrypted = try #require(Data(base64Encoded: body.encryptedToken))
        let decrypted = try #require(keys.decryptOAEPSHA256(encrypted))
        #expect(String(decoding: decrypted, as: UTF8.self) == "tok-abc|1781202877958")

        // Redeem używa tokenu operacji uwierzytelnienia (Bearer).
        let redeemRequest = try #require(transport.request(matching: "auth/token/redeem"))
        #expect(redeemRequest.value(forHTTPHeaderField: "Authorization") == "Bearer temp-jwt")
    }

    @Test("Polling czeka, dopóki status ma kod 100 (w toku)")
    func authenticatePolling() async throws {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
        transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)

        // Dwa pierwsze odpytania zwracają "w toku", trzecie sukces.
        var statusCalls = 0
        transport.route("auth/AUTH-REF-1") { _ in
            statusCalls += 1
            return (200, statusCalls < 3 ? AuthFixtures.authPending : AuthFixtures.authOK)
        }

        let service = makeService(transport: transport, keys: keys)
        _ = try await service.authenticate()

        #expect(statusCalls == 3)
        #expect(service.accessToken == "ACCESS-JWT")
    }

    @Test("Status błędu (kod ≥ 400) przerywa uwierzytelnienie z opisem")
    func authenticateFailure() async {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
        transport.routeOK(
            "auth/AUTH-REF-1",
            data: Data(#"{"status":{"code":450,"description":"Błędny token","details":["Nieprawidłowy token"]}}"#.utf8)
        )

        let service = makeService(transport: transport, keys: keys)
        await #expect(throws: KSeFError.authenticationFailed("Błędny token Nieprawidłowy token")) {
            try await service.authenticate()
        }
    }

    @Test("Brak NIP-u lub tokenu zgłasza missingCredentials bez żądań sieciowych")
    func missingCredentials() async {
        let transport = MockTransport()
        let service = makeService(transport: transport, keys: TestRSAKeyPair(), nip: "", token: "")
        await #expect(throws: KSeFError.missingCredentials) {
            try await service.authenticate()
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("Limit żądań (HTTP 429) jest ponawiany automatycznie")
    func rateLimitRetry() async throws {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)

        // Dwa pierwsze żądania o challenge zwracają 429, trzecie sukces.
        var challengeCalls = 0
        let routes = MockTransport()
        routes.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        routes.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
        routes.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
        routes.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)
        routes.route("auth/challenge") { _ in
            challengeCalls += 1
            if challengeCalls < 3 {
                return (429, Data(#"{"status":{"code":429,"description":"Too Many Requests"}}"#.utf8))
            }
            return (200, AuthFixtures.challenge)
        }

        let service = makeService(transport: routes, keys: keys)
        service.rateLimitRetryDelay = 0
        let token = try await service.authenticate()

        #expect(token == "ACCESS-JWT")
        #expect(challengeCalls == 3)
    }

    @Test("Trwały limit 429 kończy się błędem po wyczerpaniu ponowień")
    func rateLimitGivesUp() async {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        transport.route("auth/challenge") { _ in
            (429, Data(#"{"status":{"code":429,"description":"Too Many Requests"}}"#.utf8))
        }
        let service = makeService(transport: transport, keys: keys)
        service.rateLimitRetryDelay = 0
        service.rateLimitMaxRetries = 2

        await #expect(throws: KSeFError.self) {
            try await service.authenticate()
        }
        // 1 żądanie + 2 ponowienia.
        #expect(transport.requests.count == 3)
    }

    @Test("Błąd HTTP z treścią problem+json daje czytelny komunikat")
    func problemJSONErrorMapping() async {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        transport.route("auth/challenge") { _ in
            (400, Data(#"{"title":"Bad Request","detail":"Nieprawidłowy kontekst","status":400}"#.utf8))
        }
        let service = makeService(transport: transport, keys: keys)

        await #expect(throws: KSeFError.badStatus(code: 400, message: "Nieprawidłowy kontekst")) {
            try await service.authenticate()
        }
    }

    @Test("Brak certyfikatu o wymaganym przeznaczeniu zgłasza noPublicKey")
    func noUsableCertificate() async {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.routeOK(
            "security/public-key-certificates",
            data: Data(#"[{"certificate":"RkFLRQ==","certificateId":"AQ==","publicKeyId":"AQ==","usage":["SymmetricKeyEncryption"],"validFrom":"2026-01-01T00:00:00Z","validTo":"2030-01-01T00:00:00Z"}]"#.utf8)
        )
        let service = makeService(transport: transport, keys: keys)

        await #expect(throws: KSeFError.noPublicKey) {
            try await service.authenticate()
        }
    }
}

// MARK: - Testy pobierania faktur (inbound)

@Suite("KSeFService — pobieranie faktur zakupowych")
struct KSeFServiceFetchTests {

    private func metadataJSON(hasMore: Bool = false) -> Data {
        Data("""
        {
          "hasMore": \(hasMore),
          "invoices": [
            {
              "ksefNumber": "\(testKsefNumber)",
              "invoiceNumber": "FV/2026/06/001",
              "issueDate": "2026-06-01",
              "seller": { "nip": "5260250274", "name": "ACME Sp. z o.o." },
              "buyer": { "identifier": { "type": "Nip", "value": "1111111111" }, "name": "Kontrahent S.A." },
              "netAmount": 100.0,
              "vatAmount": 23.0,
              "grossAmount": 123.0,
              "currency": "PLN"
            }
          ]
        }
        """.utf8)
    }

    @Test("Pobiera metadane, ściąga XML i zwraca sparsowane faktury z numerem KSeF")
    func fetchPurchaseInvoices() async throws {
        let invoiceXML = FA2XMLGenerator.generateXML(for: makeValidDraft())

        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)
        transport.routeOK("invoices/query/metadata", data: metadataJSON())
        transport.routeOK("invoices/ksef/", data: Data(invoiceXML.utf8))

        let service = makeService(transport: transport, keys: keys)
        let from = FA2Format.dateFormatter.date(from: "2026-03-01")!
        let to = FA2Format.dateFormatter.date(from: "2026-06-11")!

        let invoices = try await service.fetchPurchaseInvoices(from: from, to: to)

        #expect(invoices.count == 1)
        let invoice = try #require(invoices.first)
        #expect(invoice.ksefId == testKsefNumber)
        #expect(invoice.invoiceNumber == "FV/2026/06/001")
        #expect(invoice.sellerName == "ACME Sp. z o.o.")
        #expect(abs(invoice.grossAmount - 123.0) < 0.001)
        #expect(invoice.rawXML.contains("<Faktura"))

        // Zapytanie o metadane: nabywca (Subject2), zakres dat, token dostępowy.
        let queryRequest = try #require(transport.request(matching: "invoices/query/metadata"))
        #expect(queryRequest.value(forHTTPHeaderField: "Authorization") == "Bearer ACCESS-JWT")
        let queryBody = String(decoding: queryRequest.httpBody ?? Data(), as: UTF8.self)
        #expect(queryBody.contains("Subject2"))
        #expect(queryBody.contains("Issue"))
    }

    @Test("Gdy XML jest niedostępny, faktura powstaje z metadanych")
    func fetchFallsBackToMetadata() async throws {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)
        transport.routeOK("invoices/query/metadata", data: metadataJSON())
        transport.route("invoices/ksef/") { _ in (403, Data(#"{"title":"Forbidden"}"#.utf8)) }

        let service = makeService(transport: transport, keys: keys)
        let invoices = try await service.fetchPurchaseInvoices(from: .distantPast, to: .now)

        #expect(invoices.count == 1)
        let invoice = try #require(invoices.first)
        #expect(invoice.ksefId == testKsefNumber)
        #expect(invoice.invoiceNumber == "FV/2026/06/001")
        #expect(invoice.sellerNIP == "5260250274")
        #expect(invoice.buyerNIP == "1111111111")
        #expect(abs(invoice.grossAmount - 123.0) < 0.001)
        #expect(FA2Format.dateFormatter.string(from: invoice.issueDate) == "2026-06-01")
        #expect(invoice.rawXML.isEmpty)
    }

    @Test("Pusta lista metadanych zwraca pustą listę faktur")
    func fetchEmptyList() async throws {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)
        transport.routeOK("invoices/query/metadata", data: Data(#"{"hasMore":false,"invoices":[]}"#.utf8))

        let service = makeService(transport: transport, keys: keys)
        let invoices = try await service.fetchPurchaseInvoices(from: .distantPast, to: .now)

        #expect(invoices.isEmpty)
    }

    @Test("Faktury z kompletem danych nie pobierają ponownie dokumentu XML")
    func skipsDocumentDownloadForCompleteInvoices() async throws {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)
        transport.routeOK("invoices/query/metadata", data: metadataJSON())

        let service = makeService(transport: transport, keys: keys)
        let invoices = try await service.fetchInvoices(
            role: .buyer,
            from: .distantPast,
            to: .now,
            skipDocumentsFor: [testKsefNumber]
        )

        // Faktura zbudowana z metadanych, bez żądania o dokument XML.
        #expect(invoices.count == 1)
        #expect(invoices.first?.rawXML.isEmpty == true)
        #expect(invoices.first?.invoiceNumber == "FV/2026/06/001")
        #expect(transport.request(matching: "invoices/ksef/") == nil)
    }

    @Test("Pobieranie faktur sprzedażowych odpytuje rolę Subject1")
    func fetchSalesInvoicesUsesSubject1() async throws {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)
        transport.routeOK("invoices/query/metadata", data: Data(#"{"hasMore":false,"invoices":[]}"#.utf8))

        let service = makeService(transport: transport, keys: keys)
        _ = try await service.fetchSalesInvoices(from: .distantPast, to: .now)

        let queryRequest = try #require(transport.request(matching: "invoices/query/metadata"))
        let body = String(decoding: queryRequest.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("Subject1"))
        #expect(!body.contains("Subject2"))
    }

    @Test("Niepoprawny JSON odpowiedzi zgłasza invalidResponse")
    func invalidQueryResponse() async {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)
        transport.routeOK("invoices/query/metadata", data: Data("nie-json".utf8))

        let service = makeService(transport: transport, keys: keys)
        await #expect(throws: KSeFError.invalidResponse) {
            _ = try await service.fetchPurchaseInvoices(from: .distantPast, to: .now)
        }
    }
}

// MARK: - Testy wysyłki faktur (outbound)

@Suite("KSeFService — wystawianie faktur (sesja interaktywna)")
struct KSeFServiceSendTests {

    @Test("Wysyłka: otwarcie sesji z szyfrowaniem AES, faktura, zamknięcie, numer KSeF")
    func sendInvoiceSuccess() async throws {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)
        // Kolejność tras ma znaczenie — od najbardziej szczegółowych.
        transport.routeOK("sessions/online/SESS-1/invoices", data: Data(#"{"referenceNumber":"INV-REF-1"}"#.utf8))
        transport.routeOK("sessions/online/SESS-1/close", data: Data("{}".utf8))
        transport.routeOK(
            "sessions/SESS-1/invoices/INV-REF-1",
            data: Data(#"{"ksefNumber":"\#(testKsefNumber)","status":{"code":200,"description":"OK"}}"#.utf8)
        )
        transport.routeOK("sessions/online", data: Data(#"{"referenceNumber":"SESS-1","validUntil":"2026-06-12T00:00:00Z"}"#.utf8))

        let service = makeService(transport: transport, keys: keys)
        let result = try await service.sendInvoice(makeValidDraft())

        #expect(result.elementReferenceNumber == testKsefNumber)
        #expect(result.invoiceReferenceNumber == "INV-REF-1")
        #expect(result.ksefNumber == testKsefNumber)
        #expect(result.sessionReferenceNumber == "SESS-1")
        #expect(result.xml.contains("<P_2>FV/2026/06/001</P_2>"))

        // Klucz AES z otwarcia sesji musi odszyfrować się naszym kluczem prywatnym...
        let openRequest = try #require(
            transport.requests.first { ($0.url?.path ?? "").hasSuffix("sessions/online") }
        )
        let openBody = try JSONDecoder().decode(
            CapturedOpenSessionRequest.self,
            from: try #require(openRequest.httpBody)
        )
        #expect(openBody.formCode.systemCode == "FA (3)")
        let encryptedKey = try #require(Data(base64Encoded: openBody.encryption.encryptedSymmetricKey))
        let aesKey = try #require(keys.decryptOAEPSHA256(encryptedKey))
        #expect(aesKey.count == 32)
        let iv = try #require(Data(base64Encoded: openBody.encryption.initializationVector))
        #expect(iv.count == 16)

        // ...a zaszyfrowana faktura musi odszyfrować się tym kluczem do wysłanego XML.
        let sendRequest = try #require(transport.request(matching: "sessions/online/SESS-1/invoices"))
        let sendBody = try JSONDecoder().decode(
            CapturedSendInvoiceRequest.self,
            from: try #require(sendRequest.httpBody)
        )
        let encryptedInvoice = try #require(Data(base64Encoded: sendBody.encryptedInvoiceContent))
        let decryptedXML = try KSeFCrypto.aesDecryptCBC(encryptedInvoice, key: aesKey, iv: iv)
        #expect(String(decoding: decryptedXML, as: UTF8.self) == result.xml)

        // Skróty SHA-256 muszą się zgadzać.
        #expect(sendBody.invoiceHash == KSeFCrypto.sha256Base64(Data(result.xml.utf8)))
        #expect(sendBody.encryptedInvoiceHash == KSeFCrypto.sha256Base64(encryptedInvoice))
        #expect(sendBody.invoiceSize == Data(result.xml.utf8).count)

        // Sesja została zamknięta.
        #expect(transport.request(matching: "sessions/online/SESS-1/close") != nil)
    }

    @Test("Wysyłka w toku zwraca osobno referencję i brak numeru KSeF")
    func sendInvoiceStillProcessing() async throws {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)
        transport.routeOK("sessions/online/SESS-1/invoices", data: Data(#"{"referenceNumber":"INV-PENDING-1"}"#.utf8))
        transport.routeOK("sessions/online/SESS-1/close", data: Data("{}".utf8))
        transport.routeOK(
            "sessions/SESS-1/invoices/INV-PENDING-1",
            data: Data(#"{"status":{"code":150,"description":"Trwa przetwarzanie"}}"#.utf8)
        )
        transport.routeOK("sessions/online", data: Data(#"{"referenceNumber":"SESS-1"}"#.utf8))

        let service = makeService(transport: transport, keys: keys)
        service.maxPollAttempts = 1
        let result = try await service.sendInvoice(makeValidDraft())

        #expect(result.invoiceReferenceNumber == "INV-PENDING-1")
        #expect(result.ksefNumber == nil)
        #expect(result.elementReferenceNumber == "INV-PENDING-1")
    }

    @Test("Odczyt statusu rozróżnia przyjęcie, przetwarzanie i odrzucenie")
    func fetchProcessingStates() async throws {
        let keys = TestRSAKeyPair()

        let acceptedTransport = MockTransport()
        routeSuccessfulAuth(on: acceptedTransport)
        acceptedTransport.routeOK(
            "sessions/S/invoices/A",
            data: Data(#"{"ksefNumber":"KSEF-A","acquisitionDate":"2026-07-11T08:30:00Z","status":{"code":200,"description":"Przyjęta"}}"#.utf8)
        )
        let acceptedService = makeService(transport: acceptedTransport, keys: keys)
        let accepted = try await acceptedService.fetchInvoiceStatus(
            sessionReference: "S", invoiceReference: "A"
        )
        #expect(accepted.status == .accepted)
        #expect(accepted.ksefNumber == "KSEF-A")
        #expect(accepted.acquisitionDate != nil)

        let pendingTransport = MockTransport()
        routeSuccessfulAuth(on: pendingTransport)
        pendingTransport.routeOK(
            "sessions/S/invoices/P",
            data: Data(#"{"status":{"code":150,"description":"W toku"}}"#.utf8)
        )
        let pendingService = makeService(transport: pendingTransport, keys: keys)
        let pending = try await pendingService.fetchInvoiceStatus(
            sessionReference: "S", invoiceReference: "P"
        )
        #expect(pending.status == .processing)
        #expect(pending.statusCode == 150)

        let rejectedTransport = MockTransport()
        routeSuccessfulAuth(on: rejectedTransport)
        rejectedTransport.routeOK(
            "sessions/S/invoices/R",
            data: Data(#"{"status":{"code":440,"description":"Odrzucona","details":["Błąd schemy"]}}"#.utf8)
        )
        let rejectedService = makeService(transport: rejectedTransport, keys: keys)
        let rejected = try await rejectedService.fetchInvoiceStatus(
            sessionReference: "S", invoiceReference: "R"
        )
        #expect(rejected.status == .rejected)
        #expect(rejected.description == "Odrzucona Błąd schemy")
    }

    @Test("Odrzucenie faktury wraca jako trwały wynik z referencją i opisem")
    func sendInvoiceRejected() async throws {
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)
        transport.routeOK("sessions/online/SESS-1/invoices", data: Data(#"{"referenceNumber":"INV-REF-1"}"#.utf8))
        transport.routeOK("sessions/online/SESS-1/close", data: Data("{}".utf8))
        transport.routeOK(
            "sessions/SESS-1/invoices/INV-REF-1",
            data: Data(#"{"status":{"code":440,"description":"Błąd weryfikacji semantyki dokumentu"}}"#.utf8)
        )
        transport.routeOK("sessions/online", data: Data(#"{"referenceNumber":"SESS-1","validUntil":"2026-06-12T00:00:00Z"}"#.utf8))

        let service = makeService(transport: transport, keys: keys)
        let result = try await service.sendInvoice(makeValidDraft())
        #expect(result.invoiceReferenceNumber == "INV-REF-1")
        #expect(result.ksefNumber == nil)
        #expect(result.processingResult.status == .rejected)
        #expect(result.processingResult.statusCode == 440)
        #expect(result.processingResult.description == "Błąd weryfikacji semantyki dokumentu")
    }

    @Test("Pobieranie UPO używa referencji sesji i numeru KSeF")
    func downloadUPO() async throws {
        let upoXML = Data("<Potwierdzenie><NrReferencyjny>UPO-1</NrReferencyjny></Potwierdzenie>".utf8)
        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        routeSuccessfulAuth(on: transport)
        transport.routeOK("sessions/SESS-1/invoices/ksef/\(testKsefNumber)/upo", data: upoXML)

        let service = makeService(transport: transport, keys: keys)
        let upo = try await service.downloadUPO(sessionReference: "SESS-1", ksefNumber: testKsefNumber)

        #expect(upo == upoXML)
        let request = try #require(transport.request(matching: "/upo"))
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ACCESS-JWT")
    }

    @Test("Niepoprawna faktura jest odrzucana przed jakąkolwiek komunikacją")
    func sendInvalidInvoice() async {
        let transport = MockTransport()
        let service = makeService(transport: transport, keys: TestRSAKeyPair())

        var draft = makeValidDraft()
        draft.invoiceNumber = ""
        draft.buyerNIP = "123"

        await #expect(throws: KSeFError.validationFailed([.emptyInvoiceNumber, .invalidBuyerNIP])) {
            _ = try await service.sendInvoice(draft)
        }
        // Walidacja zatrzymała wysyłkę — zero żądań sieciowych.
        #expect(transport.requests.isEmpty)
    }
}

// MARK: - Struktury do dekodowania przechwyconych żądań

private struct CapturedTokenAuthRequest: Decodable {
    struct ContextIdentifier: Decodable {
        let type: String
        let value: String
    }
    let challenge: String
    let contextIdentifier: ContextIdentifier
    let encryptedToken: String
}

private struct CapturedOpenSessionRequest: Decodable {
    struct FormCode: Decodable {
        let systemCode: String
        let schemaVersion: String
        let value: String
    }
    struct Encryption: Decodable {
        let encryptedSymmetricKey: String
        let initializationVector: String
    }
    let formCode: FormCode
    let encryption: Encryption
}

private struct CapturedSendInvoiceRequest: Decodable {
    let invoiceHash: String
    let invoiceSize: Int
    let encryptedInvoiceHash: String
    let encryptedInvoiceSize: Int
    let encryptedInvoiceContent: String
}
