import Foundation
import Testing
@testable import KsefiarzCore

// MARK: - Odszyfrowanie zaszyfrowanego klucza PKCS#8 (PBES2)

@Suite("PKCS8EncryptedKey — odszyfrowanie klucza PBES2")
struct PKCS8EncryptedKeyTests {

    private func der(_ base64: String) -> Data { Data(base64Encoded: base64)! }

    @Test("EC P-256, PBKDF2-SHA256 + AES-256-CBC — odszyfrowany klucz to poprawny PKCS#8")
    func decryptECSHA256() throws {
        let decrypted = try PKCS8EncryptedKey.decrypt(
            der(EncryptedKeyFixtures.ecEncSHA256),
            password: EncryptedKeyFixtures.password
        )
        let (_, keyType) = try KSeFCertificateImporter.decodePKCS8(decrypted)
        #expect(keyType == .ec)
    }

    @Test("EC, domyślny PRF (HMAC-SHA1) — obsługiwany")
    func decryptECSHA1() throws {
        let decrypted = try PKCS8EncryptedKey.decrypt(
            der(EncryptedKeyFixtures.ecEncSHA1),
            password: EncryptedKeyFixtures.password
        )
        let (_, keyType) = try KSeFCertificateImporter.decodePKCS8(decrypted)
        #expect(keyType == .ec)
    }

    @Test("EC, szyfr AES-128-CBC — obsługiwany (klucz 16 bajtów)")
    func decryptECAES128() throws {
        let decrypted = try PKCS8EncryptedKey.decrypt(
            der(EncryptedKeyFixtures.ecEncAES128),
            password: EncryptedKeyFixtures.password
        )
        let (_, keyType) = try KSeFCertificateImporter.decodePKCS8(decrypted)
        #expect(keyType == .ec)
    }

    @Test("RSA-2048, PBKDF2-SHA256 + AES-256-CBC — obsługiwany")
    func decryptRSASHA256() throws {
        let decrypted = try PKCS8EncryptedKey.decrypt(
            der(EncryptedKeyFixtures.rsaEncSHA256),
            password: EncryptedKeyFixtures.password
        )
        let (_, keyType) = try KSeFCertificateImporter.decodePKCS8(decrypted)
        #expect(keyType == .rsa)
    }

    @Test("Błędne hasło zgłasza błąd (bez zwrócenia śmieci)", arguments: [
        "zle-haslo", "niepoprawne", "x", "TestHaslo124", "aaaaaaaa", "12345678",
    ])
    func wrongPasswordThrows(_ password: String) {
        #expect(throws: PKCS8EncryptedKey.DecryptError.self) {
            try PKCS8EncryptedKey.decrypt(
                der(EncryptedKeyFixtures.ecEncSHA256),
                password: password
            )
        }
    }

    @Test("Absurdalna liczba iteracji jest odrzucana (ochrona przed zawieszeniem)")
    func rejectsHugeIterationCount() {
        // Ręcznie zbudowana struktura PBES2 z liczbą iteracji > 10 mln —
        // parser powinien odmówić PRZED uruchomieniem PBKDF2.
        let oid = { (dotted: String) in ASN1DER.objectIdentifier(dotted) }
        let pbkdf2Params = ASN1DER.sequence([
            ASN1DER.octetString(Data(repeating: 0xAB, count: 16)),
            ASN1DER.integer(20_000_000),
        ])
        let kdf = ASN1DER.sequence([oid("1.2.840.113549.1.5.12"), pbkdf2Params])
        let cipher = ASN1DER.sequence([
            oid("2.16.840.1.101.3.4.1.42"),
            ASN1DER.octetString(Data(repeating: 0, count: 16)),
        ])
        let algorithm = ASN1DER.sequence([
            oid("1.2.840.113549.1.5.13"),
            ASN1DER.sequence([kdf, cipher]),
        ])
        let encryptedInfo = ASN1DER.sequence([algorithm, ASN1DER.octetString(Data(count: 16))])

        #expect(throws: PKCS8EncryptedKey.DecryptError.self) {
            try PKCS8EncryptedKey.decrypt(encryptedInfo, password: "cokolwiek")
        }
    }
}

