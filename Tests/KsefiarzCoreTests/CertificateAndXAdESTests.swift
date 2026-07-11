import Foundation
import Security
import Testing
@testable import KsefiarzCore

// MARK: - Pomocnicze

private final class InMemorySecretStorage: SecretStorage {
    var values: [String: String] = [:]
    func read(account: String) -> String? { values[account] }
    func save(_ value: String, account: String) { values[account] = value }
    func delete(account: String) { values[account] = nil }
}

/// Buduje testowy certyfikat KSeF (self-signed, RSA-2048) z pieczęcią VATPL-{NIP}.
private func makeTestCertificate(nip: String = "5265877635") throws -> KSeFCertificate {
    let key = try X509Builder.generateRSAKeyPair()
    let der = try X509Builder.makeSelfSignedCertificate(
        subject: [
            .countryName("PL"),
            .organizationName("Ksefiarz Test"),
            .commonName("Ksefiarz Test"),
            .organizationIdentifier("VATPL-\(nip)"),
        ],
        privateKey: key
    )
    return KSeFCertificate(certificateDER: der, privateKeyDER: try X509Builder.exportPrivateKey(key))
}

// MARK: - ASN.1 DER

@Suite("ASN.1 DER — kodowanie i odczyt")
struct ASN1DERTests {

    @Test("OID koduje się do znanych bajtów i przechodzi round-trip przez czytnik")
    func oidRoundTrip() throws {
        // 2.5.4.97 → 06 03 55 04 61
        let encoded = ASN1DER.objectIdentifier("2.5.4.97")
        #expect(encoded == Data([0x06, 0x03, 0x55, 0x04, 0x61]))

        // 1.2.840.113549.1.1.11 (sha256WithRSA) — wielobajtowe człony.
        let rsa = ASN1DER.objectIdentifier("1.2.840.113549.1.1.11")
        #expect(rsa == Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]))
    }

    @Test("Długości: forma krótka i długa")
    func lengthEncoding() {
        #expect(ASN1DER.length(5) == Data([0x05]))
        #expect(ASN1DER.length(127) == Data([0x7F]))
        #expect(ASN1DER.length(128) == Data([0x81, 0x80]))
        #expect(ASN1DER.length(300) == Data([0x82, 0x01, 0x2C]))
    }

    @Test("INTEGER dokłada wiodące zero przy ustawionym najstarszym bicie")
    func integerEncoding() {
        #expect(ASN1DER.integer(rawBytes: Data([0x80])) == Data([0x02, 0x02, 0x00, 0x80]))
        #expect(ASN1DER.integer(rawBytes: Data([0x7F])) == Data([0x02, 0x01, 0x7F]))
        #expect(ASN1DER.integer(0) == Data([0x02, 0x01, 0x00]))
    }

    @Test("Czytnik elementów parsuje zagnieżdżone sekwencje")
    func readNested() throws {
        let inner = ASN1DER.sequence([ASN1DER.integer(7), ASN1DER.utf8String("abc")])
        let outer = ASN1DER.sequence([inner])
        let root = try #require(ASN1DER.readElement(outer))
        #expect(root.tag == 0x30)
        let children = ASN1DER.children(of: root.content)
        #expect(children.count == 1)
        let innerChildren = ASN1DER.children(of: children[0].content)
        #expect(innerChildren.count == 2)
        #expect(innerChildren[0].content == Data([0x07]))
        #expect(String(decoding: innerChildren[1].content, as: UTF8.self) == "abc")
    }

