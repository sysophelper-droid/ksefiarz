import Foundation
import Security

// MARK: - Środowiska KSeF 2.0

/// Środowisko API Krajowego Systemu e-Faktur (KSeF 2.0).
public enum KSeFEnvironment: String, CaseIterable, Identifiable, Sendable {
    case test
    case demo
    case production

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .test: return "Testowe"
        case .demo: return "Demo (przedprodukcyjne)"
        case .production: return "Produkcyjne"
        }
    }

    /// Bazowy adres API 2.0 dla danego środowiska.
    public var baseURL: URL {
        switch self {
        case .test: return URL(string: "https://api-test.ksef.mf.gov.pl/api/v2")!
        case .demo: return URL(string: "https://api-demo.ksef.mf.gov.pl/api/v2")!
        case .production: return URL(string: "https://api.ksef.mf.gov.pl/api/v2")!
        }
    }
}

// MARK: - Błędy

/// Błędy zgłaszane przez warstwę usługową KSeF.
public enum KSeFError: LocalizedError, Equatable {
    case missingCredentials
    case notAuthorized
    case badStatus(code: Int, message: String)
    case invalidResponse
    case xmlParsingFailed(String)
    case validationFailed([InvoiceValidationError])
    case encryptionFailed(String)
    case noPublicKey
    case authenticationFailed(String)
    case authenticationTimeout
    case invoiceRejected(String)
    case certificateEnrollmentFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Brak danych uwierzytelniających — uzupełnij NIP oraz certyfikat lub token KSeF w Ustawieniach."
        case .notAuthorized:
            return "Brak aktywnej autoryzacji w KSeF."
        case .badStatus(let code, let message):
            return "Serwer KSeF zwrócił błąd (HTTP \(code)). \(message)"
        case .invalidResponse:
            return "Nieprawidłowa odpowiedź serwera KSeF."
        case .xmlParsingFailed(let details):
            return "Błąd parsowania dokumentu e-Faktury: \(details)"
        case .validationFailed(let errors):
            let list = errors.compactMap(\.errorDescription).joined(separator: " ")
            return "Faktura zawiera błędy: \(list)"
        case .encryptionFailed(let details):
            return "Błąd kryptograficzny: \(details)"
        case .noPublicKey:
            return "KSeF nie udostępnił certyfikatu klucza publicznego wymaganego do szyfrowania."
        case .authenticationFailed(let details):
            return "Uwierzytelnienie w KSeF nie powiodło się: \(details)"
        case .authenticationTimeout:
            return "Przekroczono czas oczekiwania na uwierzytelnienie w KSeF."
        case .invoiceRejected(let details):
            return "KSeF odrzucił fakturę: \(details)"
        case .certificateEnrollmentFailed(let details):
            return "Wniosek o certyfikat KSeF nie powiódł się: \(details)"
        }
    }
}

// MARK: - Transport HTTP

/// Abstrakcja warstwy transportowej HTTP — pozwala podmienić `URLSession`
/// na atrapę w testach jednostkowych.
public protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KSeFError.invalidResponse
        }
        return (data, http)
    }
}

// MARK: - Modele żądań/odpowiedzi API 2.0

struct AuthChallengeResponse: Decodable {
    let challenge: String
    let timestampMs: Int64
}

struct PublicKeyCertificateDTO: Decodable {
    let certificate: String
    let usage: [String]
}

struct InitTokenAuthRequest: Encodable {
    struct ContextIdentifier: Encodable {
        let type: String
        let value: String
    }
    let challenge: String
    let contextIdentifier: ContextIdentifier
    let encryptedToken: String
}

struct TokenInfoDTO: Decodable {
    let token: String
}

struct AuthInitResponse: Decodable {
    let referenceNumber: String
    let authenticationToken: TokenInfoDTO
}

struct StatusInfoDTO: Decodable {
    let code: Int
    let description: String
    let details: [String]?
}

struct AuthStatusResponse: Decodable {
    let status: StatusInfoDTO
}

