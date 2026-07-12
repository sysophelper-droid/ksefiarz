import Foundation
import CommonCrypto

/// Odszyfrowanie zaszyfrowanego klucza prywatnego PKCS#8
/// (`EncryptedPrivateKeyInfo`) — format wydawany m.in. przez KSeF razem
/// z certyfikatem `.crt`. Obsługiwany schemat: **PBES2** (RFC 8018) —
/// wyprowadzenie klucza PBKDF2 (HMAC-SHA1/224/256/384/512) i szyfr
/// AES-128/192/256-CBC. Wynik to niezaszyfrowany `PrivateKeyInfo` (DER),
/// który dalej rozpoznaje `KSeFCertificateImporter.decodePKCS8`.
enum PKCS8EncryptedKey {

    enum DecryptError: LocalizedError, Equatable {
        case malformed(String)
        case unsupportedScheme(String)
        case wrongPassword

        var errorDescription: String? {
            switch self {
            case .malformed(let details):
                return "Nieprawidłowa struktura zaszyfrowanego klucza PKCS#8: \(details)"
            case .unsupportedScheme(let details):
                return "Nieobsługiwany sposób szyfrowania klucza prywatnego: \(details)"
            case .wrongPassword:
                return "Nie udało się odszyfrować klucza prywatnego — najprawdopodobniej błędne hasło."
            }
        }
    }

    /// Zwraca odszyfrowany `PrivateKeyInfo` (PKCS#8) w postaci DER.
    static func decrypt(_ der: Data, password: String) throws -> Data {
        // EncryptedPrivateKeyInfo ::= SEQUENCE { encryptionAlgorithm, encryptedData OCTET STRING }
        guard let root = ASN1DER.readElement(der), root.tag == 0x30 else {
            throw DecryptError.malformed("brak nadrzędnego SEQUENCE")
        }
        let top = ASN1DER.children(of: root.content)
        guard top.count >= 2, top[0].tag == 0x30, top[1].tag == 0x04 else {
            throw DecryptError.malformed("oczekiwano algorytmu i zaszyfrowanych danych")
        }
        let algorithm = ASN1DER.children(of: top[0].content)
        let encryptedData = top[1].content
        guard let schemeOID = algorithm.first, schemeOID.tag == 0x06 else {
            throw DecryptError.malformed("brak identyfikatora algorytmu")
        }
        // PBES2 = 1.2.840.113549.1.5.13
        guard schemeOID.content == oid("1.2.840.113549.1.5.13"), algorithm.count >= 2 else {
            throw DecryptError.unsupportedScheme("obsługiwany jest wyłącznie PBES2 (PBKDF2 + AES-CBC)")
        }
        // PBES2-params ::= SEQUENCE { keyDerivationFunc, encryptionScheme }
        let params = ASN1DER.children(of: algorithm[1].content)
        guard params.count >= 2, params[0].tag == 0x30, params[1].tag == 0x30 else {
            throw DecryptError.malformed("nieprawidłowe parametry PBES2")
        }
        let kdf = try parsePBKDF2(params[0])
        let cipher = try parseCipher(params[1])
        let key = try deriveKey(
            password: password,
            salt: kdf.salt,
            iterations: kdf.iterations,
            length: cipher.keyLength,
            prf: kdf.prf
        )
        let plaintext = try aesCBCDecrypt(encryptedData, key: key, iv: cipher.iv)

        // Poprawnie odszyfrowany klucz to PrivateKeyInfo:
        //   SEQUENCE { version INTEGER (0), privateKeyAlgorithm SEQUENCE, ... }
        // obejmujący cały bufor. Błędne hasło daje błąd dopełnienia (wyżej)
        // albo śmieci — pełna weryfikacja kształtu (nie tylko zewnętrzny tag)
        // deterministycznie wychwytuje przypadek „padding przypadkiem OK”,
        // żeby śmieci nigdy nie trafiły do parsera klucza.
        guard let inner = ASN1DER.readElement(plaintext), inner.tag == 0x30,
              inner.totalLength == plaintext.count else {
            throw DecryptError.wrongPassword
        }
        let parts = ASN1DER.children(of: inner.content)
        guard parts.count >= 2,
              parts[0].tag == 0x02, parts[0].content == Data([0x00]),
              parts[1].tag == 0x30 else {
            throw DecryptError.wrongPassword
        }
        return plaintext
    }

    // MARK: Parsowanie parametrów

    private struct PBKDF2Params {
        let salt: Data
        let iterations: Int
        let prf: CCPseudoRandomAlgorithm
    }