    @Test("Zapis dziesiętny numeru seryjnego przekraczającego Int64")
    func bigSerialDecimal() {
        // 2^64 = 18446744073709551616
        let bytes = Data([0x01, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(ASN1DER.decimalString(fromBigEndian: bytes) == "18446744073709551616")
        #expect(ASN1DER.decimalString(fromBigEndian: Data([0x00])) == "0")
        #expect(ASN1DER.decimalString(fromBigEndian: Data([0x01, 0x00])) == "256")
    }
}

// MARK: - X.509

@Suite("X509Builder — certyfikat self-signed i CSR")
struct X509BuilderTests {

    @Test("Certyfikat self-signed jest akceptowany przez Security.framework i ma komplet pól")
    func selfSignedCertificate() throws {
        let certificate = try makeTestCertificate()
        let info = try #require(certificate.info)

        #expect(info.subjectSummary.contains("Ksefiarz Test"))
        #expect(info.issuerName.contains("CN=Ksefiarz Test"))
        #expect(info.issuerName.contains("2.5.4.97=VATPL-5265877635"))
        #expect(info.issuerName.contains("C=PL"))
        #expect(info.isValid())
        #expect(!info.serialNumberDecimal.isEmpty)
        #expect(info.serialNumberHex.count == 32) // 16 losowych bajtów
        #expect(info.daysToExpiry() >= 29)
    }

    @Test("Klucz prywatny przechodzi round-trip przez eksport i import DER")
    func privateKeyRoundTrip() throws {
        let key = try X509Builder.generateRSAKeyPair()
        let der = try X509Builder.exportPrivateKey(key)
        let restored = try X509Builder.importPrivateKey(der)

        // Podpis wykonany odtworzonym kluczem weryfikuje się kluczem publicznym oryginału.
        let message = Data("dane testowe".utf8)
        let signature = try X509Builder.signSHA256RSA(message, privateKey: restored)
        let publicKey = try #require(SecKeyCopyPublicKey(key))
        #expect(SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData, signature as CFData, nil
        ))
    }

    @Test("CSR (PKCS#10) ma poprawną strukturę i prawidłowy podpis")
    func csrStructure() throws {
        let key = try X509Builder.generateRSAKeyPair()
        let subject: [X509Builder.NameAttribute] = [
            .commonName("Firma Testowa"),
            .countryName("PL"),
            .organizationName("Firma Testowa Sp. z o.o."),
            .organizationIdentifier("7762811692"),
        ]
        let csr = try X509Builder.makeCSR(subject: subject, privateKey: key)

        let root = try #require(ASN1DER.readElement(csr))
        #expect(root.tag == 0x30)
        let parts = ASN1DER.children(of: root.content)
        #expect(parts.count == 3) // info, algorytm, podpis

        // Podpis (BIT STRING, po bajcie nieużywanych bitów) weryfikuje się
        // kluczem publicznym nad bajtami CertificationRequestInfo.
        let infoBytes = ASN1DER.tagged(0x30, parts[0].content)
        let signature = parts[2].content.dropFirst()
        let publicKey = try #require(SecKeyCopyPublicKey(key))
        #expect(SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePKCS1v15SHA256,
            infoBytes as CFData, Data(signature) as CFData, nil
        ))

        // Podmiot zawiera wszystkie atrybuty w zadanej kolejności.
        let infoChildren = ASN1DER.children(of: parts[0].content)
        #expect(infoChildren.count == 4) // wersja, podmiot, klucz, atrybuty
        let subjectElement = infoChildren[1]
        let dn = KSeFCertificate.distinguishedName(fromDERName: subjectElement)
        #expect(dn.contains("CN=Firma Testowa"))
        #expect(dn.contains("2.5.4.97=7762811692"))
    }
}

// MARK: - Magazyn certyfikatów

@Suite("KSeFCertificateStore — pęk kluczy per typ i środowisko")
struct KSeFCertificateStoreTests {

    private func makeDefaults(environment: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "test.certstore.\(UUID().uuidString)")!
        defaults.set(environment, forKey: AppSettingsKeys.environment)
        return defaults
    }

    @Test("Konta pęku kluczy: produkcja bez sufiksu, pozostałe środowiska z sufiksem")
    func accountNaming() {
        #expect(KSeFCertificateStore.account(type: .authentication, environmentRaw: "production") == "ksef.cert.auth")
        #expect(KSeFCertificateStore.account(type: .authentication, environmentRaw: "") == "ksef.cert.auth")
        #expect(KSeFCertificateStore.account(type: .authentication, environmentRaw: "test") == "ksef.cert.auth.test")
        #expect(KSeFCertificateStore.account(type: .offline, environmentRaw: "production") == "ksef.cert.offline")
        #expect(KSeFCertificateStore.account(type: .offline, environmentRaw: "demo") == "ksef.cert.offline.demo")
    }

    @Test("Zapis, odczyt i usunięcie certyfikatu")
    func saveReadDelete() throws {
        let storage = InMemorySecretStorage()
        let store = KSeFCertificateStore(storage: storage, defaults: makeDefaults(environment: "test"))
        let certificate = try makeTestCertificate()

        store.save(certificate, type: .authentication)
        #expect(store.authenticationCertificate == certificate)
        #expect(store.offlineCertificate == nil)
        #expect(storage.values["ksef.cert.auth.test"] != nil)

        // Nowa instancja czyta ten sam magazyn.
        let second = KSeFCertificateStore(storage: storage, defaults: makeDefaults(environment: "test"))
        #expect(second.authenticationCertificate == certificate)

        store.delete(type: .authentication)
        #expect(store.authenticationCertificate == nil)
        #expect(storage.values["ksef.cert.auth.test"] == nil)
    }

    @Test("Przełączenie środowiska nie nadpisuje certyfikatów innych środowisk")
    func environmentSwitch() throws {
        let storage = InMemorySecretStorage()
        let store = KSeFCertificateStore(storage: storage, defaults: makeDefaults(environment: "production"))
        let productionCert = try makeTestCertificate(nip: "1111111111")
        let testCert = try makeTestCertificate(nip: "2222222222")

        store.save(productionCert, type: .authentication)
        store.switchEnvironment("test")
        #expect(store.authenticationCertificate == nil)

        store.save(testCert, type: .authentication)
        store.switchEnvironment("production")
        #expect(store.authenticationCertificate == productionCert)
        #expect(storage.values["ksef.cert.auth.test"] != nil)
        #expect(storage.values["ksef.cert.auth"] != nil)
    }
}