struct AuthTokensResponse: Decodable {
    let accessToken: TokenInfoDTO
}

struct InvoiceQueryRequestDTO: Encodable {
    struct DateRange: Encodable {
        let dateType: String
        let from: String
        let to: String
    }
    let subjectType: String
    let dateRange: DateRange
}

/// Metadane faktury zwracane przez zapytanie o listę faktur.
public struct KSeFInvoiceMetadata: Decodable, Sendable {
    struct Seller: Decodable {
        let nip: String?
        let name: String?
    }
    struct BuyerIdentifier: Decodable {
        let type: String?
        let value: String?
    }
    struct Buyer: Decodable {
        let identifier: BuyerIdentifier?
        let name: String?
    }

    public let ksefNumber: String
    let invoiceNumber: String?
    let issueDate: String?
    let seller: Seller?
    let buyer: Buyer?
    let netAmount: Double?
    let vatAmount: Double?
    let grossAmount: Double?
}

struct InvoiceQueryResponseDTO: Decodable {
    let hasMore: Bool?
    let invoices: [KSeFInvoiceMetadata]
}

struct FormCodeDTO: Encodable {
    let systemCode: String
    let schemaVersion: String
    let value: String
}

struct OpenOnlineSessionRequestDTO: Encodable {
    struct EncryptionInfo: Encodable {
        let encryptedSymmetricKey: String
        let initializationVector: String
    }
    let formCode: FormCodeDTO
    let encryption: EncryptionInfo
}

struct OpenOnlineSessionResponseDTO: Decodable {
    let referenceNumber: String
}

struct SendInvoicePayloadDTO: Encodable {
    let invoiceHash: String
    let invoiceSize: Int
    let encryptedInvoiceHash: String
    let encryptedInvoiceSize: Int
    let encryptedInvoiceContent: String
    /// Faktura wystawiona w trybie offline (offline24/awaria) — dosyłana
    /// po terminie wystawienia; data wystawienia pozostaje z pola P_1.
    let offlineMode: Bool
}

struct SendInvoiceResponseDTO: Decodable {
    let referenceNumber: String
}

struct SessionInvoiceStatusDTO: Decodable {
    let ksefNumber: String?
    let status: StatusInfoDTO?
    let acquisitionDate: String?
}

/// Standardowy format błędu API (application/problem+json).
struct ProblemDetailsDTO: Decodable {
    struct ApiError: Decodable {
        let description: String?
    }
    let title: String?
    let detail: String?
    let errors: [ApiError]?
}

/// Wynik wysyłki faktury do KSeF.
public struct KSeFSendResult: Sendable {
    /// Referencja faktury w sesji — dostępna od razu po przesłaniu.
    public let invoiceReferenceNumber: String
    /// Docelowy numer KSeF; nil oznacza, że dokument nadal jest przetwarzany.
    public let ksefNumber: String?
    /// Numer referencyjny sesji interaktywnej — potrzebny do pobrania UPO.
    public let sessionReferenceNumber: String
    /// Wygenerowany i wysłany dokument XML.
    public let xml: String
    /// Stan zwrócony po końcowym odpytywaniu w ramach wysyłki.
    public let processingResult: KSeFInvoiceProcessingResult

    /// Zgodność źródłowa ze starszym kodem. Nowy kod nie powinien używać
    /// tej wartości jako numeru KSeF, bo może to być tylko referencja.
    public var elementReferenceNumber: String {
        ksefNumber ?? invoiceReferenceNumber
    }
}

/// Wynik pojedynczego sprawdzenia statusu faktury wysłanej do KSeF.
public struct KSeFInvoiceProcessingResult: Equatable, Sendable {
    public let status: KSeFSubmissionStatus
    public let statusCode: Int?
    public let description: String
    public let ksefNumber: String?
    public let acquisitionDate: Date?

