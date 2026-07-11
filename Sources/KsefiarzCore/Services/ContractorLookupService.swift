import Foundation

/// Dane kontrahenta pobrane z Wykazu podatników VAT („Biała lista”).
public struct ContractorLookupResult: Equatable, Sendable {
    public var name: String
    public var nip: String
    public var street: String
    public var houseNumber: String
    public var apartmentNumber: String
    public var postalCode: String
    public var city: String
    /// Status VAT podmiotu (np. "Czynny", "Zwolniony").
    public var vatStatus: String
    /// Rachunki bankowe podmiotu zgłoszone do wykazu (białej listy).
    public var accountNumbers: [String]
}

/// Pobieranie danych kontrahenta po NIP z publicznego API Wykazu podatników
/// VAT Ministerstwa Finansów (wl-api.mf.gov.pl) — bez klucza API.
public struct ContractorLookupService {

    public enum LookupError: LocalizedError, Equatable {
        case invalidNIP
        case notFound
        case serviceError(String)

        public var errorDescription: String? {
            switch self {
            case .invalidNIP:
                return "Nieprawidłowy NIP — wymagane 10 cyfr z poprawną sumą kontrolną."
            case .notFound:
                return "Nie znaleziono podmiotu o podanym NIP w wykazie podatników VAT."
            case .serviceError(let details):
                return "Błąd usługi wykazu podatników: \(details)"
            }
        }
    }

    private let transport: HTTPTransport
    private let baseURL: URL

    public init(
        transport: HTTPTransport = URLSession.shared,
        baseURL: URL = URL(string: "https://wl-api.mf.gov.pl")!
    ) {
        self.transport = transport
        self.baseURL = baseURL
    }

    /// Pobiera dane podmiotu po NIP (stan na dzisiejszą datę).
    public func lookup(nip: String, date: Date = .now) async throws -> ContractorLookupResult {
        let cleaned = nip.filter(\.isNumber)
        guard InvoiceValidator.isValidNIP(cleaned) else { throw LookupError.invalidNIP }

        let day = FA2Format.dateFormatter.string(from: date)
        let url = baseURL.appending(path: "/api/search/nip/\(cleaned)")
            .appending(queryItems: [URLQueryItem(name: "date", value: day)])
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            // API zwraca błędy jako {"message": "..."} albo {"code","message"}.
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.message
            throw LookupError.serviceError(message ?? "HTTP \(response.statusCode)")
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let subject = decoded.result.subject else { throw LookupError.notFound }

        // Adres: firmy mają workingAddress, JDG często tylko residenceAddress.
        let address = Self.parseAddress(subject.workingAddress ?? subject.residenceAddress ?? "")
        return ContractorLookupResult(
            name: subject.name,
            nip: cleaned,
            street: address.street,
            houseNumber: address.houseNumber,
            apartmentNumber: address.apartmentNumber,
            postalCode: address.postalCode,
            city: address.city,
            vatStatus: subject.statusVat ?? "",
            accountNumbers: subject.accountNumbers ?? []
        )
    }

    /// Sprawdza, czy rachunek figuruje na białej liście podmiotu o danym NIP.
    /// Używa dedykowanego endpointu `check/.../bank-account/...`, bo rozpoznaje
    /// on także RACHUNKI WIRTUALNE (masowe, np. operatorów telekomów), których
    /// nie ma na liście `accountNumbers` podmiotu. Numer jest normalizowany
    /// do 26 cyfr NRB (spacje/myślniki/prefiks PL nie przeszkadzają).
    /// Istotne dla przelewów powyżej 15 000 zł — zapłata na rachunek spoza
    /// wykazu wyklucza koszt podatkowy i grozi solidarną odpowiedzialnością VAT.
    public func verifyAccount(nip: String, account: String, date: Date = .now) async throws -> Bool {
        let cleanedNIP = nip.filter(\.isNumber)
        guard InvoiceValidator.isValidNIP(cleanedNIP) else { throw LookupError.invalidNIP }
        let needle = Self.normalizedAccount(account)
        guard needle.count == 26 else { return false }

        let day = FA2Format.dateFormatter.string(from: date)
        let url = baseURL
            .appending(path: "/api/check/nip/\(cleanedNIP)/bank-account/\(needle)")
            .appending(queryItems: [URLQueryItem(name: "date", value: day)])
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.message
            throw LookupError.serviceError(message ?? "HTTP \(response.statusCode)")
        }
        let decoded = try JSONDecoder().decode(CheckResponse.self, from: data)
        return decoded.result.accountAssigned.uppercased() == "TAK"
    }

    /// Numer rachunku sprowadzony do samych cyfr (NRB, 26 cyfr).
    static func normalizedAccount(_ account: String) -> String {
        String(account.filter(\.isNumber).suffix(26))
    }

    // MARK: Parsowanie adresu

    /// Rozkłada jednolinijkowy adres wykazu („UL. KWIATOWA 12/3, 00-001 WARSZAWA”)
    /// na pola słownika. Format jest niegwarantowany, więc parsowanie jest
    /// defensywne — w razie wątpliwości całość ląduje w polu ulicy.
    static func parseAddress(_ raw: String) -> (
        street: String, houseNumber: String, apartmentNumber: String,
        postalCode: String, city: String
    ) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "", "", "", "") }

        // Część miejscowa: po ostatnim przecinku, z kodem pocztowym NN-NNN.
        var streetPart = trimmed
        var postalCode = ""
        var city = ""
        if let commaIndex = trimmed.range(of: ",", options: .backwards) {
            let cityPart = trimmed[commaIndex.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            if let match = cityPart.range(of: #"^\d{2}-\d{3}"#, options: .regularExpression) {
                postalCode = String(cityPart[match])
                city = cityPart[match.upperBound...].trimmingCharacters(in: .whitespaces)
                streetPart = String(trimmed[..<commaIndex.lowerBound])
            }
        }

        // Numer domu/lokalu: ostatni człon ulicy zaczynający się cyfrą („12”, „12/3”, „12A/3”).
        var street = streetPart.trimmingCharacters(in: .whitespaces)
        var houseNumber = ""
        var apartmentNumber = ""
        if let spaceIndex = street.range(of: " ", options: .backwards) {
            let lastToken = String(street[spaceIndex.upperBound...])
            if lastToken.first?.isNumber == true {
                street = String(street[..<spaceIndex.lowerBound])
                let parts = lastToken.split(separator: "/", maxSplits: 1)
                houseNumber = String(parts.first ?? "")
                apartmentNumber = parts.count > 1 ? String(parts[1]) : ""
            }
        }
        return (street, houseNumber, apartmentNumber, postalCode, city)
    }

    // MARK: DTO odpowiedzi API

    private struct SearchResponse: Decodable {
        let result: Result
        struct Result: Decodable {
            let subject: Subject?
        }
    }

    private struct Subject: Decodable {
        let name: String
        let statusVat: String?
        let workingAddress: String?
        let residenceAddress: String?
        let accountNumbers: [String]?
    }

    private struct CheckResponse: Decodable {
        let result: Result
        struct Result: Decodable {
            let accountAssigned: String
        }
    }

    private struct APIError: Decodable {
        let message: String?
    }
}