// MARK: - XAdES

@Suite("XAdESSigner — podpis AuthTokenRequest (XAdES-BES enveloped)")
struct XAdESSignerTests {

    private let challenge = "20260711-CR-1234567890-ABCDEF0123-45"
    private let nip = "5265877635"

    @Test("Dokument zawiera komplet elementów i deklarację przestrzeni auth 2.0")
    func documentStructure() throws {
        let certificate = try makeTestCertificate(nip: nip)
        let xml = try XAdESSigner.signAuthTokenRequest(challenge: challenge, nip: nip, certificate: certificate)

        #expect(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(xml.contains("<AuthTokenRequest xmlns=\"http://ksef.mf.gov.pl/auth/token/2.0\">"))
        #expect(xml.contains("<Challenge>\(challenge)</Challenge>"))
        #expect(xml.contains("<ContextIdentifier><Nip>\(nip)</Nip></ContextIdentifier>"))
        #expect(xml.contains("<SubjectIdentifierType>certificateSubject</SubjectIdentifierType>"))
        #expect(xml.contains("<ds:Signature xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\""))
        #expect(xml.contains("<xades:SignedProperties"))
        #expect(xml.contains("<ds:X509Certificate>\(certificate.certificateDER.base64EncodedString())</ds:X509Certificate>"))
        // Podpis enveloped — tuż przed zamknięciem elementu głównego.
        #expect(xml.hasSuffix("</ds:Signature></AuthTokenRequest>"))
    }

