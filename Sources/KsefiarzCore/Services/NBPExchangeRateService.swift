import Foundation

/// Kurs waluty pobrany z tabeli A NBP.
public struct NBPRate: Equatable, Sendable {
    /// Kurs średni (PLN za 1 jednostkę waluty).
    public var mid: Double
    /// Data publikacji kursu (yyyy-MM-dd).
    public var effectiveDate: String
    /// Numer tabeli NBP (np. "113/A/NBP/2026").
    public var tableNumber: String
}

/// Pobieranie średnich kursów walut z publicznego API NBP (api.nbp.pl,
/// tabela A, bez klucza). Dla potrzeb VAT właściwy jest kurs z ostatniego
/// dnia roboczego POPRZEDZAJĄCEGO datę wystawienia/sprzedaży (art. 31a
/// ustawy o VAT) — wywołujący przekazuje już dzień poprzedni, a usługa
/// cofa się po tabeli do ostatniego opublikowanego kursu (weekendy, święta).
public struct NBPExchangeRateService {

    public enum RateError: LocalizedError, Equatable {
        case unsupportedCurrency(String)
        case noRateAvailable
        case serviceError(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedCurrency(let code):
                return "NBP nie publikuje kursu dla waluty \(code) w tabeli A."
            case .noRateAvailable:
                return "Brak opublikowanego kursu NBP dla wskazanego okresu."
            case .serviceError(let details):
                return "Błąd usługi NBP: \(details)"
            }
        }
    }

    private let transport: HTTPTransport
    private let baseURL: URL

    public init(
        transport: HTTPTransport = URLSession.shared,
        baseURL: URL = URL(string: "https://api.nbp.pl")!
    ) {
        self.transport = transport
        self.baseURL = baseURL
    }

    /// Zwraca ostatni kurs średni opublikowany NIE PÓŹNIEJ niż `onOrBefore`.
    /// Zapytanie obejmuje 10 dni wstecz — wystarcza na każdy układ weekendów
    /// i świąt; brana jest najnowsza pozycja zakresu.
    public func midRate(currency: String, onOrBefore date: Date) async throws -> NBPRate {
        let code = currency.lowercased()
        guard code != "pln" else { return NBPRate(mid: 1, effectiveDate: "", tableNumber: "") }

        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -10, to: date) ?? date
        let url = baseURL.appending(
            path: "/api/exchangerates/rates/a/\(code)/"
                + "\(FA2Format.dateFormatter.string(from: start))/"
                + "\(FA2Format.dateFormatter.string(from: date))/"
        ).appending(queryItems: [URLQueryItem(name: "format", value: "json")])

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.send(request)

        switch response.statusCode {
        case 200:
            break
        case 404:
            // 404 dla nieznanej waluty albo zakresu bez notowań.
            throw RateError.unsupportedCurrency(currency)
        default:
            throw RateError.serviceError("HTTP \(response.statusCode)")
        }

        let decoded = try JSONDecoder().decode(RatesResponse.self, from: data)
        guard let latest = decoded.rates.max(by: { $0.effectiveDate < $1.effectiveDate }) else {
            throw RateError.noRateAvailable
        }
        return NBPRate(mid: latest.mid, effectiveDate: latest.effectiveDate, tableNumber: latest.no)
    }

    private struct RatesResponse: Decodable {
        let rates: [Rate]
        struct Rate: Decodable {
            let no: String
            let effectiveDate: String
            let mid: Double
        }
    }
}
