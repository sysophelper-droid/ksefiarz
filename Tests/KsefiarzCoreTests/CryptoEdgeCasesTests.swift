import Foundation
import Security
import CommonCrypto
import Testing
@testable import KsefiarzCore

// Testy domykające pokrycie ścieżek brzegowych i błędów w warstwie
// kryptograficznej: X509Builder, KSeFCrypto, PKCS8EncryptedKey oraz ASN1DER.
// Wiele przypadków to celowo wadliwe wejścia (błędny DER, nieobsługiwany
// algorytm, złe hasło, niedopasowany klucz), których nie da się wywołać
// prawidłowym użyciem API. Helpery są prywatne wewnątrz każdej suity, więc
// nie kolidują z pomocnikami z innych plików testowych w tym module.

// MARK: - X509Builder: atrybuty DN i ścieżki błędów

@Suite("X509Builder — atrybuty DN, klucze EC i ścieżki błędów podpisu")
struct CryptoEdgeX509Tests {

    private let dane = Data("dane do podpisu".utf8)

    private func subjectEC_crypto(nip: String = "5265877635") -> [X509Builder.NameAttribute] {
        [
            .countryName("PL"),
            .organizationName("Ksefiarz Test EC"),
            .commonName("Ksefiarz Test EC"),
            .organizationIdentifier("VATPL-\(nip)"),
        ]
    }

    @Test("Fabryki atrybutów DN zwracają właściwe identyfikatory OID")
    func atrybutyDN() {
        #expect(X509Builder.NameAttribute.serialNumber("PNOPL-123").oid == "2.5.4.5")
        #expect(X509Builder.NameAttribute.givenName("Jan").oid == "2.5.4.42")
        #expect(X509Builder.NameAttribute.surname("Kowalski").oid == "2.5.4.4")
        // serialNumber kodowany jest jako PrintableString (0x13).
        #expect(X509Builder.NameAttribute.serialNumber("PNOPL-123").encodedValue.first == 0x13)
        // givenName/surname jako UTF8String (0x0C).
        #expect(X509Builder.NameAttribute.givenName("Jan").encodedValue.first == 0x0C)
    }

    @Test("Pełna ścieżka EC: klucz, certyfikat self-signed, CSR i podpis P1363")
    func ecSciezkaPozytywna() throws {
        let key = try X509Builder.generateECKeyPair()

        // Certyfikat self-signed EC — uruchamia gałąź EC w subjectPublicKeyInfo
        // (id-ecPublicKey + krzywa P-256) oraz podpis ECDSA w signStructure.
        let certDER = try X509Builder.makeSelfSignedCertificate(
            subject: subjectEC_crypto(), privateKey: key, keyType: .ec
        )
        #expect(!certDER.isEmpty)
        #expect(SecCertificateCreateWithData(nil, certDER as CFData) != nil)

        // CSR EC — druga droga przez signStructure w gałęzi ECDSA.
        let csr = try X509Builder.makeCSR(subject: subjectEC_crypto(), privateKey: key, keyType: .ec)
        #expect(ASN1DER.readElement(csr)?.tag == 0x30)

        // Podpis SHA-256 kluczem EC → konwersja DER→P1363 (R‖S po 32 bajty).
        let podpis = try X509Builder.signSHA256(dane, privateKey: key, keyType: .ec)
        #expect(podpis.count == 64)
    }