    @Test("Skrót referencji URI=\"\" odpowiada dokumentowi bez podpisu")
    func documentDigestMatches() throws {
        let certificate = try makeTestCertificate(nip: nip)
        let xml = try XAdESSigner.signAuthTokenRequest(challenge: challenge, nip: nip, certificate: certificate)

        let unsigned = XAdESSigner.unsignedDocument(challenge: challenge, nip: nip)
        let expected = XAdESSigner.sha256Base64(unsigned)
        #expect(xml.contains("<ds:DigestValue>\(expected)</ds:DigestValue>"))

        // Usunięcie podpisu z gotowego dokumentu odtwarza dokładnie bajty,
        // z których policzono skrót (transformata enveloped + exc-c14n).
        let withoutDeclaration = xml.replacingOccurrences(of: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>", with: "")
        let start = try #require(withoutDeclaration.range(of: "<ds:Signature"))
        let end = try #require(withoutDeclaration.range(of: "</ds:Signature>"))
        var stripped = withoutDeclaration
        stripped.removeSubrange(start.lowerBound..<end.upperBound)
        #expect(stripped == unsigned)
    }

    @Test("Skrót SignedProperties liczony jest z ciągu obecnego w dokumencie")
    func signedPropertiesDigestMatches() throws {
        let certificate = try makeTestCertificate(nip: nip)
        let signingTime = Date(timeIntervalSince1970: 1_790_000_000)
        let xml = try XAdESSigner.signAuthTokenRequest(
            challenge: challenge, nip: nip, certificate: certificate, signingTime: signingTime
        )
        let info = try #require(certificate.info)
        let properties = XAdESSigner.canonicalSignedProperties(
            certificateDER: certificate.certificateDER,
            issuerName: info.issuerName,
            serialDecimal: info.serialNumberDecimal,
            signingTime: signingTime
        )
        // Dokument zawiera SignedProperties dokładnie w postaci kanonicznej...
        #expect(xml.contains(properties))
        // ...a jej skrót jest w drugiej referencji.
        #expect(xml.contains("<ds:DigestValue>\(XAdESSigner.sha256Base64(properties))</ds:DigestValue>"))
        // SignedProperties zawiera skrót certyfikatu i dane wystawcy.
        #expect(properties.contains(XAdESSigner.sha256Base64(certificate.certificateDER)))
        #expect(properties.contains("<ds:X509SerialNumber xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\">\(info.serialNumberDecimal)</ds:X509SerialNumber>"))
        #expect(properties.contains("<xades:SigningTime>2026-09-21T14:13:20Z</xades:SigningTime>"))
    }

    @Test("SignatureValue weryfikuje się kluczem publicznym nad kanonicznym SignedInfo")
    func signatureVerifies() throws {
        let certificate = try makeTestCertificate(nip: nip)
        let signingTime = Date(timeIntervalSince1970: 1_790_000_000)
        let xml = try XAdESSigner.signAuthTokenRequest(
            challenge: challenge, nip: nip, certificate: certificate, signingTime: signingTime
        )
        let info = try #require(certificate.info)

        // Rekonstrukcja kanonicznego SignedInfo z tych samych składników.
        let unsigned = XAdESSigner.unsignedDocument(challenge: challenge, nip: nip)
        let properties = XAdESSigner.canonicalSignedProperties(
            certificateDER: certificate.certificateDER,
            issuerName: info.issuerName,
            serialDecimal: info.serialNumberDecimal,
            signingTime: signingTime
        )
        let signedInfo = XAdESSigner.canonicalSignedInfo(
            documentDigest: XAdESSigner.sha256Base64(unsigned),
            signedPropertiesDigest: XAdESSigner.sha256Base64(properties)
        )
        // Dokument zawiera SignedInfo (bez powtórzonej deklaracji xmlns:ds).
        #expect(xml.contains(signedInfo.replacingOccurrences(
            of: "<ds:SignedInfo xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\">",
            with: "<ds:SignedInfo>"
        )))

        // Wyciągnięcie SignatureValue i weryfikacja RSA-SHA256.
        let valueStart = try #require(xml.range(of: "<ds:SignatureValue>"))
        let valueEnd = try #require(xml.range(of: "</ds:SignatureValue>"))
        let base64 = String(xml[valueStart.upperBound..<valueEnd.lowerBound])
        let signature = try #require(Data(base64Encoded: base64))

        let secCertificate = try #require(SecCertificateCreateWithData(nil, certificate.certificateDER as CFData))
        let publicKey = try #require(SecCertificateCopyKey(secCertificate))
        #expect(SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePKCS1v15SHA256,
            Data(signedInfo.utf8) as CFData, signature as CFData, nil
        ))
    }

    @Test("Znaki specjalne XML w treści są poprawnie uciekane")
    func escaping() {
        #expect(XAdESSigner.escape("A&B <C>") == "A&amp;B &lt;C&gt;")
    }
}

// MARK: - Uwierzytelnienie certyfikatem w usłudze

@Suite("KSeFService — uwierzytelnienie certyfikatem i fail-back do tokenu")
struct KSeFServiceCertificateAuthTests {

    private let nip = "5265877635"

