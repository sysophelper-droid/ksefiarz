import Foundation
import Security

// MARK: - Modele API certyfikatów KSeF

/// Dane podmiotu do wniosku certyfikacyjnego — CSR musi zawierać DOKŁADNIE
/// te wartości (jakakolwiek zmiana = odrzucenie wniosku, błąd 25003).
public struct KSeFEnrollmentData: Decodable, Sendable {
    public let commonName: String
    public let countryName: String
    public let givenName: String?
    public let surname: String?
    public let serialNumber: String?
    public let uniqueIdentifier: String?
    public let organizationName: String?
    public let organizationIdentifier: String?

    /// Atrybuty nazwy wyróżniającej (DN) dla wniosku CSR — w kolejności
    /// z przykładów oficjalnej dokumentacji.
    public var subjectAttributes: [X509Builder.NameAttribute] {
        var attributes: [X509Builder.NameAttribute] = [.commonName(commonName)]
        if let givenName, !givenName.isEmpty { attributes.append(.givenName(givenName)) }
        if let surname, !surname.isEmpty { attributes.append(.surname(surname)) }
        if let serialNumber, !serialNumber.isEmpty { attributes.append(.serialNumber(serialNumber)) }
        if let organizationName, !organizationName.isEmpty { attributes.append(.organizationName(organizationName)) }
        if let organizationIdentifier, !organizationIdentifier.isEmpty {
            attributes.append(.organizationIdentifier(organizationIdentifier))
        }
        if let uniqueIdentifier, !uniqueIdentifier.isEmpty {
            attributes.append(.init(oid: "2.5.4.45", value: uniqueIdentifier))
        }
        attributes.append(.countryName(countryName))
        return attributes
    }
}

/// Limity wniosków i certyfikatów uwierzytelnionego podmiotu.
public struct KSeFCertificateLimits: Decodable, Sendable {
    public struct Limit: Decodable, Sendable {
        public let remaining: Int
        public let limit: Int
    }
    public let canRequest: Bool
    public let enrollment: Limit
    public let certificate: Limit
}

struct EnrollCertificateRequestDTO: Encodable {
    let certificateName: String
    let certificateType: String
    let csr: String
}

struct EnrollCertificateResponseDTO: Decodable {
    let referenceNumber: String
}

struct CertificateEnrollmentStatusDTO: Decodable {
    let status: StatusInfoDTO
    let certificateSerialNumber: String?
}

struct RetrieveCertificatesRequestDTO: Encodable {
    let certificateSerialNumbers: [String]
}

struct RetrieveCertificatesResponseDTO: Decodable {
    struct Item: Decodable {
        let certificate: String
        let certificateName: String
        let certificateSerialNumber: String
        let certificateType: String
    }
    let certificates: [Item]
}

// MARK: - Operacje na certyfikatach

public extension KSeFService {

    /// Wartość `certificateType` w API dla rodzaju certyfikatu.
    private static func apiType(_ type: KSeFCertificateType) -> String {
        switch type {
        case .authentication: return "Authentication"
        case .offline: return "Offline"
        }
    }

    /// Pobiera limity certyfikatów (m.in. flagę, czy można złożyć wniosek).
    /// Wymaga uwierzytelnienia podpisem XAdES — token KSeF nie wystarcza.
    func fetchCertificateLimits() async throws -> KSeFCertificateLimits {
        try await ensureAuthenticated()
        let data = try await perform(
            path: "certificates/limits",
            method: "GET",
            body: nil,
            bearer: try requireAccessToken()
        )
        return try decode(data)
    }

    /// Pobiera dane podmiotu, które muszą znaleźć się w CSR.
    func fetchCertificateEnrollmentData() async throws -> KSeFEnrollmentData {
        try await ensureAuthenticated()
        let data = try await perform(
            path: "certificates/enrollments/data",
            method: "GET",
            body: nil,
            bearer: try requireAccessToken()
        )
        return try decode(data)
    }