    @Test("Import klucza prywatnego z błędnych bajtów DER zgłasza błąd")
    func importZlegoKlucza() {
        #expect(throws: KSeFError.self) {
            _ = try X509Builder.importPrivateKey(Data([0x00, 0x01, 0x02, 0x03]), keyType: .rsa)
        }
    }

    @Test("Podpis RSA kluczem EC nie powiódł się (niezgodny algorytm)")
    func podpisRSAKluczemEC() throws {
        let ecKey = try X509Builder.generateECKeyPair()
        // signSHA256RSA żąda algorytmu RSA-PKCS1 — klucz EC go nie wspiera.
        #expect(throws: KSeFError.self) {
            _ = try X509Builder.signSHA256RSA(dane, privateKey: ecKey)
        }
    }

    @Test("Podpis ECDSA kluczem RSA nie powiódł się (niezgodny algorytm)")
    func podpisECDSAKluczemRSA() throws {
        let rsaKey = try X509Builder.generateRSAKeyPair()
        // signSHA256 w gałęzi .ec żąda ECDSA — klucz RSA go nie wspiera.
        #expect(throws: KSeFError.self) {
            _ = try X509Builder.signSHA256(dane, privateKey: rsaKey, keyType: .ec)
        }
    }

    @Test("CSR z kluczem RSA, ale typem EC — podpis struktury ECDSA zawodzi")
    func csrNiezgodnyTypKlucza() throws {
        let rsaKey = try X509Builder.generateRSAKeyPair()
        // subjectPublicKeyInfo przejdzie (eksport klucza publicznego działa),
        // ale signStructure w gałęzi ECDSA odrzuci klucz RSA.
        #expect(throws: KSeFError.self) {
            _ = try X509Builder.makeCSR(subject: subjectEC_crypto(), privateKey: rsaKey, keyType: .ec)
        }
    }

    @Test("p1363Signature: struktura niebędąca SEQUENCE jest odrzucana")
    func p1363BlednyRoot() {
        #expect(throws: KSeFError.self) {
            _ = try X509Builder.p1363Signature(fromDER: Data([0x02, 0x01, 0x00]), coordinateLength: 32)
        }
    }

    @Test("p1363Signature: SEQUENCE bez pary (r, s) jest odrzucany")
    func p1363BrakPary() {
        let jedenInteger = ASN1DER.sequence([ASN1DER.integer(1)])
        #expect(throws: KSeFError.self) {
            _ = try X509Builder.p1363Signature(fromDER: jedenInteger, coordinateLength: 32)
        }
    }

    @Test("p1363Signature: współrzędna dłuższa niż długość docelowa jest odrzucana")
    func p1363WspolrzednaZaDluga() {
        let der = ASN1DER.sequence([
            ASN1DER.integer(rawBytes: Data([0x11, 0x22, 0x33, 0x44])),
            ASN1DER.integer(rawBytes: Data([0x55])),
        ])
        // coordinateLength = 1, a pierwsza współrzędna ma 4 bajty → błąd.
        #expect(throws: KSeFError.self) {
            _ = try X509Builder.p1363Signature(fromDER: der, coordinateLength: 1)
        }
    }
}

// MARK: - KSeFCrypto: przypadki brzegowe

@Suite("KSeFCrypto — przypadki brzegowe szyfrowania")
struct CryptoEdgeKSeFCryptoTests {

    @Test("Odczyt klucza publicznego z poprawnego certyfikatu DER zwraca klucz")
    func kluczZPoprawnegoCertyfikatu() throws {
        let key = try X509Builder.generateRSAKeyPair()
        let der = try X509Builder.makeSelfSignedCertificate(
            subject: [.commonName("Ksefiarz Test"), .organizationIdentifier("VATPL-5265877635")],
            privateKey: key
        )
        let publicKey = try KSeFCrypto.publicKey(fromDERCertificate: der)
        // Zwrócony klucz jest użyteczny — da się go wyeksportować.
        #expect(SecKeyCopyExternalRepresentation(publicKey, nil) != nil)
    }

    @Test("RSA-OAEP odrzuca tekst jawny dłuższy niż pojemność klucza")
    func rsaTekstZaDlugi() throws {
        let priv = try X509Builder.generateRSAKeyPair()
        let pub = try #require(SecKeyCopyPublicKey(priv))
        // Dla RSA-2048 + OAEP/SHA-256 maksimum to 190 bajtów — 300 bajtów zawiedzie.
        #expect(throws: KSeFError.self) {
            _ = try KSeFCrypto.rsaEncryptOAEPSHA256(Data(count: 300), publicKey: pub)
        }
    }

    @Test("AES-CBC: round-trip odtwarza tekst; uszkodzony szyfrogram nie rzuca (macOS)")
    func aesRoundTripIQuirkDopelnienia() throws {
        let key = Data(repeating: 0x2B, count: 32)
        let iv = Data(repeating: 0x3C, count: 16)
        let plaintext = Data("dane testowe do szyfrowania AES-CBC".utf8)
        let cipher = try KSeFCrypto.aesEncryptCBC(plaintext, key: key, iv: iv)
        #expect(try KSeFCrypto.aesDecryptCBC(cipher, key: key, iv: iv) == plaintext)

        // Uwaga platformowa: jednorazowe CCCrypt z PKCS7 na macOS NIE waliduje
        // dopełnienia ani wyrównania — po uszkodzeniu szyfrogramu zwraca sukces
        // (śmieci), a nie błąd. Dlatego PKCS8EncryptedKey dodatkowo weryfikuje
        // kształt odszyfrowanego klucza, zamiast polegać na błędzie dopełnienia
        // (gałąź „status ≠ sukces" w aesCBC jest tu praktycznie nieosiągalna).
        var corrupted = cipher
        corrupted[corrupted.index(before: corrupted.endIndex)] ^= 0xFF
        #expect(throws: Never.self) {
            _ = try KSeFCrypto.aesDecryptCBC(corrupted, key: key, iv: iv)
        }
    }
}