    /// Trasy przepływu certyfikatowego (challenge → xades → polling → redeem).
    private func routeCertificateAuth(on transport: MockTransport) {
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.routeOK("auth/xades-signature", data: AuthFixtures.authInit)
        transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
        transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)
    }

    /// Trasy przepływu tokenowego (używane przy fail-backu).
    private func routeTokenAuth(on transport: MockTransport) {
        transport.routeOK("security/public-key-certificates", data: AuthFixtures.certificates)
        transport.routeOK("auth/ksef-token", data: AuthFixtures.authInit)
    }

    private func makeService(
        transport: MockTransport,
        certificate: KSeFCertificate?,
        token: String,
        keys: TestRSAKeyPair = TestRSAKeyPair()
    ) -> KSeFService {
        let service = KSeFService(
            environment: .test,
            nip: nip,
            authToken: token,
            certificate: certificate,
            transport: transport,
            publicKeyResolver: { _ in keys.publicKey }
        )
        service.pollInterval = 0
        return service
    }

    @Test("Certyfikat ma pierwszeństwo: podpisany XML trafia na /auth/xades-signature")
    func certificatePreferred() async throws {
        let certificate = try makeTestCertificate(nip: nip)
        let transport = MockTransport()
        routeCertificateAuth(on: transport)

        let service = makeService(transport: transport, certificate: certificate, token: "tok-abc")
        let token = try await service.authenticate()

        #expect(token == "ACCESS-JWT")
        #expect(service.lastAuthenticationMethod == .certificate)

        let request = try #require(transport.request(matching: "auth/xades-signature"))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/xml")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("<Challenge>20260611-CR-TEST</Challenge>"))
        #expect(body.contains("<Nip>\(nip)</Nip>"))
        #expect(body.contains("<ds:SignatureValue>"))

        // Ścieżka tokenowa nie została użyta.
        #expect(transport.request(matching: "security/public-key-certificates") == nil)
        #expect(transport.request(matching: "auth/ksef-token") == nil)
    }

    @Test("Certyfikat działa również bez skonfigurowanego tokenu")
    func certificateOnly() async throws {
        let certificate = try makeTestCertificate(nip: nip)
        let transport = MockTransport()
        routeCertificateAuth(on: transport)

        let service = makeService(transport: transport, certificate: certificate, token: "")
        #expect(try await service.authenticate() == "ACCESS-JWT")
    }

    @Test("Nieudane uwierzytelnienie certyfikatem wraca do tokenu KSeF")
    func failBackToToken() async throws {
        let certificate = try makeTestCertificate(nip: nip)
        let transport = MockTransport()
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        // Odrzucenie podpisu (np. certyfikat nieuznawany na produkcji).
        transport.route("auth/xades-signature") { _ in
            (400, Data(#"{"title":"Bad Request","detail":"Nieprawidłowy certyfikat"}"#.utf8))
        }
        routeTokenAuth(on: transport)
        transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
        transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)

        let service = makeService(transport: transport, certificate: certificate, token: "tok-abc")
        let token = try await service.authenticate()

        #expect(token == "ACCESS-JWT")
        #expect(service.lastAuthenticationMethod == .token)
        // Obie ścieżki zostały odwiedzone.
        #expect(transport.request(matching: "auth/xades-signature") != nil)
        #expect(transport.request(matching: "auth/ksef-token") != nil)
    }

    @Test("Bez tokenu błąd certyfikatu jest zgłaszany wprost (bez fail-backu)")
    func certificateFailureWithoutToken() async throws {
        let certificate = try makeTestCertificate(nip: nip)
        let transport = MockTransport()
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        transport.route("auth/xades-signature") { _ in
            (400, Data(#"{"title":"Bad Request","detail":"Nieprawidłowy certyfikat"}"#.utf8))
        }

        let service = makeService(transport: transport, certificate: certificate, token: "")
        await #expect(throws: KSeFError.badStatus(code: 400, message: "Nieprawidłowy certyfikat")) {
            try await service.authenticate()
        }
    }

    @Test("Przeterminowany certyfikat jest pomijany — od razu ścieżka tokenowa")
    func expiredCertificateSkipped() async throws {
        let key = try X509Builder.generateRSAKeyPair()
        let der = try X509Builder.makeSelfSignedCertificate(
            subject: [.countryName("PL"), .commonName("Wygasły"), .organizationIdentifier("VATPL-\(nip)")],
            privateKey: key,
            validFrom: Date(timeIntervalSinceNow: -400 * 86_400),
            validTo: Date(timeIntervalSinceNow: -30 * 86_400)
        )
        let expired = KSeFCertificate(certificateDER: der, privateKeyDER: try X509Builder.exportPrivateKey(key))

        let keys = TestRSAKeyPair()
        let transport = MockTransport()
        transport.routeOK("auth/challenge", data: AuthFixtures.challenge)
        routeTokenAuth(on: transport)
        transport.routeOK("auth/token/redeem", data: AuthFixtures.tokens)
        transport.routeOK("auth/AUTH-REF-1", data: AuthFixtures.authOK)

        let service = makeService(transport: transport, certificate: expired, token: "tok-abc", keys: keys)
        let token = try await service.authenticate()

        #expect(token == "ACCESS-JWT")
        #expect(service.lastAuthenticationMethod == .token)
        #expect(transport.request(matching: "auth/xades-signature") == nil)
    }

    @Test("Brak certyfikatu i tokenu zgłasza missingCredentials")
    func missingBoth() async {
        let transport = MockTransport()
        let service = makeService(transport: transport, certificate: nil, token: "")
        await #expect(throws: KSeFError.missingCredentials) {
            try await service.authenticate()
        }
        #expect(transport.requests.isEmpty)
    }
}