    public init(
        status: KSeFSubmissionStatus,
        statusCode: Int?,
        description: String,
        ksefNumber: String? = nil,
        acquisitionDate: Date? = nil
    ) {
        self.status = status
        self.statusCode = statusCode
        self.description = description
        self.ksefNumber = ksefNumber
        self.acquisitionDate = acquisitionDate
    }
}

// MARK: - Usługa KSeF 2.0

/// Warstwa usługowa integracji z Krajowym Systemem e-Faktur (API 2.0).
///
/// Przepływ uwierzytelnienia tokenem KSeF:
/// 1. `POST /auth/challenge` — pobranie wyzwania i znacznika czasu,
/// 2. zaszyfrowanie ciągu `token|timestampMs` RSA-OAEP (SHA-256) kluczem publicznym MF,
/// 3. `POST /auth/ksef-token` — rozpoczęcie operacji uwierzytelnienia,
/// 4. `GET /auth/{referenceNumber}` — odpytywanie o status do kodu 200,
/// 5. `POST /auth/token/redeem` — wymiana na właściwy `accessToken` (JWT).
///
/// Wysyłka faktur odbywa się w sesji interaktywnej z obowiązkowym szyfrowaniem
/// AES-256-CBC (klucz symetryczny zaszyfrowany kluczem publicznym MF).
public final class KSeFService {

    /// Resolver klucza publicznego z certyfikatu DER — podmieniany w testach,
    /// aby nie zależeć od prawdziwych certyfikatów Ministerstwa Finansów.
    public typealias PublicKeyResolver = (Data) throws -> SecKey

    public let environment: KSeFEnvironment
    private let nip: String
    private let authToken: String
    /// Certyfikat KSeF (typ 1) — preferowana metoda uwierzytelnienia;
    /// przy braku lub niepowodzeniu następuje powrót do tokenu KSeF.
    private let certificate: KSeFCertificate?
    private let transport: HTTPTransport
    private let publicKeyResolver: PublicKeyResolver

    /// Odstęp między kolejnymi odpytaniami o status (testy ustawiają 0).
    var pollInterval: TimeInterval = 1.0
    /// Maksymalna liczba odpytań o status operacji.
    var maxPollAttempts = 30
    /// Odczekanie po odpowiedzi HTTP 429 (limit KSeF: 8 żądań/s) przed ponowieniem.
    var rateLimitRetryDelay: TimeInterval = 1.2
    /// Maksymalna liczba ponowień po HTTP 429.
    var rateLimitMaxRetries = 5

    /// Token dostępowy (JWT) aktywnej autoryzacji.
    public private(set) var accessToken: String?

    /// Metoda, którą uzyskano bieżący token dostępowy.
    public enum AuthenticationMethod: String, Sendable {
        case certificate = "certyfikat"
        case token = "token"
    }
    public private(set) var lastAuthenticationMethod: AuthenticationMethod?

    public init(
        environment: KSeFEnvironment = .test,
        nip: String,
        authToken: String,
        certificate: KSeFCertificate? = nil,
        transport: HTTPTransport = URLSession.shared,
        publicKeyResolver: @escaping PublicKeyResolver = KSeFCrypto.publicKey(fromDERCertificate:)
    ) {
        self.environment = environment
        self.nip = nip
        self.authToken = authToken
        self.certificate = certificate
        self.transport = transport
        self.publicKeyResolver = publicKeyResolver
    }

    // MARK: Uwierzytelnienie

    /// Przeprowadza pełne uwierzytelnienie i zwraca token dostępowy.
    /// Preferuje certyfikat KSeF (podpis XAdES); gdy certyfikatu brak albo
    /// uwierzytelnienie nim się nie powiedzie, wraca do tokenu KSeF.
    @discardableResult
    public func authenticate() async throws -> String {
        guard !nip.isEmpty else { throw KSeFError.missingCredentials }

        if let certificate, certificate.info?.isValid() == true {
            do {
                return try await authenticateWithCertificate(certificate)
            } catch {
                // Fail-back do tokenu tylko, gdy w ogóle jest skonfigurowany.
                guard !authToken.isEmpty else { throw error }
            }
        }
        guard !authToken.isEmpty else { throw KSeFError.missingCredentials }
        return try await authenticateWithToken()
    }

