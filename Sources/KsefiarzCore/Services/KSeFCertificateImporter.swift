import Foundation
import Security
import CryptoKit

/// Import certyfikatu KSeF z pliku — ścieżka dla certyfikatów pozyskanych
/// poza aplikacją (np. w Aplikacji Podatnika KSeF 2.0). Obsługiwane formaty:
/// - PKCS#12 (.p12/.pfx) z hasłem,
/// - para PEM: certyfikat + klucz prywatny (PKCS#1, PKCS#8 lub SEC1/EC).
public enum KSeFCertificateImporter {

    public enum ImportError: LocalizedError {
        case invalidPKCS12(String)
        case invalidPEM(String)
        case unsupportedKey(String)
        case keyMismatch
        case encryptedKeyNeedsPassword
        case keyDecryptionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidPKCS12(let details):
                return "Nie udało się odczytać pliku PKCS#12: \(details)"
            case .invalidPEM(let details):
                return "Nie udało się odczytać pliku PEM: \(details)"
            case .unsupportedKey(let details):
                return "Nieobsługiwany rodzaj klucza prywatnego: \(details)"
            case .keyMismatch:
                return "Klucz prywatny nie pasuje do certyfikatu."
            case .encryptedKeyNeedsPassword:
                return "Klucz prywatny jest zaszyfrowany — podaj hasło do jego odszyfrowania."
            case .keyDecryptionFailed(let details):
                return "Nie udało się odszyfrować klucza prywatnego: \(details)"
            }
        }
    }

    // MARK: PKCS#12

    /// Importuje tożsamość (certyfikat + klucz) z danych PKCS#12.
    public static func importPKCS12(data: Data, password: String) throws -> KSeFCertificate {
        var items: CFArray?
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        let status = SecPKCS12Import(data as CFData, options, &items)
        guard status == errSecSuccess else {
            let message = status == errSecAuthFailed || status == errSecPkcs12VerifyFailure
                ? "nieprawidłowe hasło"
                : "kod błędu \(status)"
            throw ImportError.invalidPKCS12(message)
        }
        guard let array = items as? [[String: Any]],
              let first = array.first,
              let identity = first[kSecImportItemIdentity as String] else {
            throw ImportError.invalidPKCS12("plik nie zawiera tożsamości (certyfikat + klucz)")
        }
        // swiftlint:disable:next force_cast
        let secIdentity = identity as! SecIdentity

        var certificateRef: SecCertificate?
        guard SecIdentityCopyCertificate(secIdentity, &certificateRef) == errSecSuccess,
              let certificate = certificateRef else {
            throw ImportError.invalidPKCS12("brak certyfikatu w tożsamości")
        }
        var keyRef: SecKey?
        guard SecIdentityCopyPrivateKey(secIdentity, &keyRef) == errSecSuccess,
              let privateKey = keyRef else {
            throw ImportError.invalidPKCS12("brak klucza prywatnego w tożsamości")
        }

        let certificateDER = SecCertificateCopyData(certificate) as Data
        let keyType = try keyType(ofCertificate: certificate)
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(privateKey, &error) else {
            let details = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "klucz nieeksportowalny"
            throw ImportError.invalidPKCS12(details)
        }

        // SecPKCS12Import mógł dodać elementy do pęku kluczy — sprzątamy,
        // bo certyfikat trzymamy we własnym wpisie (JSON w generic password).
        SecItemDelete([kSecValueRef as String: secIdentity] as CFDictionary)
        SecItemDelete([kSecValueRef as String: certificate] as CFDictionary)
        SecItemDelete([kSecValueRef as String: privateKey] as CFDictionary)

        return try validated(KSeFCertificate(
            certificateDER: certificateDER,
            privateKeyDER: keyData as Data,
            keyType: keyType
        ))
    }

    // MARK: PEM

    /// Importuje certyfikat i klucz prywatny z treści plików PEM.
    /// Oba bloki mogą być w jednym pliku — wtedy przekaż tę samą treść dwa razy.
    /// `password` jest wymagane tylko dla zaszyfrowanego klucza
    /// (`ENCRYPTED PRIVATE KEY`, PKCS#8/PBES2) — np. wydawanego przez KSeF.
    public static func importPEM(
        certificatePEM: String,
        privateKeyPEM: String,
        password: String? = nil
    ) throws -> KSeFCertificate {
        guard let certificateDER = pemBlock(named: "CERTIFICATE", in: certificatePEM) else {
            throw ImportError.invalidPEM("brak bloku CERTIFICATE")
        }
        guard SecCertificateCreateWithData(nil, certificateDER as CFData) != nil else {
            throw ImportError.invalidPEM("nieprawidłowa treść certyfikatu")
        }

        let (keyData, keyType) = try decodePrivateKeyPEM(privateKeyPEM, password: password)
        return try validated(KSeFCertificate(
            certificateDER: certificateDER,
            privateKeyDER: keyData,
            keyType: keyType
        ))
    }

    /// Rozpoznaje i dekoduje klucz prywatny z PEM do postaci akceptowanej
    /// przez SecKey (RSA: PKCS#1; EC: 04‖X‖Y‖K). Zaszyfrowany klucz PKCS#8
    /// (`ENCRYPTED PRIVATE KEY`) jest najpierw odszyfrowywany hasłem.
    static func decodePrivateKeyPEM(_ pem: String, password: String? = nil) throws -> (Data, KSeFKeyType) {
        if let encrypted = pemBlock(named: "ENCRYPTED PRIVATE KEY", in: pem) {
            guard let password, !password.isEmpty else {
                throw ImportError.encryptedKeyNeedsPassword
            }
            let decrypted: Data
            do {
                decrypted = try PKCS8EncryptedKey.decrypt(encrypted, password: password)
            } catch let error as PKCS8EncryptedKey.DecryptError {
                throw ImportError.keyDecryptionFailed(error.errorDescription ?? "nieznany błąd")
            }
            return try decodePKCS8(decrypted)
        }
        if let rsa = pemBlock(named: "RSA PRIVATE KEY", in: pem) {
            return (rsa, .rsa)
        }
        if let sec1 = pemBlock(named: "EC PRIVATE KEY", in: pem) {
            return (try ecRawKey(fromSEC1: sec1), .ec)
        }
        if let pkcs8 = pemBlock(named: "PRIVATE KEY", in: pem) {
            return try decodePKCS8(pkcs8)
        }
        throw ImportError.invalidPEM("brak bloku PRIVATE KEY")
    }

    /// PKCS#8: SEQUENCE { wersja, AlgorithmIdentifier, OCTET STRING klucz }.
    static func decodePKCS8(_ der: Data) throws -> (Data, KSeFKeyType) {
        guard let root = ASN1DER.readElement(der), root.tag == 0x30 else {
            throw ImportError.invalidPEM("nieprawidłowa struktura PKCS#8")
        }
        let fields = ASN1DER.children(of: root.content)
        guard fields.count >= 3, fields[2].tag == 0x04,
              let algorithm = ASN1DER.children(of: fields[1].content).first else {
            throw ImportError.invalidPEM("nieprawidłowa struktura PKCS#8")
        }
        let rsaOID = ASN1DER.objectIdentifier("1.2.840.113549.1.1.1").dropFirst(2)
        let ecOID = ASN1DER.objectIdentifier("1.2.840.10045.2.1").dropFirst(2)
        if algorithm.content == Data(rsaOID) {
            return (fields[2].content, .rsa)
        }
        if algorithm.content == Data(ecOID) {
            return (try ecRawKey(fromSEC1: fields[2].content), .ec)
        }
        throw ImportError.unsupportedKey("obsługiwane są klucze RSA i EC P-256")
    }

    /// SEC1 ECPrivateKey → surowa postać SecKey (04‖X‖Y‖K). Część publiczna
    /// jest wyprowadzana z klucza prywatnego (CryptoKit P-256), więc plik
    /// bez osadzonego klucza publicznego również działa.
    static func ecRawKey(fromSEC1 der: Data) throws -> Data {
        guard let root = ASN1DER.readElement(der), root.tag == 0x30 else {
            throw ImportError.invalidPEM("nieprawidłowa struktura klucza EC")
        }
        let fields = ASN1DER.children(of: root.content)
        guard fields.count >= 2, fields[0].tag == 0x02, fields[1].tag == 0x04 else {
            throw ImportError.invalidPEM("nieprawidłowa struktura klucza EC")
        }
        let scalar = fields[1].content
        guard let key = try? P256.Signing.PrivateKey(rawRepresentation: scalar) else {
            throw ImportError.unsupportedKey("klucz EC spoza krzywej P-256")
        }
        return key.publicKey.x963Representation + scalar
    }

    // MARK: Pomocnicze

    /// Wycina i dekoduje blok PEM o podanej nazwie.
    static func pemBlock(named name: String, in pem: String) -> Data? {
        let begin = "-----BEGIN \(name)-----"
        let end = "-----END \(name)-----"
        guard let beginRange = pem.range(of: begin),
              let endRange = pem.range(of: end),
              beginRange.upperBound <= endRange.lowerBound else { return nil }
        let base64 = pem[beginRange.upperBound..<endRange.lowerBound]
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        return Data(base64Encoded: base64)
    }

    /// Rodzaj klucza publicznego certyfikatu.
    static func keyType(ofCertificate certificate: SecCertificate) throws -> KSeFKeyType {
        guard let publicKey = SecCertificateCopyKey(certificate),
              let attributes = SecKeyCopyAttributes(publicKey) as? [String: Any],
              let type = attributes[kSecAttrKeyType as String] as? String else {
            throw ImportError.invalidPEM("nie udało się odczytać klucza publicznego certyfikatu")
        }
        if type == (kSecAttrKeyTypeRSA as String) { return .rsa }
        if type == (kSecAttrKeyTypeECSECPrimeRandom as String) { return .ec }
        throw ImportError.unsupportedKey("certyfikat z kluczem innym niż RSA/EC")
    }

    /// Weryfikuje, że klucz prywatny pasuje do certyfikatu (podpis próbny).
    static func validated(_ certificate: KSeFCertificate) throws -> KSeFCertificate {
        guard let secCertificate = SecCertificateCreateWithData(nil, certificate.certificateDER as CFData),
              let publicKey = SecCertificateCopyKey(secCertificate) else {
            throw ImportError.invalidPEM("nieprawidłowa treść certyfikatu")
        }
        let sample = Data("ksefiarz-weryfikacja-pary-kluczy".utf8)
        let privateKey = try certificate.privateKey()
        let algorithm: SecKeyAlgorithm = certificate.keyType == .rsa
            ? .rsaSignatureMessagePKCS1v15SHA256
            : .ecdsaSignatureMessageX962SHA256
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, algorithm, sample as CFData, &error),
              SecKeyVerifySignature(publicKey, algorithm, sample as CFData, signature, nil) else {
            throw ImportError.keyMismatch
        }
        return certificate
    }
}