// MARK: - PKCS8EncryptedKey: błędne struktury i deszyfrowanie

@Suite("PKCS8EncryptedKey — wadliwe struktury i wynik deszyfrowania")
struct CryptoEdgePKCS8Tests {

    // Identyfikatory OID używane w PBES2 (kropkowo).
    private let pbes2OID = "1.2.840.113549.1.5.13"
    private let pbkdf2OID = "1.2.840.113549.1.5.12"
    private let aes256OID = "2.16.840.1.101.3.4.1.42"

    private func oid_crypto(_ dotted: String) -> Data { ASN1DER.objectIdentifier(dotted) }

    /// Poprawny KDF (PBKDF2: sól + liczba iteracji, domyślny PRF HMAC-SHA1).
    private func validKDF_crypto(salt: Data = Data(repeating: 0xAB, count: 8), iters: Int = 1000) -> Data {
        ASN1DER.sequence([
            oid_crypto(pbkdf2OID),
            ASN1DER.sequence([ASN1DER.octetString(salt), ASN1DER.integer(iters)]),
        ])
    }

    /// Poprawny szyfr (AES-256-CBC z 16-bajtowym IV).
    private func validCipher_crypto(iv: Data = Data(count: 16)) -> Data {
        ASN1DER.sequence([oid_crypto(aes256OID), ASN1DER.octetString(iv)])
    }

    /// Składa EncryptedPrivateKeyInfo z gotowych elementów KDF i szyfru.
    private func pbes2Info_crypto(kdf: Data, cipher: Data, encrypted: Data = Data(count: 16)) -> Data {
        let params = ASN1DER.sequence([kdf, cipher])
        let algorithm = ASN1DER.sequence([oid_crypto(pbes2OID), params])
        return ASN1DER.sequence([algorithm, ASN1DER.octetString(encrypted)])
    }