    /// keyDerivationFunc ::= SEQUENCE { OID(PBKDF2), PBKDF2-params }
    private static func parsePBKDF2(_ element: ASN1DER.Element) throws -> PBKDF2Params {
        let kdf = ASN1DER.children(of: element.content)
        guard kdf.count >= 2, kdf[0].tag == 0x06,
              kdf[0].content == oid("1.2.840.113549.1.5.12") else {
            throw DecryptError.unsupportedScheme("obsługiwane wyprowadzenie klucza to wyłącznie PBKDF2")
        }
        let fields = ASN1DER.children(of: kdf[1].content)
        guard fields.count >= 2, fields[0].tag == 0x04, fields[1].tag == 0x02 else {
            throw DecryptError.malformed("nieprawidłowe parametry PBKDF2")
        }
        let salt = fields[0].content
        let iterations = intValue(fields[1].content)
        // Górny limit chroni przed zamrożeniem aplikacji: PBKDF2 liczy się
        // synchronicznie, a spreparowany/uszkodzony plik mógłby podać miliardy
        // iteracji. Realne pliki (KSeF, OpenSSL) mają rzędu tysięcy.
        guard iterations > 0, iterations <= 10_000_000 else {
            throw DecryptError.malformed("nieprawidłowa liczba iteracji PBKDF2")
        }

        // Opcjonalne: keyLength (INTEGER — pomijamy, bierzemy z szyfru) oraz
        // prf (SEQUENCE). Brak prf oznacza domyślnie HMAC-SHA1.
        var prf = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
        for extra in fields.dropFirst(2) where extra.tag == 0x30 {
            let prfOID = ASN1DER.children(of: extra.content).first
            prf = try pseudoRandom(from: prfOID?.content)
        }
        return PBKDF2Params(salt: salt, iterations: iterations, prf: prf)
    }

    /// encryptionScheme ::= SEQUENCE { OID(AES-CBC), IV OCTET STRING }
    private static func parseCipher(_ element: ASN1DER.Element) throws -> (keyLength: Int, iv: Data) {
        let fields = ASN1DER.children(of: element.content)
        guard fields.count >= 2, fields[0].tag == 0x06, fields[1].tag == 0x04 else {
            throw DecryptError.malformed("nieprawidłowe parametry szyfru")
        }
        let cipherOID = fields[0].content
        let iv = fields[1].content
        let keyLength: Int
        switch cipherOID {
        case oid("2.16.840.1.101.3.4.1.2"): keyLength = 16   // aes-128-cbc
        case oid("2.16.840.1.101.3.4.1.22"): keyLength = 24  // aes-192-cbc
        case oid("2.16.840.1.101.3.4.1.42"): keyLength = 32  // aes-256-cbc
        default:
            throw DecryptError.unsupportedScheme("obsługiwane szyfry to AES-128/192/256-CBC")
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw DecryptError.malformed("nieprawidłowy wektor IV")
        }
        return (keyLength, iv)
    }

    private static func pseudoRandom(from oidBytes: Data?) throws -> CCPseudoRandomAlgorithm {
        guard let oidBytes else { return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1) }
        switch oidBytes {
        case oid("1.2.840.113549.2.7"): return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
        case oid("1.2.840.113549.2.8"): return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA224)
        case oid("1.2.840.113549.2.9"): return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
        case oid("1.2.840.113549.2.10"): return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384)
        case oid("1.2.840.113549.2.11"): return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
        default:
            throw DecryptError.unsupportedScheme("obsługiwane PRF to HMAC-SHA1/224/256/384/512")
        }
    }

    // MARK: Kryptografia

    private static func deriveKey(
        password: String,
        salt: Data,
        iterations: Int,
        length: Int,
        prf: CCPseudoRandomAlgorithm
    ) throws -> Data {
        var derived = Data(count: length)
        let passwordBytes = Data(password.utf8)
        let status = derived.withUnsafeMutableBytes { derivedPtr in
            passwordBytes.withUnsafeBytes { passwordPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress?.assumingMemoryBound(to: CChar.self), passwordBytes.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        prf,
                        UInt32(min(iterations, Int(UInt32.max))),
                        derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), length
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw DecryptError.malformed("wyprowadzenie klucza PBKDF2 nie powiodło się (kod \(status))")
        }
        return derived
    }

    private static func aesCBCDecrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputPtr in
            data.withUnsafeBytes { dataPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, data.count,
                            outputPtr.baseAddress, outputPtr.count,
                            &moved
                        )
                    }
                }
            }
        }
        if status == CCCryptorStatus(kCCDecodeError) {
            // Błąd dopełnienia PKCS#7 — praktycznie zawsze oznacza złe hasło.
            throw DecryptError.wrongPassword
        }
        guard status == CCCryptorStatus(kCCSuccess) else {
            throw DecryptError.malformed("odszyfrowanie AES-CBC nie powiodło się (kod \(status))")
        }
        output.removeSubrange(moved..<output.count)
        return output
    }

    // MARK: Pomocnicze

    /// Zawartość (bez nagłówka tag+długość) OID w postaci DER — do porównań.
    private static func oid(_ dotted: String) -> Data {
        Data(ASN1DER.objectIdentifier(dotted).dropFirst(2))
    }

    /// Wartość nieujemnego INTEGER z bajtów big-endian.
    private static func intValue(_ bytes: Data) -> Int {
        bytes.reduce(0) { ($0 << 8) | Int($1) }
    }
}
