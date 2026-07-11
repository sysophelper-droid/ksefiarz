import Foundation
import Security
import CryptoKit
import Testing
@testable import KsefiarzCore

// MARK: - Wniosek o certyfikat (enrollment)

@Suite("KSeFService — wniosek o certyfikat KSeF")
struct CertificateEnrollmentTests {

    private let enrollmentDataJSON = Data("""
    {
      "commonName": "Firma Kowalski Certyfikat",
      "countryName": "PL",
      "organizationName": "Firma Kowalski Sp. z o.o.",
      "organizationIdentifier": "7762811692"
    }
    """.utf8)

    /// Certyfikat „wystawiony przez KSeF" w odpowiedzi retrieve (atrapa).
    private func makeIssuedCertificateDER() throws -> Data {
        let key = try X509Builder.generateRSAKeyPair()
        return try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("Firma Kowalski Certyfikat"), .countryName("PL")],
            privateKey: key,
            validTo: .now.addingTimeInterval(2 * 365 * 86_400)
        )
    }

    private func makeService(transport: MockTransport) -> KSeFService {
        let keys = TestRSAKeyPair()
        let service = KSeFService(
            environment: .test,
            nip: "7762811692",
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

    @Test("Pełny wniosek: dane podmiotu → CSR → polling → pobranie certyfikatu")
    func fullEnrollment() async throws {
        let issuedDER = try makeIssuedCertificateDER()
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("certificates/enrollments/data", data: enrollmentDataJSON)
        transport.routeOK("certificates/enrollments/ENROLL-1", data: Data(
            #"{"requestDate":"2026-07-11T10:00:00Z","status":{"code":200,"description":"Wniosek obsłużony"},"certificateSerialNumber":"0321C82DA41B4362"}"#.utf8
        ))
        transport.routeOK("certificates/enrollments", data: Data(
            #"{"referenceNumber":"ENROLL-1","timestamp":"2026-07-11T10:00:00Z"}"#.utf8
        ))
        transport.routeOK("certificates/retrieve", data: Data("""
        {"certificates":[{"certificate":"\(issuedDER.base64EncodedString())","certificateName":"Ksefiarz","certificateSerialNumber":"0321C82DA41B4362","certificateType":"Authentication"}]}
        """.utf8))

        let service = makeService(transport: transport)
        let certificate = try await service.requestCertificate(name: "Ksefiarz auth", type: .authentication)

        #expect(certificate.certificateDER == issuedDER)
        #expect(certificate.serialNumberHex == "0321C82DA41B4362")
        #expect(certificate.keyType == .rsa)
        // Klucz prywatny jest funkcjonalny.
        #expect(throws: Never.self) { try certificate.privateKey() }

        // Żądanie wniosku: nazwa, typ i CSR z danymi podmiotu.
        let enrollRequest = try #require(transport.requests.first {
            ($0.url?.path ?? "").hasSuffix("certificates/enrollments") && $0.httpMethod == "POST"
        })
        let body = try JSONDecoder().decode(CapturedEnrollRequest.self, from: try #require(enrollRequest.httpBody))
        #expect(body.certificateName == "Ksefiarz auth")
        #expect(body.certificateType == "Authentication")

        // CSR: poprawny DER, podmiot dokładnie z danych enrollment.
        let csr = try #require(Data(base64Encoded: body.csr))
        let root = try #require(ASN1DER.readElement(csr))
        let parts = ASN1DER.children(of: root.content)
        #expect(parts.count == 3)
        let infoChildren = ASN1DER.children(of: parts[0].content)
        let dn = KSeFCertificate.distinguishedName(fromDERName: infoChildren[1])
        #expect(dn.contains("CN=Firma Kowalski Certyfikat"))
        #expect(dn.contains("O=Firma Kowalski Sp. z o.o."))
        #expect(dn.contains("2.5.4.97=7762811692"))
        #expect(dn.contains("C=PL"))

        // Retrieve pyta o właściwy numer seryjny.
        let retrieveRequest = try #require(transport.request(matching: "certificates/retrieve"))
        let retrieveBody = String(decoding: retrieveRequest.httpBody ?? Data(), as: UTF8.self)
        #expect(retrieveBody.contains("0321C82DA41B4362"))
    }

    @Test("Polling czeka na kod 200 (wniosek w realizacji)")
    func enrollmentPolling() async throws {
        let issuedDER = try makeIssuedCertificateDER()
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("certificates/enrollments/data", data: enrollmentDataJSON)
        var statusCalls = 0
        transport.route("certificates/enrollments/ENROLL-1") { _ in
            statusCalls += 1
            if statusCalls < 3 {
                return (200, Data(#"{"requestDate":"2026-07-11T10:00:00Z","status":{"code":100,"description":"Przyjęty"}}"#.utf8))
            }
            return (200, Data(#"{"requestDate":"2026-07-11T10:00:00Z","status":{"code":200,"description":"OK"},"certificateSerialNumber":"0321C82DA41B4362"}"#.utf8))
        }
        transport.routeOK("certificates/enrollments", data: Data(#"{"referenceNumber":"ENROLL-1"}"#.utf8))
        transport.routeOK("certificates/retrieve", data: Data("""
        {"certificates":[{"certificate":"\(issuedDER.base64EncodedString())","certificateName":"K","certificateSerialNumber":"0321C82DA41B4362","certificateType":"Offline"}]}
        """.utf8))

        let service = makeService(transport: transport)
        let certificate = try await service.requestCertificate(name: "Ksefiarz offline", type: .offline)
        #expect(statusCalls == 3)
        #expect(certificate.serialNumberHex == "0321C82DA41B4362")
    }

    @Test("Odrzucenie wniosku zgłasza czytelny błąd z opisem")
    func enrollmentRejected() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("certificates/enrollments/data", data: enrollmentDataJSON)
        transport.routeOK("certificates/enrollments/ENROLL-1", data: Data(
            #"{"requestDate":"2026-07-11T10:00:00Z","status":{"code":400,"description":"Wniosek odrzucony","details":["Osiągnięto dopuszczalny limit posiadanych certyfikatów."]}}"#.utf8
        ))
        transport.routeOK("certificates/enrollments", data: Data(#"{"referenceNumber":"ENROLL-1"}"#.utf8))

        let service = makeService(transport: transport)
        await #expect(throws: KSeFError.certificateEnrollmentFailed(
            "Wniosek odrzucony Osiągnięto dopuszczalny limit posiadanych certyfikatów."
        )) {
            _ = try await service.requestCertificate(name: "Ksefiarz auth", type: .authentication)
        }
    }

    @Test("Limity certyfikatów dekodują się z odpowiedzi API")
    func certificateLimits() async throws {
        let transport = MockTransport()
        routeAuth(on: transport)
        transport.routeOK("certificates/limits", data: Data(
            #"{"canRequest":true,"enrollment":{"remaining":298,"limit":300},"certificate":{"remaining":99,"limit":100}}"#.utf8
        ))
        let service = makeService(transport: transport)
        let limits = try await service.fetchCertificateLimits()
        #expect(limits.canRequest)
        #expect(limits.enrollment.remaining == 298)
        #expect(limits.certificate.limit == 100)
    }
}

private struct CapturedEnrollRequest: Decodable {
    let certificateName: String
    let certificateType: String
    let csr: String
}

// MARK: - Import z pliku

@Suite("KSeFCertificateImporter — import certyfikatu z pliku")
struct CertificateImportTests {

    private func pem(_ name: String, _ der: Data) -> String {
        let base64 = der.base64EncodedString(options: [.lineLength64Characters])
        return "-----BEGIN \(name)-----\n\(base64)\n-----END \(name)-----\n"
    }

    @Test("PEM: certyfikat RSA + klucz PKCS#1")
    func pemRSAPKCS1() throws {
        let key = try X509Builder.generateRSAKeyPair()
        let certDER = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("Import RSA"), .countryName("PL")],
            privateKey: key
        )
        let keyDER = try X509Builder.exportPrivateKey(key)

        let imported = try KSeFCertificateImporter.importPEM(
            certificatePEM: pem("CERTIFICATE", certDER),
            privateKeyPEM: pem("RSA PRIVATE KEY", keyDER)
        )
        #expect(imported.certificateDER == certDER)
        #expect(imported.keyType == .rsa)
        #expect(imported.info?.subjectSummary.contains("Import RSA") == true)
    }

    @Test("PEM: klucz RSA w kopercie PKCS#8")
    func pemRSAPKCS8() throws {
        let key = try X509Builder.generateRSAKeyPair()
        let certDER = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("Import PKCS8"), .countryName("PL")],
            privateKey: key
        )
        let pkcs1 = try X509Builder.exportPrivateKey(key)
        let pkcs8 = ASN1DER.sequence([
            ASN1DER.integer(0),
            ASN1DER.sequence([ASN1DER.objectIdentifier("1.2.840.113549.1.1.1"), ASN1DER.null()]),
            ASN1DER.octetString(pkcs1),
        ])

        let imported = try KSeFCertificateImporter.importPEM(
            certificatePEM: pem("CERTIFICATE", certDER),
            privateKeyPEM: pem("PRIVATE KEY", pkcs8)
        )
        #expect(imported.keyType == .rsa)
        #expect(imported.privateKeyDER == pkcs1)
    }

    @Test("PEM: certyfikat EC P-256 + klucz SEC1 (bez osadzonego klucza publicznego)")
    func pemECSEC1() throws {
        let key = try X509Builder.generateECKeyPair()
        let certDER = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("Import EC"), .countryName("PL")],
            privateKey: key,
            keyType: .ec
        )
        // Skalar z surowej postaci SecKey: 04‖X‖Y‖K → K to ostatnie 32 bajty.
        let raw = try X509Builder.exportPrivateKey(key)
        let scalar = raw.suffix(32)
        // SEC1 tylko z wersją i skalarem — część publiczna do wyprowadzenia.
        let sec1 = ASN1DER.sequence([
            ASN1DER.integer(1),
            ASN1DER.octetString(Data(scalar)),
        ])

        let imported = try KSeFCertificateImporter.importPEM(
            certificatePEM: pem("CERTIFICATE", certDER),
            privateKeyPEM: pem("EC PRIVATE KEY", sec1)
        )
        #expect(imported.keyType == .ec)
        #expect(imported.privateKeyDER == raw)
        #expect(imported.info?.subjectSummary.contains("Import EC") == true)
    }

    @Test("PEM: klucz EC w kopercie PKCS#8")
    func pemECPKCS8() throws {
        let key = try X509Builder.generateECKeyPair()
        let certDER = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("Import EC PKCS8"), .countryName("PL")],
            privateKey: key,
            keyType: .ec
        )
        let raw = try X509Builder.exportPrivateKey(key)
        let scalar = raw.suffix(32)
        let sec1 = ASN1DER.sequence([
            ASN1DER.integer(1),
            ASN1DER.octetString(Data(scalar)),
        ])
        let pkcs8 = ASN1DER.sequence([
            ASN1DER.integer(0),
            ASN1DER.sequence([
                ASN1DER.objectIdentifier("1.2.840.10045.2.1"),
                ASN1DER.objectIdentifier("1.2.840.10045.3.1.7"),
            ]),
            ASN1DER.octetString(sec1),
        ])

        let imported = try KSeFCertificateImporter.importPEM(
            certificatePEM: pem("CERTIFICATE", certDER),
            privateKeyPEM: pem("PRIVATE KEY", pkcs8)
        )
        #expect(imported.keyType == .ec)
        #expect(imported.privateKeyDER == raw)
    }

    @Test("Import odrzuca klucz niepasujący do certyfikatu")
    func keyMismatch() throws {
        let certKey = try X509Builder.generateRSAKeyPair()
        let otherKey = try X509Builder.generateRSAKeyPair()
        let certDER = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("Para"), .countryName("PL")],
            privateKey: certKey
        )
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.importPEM(
                certificatePEM: pem("CERTIFICATE", certDER),
                privateKeyPEM: pem("RSA PRIVATE KEY", try X509Builder.exportPrivateKey(otherKey))
            )
        }
    }

    @Test("Czytelne błędy przy brakujących blokach PEM")
    func missingBlocks() {
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.importPEM(certificatePEM: "puste", privateKeyPEM: "puste")
        }
    }

    @Test("Podpis XAdES certyfikatem EC weryfikuje się (ECDSA R‖S)")
    func xadesWithECKey() throws {
        let key = try X509Builder.generateECKeyPair()
        let certDER = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("EC XAdES"), .countryName("PL"), .organizationIdentifier("VATPL-1111111111")],
            privateKey: key,
            keyType: .ec
        )
        let certificate = KSeFCertificate(
            certificateDER: certDER,
            privateKeyDER: try X509Builder.exportPrivateKey(key),
            keyType: .ec
        )
        let xml = try XAdESSigner.signAuthTokenRequest(
            challenge: "20260711-CR-1234567890-ABCDEF0123-45",
            nip: "1111111111",
            certificate: certificate
        )
        #expect(xml.contains("Algorithm=\"http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256\""))

        // Podpis: R‖S (64 bajty) — weryfikacja wymaga konwersji do DER.
        let valueStart = try #require(xml.range(of: "<ds:SignatureValue>"))
        let valueEnd = try #require(xml.range(of: "</ds:SignatureValue>"))
        let signature = try #require(Data(base64Encoded: String(xml[valueStart.upperBound..<valueEnd.lowerBound])))
        #expect(signature.count == 64)

        // Weryfikacja przez CryptoKit (przyjmuje postać surową R‖S).
        let secCertificate = try #require(SecCertificateCreateWithData(nil, certDER as CFData))
        let publicKeySec = try #require(SecCertificateCopyKey(secCertificate))
        let publicKeyData = try #require(SecKeyCopyExternalRepresentation(publicKeySec, nil)) as Data
        let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
        let ecdsaSignature = try P256.Signing.ECDSASignature(rawRepresentation: signature)

        // Zrekonstruowane SignedInfo — takie samo jak przy podpisywaniu.
        let signedInfoStart = try #require(xml.range(of: "<ds:SignedInfo>"))
        let signedInfoEnd = try #require(xml.range(of: "</ds:SignedInfo>"))
        let inlineSignedInfo = String(xml[signedInfoStart.lowerBound..<signedInfoEnd.upperBound])
        let canonical = inlineSignedInfo.replacingOccurrences(
            of: "<ds:SignedInfo>",
            with: "<ds:SignedInfo xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\">"
        )
        #expect(publicKey.isValidSignature(ecdsaSignature, for: Data(canonical.utf8)))
    }
}
