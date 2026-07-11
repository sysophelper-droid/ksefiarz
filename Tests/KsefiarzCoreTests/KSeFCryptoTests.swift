import Foundation
import Security
import Testing
@testable import KsefiarzCore

@Suite("Kryptografia KSeF")
struct KSeFCryptoTests {

    @Test("Losowe bajty mają żądaną długość i nie powtarzają się")
    func randomBytes() throws {
        let first = try KSeFCrypto.randomBytes(32)
        let second = try KSeFCrypto.randomBytes(32)
        #expect(first.count == 32)
        #expect(second.count == 32)
        #expect(first != second)
    }

    @Test("SHA-256 zgadza się ze znanym wektorem testowym")
    func sha256KnownVector() {
        // SHA-256("abc") = ba7816bf... → Base64 poniżej.
        #expect(KSeFCrypto.sha256Base64(Data("abc".utf8)) == "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=")
    }

    @Test("AES-256-CBC: szyfrowanie i odszyfrowanie daje oryginalne dane")
    func aesRoundTrip() throws {
        let key = try KSeFCrypto.randomBytes(32)
        let iv = try KSeFCrypto.randomBytes(16)
        let message = Data("Przykładowa faktura FA(2) — żółć, ąęśćń.".utf8)

        let encrypted = try KSeFCrypto.aesEncryptCBC(message, key: key, iv: iv)
        #expect(encrypted != message)
        // PKCS#7 — długość zaszyfrowana jest wielokrotnością bloku.
        #expect(encrypted.count % 16 == 0)

        let decrypted = try KSeFCrypto.aesDecryptCBC(encrypted, key: key, iv: iv)
        #expect(decrypted == message)
    }

    @Test("AES odrzuca klucz lub IV o złej długości")
    func aesRejectsBadKeySizes() throws {
        let data = Data("x".utf8)
        #expect(throws: KSeFError.self) {
            _ = try KSeFCrypto.aesEncryptCBC(data, key: Data(count: 16), iv: Data(count: 16))
        }
        #expect(throws: KSeFError.self) {
            _ = try KSeFCrypto.aesEncryptCBC(data, key: Data(count: 32), iv: Data(count: 8))
        }
    }

    @Test("RSA-OAEP (SHA-256): szyfrowanie kluczem publicznym, odszyfrowanie prywatnym")
    func rsaRoundTrip() throws {
        let keys = TestRSAKeyPair()
        let message = Data("token-ksef|1781202877958".utf8)

        let encrypted = try KSeFCrypto.rsaEncryptOAEPSHA256(message, publicKey: keys.publicKey)
        #expect(encrypted != message)

        let decrypted = try #require(keys.decryptOAEPSHA256(encrypted))
        #expect(decrypted == message)
    }

    @Test("Nieprawidłowy certyfikat DER zgłasza błąd kryptograficzny")
    func invalidCertificate() {
        #expect(throws: KSeFError.self) {
            _ = try KSeFCrypto.publicKey(fromDERCertificate: Data("to-nie-jest-certyfikat".utf8))
        }
    }
}
