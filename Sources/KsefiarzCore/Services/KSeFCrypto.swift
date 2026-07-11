import Foundation
import Security
import CryptoKit
import CommonCrypto

/// Operacje kryptograficzne wymagane przez API KSeF 2.0:
/// - szyfrowanie tokenu autoryzacyjnego i klucza symetrycznego RSA-OAEP (SHA-256),
/// - szyfrowanie dokumentów faktur AES-256-CBC (PKCS#7),
/// - skróty SHA-256.
public enum KSeFCrypto {

    /// Wyodrębnia klucz publiczny z certyfikatu DER (pobranego z API KSeF).
    public static func publicKey(fromDERCertificate data: Data) throws -> SecKey {
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData),
              let key = SecCertificateCopyKey(certificate) else {
            throw KSeFError.encryptionFailed("Nie udało się odczytać klucza publicznego z certyfikatu KSeF.")
        }
        return key
    }

    /// Szyfruje dane algorytmem RSA-OAEP z funkcją skrótu SHA-256 (MGF1).
    public static func rsaEncryptOAEPSHA256(_ plaintext: Data, publicKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            plaintext as CFData,
            &error
        ) else {
            let details = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "nieznany błąd"
            throw KSeFError.encryptionFailed("Szyfrowanie RSA nie powiodło się: \(details)")
        }
        return encrypted as Data
    }

    /// Szyfruje dane algorytmem AES-256-CBC z dopełnieniem PKCS#7.
    public static func aesEncryptCBC(_ data: Data, key: Data, iv: Data) throws -> Data {
        try aesCBC(operation: CCOperation(kCCEncrypt), data: data, key: key, iv: iv)
    }

    /// Odszyfrowuje dane AES-256-CBC (PKCS#7) — używane w testach do weryfikacji round-trip.
    public static func aesDecryptCBC(_ data: Data, key: Data, iv: Data) throws -> Data {
        try aesCBC(operation: CCOperation(kCCDecrypt), data: data, key: key, iv: iv)
    }

    private static func aesCBC(operation: CCOperation, data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES256 else {
            throw KSeFError.encryptionFailed("Klucz AES musi mieć 32 bajty.")
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw KSeFError.encryptionFailed("Wektor IV musi mieć 16 bajtów.")
        }

        var output = Data(count: data.count + kCCBlockSizeAES128)
        var movedBytes = 0

        let status = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { dataBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress, key.count,
                            ivBuffer.baseAddress,
                            dataBuffer.baseAddress, data.count,
                            outputBuffer.baseAddress, outputBuffer.count,
                            &movedBytes
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw KSeFError.encryptionFailed("Operacja AES nie powiodła się (kod \(status)).")
        }
        output.removeSubrange(movedBytes..<output.count)
        return output
    }

    /// Generuje kryptograficznie bezpieczne losowe bajty (klucz AES, IV).
    public static func randomBytes(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw KSeFError.encryptionFailed("Generowanie losowych bajtów nie powiodło się.")
        }
        return bytes
    }

    /// Skrót SHA-256 zakodowany w Base64 (format wymagany przez API KSeF).
    public static func sha256Base64(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
    }
}
