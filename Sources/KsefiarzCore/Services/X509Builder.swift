import Foundation
import Security

/// Budowa struktur X.509 w czystym Swifcie: wniosek CSR (PKCS#10) dla
/// certyfikatów KSeF oraz certyfikat self-signed (uwierzytelnienie na
/// środowisku testowym i testy jednostkowe). Podpisy RSA (SHA-256) przez
/// Security.framework — klucz prywatny nigdy nie opuszcza procesu.
public enum X509Builder {

    // MARK: Nazwa wyróżniająca (DN)

    /// Pojedynczy atrybut nazwy wyróżniającej podmiotu certyfikatu.
    public struct NameAttribute: Equatable, Sendable {
        public let oid: String
        public let value: String

        public init(oid: String, value: String) {
            self.oid = oid
            self.value = value
        }

        /// Znane skróty OID — do budowy DN z danych API i prezentacji.
        public static func commonName(_ value: String) -> NameAttribute {
            NameAttribute(oid: "2.5.4.3", value: value)
        }
        public static func organizationName(_ value: String) -> NameAttribute {
            NameAttribute(oid: "2.5.4.10", value: value)
        }
        public static func countryName(_ value: String) -> NameAttribute {
            NameAttribute(oid: "2.5.4.6", value: value)
        }
        /// organizationIdentifier (2.5.4.97) — KSeF koduje tu VATPL-{NIP}.
        public static func organizationIdentifier(_ value: String) -> NameAttribute {
            NameAttribute(oid: "2.5.4.97", value: value)
        }
        /// serialNumber (2.5.4.5) — w certyfikatach osobistych numer PESEL/NIP.
        public static func serialNumber(_ value: String) -> NameAttribute {
            NameAttribute(oid: "2.5.4.5", value: value)
        }
        public static func givenName(_ value: String) -> NameAttribute {
            NameAttribute(oid: "2.5.4.42", value: value)
        }
        public static func surname(_ value: String) -> NameAttribute {
            NameAttribute(oid: "2.5.4.4", value: value)
        }

        /// Kodowanie DER: countryName i serialNumber jako PrintableString,
        /// pozostałe UTF8String (zgodnie z praktyką RFC 5280).
        var encodedValue: Data {
            switch oid {
            case "2.5.4.6", "2.5.4.5": return ASN1DER.printableString(value)
            default: return ASN1DER.utf8String(value)
            }
        }
    }

    /// Koduje nazwę wyróżniającą (RDNSequence) — po jednym atrybucie na RDN,
    /// w podanej kolejności.
    static func encodeName(_ attributes: [NameAttribute]) -> Data {
        ASN1DER.sequence(attributes.map { attribute in
            ASN1DER.set([
                ASN1DER.sequence([
                    ASN1DER.objectIdentifier(attribute.oid),
                    attribute.encodedValue,
                ])
            ])
        })
    }

    // MARK: Identyfikatory algorytmów

    /// sha256WithRSAEncryption (1.2.840.113549.1.1.11).
    private static var sha256WithRSA: Data {
        ASN1DER.sequence([
            ASN1DER.objectIdentifier("1.2.840.113549.1.1.11"),
            ASN1DER.null(),
        ])
    }

    /// ecdsa-with-SHA256 (1.2.840.10045.4.3.2) — bez parametrów NULL.
    private static var ecdsaWithSHA256: Data {
        ASN1DER.sequence([ASN1DER.objectIdentifier("1.2.840.10045.4.3.2")])
    }

    private static func signatureAlgorithm(for keyType: KSeFKeyType) -> Data {
        keyType == .rsa ? sha256WithRSA : ecdsaWithSHA256
    }

    /// rsaEncryption (1.2.840.113549.1.1.1) — do SubjectPublicKeyInfo.
    private static var rsaEncryption: Data {
        ASN1DER.sequence([
            ASN1DER.objectIdentifier("1.2.840.113549.1.1.1"),
            ASN1DER.null(),
        ])
    }

