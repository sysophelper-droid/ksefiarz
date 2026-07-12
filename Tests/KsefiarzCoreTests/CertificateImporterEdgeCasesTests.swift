import Foundation
import Security
import CryptoKit
import Testing
@testable import KsefiarzCore

// Ścieżki brzegowe importera certyfikatu KSeF: błędne struktury DER,
// nieobsługiwane klucze, uszkodzony PKCS#12 oraz rozpoznanie typu klucza
// z certyfikatu. Uzupełnia „szczęśliwe" testy z CertificateEnrollmentAndImportTests.

@Suite("Import certyfikatu — struktury błędne i rozpoznanie klucza")
struct CertificateImporterEdgeCasesTests {

    // MARK: Pomocnicze — minimalne kodowanie DER (długość < 128 bajtów)

    private func der(_ tag: UInt8, _ content: Data) -> Data {
        Data([tag, UInt8(content.count)]) + content
    }
    private func der(_ tag: UInt8, _ bytes: [UInt8]) -> Data { der(tag, Data(bytes)) }

    // MARK: errorDescription

    @Test("ImportError — wszystkie warianty mają niepusty, konkretny opis")
    func importErrorDescriptions() {
        let cases: [KSeFCertificateImporter.ImportError] = [
            .invalidPKCS12("szczegóły"), .invalidPEM("szczegóły"),
            .unsupportedKey("szczegóły"), .keyMismatch,
            .encryptedKeyNeedsPassword, .keyDecryptionFailed("szczegóły"),
        ]
        for error in cases {
            #expect(error.errorDescription?.isEmpty == false)
        }
        #expect(KSeFCertificateImporter.ImportError.invalidPKCS12("XYZ")
            .errorDescription?.contains("XYZ") == true)
    }

    // MARK: PKCS#12

    @Test("importPKCS12 — uszkodzone dane zgłaszają invalidPKCS12")
    func pkcs12Garbage() {
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.importPKCS12(
                data: Data([0x00, 0x01, 0x02, 0x03, 0x04]),
                password: "bez-znaczenia"
            )
        }
    }

    // MARK: decodePrivateKeyPEM

    @Test("decodePrivateKeyPEM — brak rozpoznanego bloku klucza")
    func brakBlokuKlucza() {
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.decodePrivateKeyPEM("zupełnie pusty tekst")
        }
    }

    @Test("importPEM — poprawny nagłówek CERTIFICATE, ale nieprawidłowa treść DER")
    func certyfikatZlyDER() {
        let fakeCert = """
        -----BEGIN CERTIFICATE-----
        \(Data([0x00, 0x01, 0x02, 0x03]).base64EncodedString())
        -----END CERTIFICATE-----
        """
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.importPEM(
                certificatePEM: fakeCert,
                privateKeyPEM: "-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----"
            )
        }
    }

    // MARK: decodePKCS8 — błędne struktury

    @Test("decodePKCS8 — element niebędący SEQUENCE")
    func pkcs8NieSequence() {
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.decodePKCS8(der(0x02, [0x00]))
        }
    }

    @Test("decodePKCS8 — SEQUENCE z niepełnym zestawem pól")
    func pkcs8ZaMaloPol() {
        let root = der(0x30, der(0x02, [0x00])) // tylko wersja
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.decodePKCS8(root)
        }
    }

    @Test("decodePKCS8 — nieobsługiwany algorytm klucza (nie RSA/EC)")
    func pkcs8NieznanyAlgorytm() {
        let version = der(0x02, [0x00])
        let bogusOID = ASN1DER.objectIdentifier("1.3.6.1.4.1.99999") // dowolny, nie RSA/EC
        let algorithm = der(0x30, bogusOID)
        let key = der(0x04, Data())
        let root = der(0x30, version + algorithm + key)
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.decodePKCS8(root)
        }
    }

    // MARK: ecRawKey — błędne struktury

    @Test("ecRawKey — element niebędący SEQUENCE")
    func ecNieSequence() {
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.ecRawKey(fromSEC1: der(0x02, [0x00]))
        }
    }

    @Test("ecRawKey — SEQUENCE z niepełnym zestawem pól")
    func ecZaMaloPol() {
        let root = der(0x30, der(0x02, [0x01]))
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.ecRawKey(fromSEC1: root)
        }
    }

    @Test("ecRawKey — skalar spoza krzywej P-256 (zła długość)")
    func ecZlyScalar() {
        // SEQUENCE { INTEGER wersja, OCTET STRING skalar 10 bajtów }
        let root = der(0x30, der(0x02, [0x01]) + der(0x04, Data(repeating: 0x11, count: 10)))
        #expect(throws: KSeFCertificateImporter.ImportError.self) {
            _ = try KSeFCertificateImporter.ecRawKey(fromSEC1: root)
        }
    }

    // MARK: keyType(ofCertificate:)

    @Test("keyType — certyfikat RSA rozpoznany jako .rsa")
    func keyTypeRSA() throws {
        let key = try X509Builder.generateRSAKeyPair()
        let certDER = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("RSA Test"), .countryName("PL")],
            privateKey: key
        )
        let certificate = SecCertificateCreateWithData(nil, certDER as CFData)!
        #expect(try KSeFCertificateImporter.keyType(ofCertificate: certificate) == .rsa)
    }

    @Test("keyType — certyfikat EC rozpoznany jako .ec")
    func keyTypeEC() throws {
        let key = try X509Builder.generateECKeyPair()
        let certDER = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("EC Test"), .countryName("PL")],
            privateKey: key,
            keyType: .ec
        )
        let certificate = SecCertificateCreateWithData(nil, certDER as CFData)!
        #expect(try KSeFCertificateImporter.keyType(ofCertificate: certificate) == .ec)
    }
}