// MARK: - Test na żywo (opcjonalny, wyłącznie środowisko testowe)

/// Weryfikacja podpisu XAdES na żywym API — środowisko testowe akceptuje
/// certyfikaty self-signed, więc test dowodzi zgodności kanonikalizacji
/// i struktury podpisu z weryfikatorem KSeF. Wykonuje wyłącznie
/// uwierzytelnienie (odczyt); aktywuje się przez KSEF_LIVE_NIP przy
/// KSEF_LIVE_ENV=test.
@Suite("Uwierzytelnienie certyfikatem na żywo (opcjonalne)")
struct LiveCertificateAuthTests {

    static var liveNIP: String? {
        let env = ProcessInfo.processInfo.environment
        guard let nip = env["KSEF_LIVE_NIP"], !nip.isEmpty,
              (env["KSEF_LIVE_ENV"] ?? "") == "test" else { return nil }
        return nip
    }

    @Test("Pełne uwierzytelnienie XAdES certyfikatem self-signed na api-test", .enabled(if: liveNIP != nil))
    func liveCertificateAuthentication() async throws {
        let nip = try #require(Self.liveNIP)
        let key = try X509Builder.generateRSAKeyPair()
        let der = try X509Builder.makeSelfSignedCertificate(
            subject: [
                .countryName("PL"),
                .organizationName("Ksefiarz Test \(nip)"),
                .commonName("Ksefiarz Test \(nip)"),
                .organizationIdentifier("VATPL-\(nip)"),
            ],
            privateKey: key
        )
        let certificate = KSeFCertificate(
            certificateDER: der,
            privateKeyDER: try X509Builder.exportPrivateKey(key)
        )

        let service = KSeFService(environment: .test, nip: nip, authToken: "", certificate: certificate)
        let accessToken = try await service.authenticate()

        #expect(!accessToken.isEmpty)
        #expect(service.lastAuthenticationMethod == .certificate)
        print("Uwierzytelnienie certyfikatem na żywo: OK (token \(accessToken.prefix(16))…)")
    }

    @Test("Pełny cykl na api-test: wniosek o certyfikat KSeF i logowanie nim", .enabled(if: liveNIP != nil))
    func liveCertificateEnrollment() async throws {
        let nip = try #require(Self.liveNIP)

        // 1. Uwierzytelnienie XAdES certyfikatem self-signed (bootstrap).
        let key = try X509Builder.generateRSAKeyPair()
        let der = try X509Builder.makeSelfSignedCertificate(
            subject: [
                .countryName("PL"),
                .organizationName("Ksefiarz Test \(nip)"),
                .commonName("Ksefiarz Test \(nip)"),
                .organizationIdentifier("VATPL-\(nip)"),
            ],
            privateKey: key
        )
        let bootstrap = KSeFCertificate(
            certificateDER: der,
            privateKeyDER: try X509Builder.exportPrivateKey(key)
        )
        let service = KSeFService(environment: .test, nip: nip, authToken: "", certificate: bootstrap)

        // 2. Limity i wniosek o prawdziwy certyfikat KSeF typu 1.
        let limits = try await service.fetchCertificateLimits()
        print("Limity: canRequest=\(limits.canRequest), wnioski \(limits.enrollment.remaining)/\(limits.enrollment.limit), certyfikaty \(limits.certificate.remaining)/\(limits.certificate.limit)")
        try #require(limits.canRequest, "Podmiot nie może złożyć wniosku o certyfikat")

        let issued = try await service.requestCertificate(
            name: "Ksefiarz test e2e",
            type: .authentication
        )
        let info = try #require(issued.info)
        print("Wystawiony certyfikat: \(info.subjectSummary), seryjny \(issued.serialNumberHex), ważny do \(info.validTo)")
        #expect(info.isValid())
        #expect(issued.serialNumberHex.count == 16)

        // 3. Logowanie wystawionym certyfikatem KSeF.
        let certService = KSeFService(environment: .test, nip: nip, authToken: "", certificate: issued)
        let accessToken = try await certService.authenticate()
        #expect(!accessToken.isEmpty)
        #expect(certService.lastAuthenticationMethod == .certificate)
        print("Logowanie certyfikatem KSeF: OK")
    }
}