    /// Uwierzytelnienie podpisem XAdES wykonanym certyfikatem KSeF:
    /// challenge → podpisany AuthTokenRequest → /auth/xades-signature →
    /// polling → redeem.
    @discardableResult
    public func authenticateWithCertificate(_ certificate: KSeFCertificate) async throws -> String {
        let challengeData = try await perform(path: "auth/challenge", method: "POST", body: nil, bearer: nil)
        let challenge: AuthChallengeResponse = try decode(challengeData)

        let signedXML = try XAdESSigner.signAuthTokenRequest(
            challenge: challenge.challenge,
            nip: nip,
            certificate: certificate
        )
        let initData = try await perform(
            path: "auth/xades-signature",
            method: "POST",
            body: Data(signedXML.utf8),
            bearer: nil,
            contentType: "application/xml"
        )
        let initResponse: AuthInitResponse = try decode(initData)
        let operationToken = initResponse.authenticationToken.token

        try await waitForAuthentication(
            referenceNumber: initResponse.referenceNumber,
            operationToken: operationToken
        )

        let redeemData = try await perform(path: "auth/token/redeem", method: "POST", body: nil, bearer: operationToken)
        let tokens: AuthTokensResponse = try decode(redeemData)
        accessToken = tokens.accessToken.token
        lastAuthenticationMethod = .certificate
        return tokens.accessToken.token
    }

    /// Uwierzytelnienie tokenem KSeF (RSA-OAEP na "token|timestampMs").
    @discardableResult
    func authenticateWithToken() async throws -> String {
        // 1. Wyzwanie autoryzacyjne.
        let challengeData = try await perform(path: "auth/challenge", method: "POST", body: nil, bearer: nil)
        let challenge: AuthChallengeResponse = try decode(challengeData)

        // 2. Szyfrowanie "token|timestampMs" kluczem publicznym MF.
        let publicKey = try await fetchEncryptionKey(usage: "KsefTokenEncryption")
        let plaintext = Data("\(authToken)|\(challenge.timestampMs)".utf8)
        let encryptedToken = try KSeFCrypto.rsaEncryptOAEPSHA256(plaintext, publicKey: publicKey)

        // 3. Rozpoczęcie operacji uwierzytelnienia.
        let initRequest = InitTokenAuthRequest(
            challenge: challenge.challenge,
            contextIdentifier: .init(type: "Nip", value: nip),
            encryptedToken: encryptedToken.base64EncodedString()
        )
        let initData = try await perform(
            path: "auth/ksef-token",
            method: "POST",
            body: try JSONEncoder().encode(initRequest),
            bearer: nil
        )
        let initResponse: AuthInitResponse = try decode(initData)
        let operationToken = initResponse.authenticationToken.token

        // 4. Oczekiwanie na zakończenie uwierzytelnienia (status 200).
        try await waitForAuthentication(
            referenceNumber: initResponse.referenceNumber,
            operationToken: operationToken
        )

        // 5. Wymiana tokenu operacji na właściwy token dostępowy.
        let redeemData = try await perform(path: "auth/token/redeem", method: "POST", body: nil, bearer: operationToken)
        let tokens: AuthTokensResponse = try decode(redeemData)
        accessToken = tokens.accessToken.token
        lastAuthenticationMethod = .token
        return tokens.accessToken.token
    }

    /// Odpytuje o status operacji uwierzytelnienia do skutku (kod 200) lub błędu.
    private func waitForAuthentication(referenceNumber: String, operationToken: String) async throws {
        for attempt in 0..<maxPollAttempts {
            let statusData = try await perform(
                path: "auth/\(referenceNumber)",
                method: "GET",
                body: nil,
                bearer: operationToken
            )
            let response: AuthStatusResponse = try decode(statusData)

            switch response.status.code {
            case 200:
                return
            case 400...:
                let details = ([response.status.description] + (response.status.details ?? []))
                    .joined(separator: " ")
                throw KSeFError.authenticationFailed(details)
            default:
                // Uwierzytelnianie w toku — czekamy i ponawiamy.
                if attempt < maxPollAttempts - 1, pollInterval > 0 {
                    try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                }
            }
        }
        throw KSeFError.authenticationTimeout
    }

