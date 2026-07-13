import Foundation

/// Wynik sprawdzenia numeru VAT-UE kontrahenta w systemie VIES (unijna baza
/// VAT — VAT Information Exchange System Komisji Europejskiej).
public struct VIESLookupResult: Equatable, Sendable {
    /// Czy numer VAT-UE jest aktywny w VIES (pole `isValid` odpowiedzi).
    public var isValid: Bool
    /// Kod kraju (prefiks VAT) w postaci znormalizowanej (Grecja = „EL”).
    public var countryCode: String
    /// Numer identyfikacyjny VAT bez prefiksu kraju.
    public var vatNumber: String
    /// Nazwa podmiotu zwrócona przez VIES (pusta, gdy kraj nie udostępnia danych
    /// — VIES zwraca wtedy „---”).
    public var name: String
    /// Adres podmiotu zwrócony przez VIES (może być wielolinijkowy; pusty przy „---”).
    public var address: String
    /// Data zapytania w VIES (napis ISO 8601 z odpowiedzi usługi).
    public var requestDate: String
    /// Numer potwierdzenia zapytania (consultation number, pole `requestIdentifier`)
    /// — dowód sprawdzenia. Zwracany wyłącznie, gdy w zapytaniu podano dane
    /// pytającego (`requesterNIP`); dla zapytania anonimowego jest pusty.
    public var consultationNumber: String

    public init(
        isValid: Bool,
        countryCode: String,
        vatNumber: String,
        name: String,
        address: String,
        requestDate: String,
        consultationNumber: String
    ) {
        self.isValid = isValid
        self.countryCode = countryCode
        self.vatNumber = vatNumber
        self.name = name
        self.address = address
        self.requestDate = requestDate
        self.consultationNumber = consultationNumber
    }
}

/// Sprawdzanie numerów VAT-UE kontrahentów unijnych w publicznym REST API VIES
/// Komisji Europejskiej (`ec.europa.eu/taxation_customs/vies/rest-api`) — bez
/// klucza API. Odpowiednik `ContractorLookupService` (Wykaz podatników VAT)
/// dla kontrahentów spoza Polski.
///
/// Kontrakt API zweryfikowany u źródła (13.07.2026):
/// `GET /ms/{kodKraju}/vat/{numer}` zwraca HTTP 200 z polami `isValid`,
/// `userError` (`VALID`/`INVALID`/kody awarii), `name`, `address`,
/// `requestDate`, `requestIdentifier`. Podanie `requesterMemberStateCode`
/// i `requesterNumber` w zapytaniu daje niepusty numer potwierdzenia.
public struct VIESLookupService {

    public enum LookupError: LocalizedError, Equatable {
        /// VIES odrzucił dane wejściowe (błędny kod kraju albo pusty numer).
        case invalidInput
        /// Krajowy rejestr VAT nie odpowiada (MS_UNAVAILABLE / TIMEOUT / limit).
        case memberStateUnavailable
        /// Inny błąd usługi VIES (sieć, HTTP, nieznany kod).
        case serviceError(String)

        public var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "VIES odrzucił zapytanie jako nieprawidłowe (błędny kod kraju lub numer VAT-UE)."
            case .memberStateUnavailable:
                return "Krajowy rejestr VAT jest chwilowo niedostępny w VIES — spróbuj ponownie później."
            case .serviceError(let details):
                return "Błąd usługi VIES: \(details)"
            }
        }
    }

    private let transport: HTTPTransport
    private let baseURL: URL

    public init(
        transport: HTTPTransport = URLSession.shared,
        baseURL: URL = URL(string: "https://ec.europa.eu/taxation_customs/vies/rest-api")!
    ) {
        self.transport = transport
        self.baseURL = baseURL
    }

    /// Sprawdza numer VAT-UE w VIES.
    /// - Parameters:
    ///   - countryCode: dwuliterowy kod kraju (prefiks VAT; „GR” jest
    ///     normalizowane do „EL”).
    ///   - vatNumber: numer VAT bez prefiksu kraju (dozwolone litery i cyfry).
    ///   - requesterNIP: opcjonalny polski NIP naszej firmy. Gdy podany, VIES
    ///     zwraca numer potwierdzenia zapytania (dowód należytej staranności).
    /// - Returns: wynik z aktualnym statusem oraz — jeśli kraj udostępnia —
    ///   nazwą i adresem podmiotu.
    /// - Throws: `LookupError`, gdy zapytanie jest błędne albo usługa/rejestr
    ///   są niedostępne (status `INVALID` NIE jest błędem — to legalny wynik
    ///   „numer nieaktywny”, zwracany w `isValid == false`).
    public func lookup(
        countryCode: String,
        vatNumber: String,
        requesterNIP: String? = nil
    ) async throws -> VIESLookupResult {
        let rawCC = countryCode.uppercased().filter(\.isLetter)
        let number = vatNumber.uppercased().filter { $0.isLetter || $0.isNumber }
        guard rawCC.count == 2, !number.isEmpty else { throw LookupError.invalidInput }
        // VIES używa „EL” dla Grecji; w ścieżce URL musi być kod VIES.
        let cc = rawCC == "GR" ? "EL" : rawCC

        var url = baseURL.appending(path: "/ms/\(cc)/vat/\(number)")
        if let requesterNIP {
            let requesterNumber = requesterNIP.filter(\.isNumber)
            if !requesterNumber.isEmpty {
                url = url.appending(queryItems: [
                    URLQueryItem(name: "requesterMemberStateCode", value: "PL"),
                    URLQueryItem(name: "requesterNumber", value: requesterNumber),
                ])
            }
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.message
            throw LookupError.serviceError(message ?? "HTTP \(response.statusCode)")
        }

        let decoded = try JSONDecoder().decode(VIESResponse.self, from: data)

        // `userError` inne niż VALID/INVALID to awaria po stronie usługi lub
        // krajowego rejestru — NIE wolno ich pomylić z „numer nieaktywny”.
        switch (decoded.userError ?? "").uppercased() {
        case "VALID", "INVALID", "":
            break
        case "INVALID_INPUT", "INVALID_REQUESTER_INFO":
            throw LookupError.invalidInput
        case "MS_UNAVAILABLE", "TIMEOUT", "MS_MAX_CONCURRENT_REQ", "MS_MAX_CONCURRENT_REQ_TIME":
            throw LookupError.memberStateUnavailable
        case let other:
            throw LookupError.serviceError(other)
        }

        return VIESLookupResult(
            isValid: decoded.isValid ?? false,
            countryCode: cc,
            vatNumber: number,
            name: Self.normalizeField(decoded.name),
            address: Self.normalizeField(decoded.address),
            requestDate: decoded.requestDate ?? "",
            consultationNumber: (decoded.requestIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// VIES zwraca „---”, gdy kraj rejestracji nie udostępnia danych podmiotu.
    /// Traktujemy taki placeholder jak brak danych.
    static func normalizeField(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "---" ? "" : trimmed
    }

    // MARK: DTO odpowiedzi API

    private struct VIESResponse: Decodable {
        let isValid: Bool?
        let userError: String?
        let name: String?
        let address: String?
        let requestDate: String?
        let requestIdentifier: String?
    }

    private struct APIError: Decodable {
        let message: String?
    }
}
