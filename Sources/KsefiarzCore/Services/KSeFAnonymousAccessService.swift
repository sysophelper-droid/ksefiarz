import Foundation

/// Typ identyfikatora nabywcy wymagany przez publiczną bramkę anonimowego
/// dostępu do faktury KSeF.
public enum AnonymousInvoiceBuyerIdentifierType: String, CaseIterable, Identifiable, Sendable {
    case nip = "Nip"
    case vatUE = "VatUe"
    case other = "Other"
    case none = "None"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nip: return "NIP"
        case .vatUE: return "Numer VAT-UE"
        case .other: return "Inny identyfikator podatkowy"
        case .none: return "Brak identyfikatora"
        }
    }
}

/// Dane identyfikujące pojedynczą fakturę w anonimowym dostępie KSeF.
/// Zakres odpowiada § 8 rozporządzenia w sprawie korzystania z KSeF oraz
/// formularzowi publicznej bramki MF.
public struct AnonymousInvoiceAccessRequest: Equatable, Sendable {
    public var ksefNumber: String
    public var invoiceNumber: String
    public var buyerIdentifierType: AnonymousInvoiceBuyerIdentifierType
    public var buyerIdentifierValue: String
    public var buyerName: String?
    public var grossAmount: Decimal

    public init(
        ksefNumber: String,
        invoiceNumber: String,
        buyerIdentifierType: AnonymousInvoiceBuyerIdentifierType = .nip,
        buyerIdentifierValue: String,
        buyerName: String?,
        grossAmount: Decimal
    ) {
        self.ksefNumber = ksefNumber
        self.invoiceNumber = invoiceNumber
        self.buyerIdentifierType = buyerIdentifierType
        self.buyerIdentifierValue = buyerIdentifierValue
        self.buyerName = buyerName
        self.grossAmount = grossAmount
    }
}

/// Błędy publicznej, anonimowej bramki pobierania faktur.
public enum AnonymousInvoiceAccessError: LocalizedError, Equatable {
    case invalidKSeFNumber
    case missingInvoiceNumber
    case missingBuyerIdentifier
    case gatewayHTTPStatus(Int)
    case invalidGatewayResponse
    case invoiceNotFound
    case missingInvoiceXML

    public var errorDescription: String? {
        switch self {
        case .invalidKSeFNumber:
            return "Numer KSeF ma nieprawidłowy format."
        case .missingInvoiceNumber:
            return "Podaj numer faktury nadany przez sprzedawcę."
        case .missingBuyerIdentifier:
            return "Podaj identyfikator podatkowy nabywcy albo wybierz „Brak identyfikatora”."
        case .gatewayHTTPStatus(let status):
            return "Publiczna bramka KSeF zwróciła błąd HTTP \(status)."
        case .invalidGatewayResponse:
            return "Publiczna bramka KSeF zwróciła nieprawidłową odpowiedź."
        case .invoiceNotFound:
            return "Nie znaleziono faktury spełniającej podane kryteria. Sprawdź wszystkie dane i spróbuj ponownie."
        case .missingInvoiceXML:
            return "KSeF potwierdził fakturę, ale nie udostępnił jej pliku XML."
        }
    }
}

/// Publiczna bramka anonimowego dostępu MF.
///
/// To odrębna od integratorskiego API 2.0, dwuetapowa usługa WWW. Nie używa
/// tokenu ani certyfikatu KSeF: pobiera token anty-CSRF, utrzymuje ciasteczko
/// sesji, wysyła numer KSeF, a następnie pozostałe dane identyfikujące.
public final class KSeFAnonymousAccessService {
    public let environment: KSeFEnvironment
    private let transport: HTTPTransport

    public init(environment: KSeFEnvironment, transport: HTTPTransport? = nil) {
        self.environment = environment
        if let transport {
            self.transport = transport
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieAcceptPolicy = .always
            configuration.httpShouldSetCookies = true
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            self.transport = URLSession(configuration: configuration)
        }
    }

    /// Pobiera oryginalny XML pojedynczej faktury bez uwierzytelnienia.
    public func downloadInvoice(_ input: AnonymousInvoiceAccessRequest) async throws -> Data {
        let request = try normalized(input)
        let searchURL = gatewayBaseURL.appendingPathComponent("invoice/search")

        // Etap 1: formularz z tokenem anty-CSRF i ciasteczkiem sesyjnym.
        let firstPage = try await send(makeRequest(url: searchURL, method: "GET"))
        let firstToken = try antiForgeryToken(in: firstPage)

        // Etap 2: numer KSeF. URLSession podąża za przekierowaniem na formularz
        // pozostałych danych, zachowując ciasteczko w sesji efemerycznej.
        let numberPage = try await send(formRequest(
            url: searchURL,
            referer: searchURL,
            fields: [
                ("KsefNumber", request.ksefNumber),
                ("RedirectUrl", taxpayerAppURL.absoluteString),
                ("__RequestVerificationToken", firstToken),
            ]
        ))
        let detailsToken = try antiForgeryToken(in: numberPage)

        // Etap 3: komplet danych identyfikujących. Pomyślna odpowiedź zawiera
        // oryginalny XML w ukrytym atrybucie data-xml-text (Base64).
        let detailsURL = verificationURL(ksefNumber: request.ksefNumber)
        var fields: [(String, String)] = [
            ("InvoiceNumber", request.invoiceNumber),
            ("BuyerIdentifierType", request.buyerIdentifierType.rawValue),
            ("BuyerIdentifierValue", request.buyerIdentifierValue),
            ("BuyerName", request.buyerName ?? ""),
            ("Amount", Self.amountString(request.grossAmount)),
            ("__RequestVerificationToken", detailsToken),
        ]
        // Bramka oczekuje pustej wartości dla wariantu bez identyfikatora.
        if request.buyerIdentifierType == .none {
            fields = fields.map { $0.0 == "BuyerIdentifierValue" ? ($0.0, "") : $0 }
        }
        let resultPage = try await send(formRequest(
            url: detailsURL,
            referer: detailsURL.deletingQueryItems(),
            fields: fields
        ))
        return try invoiceXML(in: resultPage)
    }