    /// Przeprowadza pełny wniosek o certyfikat KSeF: dane podmiotu → nowa
    /// para kluczy RSA-2048 → CSR → złożenie wniosku → oczekiwanie na
    /// wystawienie → pobranie certyfikatu. Klucz prywatny powstaje lokalnie
    /// i nigdy nie opuszcza komputera.
    ///
    /// Wymaga sesji uwierzytelnionej podpisem XAdES (certyfikatem KSeF,
    /// kwalifikowanym albo — na środowisku testowym — self-signed).
    func requestCertificate(
        name: String,
        type: KSeFCertificateType
    ) async throws -> KSeFCertificate {
        try await ensureAuthenticated()

        let enrollmentData = try await fetchCertificateEnrollmentData()
        let privateKey = try X509Builder.generateRSAKeyPair()
        let csr = try X509Builder.makeCSR(
            subject: enrollmentData.subjectAttributes,
            privateKey: privateKey
        )

        let request = EnrollCertificateRequestDTO(
            certificateName: name,
            certificateType: Self.apiType(type),
            csr: csr.base64EncodedString()
        )
        let responseData = try await perform(
            path: "certificates/enrollments",
            method: "POST",
            body: try JSONEncoder().encode(request),
            bearer: try requireAccessToken()
        )
        let response: EnrollCertificateResponseDTO = try decode(responseData)

        let serialNumber = try await waitForEnrollment(referenceNumber: response.referenceNumber)
        let certificateDER = try await retrieveCertificate(serialNumberHex: serialNumber)

        return KSeFCertificate(
            certificateDER: certificateDER,
            privateKeyDER: try X509Builder.exportPrivateKey(privateKey),
            keyType: .rsa,
            serialNumberHex: serialNumber
        )
    }

    /// Standardowa nazwa certyfikatu nadawana przy wniosku i odnowieniu.
    static func certificateName(for type: KSeFCertificateType) -> String {
        "Ksefiarz \(type == .authentication ? "uwierzytelniający" : "offline")"
    }

    /// Odnawia certyfikat KSeF danego typu: składa nowy wniosek (nowa para
    /// kluczy, CSR z aktualnych danych podmiotu) i zwraca świeży certyfikat.
    /// Wymaga sesji uwierzytelnionej WAŻNYM certyfikatem typu 1 (podpis XAdES);
    /// zapis nowego certyfikatu w pęku kluczy — po stronie wołającego.
    func renewCertificate(type: KSeFCertificateType) async throws -> KSeFCertificate {
        try await requestCertificate(name: Self.certificateName(for: type), type: type)
    }

    /// Odpytuje o status wniosku do wystawienia certyfikatu (kod 200).
    private func waitForEnrollment(referenceNumber: String) async throws -> String {
        for attempt in 0..<maxPollAttempts {
            let data = try await perform(
                path: "certificates/enrollments/\(referenceNumber)",
                method: "GET",
                body: nil,
                bearer: try requireAccessToken()
            )
            let status: CertificateEnrollmentStatusDTO = try decode(data)
            switch status.status.code {
            case 200:
                guard let serial = status.certificateSerialNumber else {
                    throw KSeFError.certificateEnrollmentFailed(
                        "Wniosek obsłużony, ale brak numeru seryjnego certyfikatu."
                    )
                }
                return serial
            case 400...:
                let details = ([status.status.description] + (status.status.details ?? []))
                    .joined(separator: " ")
                throw KSeFError.certificateEnrollmentFailed(details)
            default:
                if attempt < maxPollAttempts - 1, pollInterval > 0 {
                    try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                }
            }
        }
        throw KSeFError.certificateEnrollmentFailed(
            "Przekroczono czas oczekiwania na wystawienie certyfikatu."
        )
    }

    /// Pobiera treść certyfikatu (DER) po numerze seryjnym.
    private func retrieveCertificate(serialNumberHex: String) async throws -> Data {
        let body = RetrieveCertificatesRequestDTO(certificateSerialNumbers: [serialNumberHex])
        let data = try await perform(
            path: "certificates/retrieve",
            method: "POST",
            body: try JSONEncoder().encode(body),
            bearer: try requireAccessToken()
        )
        let response: RetrieveCertificatesResponseDTO = try decode(data)
        guard let item = response.certificates.first,
              let der = Data(base64Encoded: item.certificate) else {
            throw KSeFError.certificateEnrollmentFailed("KSeF nie zwrócił treści certyfikatu.")
        }
        return der
    }
}
