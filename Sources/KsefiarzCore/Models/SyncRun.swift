import Foundation
import SwiftData

/// Pojedynczy przebieg synchronizacji z KSeF — wpis historii Centrum
/// synchronizacji. Wszystkie pola mają wartości domyślne (lekka migracja
/// istniejącej bazy użytkownika).
@Model
public final class SyncRun {

    /// Rodzaj operacji synchronizacji — Centrum prezentuje ich stany osobno.
    public enum Operation: String, Codable, CaseIterable, Sendable {
        /// Import faktur zakupowych z KSeF.
        case purchases = "zakupy"
        /// Import faktur sprzedażowych z KSeF.
        case sales = "sprzedaz"
        /// Wysyłki: dosłania kolejki offline24, statusy przesyłek i UPO.
        case submissions = "wysylki"

        public var displayName: String {
            switch self {
            case .purchases: return "Zakupy"
            case .sales: return "Sprzedaż"
            case .submissions: return "Wysyłki"
            }
        }

        public var icon: String {
            switch self {
            case .purchases: return "arrow.down.doc"
            case .sales: return "arrow.up.doc"
            case .submissions: return "paperplane"
            }
        }
    }

    /// Co uruchomiło przebieg.
    public enum Trigger: String, Codable, CaseIterable, Sendable {
        case manual = "reczna"
        case launch = "start"
        case automatic = "automat"
        case retry = "ponowienie"

        public var displayName: String {
            switch self {
            case .manual: return "ręczna"
            case .launch: return "przy starcie"
            case .automatic: return "automatyczna"
            case .retry: return "ponowienie"
            }
        }
    }

    @Attribute(.unique) public var id: UUID = UUID()
    public var startedAt: Date = Date.now
    public var finishedAt: Date = Date.now
    public var operationRaw: String = Operation.purchases.rawValue
    public var triggerRaw: String = Trigger.manual.rawValue
    /// Środowisko KSeF przebiegu (rawValue `KSeFEnvironment`).
    public var environmentRaw: String = ""
    /// Liczba dokumentów pobranych z KSeF (import) lub sprawdzonych/dosłanych (wysyłki).
    public var fetchedCount: Int = 0
    /// Liczba nowych faktur w bazie (import) lub dokumentów przyjętych (wysyłki).
    public var insertedCount: Int = 0
    /// Liczba pojedynczych dokumentów, których nie udało się obsłużyć (wysyłki).
    public var failureCount: Int = 0
    /// Komunikat błędu, gdy cały przebieg został przerwany (nil = bez błędu).
    public var errorMessage: String?

    public init(
        operation: Operation,
        trigger: Trigger,
        environmentRaw: String = "",
        startedAt: Date = .now,
        finishedAt: Date = .now,
        fetchedCount: Int = 0,
        insertedCount: Int = 0,
        failureCount: Int = 0,
        errorMessage: String? = nil
    ) {
        self.id = UUID()
        self.operationRaw = operation.rawValue
        self.triggerRaw = trigger.rawValue
        self.environmentRaw = environmentRaw
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.fetchedCount = fetchedCount
        self.insertedCount = insertedCount
        self.failureCount = failureCount
        self.errorMessage = errorMessage
    }

    public var operation: Operation {
        Operation(rawValue: operationRaw) ?? .purchases
    }

    public var trigger: Trigger {
        Trigger(rawValue: triggerRaw) ?? .manual
    }

    /// Przebieg w pełni udany: bez błędu przebiegu i bez niepowodzeń
    /// pojedynczych dokumentów.
    public var succeeded: Bool {
        errorMessage == nil && failureCount == 0
    }
}
