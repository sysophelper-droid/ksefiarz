import Foundation
import Security

// MARK: - Certyfikat KSeF (para: certyfikat + klucz prywatny)

/// Rodzaj certyfikatu KSeF zgodnie z API 2.0.
public enum KSeFCertificateType: String, CaseIterable, Codable, Sendable {
    /// Typ 1 — uwierzytelnienie (logowanie do KSeF podpisem XAdES).
    case authentication
    /// Typ 2 — offline (podpisywanie KODU II „CERTYFIKAT” na dokumentach offline).
    case offline

    public var displayName: String {
        switch self {
        case .authentication: return "Uwierzytelniający (typ 1)"
        case .offline: return "Offline (typ 2)"
        }
    }
}

/// Rodzaj klucza prywatnego certyfikatu — KSeF wspiera RSA-2048 i EC P-256.
public enum KSeFKeyType: String, Codable, Sendable {
    case rsa = "RSA"
    case ec = "EC"
}

/// Certyfikat KSeF wraz z kluczem prywatnym — przechowywany w pęku kluczy.
public struct KSeFCertificate: Codable, Equatable, Sendable {
    /// Certyfikat X.509 w DER.
    public let certificateDER: Data
    /// Klucz prywatny: RSA w DER (PKCS#1) albo EC w postaci surowej
    /// (04‖X‖Y‖K — format SecKey dla kSecAttrKeyTypeECSECPrimeRandom).
    public let privateKeyDER: Data
    /// Rodzaj klucza prywatnego.
    public let keyType: KSeFKeyType
    /// Numer seryjny certyfikatu w zapisie szesnastkowym (identyfikator w API KSeF).
    public let serialNumberHex: String

    public init(
        certificateDER: Data,
        privateKeyDER: Data,
        keyType: KSeFKeyType = .rsa,
        serialNumberHex: String = ""
    ) {
        self.certificateDER = certificateDER
        self.privateKeyDER = privateKeyDER
        self.keyType = keyType
        self.serialNumberHex = serialNumberHex.isEmpty
            ? (Self.info(fromDER: certificateDER)?.serialNumberHex ?? "")
            : serialNumberHex
    }

    /// Odczyt z JSON — starsze wpisy bez pola keyType traktowane jako RSA.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let certificateDER = try container.decode(Data.self, forKey: .certificateDER)
        let privateKeyDER = try container.decode(Data.self, forKey: .privateKeyDER)
        let keyType = try container.decodeIfPresent(KSeFKeyType.self, forKey: .keyType) ?? .rsa
        let serial = try container.decodeIfPresent(String.self, forKey: .serialNumberHex) ?? ""
        self.init(
            certificateDER: certificateDER,
            privateKeyDER: privateKeyDER,
            keyType: keyType,
            serialNumberHex: serial
        )
    }

    /// Klucz prywatny jako SecKey.
    public func privateKey() throws -> SecKey {
        try X509Builder.importPrivateKey(privateKeyDER, keyType: keyType)
    }

    /// Informacje odczytane z certyfikatu (do prezentacji i podpisu XAdES).
    public var info: CertificateInfo? {
        Self.info(fromDER: certificateDER)
    }

    /// Pola certyfikatu X.509 istotne dla aplikacji.
    public struct CertificateInfo: Equatable, Sendable {
        public let subjectSummary: String
        public let issuerName: String
        public let serialNumberDecimal: String
        public let serialNumberHex: String
        public let validFrom: Date
        public let validTo: Date

        public func isValid(at date: Date = .now) -> Bool {
            date >= validFrom && date <= validTo
        }

        /// Liczba pełnych dni do wygaśnięcia (ujemna po terminie).
        public func daysToExpiry(from date: Date = .now) -> Int {
            Int(validTo.timeIntervalSince(date) / 86_400)
        }
    }

    /// Odczytuje pola certyfikatu z DER. Zwraca nil dla nieprawidłowych danych.
    public static func info(fromDER der: Data) -> CertificateInfo? {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return nil }

        // Struktura: Certificate → TBSCertificate → [wersja], serial, alg,
        // issuer, validity, subject, ...
        guard let root = ASN1DER.readElement(der), root.tag == 0x30,
              let tbs = ASN1DER.children(of: root.content).first, tbs.tag == 0x30 else {
            return nil
        }
        var fields = ASN1DER.children(of: tbs.content)
        if fields.first?.tag == 0xA0 { fields.removeFirst() } // opcjonalna wersja [0]
        guard fields.count >= 6, fields[0].tag == 0x02 else { return nil }

        // Normalizacja: DER dokłada wiodące zero przy ustawionym najstarszym
        // bicie — numer seryjny porównujemy bez niego.
        var serialBytes = fields[0].content.drop(while: { $0 == 0 })
        if serialBytes.isEmpty { serialBytes = Data([0]) }
        let issuer = fields[2]
        let validity = ASN1DER.children(of: fields[3].content)
        guard validity.count == 2,
              let validFrom = parseTime(validity[0]),
              let validTo = parseTime(validity[1]) else { return nil }

        let summary = SecCertificateCopySubjectSummary(certificate) as String? ?? ""
        return CertificateInfo(
            subjectSummary: summary,
            issuerName: distinguishedName(fromDERName: issuer),
            serialNumberDecimal: ASN1DER.decimalString(fromBigEndian: serialBytes),
            serialNumberHex: serialBytes.map { String(format: "%02X", $0) }.joined(),
            validFrom: validFrom,
            validTo: validTo
        )
    }

    /// UTCTime (0x17) lub GeneralizedTime (0x18) → Date.
    private static func parseTime(_ element: ASN1DER.Element) -> Date? {
        let string = String(decoding: element.content, as: UTF8.self)
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = element.tag == 0x17 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
        return formatter.date(from: string)
    }

    /// Nazwa wyróżniająca w zapisie RFC 2253 (odwrócona kolejność RDN,
    /// rozdzielenie przecinkami) — używana w X509IssuerName podpisu XAdES.
    static func distinguishedName(fromDERName name: ASN1DER.Element) -> String {
        let oidNames: [String: String] = [
            "2.5.4.3": "CN", "2.5.4.7": "L", "2.5.4.8": "ST", "2.5.4.10": "O",
            "2.5.4.11": "OU", "2.5.4.6": "C", "2.5.4.9": "STREET",
            "0.9.2342.19200300.100.1.25": "DC", "0.9.2342.19200300.100.1.1": "UID",
        ]
        let rdns = ASN1DER.children(of: name.content)
        let parts: [String] = rdns.reversed().compactMap { rdn in
            guard let attribute = ASN1DER.children(of: rdn.content).first,
                  let elements = Optional(ASN1DER.children(of: attribute.content)),
                  elements.count >= 2, elements[0].tag == 0x06 else { return nil }
            let oid = decodeOID(elements[0].content)
            let value = String(decoding: elements[1].content, as: UTF8.self)
            return "\(oidNames[oid] ?? oid)=\(value)"
        }
        return parts.joined(separator: ",")
    }

    /// Dekoduje OBJECT IDENTIFIER do postaci kropkowej.
    private static func decodeOID(_ content: Data) -> String {
        guard let first = content.first else { return "" }
        var parts = [String(Int(first) / 40), String(Int(first) % 40)]
        var value: UInt64 = 0
        for byte in content.dropFirst() {
            value = (value << 7) | UInt64(byte & 0x7F)
            if byte & 0x80 == 0 {
                parts.append(String(value))
                value = 0
            }
        }
        return parts.joined(separator: ".")
    }
}