    // MARK: Adresy środowisk

    var gatewayBaseURL: URL {
        URL(string: "https://\(KSeFVerificationLink.qrHost(for: environment))")!
    }

    private var taxpayerAppURL: URL {
        switch environment {
        case .test: return URL(string: "https://ap-test.ksef.mf.gov.pl/web/")!
        case .demo: return URL(string: "https://ap-demo.ksef.mf.gov.pl/web/")!
        case .production: return URL(string: "https://ap.ksef.mf.gov.pl/web/")!
        }
    }

    private func verificationURL(ksefNumber: String) -> URL {
        let base = gatewayBaseURL
            .appendingPathComponent("client-app")
            .appendingPathComponent("invoice")
            .appendingPathComponent("search")
            .appendingPathComponent(ksefNumber)
            .appendingPathComponent("verify-download")
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "handler", value: "Format")]
        return components.url!
    }

    // MARK: Żądania HTTP

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 Ksefiarz/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }

    private func formRequest(
        url: URL,
        referer: URL,
        fields: [(String, String)]
    ) -> URLRequest {
        var request = makeRequest(url: url, method: "POST")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(gatewayBaseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw AnonymousInvoiceAccessError.gatewayHTTPStatus(response.statusCode)
        }
        return data
    }

    // MARK: Walidacja i parsowanie HTML

    private func normalized(_ input: AnonymousInvoiceAccessRequest) throws -> AnonymousInvoiceAccessRequest {
        var result = input
        result.ksefNumber = input.ksefNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let pattern = #"^[0-9]{10}-[0-9]{8}-[0-9A-Z]{12}-[0-9A-Z]{2}$"#
        guard result.ksefNumber.range(of: pattern, options: .regularExpression) != nil else {
            throw AnonymousInvoiceAccessError.invalidKSeFNumber
        }
        result.invoiceNumber = input.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.invoiceNumber.isEmpty else {
            throw AnonymousInvoiceAccessError.missingInvoiceNumber
        }
        switch input.buyerIdentifierType {
        case .nip:
            result.buyerIdentifierValue = input.buyerIdentifierValue.filter(\.isNumber)
        case .vatUE:
            result.buyerIdentifierValue = input.buyerIdentifierValue
                .filter { !$0.isWhitespace && $0 != "-" }
                .uppercased()
        case .other:
            result.buyerIdentifierValue = input.buyerIdentifierValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .none:
            result.buyerIdentifierValue = ""
        }
        if input.buyerIdentifierType != .none, result.buyerIdentifierValue.isEmpty {
            throw AnonymousInvoiceAccessError.missingBuyerIdentifier
        }
        let buyerName = input.buyerName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        result.buyerName = buyerName?.isEmpty == false ? buyerName : nil
        return result
    }

    private func antiForgeryToken(in data: Data) throws -> String {
        let html = try htmlString(data)
        let pattern = #"name=[\"']__RequestVerificationToken[\"'][^>]*value=[\"']([^\"']+)[\"']"#
        guard let token = Self.firstCapture(pattern, in: html), !token.isEmpty else {
            throw AnonymousInvoiceAccessError.invalidGatewayResponse
        }
        return Self.decodeHTMLEntities(token)
    }

    private func invoiceXML(in data: Data) throws -> Data {
        let html = try htmlString(data)
        if html.localizedCaseInsensitiveContains("Nie znaleziono faktury") {
            throw AnonymousInvoiceAccessError.invoiceNotFound
        }
        let pattern = #"data-xml-text=[\"']([^\"']*)[\"']"#
        guard let encoded = Self.firstCapture(pattern, in: html) else {
            throw AnonymousInvoiceAccessError.invalidGatewayResponse
        }
        guard !encoded.isEmpty else {
            throw AnonymousInvoiceAccessError.missingInvoiceXML
        }
        let base64 = Self.decodeHTMLEntities(encoded)
        guard let xml = Data(base64Encoded: base64), !xml.isEmpty else {
            throw AnonymousInvoiceAccessError.invalidGatewayResponse
        }
        return xml
    }

    private func htmlString(_ data: Data) throws -> String {
        guard let html = String(data: data, encoding: .utf8) else {
            throw AnonymousInvoiceAccessError.invalidGatewayResponse
        }
        return html
    }

    static func amountString(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0,00"
    }

    static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Dekoduje encje występujące w atrybucie Base64 (bramka koduje m.in.
    /// znak `+` jako `&#x2B;`). Obsługuje też encje dziesiętne i nazwane.
    static func decodeHTMLEntities(_ input: String) -> String {
        var result = input
        let expression = try? NSRegularExpression(
            pattern: #"&#(?:x([0-9A-Fa-f]+)|([0-9]+));"#
        )
        let matches = expression?.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        ) ?? []
        for match in matches.reversed() {
            let source = result as NSString
            let hex = match.range(at: 1).location == NSNotFound
                ? nil : source.substring(with: match.range(at: 1))
            let decimal = match.range(at: 2).location == NSNotFound
                ? nil : source.substring(with: match.range(at: 2))
            let value = hex.flatMap { UInt32($0, radix: 16) }
                ?? decimal.flatMap { UInt32($0, radix: 10) }
            guard let value, let scalar = UnicodeScalar(value),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: String(Character(scalar)))
        }
        return result
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

private extension URL {
    func deletingQueryItems() -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.query = nil
        return components.url!
    }
}
