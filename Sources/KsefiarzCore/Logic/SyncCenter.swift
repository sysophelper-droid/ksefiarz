import Foundation
import SwiftData

/// Centrum synchronizacji — rejestracja przebiegów (historia `SyncRun`),
/// stany poszczególnych operacji oraz wspólne domykanie wysyłek
/// (kolejka offline24 + statusy przesyłek i UPO) z zapisem wyniku.
@MainActor
public enum SyncCenter {

    /// Maksymalna liczba wpisów historii — starsze przebiegi są usuwane.
    public nonisolated static let historyLimit = 200

    /// Wynik domknięcia wysyłek. `hadWork == false` oznacza pustą kolejkę
    /// i brak przesyłek do sprawdzenia — taki przebieg nie trafia do historii.
    public struct SubmissionsOutcome: Equatable, Sendable {
        public var hadWork = false
        public var processed = 0
        public var accepted = 0
        public var rejected = 0
        public var failures = 0

        public init() {}
    }

    /// Zapisuje przebieg do historii i przycina ją do `historyLimit`.
    @discardableResult
    public static func record(
        operation: SyncRun.Operation,
        trigger: SyncRun.Trigger,
        environmentRaw: String,
        startedAt: Date,
        finishedAt: Date = .now,
        fetched: Int = 0,
        inserted: Int = 0,
        failures: Int = 0,
        error: String? = nil,
        context: ModelContext
    ) throws -> SyncRun {
        let run = SyncRun(
            operation: operation,
            trigger: trigger,
            environmentRaw: environmentRaw,
            startedAt: startedAt,
            finishedAt: finishedAt,
            fetchedCount: fetched,
            insertedCount: inserted,
            failureCount: failures,
            errorMessage: error
        )
        context.insert(run)
        try prune(context: context)
        try context.save()
        return run
    }

    /// Usuwa najstarsze wpisy ponad limit historii.
    static func prune(context: ModelContext, keep: Int = historyLimit) throws {
        let runs = try context.fetch(FetchDescriptor<SyncRun>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
        for run in runs.dropFirst(keep) {
            context.delete(run)
        }
    }

    /// Ostatni przebieg każdej operacji — stany kart Centrum synchronizacji.
    /// Przebiegi z innych środowisk niż wskazane są pomijane.
    public static func latestRuns(
        in runs: [SyncRun],
        environmentRaw: String
    ) -> [SyncRun.Operation: SyncRun] {
        var latest: [SyncRun.Operation: SyncRun] = [:]
        for run in runs where run.environmentRaw == environmentRaw {
            if let current = latest[run.operation], current.startedAt >= run.startedAt {
                continue
            }
            latest[run.operation] = run
        }
        return latest
    }

    /// Domyka wysyłki: dosyła kolejkę offline24 (zapisany XML bajt w bajt),
    /// potem statusy przesyłek i UPO. Przebieg trafia do historii tylko wtedy,
    /// gdy było co robić — automat odpytuje co 60 s i pusta kolejka
    /// zaśmiecałaby historię.
    @discardableResult
    public static func reconcileSubmissions(
        invoices: [Invoice],
        environmentRaw: String,
        trigger: SyncRun.Trigger,
        using service: KSeFInvoiceSending & KSeFSubmissionStatusProviding,
        context: ModelContext,
        now: Date = .now
    ) async -> SubmissionsOutcome {
        var outcome = SubmissionsOutcome()
        let pendingCount = OfflineQueueEngine.pending(
            in: invoices, environmentRaw: environmentRaw
        ).count
        let outstandingCount = invoices.filter {
            $0.needsKSeFFollowUp
                && ($0.ksefEnvironmentRaw.isEmpty || $0.ksefEnvironmentRaw == environmentRaw)
        }.count
        guard pendingCount + outstandingCount > 0 else {
            return outcome
        }

        let startedAt = now
        let sendSummary = await OfflineQueueEngine.sendPending(
            invoices, environmentRaw: environmentRaw, using: service, now: now
        )
        let refreshSummary = await InvoiceSubmissionStatusEngine.refreshOutstanding(
            invoices, environmentRaw: environmentRaw, using: service, now: now
        )
        try? context.save()

        outcome.hadWork = true
        outcome.processed = sendSummary.sent + refreshSummary.checked
        outcome.accepted = sendSummary.accepted + refreshSummary.accepted
        outcome.rejected = sendSummary.rejected + refreshSummary.rejected
        outcome.failures = sendSummary.failures + refreshSummary.failures

        try? record(
            operation: .submissions,
            trigger: trigger,
            environmentRaw: environmentRaw,
            startedAt: startedAt,
            fetched: outcome.processed,
            inserted: outcome.accepted,
            failures: outcome.failures,
            context: context
        )
        return outcome
    }
}