    /// Uwierzytelnia, jeśli nie ma jeszcze ważnego tokenu dostępowego.
    func ensureAuthenticated() async throws {
        if accessToken == nil {
            try await authenticate()
        }
    }

    /// Pobiera certyfikat klucza publicznego MF o wskazanym przeznaczeniu
    /// i zwraca gotowy do użycia klucz publiczny.
    private func fetchEncryptionKey(usage: String) async throws -> SecKey {
        let data = try await perform(path: "security/public-key-certificates", method: "GET", body: nil, bearer: nil)
        let certificates: [PublicKeyCertificateDTO] = try decode(data)
        guard let match = certificates.first(where: { $0.usage.contains(usage) }),
              let der = Data(base64Encoded: match.certificate) else {
            throw KSeFError.noPublicKey
        }
        return try publicKeyResolver(der)
    }

    // MARK: Pobieranie faktur (inbound)

    /// Rola, w jakiej występujemy na pobieranych fakturach.
    public enum InvoiceRole: String, Sendable {
        /// Sprzedawca (Podmiot1) — nasze faktury sprzedażowe wystawione w KSeF.
        case seller = "Subject1"
        /// Nabywca (Podmiot2) — faktury zakupowe wystawione na nasz NIP.
        case buyer = "Subject2"
    }

    /// Pobiera faktury zakupowe (wystawione na nasz NIP — Subject2) z podanego
    /// zakresu dat. Dla każdej faktury pobierany jest oryginalny dokument XML.
    public func fetchPurchaseInvoices(from: Date, to: Date) async throws -> [FA2InvoiceData] {
        try await fetchInvoices(role: .buyer, from: from, to: to)
    }

    /// Pobiera faktury sprzedażowe (wystawione przez nas — Subject1) z podanego
    /// zakresu dat.
    public func fetchSalesInvoices(from: Date, to: Date) async throws -> [FA2InvoiceData] {
        try await fetchInvoices(role: .seller, from: from, to: to)
    }

    /// Pobiera faktury, w których występujemy we wskazanej roli.
    /// - Parameter skipDocumentsFor: numery KSeF, dla których NIE pobieramy
    ///   dokumentu XML (mamy już komplet danych lokalnie) — oszczędza
    ///   limit API pobrań faktur (16/min).
    public func fetchInvoices(
        role: InvoiceRole,
        from: Date,
        to: Date,
        skipDocumentsFor: Set<String> = []
    ) async throws -> [FA2InvoiceData] {
        try await ensureAuthenticated()

        var invoices: [FA2InvoiceData] = []
        var pageOffset = 0

        // Stronicowanie — maks. 10 stron po 100 faktur na jedno odświeżenie.
        while pageOffset < 10 {
            let page = try await queryInvoiceMetadata(role: role, from: from, to: to, pageOffset: pageOffset)

            for metadata in page.invoices {
                let skipDocument = skipDocumentsFor.contains(metadata.ksefNumber)
                invoices.append(await buildInvoice(from: metadata, skipDocument: skipDocument))
            }

            guard page.hasMore == true else { break }
            pageOffset += 1
        }
        return invoices
    }

    /// Zapytanie o metadane faktur dla wskazanej roli podmiotu.
    private func queryInvoiceMetadata(role: InvoiceRole, from: Date, to: Date, pageOffset: Int) async throws -> InvoiceQueryResponseDTO {
        let formatter = FA2Format.timestampFormatter
        let body = InvoiceQueryRequestDTO(
            subjectType: role.rawValue,
            dateRange: .init(
                dateType: "Issue",
                from: formatter.string(from: from),
                to: formatter.string(from: to)
            )
        )
        let data = try await perform(
            path: "invoices/query/metadata?pageOffset=\(pageOffset)&pageSize=100",
            method: "POST",
            body: try JSONEncoder().encode(body),
            bearer: try requireAccessToken()
        )
        return try decode(data)
    }

