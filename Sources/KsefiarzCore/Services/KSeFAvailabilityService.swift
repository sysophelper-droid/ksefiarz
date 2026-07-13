import Combine
import Foundation

/// Aktualny stan działania KSeF publikowany przez publiczne API Latarni MF.
public enum KSeFSystemStatus: Equatable, Sendable {
    case available
    case maintenance
    case failure
    case totalFailure
    /// Bezpiecznik na przyszłe rozszerzenia kontraktu — nieznana wartość
    /// nie może zostać automatycznie potraktowana jak jeden z trybów offline.
    case unknown(String)
}

extension KSeFSystemStatus: Decodable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "AVAILABLE": self = .available
        case "MAINTENANCE": self = .maintenance
        case "FAILURE": self = .failure
        case "TOTAL_FAILURE": self = .totalFailure
        default: self = .unknown(raw)
        }
    }
}

/// Kategoria zdarzenia Latarni KSeF.
public enum KSeFAvailabilityCategory: Equatable, Sendable {
    case maintenance
    case failure
    case totalFailure
    case unknown(String)
}

extension KSeFAvailabilityCategory: Decodable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "MAINTENANCE": self = .maintenance
        case "FAILURE": self = .failure
        case "TOTAL_FAILURE": self = .totalFailure
        default: self = .unknown(raw)
        }
    }
}

/// Typ pojedynczego komunikatu MF. Awaria ma osobne komunikaty początku
/// i końca; planowana niedostępność zawiera cały przedział w jednym wpisie.
public enum KSeFAvailabilityMessageType: Equatable, Sendable {
    case maintenanceAnnouncement
    case failureStart
    case failureEnd
    case unknown(String)
}

extension KSeFAvailabilityMessageType: Decodable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "MAINTENANCE_ANNOUNCEMENT": self = .maintenanceAnnouncement
        case "FAILURE_START": self = .failureStart
        case "FAILURE_END": self = .failureEnd
        default: self = .unknown(raw)
        }
    }
}

/// Ustrukturyzowany komunikat Ministerstwa Finansów z API Latarni.
public struct KSeFAvailabilityMessage: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let eventId: Int
    public let category: KSeFAvailabilityCategory
    public let type: KSeFAvailabilityMessageType
    public let title: String
    public let text: String
    public let start: Date
    public let end: Date?
    public let version: Int
    public let published: Date
}

private struct KSeFAvailabilityStatusResponse: Decodable, Sendable {
    let status: KSeFSystemStatus
    let messages: [KSeFAvailabilityMessage]?
}

/// Spójny odczyt bieżącego statusu i historii komunikatów (historia jest
/// utrzymywana przez MF przez 30 dni po zakończeniu zdarzenia).
public struct KSeFAvailabilitySnapshot: Equatable, Sendable {
    public let environment: KSeFEnvironment
    public let status: KSeFSystemStatus
    public let activeMessages: [KSeFAvailabilityMessage]
    public let messages: [KSeFAvailabilityMessage]
    public let fetchedAt: Date

    public init(
        environment: KSeFEnvironment,
        status: KSeFSystemStatus,
        activeMessages: [KSeFAvailabilityMessage],
        messages: [KSeFAvailabilityMessage],
        fetchedAt: Date = .now
    ) {
        self.environment = environment
        self.status = status
        self.activeMessages = activeMessages
        self.messages = messages
        self.fetchedAt = fetchedAt
    }
}

public enum KSeFAvailabilityError: LocalizedError, Equatable {
    case unsupportedEnvironment
    case badStatus(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unsupportedEnvironment:
            return "Latarnia KSeF nie udostępnia osobnego statusu dla środowiska Demo."
        case .badStatus(let code):
            return "Latarnia KSeF zwróciła błąd HTTP \(code)."
        case .invalidResponse:
            return "Latarnia KSeF zwróciła nieprawidłową odpowiedź."
        }
    }
}

public extension KSeFEnvironment {
    /// Oficjalne środowiska publicznego API Latarni. MF nie publikuje
    /// odpowiednika dla Demo, dlatego nie wolno mapować tam zdarzeń z TEST.
    var availabilityBaseURL: URL? {
        switch self {
        case .test:
            return URL(string: "https://api-latarnia-test.ksef.mf.gov.pl")
        case .demo:
            return nil
        case .production:
            return URL(string: "https://api-latarnia.ksef.mf.gov.pl")
        }
    }
}

/// Klient publicznego, niewymagającego autoryzacji API Latarni KSeF.
public final class KSeFAvailabilityService {
    private let environment: KSeFEnvironment
    private let transport: HTTPTransport
    private let baseURL: URL?

    public init(
        environment: KSeFEnvironment,
        transport: HTTPTransport = URLSession.shared,
        baseURL: URL? = nil
    ) {
        self.environment = environment
        self.transport = transport
        self.baseURL = baseURL ?? environment.availabilityBaseURL
    }

    public func fetchSnapshot(now: Date = .now) async throws -> KSeFAvailabilitySnapshot {
        guard let baseURL else { throw KSeFAvailabilityError.unsupportedEnvironment }

        let messagesData = try await fetch(path: "messages", baseURL: baseURL)
        // Status pobieramy jako drugi, aby w razie zmiany w trakcie dwóch
        // żądań decyzja UI opierała się na możliwie najświeższym stanie.
        let statusData = try await fetch(path: "status", baseURL: baseURL)
        let decoder = Self.makeDecoder()
        guard let status = try? decoder.decode(KSeFAvailabilityStatusResponse.self, from: statusData),
              let messages = try? decoder.decode([KSeFAvailabilityMessage].self, from: messagesData)
        else {
            throw KSeFAvailabilityError.invalidResponse
        }
        return KSeFAvailabilitySnapshot(
            environment: environment,
            status: status.status,
            activeMessages: status.messages ?? [],
            messages: messages,
            fetchedAt: now
        )
    }

    private func fetch(path: String, baseURL: URL) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw KSeFAvailabilityError.badStatus(response.statusCode)
        }
        return data
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let regular = ISO8601DateFormatter()
            regular.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: value) ?? regular.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Nieprawidłowa data ISO 8601: \(value)"
                )
            }
            return date
        }
        return decoder
    }
}

/// Wspólny, obserwowalny stan Latarni dla głównego okna i formularzy.
@MainActor
public final class KSeFAvailabilityMonitor: ObservableObject {
    public static let shared = KSeFAvailabilityMonitor()

    @Published public private(set) var snapshot: KSeFAvailabilitySnapshot?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastError: String?

    private init() {}

    @discardableResult
    public func refresh(environment: KSeFEnvironment) async -> KSeFAvailabilitySnapshot? {
        guard environment.availabilityBaseURL != nil else {
            snapshot = nil
            lastError = KSeFAvailabilityError.unsupportedEnvironment.localizedDescription
            return nil
        }
        guard !isRefreshing else { return snapshot }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await KSeFAvailabilityService(environment: environment).fetchSnapshot()
            snapshot = result
            lastError = nil
            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