// MARK: - Import certyfikatu KSeF z zaszyfrowanym kluczem

@Suite("KSeFCertificateImporter — certyfikat + zaszyfrowany klucz")
struct EncryptedKeyImportTests {

    private func certPEM(_ base64: String) -> String {
        EncryptedKeyFixtures.pem("CERTIFICATE", base64)
    }
    private func encKeyPEM(_ base64: String) -> String {
        EncryptedKeyFixtures.pem("ENCRYPTED PRIVATE KEY", base64)
    }

    @Test("EC: import z hasłem daje zweryfikowaną parę certyfikat–klucz")
    func importEC() throws {
        let certificate = try KSeFCertificateImporter.importPEM(
            certificatePEM: certPEM(EncryptedKeyFixtures.ecCertDER),
            privateKeyPEM: encKeyPEM(EncryptedKeyFixtures.ecEncSHA256),
            password: EncryptedKeyFixtures.password
        )
        #expect(certificate.keyType == .ec)
        #expect(throws: Never.self) { try certificate.privateKey() }
    }

    @Test("RSA: import z hasłem daje zweryfikowaną parę certyfikat–klucz")
    func importRSA() throws {
        let certificate = try KSeFCertificateImporter.importPEM(
            certificatePEM: certPEM(EncryptedKeyFixtures.rsaCertDER),
            privateKeyPEM: encKeyPEM(EncryptedKeyFixtures.rsaEncSHA256),
            password: EncryptedKeyFixtures.password
        )
        #expect(certificate.keyType == .rsa)
    }

    @Test("Cert i klucz w jednym pliku PEM — działa")
    func importCombinedPEM() throws {
        let combined = certPEM(EncryptedKeyFixtures.ecCertDER) + encKeyPEM(EncryptedKeyFixtures.ecEncSHA256)
        let certificate = try KSeFCertificateImporter.importPEM(
            certificatePEM: combined,
            privateKeyPEM: combined,
            password: EncryptedKeyFixtures.password
        )
        #expect(certificate.keyType == .ec)
    }

    @Test("Brak hasła dla zaszyfrowanego klucza — czytelny błąd")
    func missingPasswordThrows() throws {
        do {
            _ = try KSeFCertificateImporter.importPEM(
                certificatePEM: certPEM(EncryptedKeyFixtures.ecCertDER),
                privateKeyPEM: encKeyPEM(EncryptedKeyFixtures.ecEncSHA256)
            )
            Issue.record("Import bez hasła powinien rzucić błąd.")
        } catch let error as KSeFCertificateImporter.ImportError {
            guard case .encryptedKeyNeedsPassword = error else {
                Issue.record("Oczekiwano encryptedKeyNeedsPassword, otrzymano: \(error)")
                return
            }
        }
    }

    @Test("Puste hasło traktowane jak brak hasła")
    func emptyPasswordThrows() throws {
        do {
            _ = try KSeFCertificateImporter.importPEM(
                certificatePEM: certPEM(EncryptedKeyFixtures.ecCertDER),
                privateKeyPEM: encKeyPEM(EncryptedKeyFixtures.ecEncSHA256),
                password: ""
            )
            Issue.record("Import z pustym hasłem powinien rzucić błąd.")
        } catch let error as KSeFCertificateImporter.ImportError {
            guard case .encryptedKeyNeedsPassword = error else {
                Issue.record("Oczekiwano encryptedKeyNeedsPassword, otrzymano: \(error)")
                return
            }
        }
    }

    @Test("Błędne hasło zgłasza błąd deszyfrowania klucza")
    func wrongPasswordThrows() throws {
        do {
            _ = try KSeFCertificateImporter.importPEM(
                certificatePEM: certPEM(EncryptedKeyFixtures.ecCertDER),
                privateKeyPEM: encKeyPEM(EncryptedKeyFixtures.ecEncSHA256),
                password: "niepoprawne"
            )
            Issue.record("Import z błędnym hasłem powinien rzucić błąd.")
        } catch let error as KSeFCertificateImporter.ImportError {
            guard case .keyDecryptionFailed = error else {
                Issue.record("Oczekiwano keyDecryptionFailed, otrzymano: \(error)")
                return
            }
        }
    }
}