    /// Buduje dane faktury: preferuje sparsowany dokument XML,
    /// a przy niepowodzeniu pobrania/parsowania korzysta z metadanych.
    private func buildInvoice(from metadata: KSeFInvoiceMetadata, skipDocument: Bool = false) async -> FA2InvoiceData {
        var rawXML = ""
        var parsed: FA2InvoiceData?

        if !skipDocument, let xmlData = try? await downloadInvoice(ksefNumber: metadata.ksefNumber) {
            rawXML = String(data: xmlData, encoding: .utf8) ?? ""
            parsed = try? FA2XMLParser.parse(data: xmlData)
        }

        if var invoice = parsed {
            invoice.ksefId = metadata.ksefNumber
            return invoice
        }

        // Awaryjnie: dane z metadanych (bez szczegółów dostępnych tylko w XML).
        let issueDate = metadata.issueDate.flatMap { FA2Format.dateFormatter.date(from: $0) } ?? .now
        return FA2InvoiceData(
            ksefId: metadata.ksefNumber,
            invoiceNumber: metadata.invoiceNumber ?? metadata.ksefNumber,
            issueDate: issueDate,
            sellerName: metadata.seller?.name ?? "",
            sellerNIP: metadata.seller?.nip ?? "",
            buyerName: metadata.buyer?.name ?? "",
            buyerNIP: metadata.buyer?.identifier?.value ?? "",
            netAmount: metadata.netAmount ?? 0,
            vatAmount: metadata.vatAmount ?? 0,
            grossAmount: metadata.grossAmount ?? 0,
            paymentDueDate: nil,
            rawXML: rawXML
        )
    }

    /// Pobiera oryginalny dokument XML faktury po numerze KSeF.
    func downloadInvoice(ksefNumber: String) async throws -> Data {
        try await perform(
            path: "invoices/ksef/\(ksefNumber)",
            method: "GET",
            body: nil,
            bearer: try requireAccessToken()
        )
    }

    // MARK: Wystawianie faktur (outbound)

    /// Waliduje dane, generuje XML FA(3) i wysyła fakturę w sesji interaktywnej
    /// (z obowiązkowym szyfrowaniem AES-256-CBC). Zwraca numer KSeF faktury
    /// lub numer referencyjny przesyłki, jeśli numer nie został jeszcze nadany.
    public func sendInvoice(_ draft: InvoiceDraft) async throws -> KSeFSendResult {
        // Walidacja przed jakąkolwiek komunikacją sieciową.
        let errors = InvoiceValidator.validate(draft)
        guard errors.isEmpty else {
            throw KSeFError.validationFailed(errors)
        }
        let xml = FA2XMLGenerator.generateXML(for: draft)
        return try await sendInvoiceXML(Data(xml.utf8), offlineMode: false)
    }