    /// id-ecPublicKey + krzywa P-256 — do SubjectPublicKeyInfo kluczy EC.
    private static var ecPublicKeyP256: Data {
        ASN1DER.sequence([
            ASN1DER.objectIdentifier("1.2.840.10045.2.1"),
            ASN1DER.objectIdentifier("1.2.840.10045.3.1.7"),
        ])
    }

    // MARK: Klucze RSA

    /// Generuje parę kluczy RSA-2048 w pamięci (bez zapisu do pęku kluczy).
    public static func generateRSAKeyPair() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let details = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "nieznany błąd"
            throw KSeFError.encryptionFailed("Generowanie klucza RSA nie powiodło się: \(details)")
        }
        return key
    }

    /// Generuje parę kluczy EC P-256 w pamięci (testy i certyfikaty EC).
    public static func generateECKeyPair() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let details = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "nieznany błąd"
            throw KSeFError.encryptionFailed("Generowanie klucza EC nie powiodło się: \(details)")
        }
        return key
    }

    /// Eksportuje klucz prywatny RSA do DER (PKCS#1) — do zapisu w pęku kluczy.
    public static func exportPrivateKey(_ key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &error) else {
            let details = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "nieznany błąd"
            throw KSeFError.encryptionFailed("Eksport klucza prywatnego nie powiódł się: \(details)")
        }
        return data as Data
    }

    /// Odtwarza klucz prywatny z eksportowanej postaci: RSA z DER (PKCS#1)
    /// albo EC z postaci surowej (04‖X‖Y‖K).
    public static func importPrivateKey(_ der: Data, keyType: KSeFKeyType = .rsa) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: keyType == .rsa
                ? kSecAttrKeyTypeRSA
                : kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            let details = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "nieznany błąd"
            throw KSeFError.encryptionFailed("Odtworzenie klucza prywatnego nie powiodło się: \(details)")
        }
        return key
    }

    /// SubjectPublicKeyInfo dla klucza publicznego (RSA: PKCS#1 w BIT STRING;
    /// EC: punkt 04‖X‖Y).
    static func subjectPublicKeyInfo(for privateKey: SecKey, keyType: KSeFKeyType = .rsa) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw KSeFError.encryptionFailed("Nie udało się wyprowadzić klucza publicznego.")
        }
        var error: Unmanaged<CFError>?
        guard let raw = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            let details = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "nieznany błąd"
            throw KSeFError.encryptionFailed("Eksport klucza publicznego nie powiódł się: \(details)")
        }
        let algorithm = keyType == .rsa ? rsaEncryption : ecPublicKeyP256
        return ASN1DER.sequence([algorithm, ASN1DER.bitString(raw as Data)])
    }

    /// Podpis struktury DER (TBS/CSR): RSA PKCS#1 v1.5 albo ECDSA w DER —
    /// formaty wymagane wewnątrz struktur X.509 (inaczej niż w XML-DSig).
    private static func signStructure(_ data: Data, privateKey: SecKey, keyType: KSeFKeyType) throws -> Data {
        if keyType == .rsa {
            return try signSHA256RSA(data, privateKey: privateKey)
        }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey, .ecdsaSignatureMessageX962SHA256, data as CFData, &error
        ) else {
            let details = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "nieznany błąd"
            throw KSeFError.encryptionFailed("Podpis ECDSA nie powiódł się: \(details)")
        }
        return signature as Data
    }

    /// Podpis RSA PKCS#1 v1.5 z SHA-256.
    static func signSHA256RSA(_ data: Data, privateKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) else {
            let details = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "nieznany błąd"
            throw KSeFError.encryptionFailed("Podpis RSA nie powiódł się: \(details)")
        }
        return signature as Data
    }

    /// Podpis SHA-256 kluczem RSA (PKCS#1 v1.5) albo EC (ECDSA, wynik R‖S
    /// po 32 bajty — format wymagany przez XML-DSig i KODY QR KSeF).
    static func signSHA256(_ data: Data, privateKey: SecKey, keyType: KSeFKeyType) throws -> Data {
        switch keyType {
        case .rsa:
            return try signSHA256RSA(data, privateKey: privateKey)
        case .ec:
            var error: Unmanaged<CFError>?
            guard let der = SecKeyCreateSignature(
                privateKey,
                .ecdsaSignatureMessageX962SHA256,
                data as CFData,
                &error
            ) else {
                let details = (error?.takeRetainedValue()).map(String.init(describing:)) ?? "nieznany błąd"
                throw KSeFError.encryptionFailed("Podpis ECDSA nie powiódł się: \(details)")
            }
            return try p1363Signature(fromDER: der as Data, coordinateLength: 32)
        }
    }

    /// Konwersja podpisu ECDSA z ASN.1 DER (SEQUENCE{r,s}) na stały format
    /// IEEE P1363 (R‖S, każda współrzędna dopełniona zerami do pełnej długości).
    static func p1363Signature(fromDER der: Data, coordinateLength: Int) throws -> Data {
        guard let root = ASN1DER.readElement(der), root.tag == 0x30 else {
            throw KSeFError.encryptionFailed("Nieprawidłowa struktura podpisu ECDSA.")
        }
        let integers = ASN1DER.children(of: root.content)
        guard integers.count == 2, integers.allSatisfy({ $0.tag == 0x02 }) else {
            throw KSeFError.encryptionFailed("Podpis ECDSA nie zawiera pary (r, s).")
        }
        func fixed(_ content: Data) throws -> Data {
            let stripped = content.drop(while: { $0 == 0 })
            guard stripped.count <= coordinateLength else {
                throw KSeFError.encryptionFailed("Współrzędna podpisu ECDSA jest za długa.")
            }
            return Data(repeating: 0, count: coordinateLength - stripped.count) + stripped
        }
        return try fixed(integers[0].content) + fixed(integers[1].content)
    }

    // MARK: CSR (PKCS#10)

    /// Buduje wniosek o certyfikat (CertificationRequest) w DER.
    /// Podmiot (DN) musi odpowiadać danym z API KSeF (enrollment data).
    public static func makeCSR(
        subject: [NameAttribute],
        privateKey: SecKey,
        keyType: KSeFKeyType = .rsa
    ) throws -> Data {
        let info = ASN1DER.sequence([
            ASN1DER.integer(0),                                        // version
            encodeName(subject),                                       // subject
            try subjectPublicKeyInfo(for: privateKey, keyType: keyType), // subjectPKInfo
            ASN1DER.contextTag(0, Data()),                             // attributes (puste)
        ])
        let signature = try signStructure(info, privateKey: privateKey, keyType: keyType)
        return ASN1DER.sequence([info, signatureAlgorithm(for: keyType), ASN1DER.bitString(signature)])
    }

    // MARK: Certyfikat self-signed

    /// Buduje certyfikat self-signed (pieczęć testowa) — środowisko testowe
    /// KSeF akceptuje takie certyfikaty przy uwierzytelnieniu XAdES;
    /// wykorzystywany również w testach jednostkowych.
    public static func makeSelfSignedCertificate(
        subject: [NameAttribute],
        privateKey: SecKey,
        keyType: KSeFKeyType = .rsa,
        validFrom: Date = .now.addingTimeInterval(-300),
        validTo: Date = .now.addingTimeInterval(30 * 86_400)
    ) throws -> Data {
        // Pierwszy bajt bez najstarszego bitu i niezerowy — numer seryjny
        // ma stałą długość 16 bajtów bez dopełnienia DER.
        var serial = try KSeFCrypto.randomBytes(16)
        serial[serial.startIndex] = (serial[serial.startIndex] & 0x7F) | 0x40
        let name = encodeName(subject)
        let algorithm = signatureAlgorithm(for: keyType)
        let tbs = ASN1DER.sequence([
            ASN1DER.contextTag(0, ASN1DER.integer(2)),         // version v3
            ASN1DER.integer(rawBytes: serial),
            algorithm,
            name,                                              // issuer = subject
            ASN1DER.sequence([
                ASN1DER.utcTime(validFrom),
                ASN1DER.utcTime(validTo),
            ]),
            name,
            try subjectPublicKeyInfo(for: privateKey, keyType: keyType),
        ])
        let signature = try signStructure(tbs, privateKey: privateKey, keyType: keyType)
        return ASN1DER.sequence([tbs, algorithm, ASN1DER.bitString(signature)])
    }
}