// MARK: - Magazyn certyfikatów (pęk kluczy)

/// Pojedyncze źródło prawdy o certyfikatach KSeF. Certyfikat wraz z kluczem
/// prywatnym żyje w pęku kluczy (osobny wpis per typ i środowisko) —
/// nigdy w UserDefaults ani w kopiach zapasowych.
public final class KSeFCertificateStore: ObservableObject {

    public static let shared = KSeFCertificateStore()

    /// Certyfikat uwierzytelniający (typ 1) bieżącego środowiska.
    @Published public private(set) var authenticationCertificate: KSeFCertificate?
    /// Certyfikat offline (typ 2) bieżącego środowiska.
    @Published public private(set) var offlineCertificate: KSeFCertificate?

    private let storage: SecretStorage
    private var environmentRaw: String

    public init(
        storage: SecretStorage = KeychainSecretStorage(),
        defaults: UserDefaults = .standard
    ) {
        self.storage = storage
        self.environmentRaw = defaults.string(forKey: AppSettingsKeys.environment) ?? ""
        reload()
    }

    /// Konto pęku kluczy dla certyfikatu danego typu i środowiska —
    /// produkcja bez sufiksu (spójnie z `TokenStore.account(forEnvironment:)`).
    public static func account(type: KSeFCertificateType, environmentRaw: String) -> String {
        let base = "ksef.cert.\(type == .authentication ? "auth" : "offline")"
        if environmentRaw.isEmpty || environmentRaw == KSeFEnvironment.production.rawValue {
            return base
        }
        return "\(base).\(environmentRaw)"
    }

    public func certificate(type: KSeFCertificateType) -> KSeFCertificate? {
        switch type {
        case .authentication: return authenticationCertificate
        case .offline: return offlineCertificate
        }
    }

    /// Zapisuje certyfikat w pęku kluczy i publikuje zmianę.
    public func save(_ certificate: KSeFCertificate, type: KSeFCertificateType) {
        guard let payload = try? JSONEncoder().encode(certificate) else { return }
        storage.save(payload.base64EncodedString(), account: Self.account(type: type, environmentRaw: environmentRaw))
        apply(certificate, type: type)
    }

    /// Usuwa certyfikat danego typu (np. po unieważnieniu).
    public func delete(type: KSeFCertificateType) {
        storage.delete(account: Self.account(type: type, environmentRaw: environmentRaw))
        apply(nil, type: type)
    }

    /// Przełącza magazyn na certyfikaty wskazanego środowiska.
    public func switchEnvironment(_ environmentRaw: String) {
        guard environmentRaw != self.environmentRaw else { return }
        self.environmentRaw = environmentRaw
        reload()
    }

    private func reload() {
        authenticationCertificate = read(type: .authentication)
        offlineCertificate = read(type: .offline)
    }

    private func read(type: KSeFCertificateType) -> KSeFCertificate? {
        guard let base64 = storage.read(account: Self.account(type: type, environmentRaw: environmentRaw)),
              let payload = Data(base64Encoded: base64),
              let certificate = try? JSONDecoder().decode(KSeFCertificate.self, from: payload) else {
            return nil
        }
        return certificate
    }

    private func apply(_ certificate: KSeFCertificate?, type: KSeFCertificateType) {
        switch type {
        case .authentication: authenticationCertificate = certificate
        case .offline: offlineCertificate = certificate
        }
    }
}