    /// Wysyła gotowy dokument XML — bez ponownego generowania. Ścieżka
    /// dosyłania dokumentów offline24: wysłane bajty muszą być identyczne
    /// z tymi, z których policzono skrót do kodów QR na wydruku.
    public func sendInvoiceXML(_ xmlData: Data, offlineMode: Bool) async throws -> KSeFSendResult {
        try await ensureAuthenticated()
        let xml = String(decoding: xmlData, as: UTF8.self)

        // 1. Klucz symetryczny sesji, zaszyfrowany kluczem publicznym MF.
        let publicKey = try await fetchEncryptionKey(usage: "SymmetricKeyEncryption")
        let aesKey = try KSeFCrypto.randomBytes(32)
        let iv = try KSeFCrypto.randomBytes(16)
        let encryptedKey = try KSeFCrypto.rsaEncryptOAEPSHA256(aesKey, publicKey: publicKey)

        // 2. Otwarcie sesji interaktywnej dla schemy FA(3) — musi się zgadzać
        // z KodFormularza generowanego dokumentu.
        let openRequest = OpenOnlineSessionRequestDTO(
            formCode: FormCodeDTO(systemCode: "FA (3)", schemaVersion: "1-0E", value: "FA"),
            encryption: .init(
                encryptedSymmetricKey: encryptedKey.base64EncodedString(),
                initializationVector: iv.base64EncodedString()
            )
        )
        let sessionData = try await perform(
            path: "sessions/online",
            method: "POST",
            body: try JSONEncoder().encode(openRequest),
            bearer: try requireAccessToken()
        )
        let session: OpenOnlineSessionResponseDTO = try decode(sessionData)

        // 3. Wysyłka zaszyfrowanej faktury wraz ze skrótami SHA-256.
        let encryptedInvoice = try KSeFCrypto.aesEncryptCBC(xmlData, key: aesKey, iv: iv)
        let payload = SendInvoicePayloadDTO(
            invoiceHash: KSeFCrypto.sha256Base64(xmlData),
            invoiceSize: xmlData.count,
            encryptedInvoiceHash: KSeFCrypto.sha256Base64(encryptedInvoice),
            encryptedInvoiceSize: encryptedInvoice.count,
            encryptedInvoiceContent: encryptedInvoice.base64EncodedString(),
            offlineMode: offlineMode
        )
        let sendData = try await perform(
            path: "sessions/online/\(session.referenceNumber)/invoices",
            method: "POST",
            body: try JSONEncoder().encode(payload),
            bearer: try requireAccessToken()
        )
        let sendResponse: SendInvoiceResponseDTO = try decode(sendData)

        // 4. Zamknięcie sesji (uruchamia generowanie UPO po stronie KSeF).
        _ = try await perform(
            path: "sessions/online/\(session.referenceNumber)/close",
            method: "POST",
            body: nil,
            bearer: try requireAccessToken()
        )

        // 5. Odpytanie o nadany numer KSeF (best effort — przetwarzanie bywa asynchroniczne).
        let processingResult = try await waitForInvoiceResult(
            sessionReference: session.referenceNumber,
            invoiceReference: sendResponse.referenceNumber
        )

        return KSeFSendResult(
            invoiceReferenceNumber: sendResponse.referenceNumber,
            ksefNumber: processingResult.ksefNumber,
            sessionReferenceNumber: session.referenceNumber,
            xml: xml,
            processingResult: processingResult
        )
    }

    // MARK: UPO

    /// Pobiera Urzędowe Poświadczenie Odbioru (UPO) faktury — dokument XML
    /// potwierdzający przyjęcie faktury przez KSeF.
    /// Wymaga numeru referencyjnego sesji, w której faktura została wysłana.
    public func downloadUPO(sessionReference: String, ksefNumber: String) async throws -> Data {
        try await ensureAuthenticated()
        return try await perform(
            path: "sessions/\(sessionReference)/invoices/ksef/\(ksefNumber)/upo",
            method: "GET",
            body: nil,
            bearer: try requireAccessToken()
        )
    }

    /// Pobiera aktualny status faktury w sesji. Odrzucenie jest zwracane jako
    /// stan domenowy, dzięki czemu aplikacja może je trwale pokazać zamiast
    /// gubić informację w jednorazowym komunikacie błędu.
    public func fetchInvoiceStatus(
        sessionReference: String,
        invoiceReference: String
    ) async throws -> KSeFInvoiceProcessingResult {
        try await ensureAuthenticated()
        let data = try await perform(
            path: "sessions/\(sessionReference)/invoices/\(invoiceReference)",
            method: "GET",
            body: nil,
            bearer: try requireAccessToken()
        )
        return processingResult(from: try decode(data))
    }