    /// Wyprowadza klucz PBKDF2 (HMAC-SHA1) — zgodnie z domyślnym PRF modułu,
    /// gdy w strukturze pominięto element PRF.
    private func deriveKey_crypto(password: String, salt: Data, iterations: Int, length: Int) -> Data {
        var derived = Data(count: length)
        let passwordBytes = Data(password.utf8)
        let status = derived.withUnsafeMutableBytes { derivedPtr in
            passwordBytes.withUnsafeBytes { passwordPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress?.assumingMemoryBound(to: CChar.self), passwordBytes.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(iterations),
                        derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), length
                    )
                }
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 w teście nie powiodło się")
        return derived
    }

    /// Zwraca błąd deszyfrowania (albo nil, gdy nieoczekiwanie się powiodło).
    private func decryptError_crypto(_ der: Data, password: String = "haslo") -> PKCS8EncryptedKey.DecryptError? {
        do {
            _ = try PKCS8EncryptedKey.decrypt(der, password: password)
            return nil
        } catch let error as PKCS8EncryptedKey.DecryptError {
            return error
        } catch {
            return nil
        }
    }

    @Test("Opisy błędów obejmują wszystkie warianty DecryptError")
    func opisyBledow() {
        #expect(PKCS8EncryptedKey.DecryptError.malformed("X").errorDescription?.contains("Nieprawidłowa struktura") == true)
        #expect(PKCS8EncryptedKey.DecryptError.unsupportedScheme("Y").errorDescription?.contains("Nieobsługiwany sposób") == true)
        #expect(PKCS8EncryptedKey.DecryptError.wrongPassword.errorDescription?.contains("błędne hasło") == true)
    }

    @Test("Dane bez nadrzędnego SEQUENCE są odrzucane")
    func brakNadrzednegoSequence() {
        #expect(decryptError_crypto(Data([0x02, 0x01, 0x00])) == .malformed("brak nadrzędnego SEQUENCE"))
    }

    @Test("Brak algorytmu i zaszyfrowanych danych jest wychwytywany")
    func brakAlgorytmuIDanych() {
        let der = ASN1DER.sequence([ASN1DER.integer(0)])
        #expect(decryptError_crypto(der) == .malformed("oczekiwano algorytmu i zaszyfrowanych danych"))
    }

    @Test("Brak identyfikatora algorytmu jest wychwytywany")
    func brakIdentyfikatoraAlgorytmu() {
        let der = ASN1DER.sequence([
            ASN1DER.sequence([ASN1DER.integer(0)]),
            ASN1DER.octetString(Data()),
        ])
        #expect(decryptError_crypto(der) == .malformed("brak identyfikatora algorytmu"))
    }

    @Test("Schemat inny niż PBES2 jest nieobsługiwany")
    func niePBES2() {
        let der = ASN1DER.sequence([
            ASN1DER.sequence([oid_crypto("1.2.3"), ASN1DER.null()]),
            ASN1DER.octetString(Data()),
        ])
        #expect(decryptError_crypto(der) == .unsupportedScheme("obsługiwany jest wyłącznie PBES2 (PBKDF2 + AES-CBC)"))
    }

    @Test("Nieprawidłowe parametry PBES2 są odrzucane")
    func blednenParametryPBES2() {
        let der = ASN1DER.sequence([
            ASN1DER.sequence([oid_crypto(pbes2OID), ASN1DER.sequence([ASN1DER.integer(0)])]),
            ASN1DER.octetString(Data()),
        ])
        #expect(decryptError_crypto(der) == .malformed("nieprawidłowe parametry PBES2"))
    }

    @Test("Wyprowadzenie klucza inne niż PBKDF2 jest nieobsługiwane")
    func niePBKDF2() {
        let kdf = ASN1DER.sequence([oid_crypto("1.2.3"), ASN1DER.sequence([])])
        let der = pbes2Info_crypto(kdf: kdf, cipher: validCipher_crypto())
        #expect(decryptError_crypto(der) == .unsupportedScheme("obsługiwane wyprowadzenie klucza to wyłącznie PBKDF2"))
    }

    @Test("Nieprawidłowe parametry PBKDF2 są odrzucane")
    func blednenParametryPBKDF2() {
        let kdf = ASN1DER.sequence([oid_crypto(pbkdf2OID), ASN1DER.sequence([ASN1DER.integer(0)])])
        let der = pbes2Info_crypto(kdf: kdf, cipher: validCipher_crypto())
        #expect(decryptError_crypto(der) == .malformed("nieprawidłowe parametry PBKDF2"))
    }

    @Test("Nieprawidłowe parametry szyfru są odrzucane")
    func blednenParametrySzyfru() {
        let cipher = ASN1DER.sequence([ASN1DER.integer(0)])
        let der = pbes2Info_crypto(kdf: validKDF_crypto(), cipher: cipher)
        #expect(decryptError_crypto(der) == .malformed("nieprawidłowe parametry szyfru"))
    }

    @Test("Nieobsługiwany szyfr (spoza AES-128/192/256-CBC) jest odrzucany")
    func nieobslugiwanySzyfr() {
        let cipher = ASN1DER.sequence([oid_crypto("1.2.3"), ASN1DER.octetString(Data(count: 16))])
        let der = pbes2Info_crypto(kdf: validKDF_crypto(), cipher: cipher)
        #expect(decryptError_crypto(der) == .unsupportedScheme("obsługiwane szyfry to AES-128/192/256-CBC"))
    }

    @Test("Nieprawidłowa długość wektora IV jest odrzucana")
    func blednaDlugoscIV() {
        let cipher = ASN1DER.sequence([oid_crypto(aes256OID), ASN1DER.octetString(Data(count: 8))])
        let der = pbes2Info_crypto(kdf: validKDF_crypto(), cipher: cipher)
        #expect(decryptError_crypto(der) == .malformed("nieprawidłowy wektor IV"))
    }

    @Test("Nieobsługiwany PRF (nieznany OID) jest odrzucany")
    func nieobslugiwanyPRF() {
        let pbkdf2Params = ASN1DER.sequence([
            ASN1DER.octetString(Data(repeating: 0xAB, count: 8)),
            ASN1DER.integer(1000),
            ASN1DER.sequence([oid_crypto("1.2.3")]),
        ])
        let kdf = ASN1DER.sequence([oid_crypto(pbkdf2OID), pbkdf2Params])
        let der = pbes2Info_crypto(kdf: kdf, cipher: validCipher_crypto())
        #expect(decryptError_crypto(der) == .unsupportedScheme("obsługiwane PRF to HMAC-SHA1/224/256/384/512"))
    }

    @Test("Poprawne deszyfrowanie, ale wewnętrzna struktura to nie PrivateKeyInfo → błędne hasło")
    func poprawneAESaleZlaStruktura() throws {
        let salt = Data(repeating: 0x01, count: 8)
        let iters = 1000
        let iv = Data(repeating: 0x02, count: 16)
        let key = deriveKey_crypto(password: "haslo", salt: salt, iterations: iters, length: 32)

        // Bufor jest poprawnym SEQUENCE obejmującym całość, lecz pierwsze pole
        // to INTEGER(1), a nie wymagane INTEGER(0) — parser uzna to za złe hasło.
        let plaintext = ASN1DER.sequence([ASN1DER.integer(1), ASN1DER.sequence([])])
        let encrypted = try KSeFCrypto.aesEncryptCBC(plaintext, key: key, iv: iv)

        let kdf = ASN1DER.sequence([oid_crypto(pbkdf2OID), ASN1DER.sequence([ASN1DER.octetString(salt), ASN1DER.integer(iters)])])
        let der = pbes2Info_crypto(kdf: kdf, cipher: validCipher_crypto(iv: iv), encrypted: encrypted)

        #expect(decryptError_crypto(der, password: "haslo") == .wrongPassword)
    }

    @Test("Błędne dopełnienie PKCS#7 po AES-CBC jest raportowane jako błędne hasło")
    func bledneDopelnienieToZleHaslo() throws {
        let salt = Data(repeating: 0x03, count: 8)
        let iters = 1000
        let iv = Data(repeating: 0x04, count: 16)
        let key = deriveKey_crypto(password: "haslo", salt: salt, iterations: iters, length: 32)

        // Pojedynczy blok, którego ostatni bajt (0xFF) to nieprawidłowe dopełnienie
        // PKCS#7 → CCCrypt zwraca kCCDecodeError.
        var blok = Data(repeating: 0xAA, count: 16)
        blok[blok.index(blok.startIndex, offsetBy: 15)] = 0xFF
        let pelny = try KSeFCrypto.aesEncryptCBC(blok, key: key, iv: iv)
        let jedenBlok = Data(pelny.prefix(16)) // pierwszy blok szyfrogramu → deszyfruje do `blok`

        let kdf = ASN1DER.sequence([oid_crypto(pbkdf2OID), ASN1DER.sequence([ASN1DER.octetString(salt), ASN1DER.integer(iters)])])
        let der = pbes2Info_crypto(kdf: kdf, cipher: validCipher_crypto(iv: iv), encrypted: jedenBlok)

        #expect(decryptError_crypto(der, password: "haslo") == .wrongPassword)
    }

    @Test("Za krótki szyfrogram nie przechodzi weryfikacji kształtu klucza")
    func szyfrogramZlaDlugosc() {
        let salt = Data(repeating: 0x05, count: 8)
        let iters = 1000
        let iv = Data(repeating: 0x06, count: 16)
        let kdf = ASN1DER.sequence([oid_crypto(pbkdf2OID), ASN1DER.sequence([ASN1DER.octetString(salt), ASN1DER.integer(iters)])])
        // 10 bajtów szyfrogramu — na macOS CCCrypt nie zgłasza błędu wyrównania,
        // więc odszyfrowanie daje śmieci, a deterministyczna weryfikacja kształtu
        // PrivateKeyInfo odrzuca je jako złe hasło (śmieci nie trafią do parsera).
        let der = pbes2Info_crypto(kdf: kdf, cipher: validCipher_crypto(iv: iv), encrypted: Data(repeating: 0xAB, count: 10))

        #expect(decryptError_crypto(der, password: "haslo") == .wrongPassword)
    }
}

// MARK: - ASN1DER: pozostałe kodery

@Suite("ASN1DER — koder wartości logicznej")
struct CryptoEdgeASN1DERTests {

    @Test("BOOLEAN koduje się do kanonicznych bajtów DER")
    func booleanKodowanie() {
        #expect(ASN1DER.boolean(true) == Data([0x01, 0x01, 0xFF]))
        #expect(ASN1DER.boolean(false) == Data([0x01, 0x01, 0x00]))
    }
}