    /// Czeka na nadanie numeru KSeF wysłanej fakturze.
    /// Zwraca `nil`, jeśli numer nie został nadany w wyznaczonym czasie
    /// (faktura nadal może zostać przyjęta — przetwarzanie jest asynchroniczne).
    private func waitForInvoiceResult(
        sessionReference: String,
        invoiceReference: String
    ) async throws -> KSeFInvoiceProcessingResult {
        var lastResult = KSeFInvoiceProcessingResult(
            status: .processing,
            statusCode: nil,
            description: "Faktura oczekuje na przetworzenie przez KSeF."
        )
        for attempt in 0..<maxPollAttempts {
            let data = try await perform(
                path: "sessions/\(sessionReference)/invoices/\(invoiceReference)",
                method: "GET",
                body: nil,
                bearer: try requireAccessToken()
            )
            let result = processingResult(from: try decode(data))
            lastResult = result
            if result.status == .accepted || result.status == .rejected { return result }
            if attempt < maxPollAttempts - 1, pollInterval > 0 {
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
        return lastResult
    }

    private func processingResult(
        from response: SessionInvoiceStatusDTO
    ) -> KSeFInvoiceProcessingResult {
        let code = response.status?.code
        let details = ([response.status?.description] + (response.status?.details ?? []))
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let description = details.isEmpty
            ? "Faktura oczekuje na przetworzenie przez KSeF."
            : details
        let acquisitionDate = response.acquisitionDate.flatMap {
            ISO8601DateFormatter().date(from: $0)
        }

        if let number = response.ksefNumber {
            return KSeFInvoiceProcessingResult(
                status: .accepted,
                statusCode: code,
                description: description,
                ksefNumber: number,
                acquisitionDate: acquisitionDate
            )
        }
        if let code, code >= 400 {
            return KSeFInvoiceProcessingResult(
                status: .rejected,
                statusCode: code,
                description: description
            )
        }
        return KSeFInvoiceProcessingResult(
            status: .processing,
            statusCode: code,
            description: description
        )
    }

    // MARK: Pomocnicze

    func requireAccessToken() throws -> String {
        guard let token = accessToken else { throw KSeFError.notAuthorized }
        return token
    }

    /// Buduje i wykonuje żądanie HTTP, weryfikując kod odpowiedzi.
    /// Treść błędów `application/problem+json` jest tłumaczona na czytelny komunikat.
    func perform(
        path: String,
        method: String,
        body: Data?,
        bearer: String?,
        contentType: String = "application/json"
    ) async throws -> Data {
        guard let url = URL(string: environment.baseURL.absoluteString + "/" + path) else {
            throw KSeFError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }

        // KSeF limituje liczbę żądań (8/s) — odpowiedź 429 ponawiamy
        // po odczekaniu, zamiast gubić dane.
        var attempt = 0
        while true {
            let (data, response) = try await transport.send(request)

            if response.statusCode == 429, attempt < rateLimitMaxRetries {
                attempt += 1
                if rateLimitRetryDelay > 0 {
                    // Wykładniczy backoff (limit minutowy potrzebuje dłuższych
                    // przerw niż sekundowy), z górnym ograniczeniem 15 s.
                    let delay = min(rateLimitRetryDelay * pow(2, Double(attempt - 1)), 15)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                continue
            }
            guard (200...299).contains(response.statusCode) else {
                throw KSeFError.badStatus(code: response.statusCode, message: errorMessage(from: data))
            }
            return data
        }
    }

    /// Wyciąga czytelny opis błędu z odpowiedzi serwera.
    private func errorMessage(from data: Data) -> String {
        if let problem = try? JSONDecoder().decode(ProblemDetailsDTO.self, from: data) {
            let errorList = (problem.errors ?? []).compactMap(\.description)
            let parts = [problem.detail ?? problem.title].compactMap { $0 } + errorList
            if !parts.isEmpty {
                return parts.joined(separator: " ")
            }
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return String(raw.prefix(300))
    }

    /// Dekoduje odpowiedź JSON, mapując błędy na `KSeFError.invalidResponse`.
    func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KSeFError.invalidResponse
        }
    }
}
