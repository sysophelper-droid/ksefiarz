import SwiftUI
import SwiftData

/// Centrum synchronizacji — osobne stany zakupów, sprzedaży i wysyłek,
/// historia przebiegów z liczbą pobranych dokumentów i błędami oraz
/// możliwość ponowienia nieudanej operacji.
public struct SyncCenterView: View {

    @Query(sort: [SortDescriptor(\SyncRun.startedAt, order: .reverse)])
    private var runs: [SyncRun]

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var tokenStore = TokenStore.shared
    @AppStorage(AppSettingsKeys.nip) private var myNIP = ""
    @AppStorage(AppSettingsKeys.environment) private var environmentRaw = KSeFEnvironment.test.rawValue
    @AppStorage(AppSettingsKeys.rangeMode) private var rangeModeRaw = DateRangeMode.last3Months.rawValue
    @AppStorage(AppSettingsKeys.rangeFrom) private var rangeFromInterval = Date.now.timeIntervalSince1970 - 30 * 86_400
    @AppStorage(AppSettingsKeys.rangeTo) private var rangeToInterval = Date.now.timeIntervalSince1970
    @AppStorage(AppSettingsKeys.prepaidForms) private var prepaidFormsRaw = PaymentFormPolicy.encode(PaymentFormPolicy.defaultPrepaidForms)

    /// Operacje wykonywane w tej chwili — blokują swoje przyciski.
    @State private var runningOperations: Set<SyncRun.Operation> = []
    @State private var errorMessage: String?
    /// Komunikat po operacji bez wpisu do historii (np. pusta kolejka wysyłek).
    @State private var infoMessage: String?

    public init() {}

    private var environment: KSeFEnvironment {
        KSeFEnvironment(rawValue: environmentRaw) ?? .test
    }

    /// Stany kart — ostatni przebieg każdej operacji na bieżącym środowisku.
    private var latestRuns: [SyncRun.Operation: SyncRun] {
        SyncCenter.latestRuns(in: runs, environmentRaw: environmentRaw)
    }

    private var hasCredentials: Bool {
        !myNIP.isEmpty
            && (!tokenStore.token.isEmpty
                || KSeFCertificateStore.shared.authenticationCertificate != nil)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Label("Środowisko: \(environment.displayName)", systemImage: "server.rack")
                    if let info = infoMessage {
                        Text("•")
                        Text(info)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                // Karty stanów — osobno zakupy, sprzedaż i wysyłki.
                HStack(alignment: .top, spacing: 16) {
                    ForEach(SyncRun.Operation.allCases, id: \.self) { operation in
                        SyncStateCard(
                            operation: operation,
                            run: latestRuns[operation],
                            isRunning: runningOperations.contains(operation),
                            isEnabled: hasCredentials
                        ) { trigger in
                            Task { await run(operation, trigger: trigger) }
                        }
                    }
                }
            }
            .padding()

            Divider()

            historyList
        }
        .navigationTitle("Centrum synchronizacji")
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) {
                    clearHistory()
                } label: {
                    Label("Wyczyść historię", systemImage: "trash")
                }
                .disabled(runs.isEmpty)
                .help("Usuń wszystkie wpisy historii synchronizacji")
            }
        }
        .alert(
            "Błąd synchronizacji z KSeF",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Historia przebiegów

    @ViewBuilder
    private var historyList: some View {
        if runs.isEmpty {
            ContentUnavailableView(
                "Brak historii synchronizacji",
                systemImage: "clock.arrow.circlepath",
                description: Text(
                    "Przebiegi ręczne i automatyczne pojawią się tutaj wraz z liczbą pobranych dokumentów i ewentualnymi błędami."
                )
            )
        } else {
            List {
                Section("Historia przebiegów (ostatnie \(SyncCenter.historyLimit))") {
                    ForEach(runs) { run in
                        SyncRunRow(
                            run: run,
                            isRetrying: runningOperations.contains(run.operation),
                            canRetry: hasCredentials && run.environmentRaw == environmentRaw
                        ) {
                            Task { await self.run(run.operation, trigger: .retry) }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func clearHistory() {
        for run in runs {
            modelContext.delete(run)
        }
        try? modelContext.save()
    }

    // MARK: Uruchamianie operacji

    /// Uruchamia wskazaną operację (przycisk karty lub „Ponów” z historii).
    @MainActor
    private func run(_ operation: SyncRun.Operation, trigger: SyncRun.Trigger) async {
        guard hasCredentials else {
            errorMessage = KSeFError.missingCredentials.localizedDescription
            return
        }
        guard !runningOperations.contains(operation) else { return }
        runningOperations.insert(operation)
        defer { runningOperations.remove(operation) }
        infoMessage = nil

        let service = KSeFService(
            environment: environment,
            nip: myNIP,
            authToken: tokenStore.token,
            certificate: KSeFCertificateStore.shared.authenticationCertificate
        )

        switch operation {
        case .purchases, .sales:
            let range = DateRangeResolver.range(
                mode: DateRangeMode(rawValue: rangeModeRaw) ?? .last3Months,
                customFrom: Date(timeIntervalSince1970: rangeFromInterval),
                customTo: Date(timeIntervalSince1970: rangeToInterval)
            )
            do {
                try await InvoiceSyncEngine.sync(
                    kind: operation == .purchases ? .purchase : .sales,
                    service: service,
                    from: range.from,
                    to: range.to,
                    prepaidForms: PaymentFormPolicy.decode(prepaidFormsRaw),
                    context: modelContext,
                    trigger: trigger,
                    environmentRaw: environmentRaw
                )
            } catch {
                // Nieudany przebieg jest już zapisany w historii — alert
                // tylko sygnalizuje problem od razu.
                errorMessage = error.localizedDescription
            }
        case .submissions:
            let invoices = (try? modelContext.fetch(FetchDescriptor<Invoice>())) ?? []
            let outcome = await SyncCenter.reconcileSubmissions(
                invoices: invoices,
                environmentRaw: environmentRaw,
                trigger: trigger,
                using: service,
                context: modelContext
            )
            if !outcome.hadWork {
                infoMessage = "Brak wysyłek do sprawdzenia — kolejka offline i przesyłki są domknięte."
            }
        }
    }
}

// MARK: - Karta stanu operacji

/// Stan pojedynczej operacji: wynik ostatniego przebiegu, liczby dokumentów
/// oraz przycisk uruchomienia (lub ponowienia po błędzie).
private struct SyncStateCard: View {
    let operation: SyncRun.Operation
    let run: SyncRun?
    let isRunning: Bool
    let isEnabled: Bool
    let action: (SyncRun.Trigger) -> Void

    private var statusIcon: (name: String, color: Color) {
        guard let run else { return ("minus.circle", .secondary) }
        if run.errorMessage != nil { return ("xmark.circle.fill", .red) }
        if run.failureCount > 0 { return ("exclamationmark.triangle.fill", .orange) }
        return ("checkmark.circle.fill", .green)
    }

    private var statusText: String {
        guard let run else { return "Jeszcze nie synchronizowano" }
        if run.errorMessage != nil { return "Błąd przebiegu" }
        if run.failureCount > 0 { return "Częściowe niepowodzenia (\(run.failureCount))" }
        return "Udany przebieg"
    }

    private var countsText: String? {
        guard let run, run.errorMessage == nil else { return nil }
        if operation == .submissions {
            return "Sprawdzono: \(run.fetchedCount) • Przyjęte: \(run.insertedCount)"
        }
        return "Pobrano: \(run.fetchedCount) • Nowe: \(run.insertedCount)"
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(operation.displayName, systemImage: operation.icon)
                        .font(.headline)
                    Spacer()
                    Image(systemName: statusIcon.name)
                        .foregroundStyle(statusIcon.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusText)
                        .font(.subheadline)
                    if let run {
                        (Text(run.finishedAt, style: .relative) + Text(" temu (\(run.trigger.displayName))"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let countsText {
                        Text(countsText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error = run?.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    action(run?.succeeded == false ? .retry : .manual)
                } label: {
                    if isRunning {
                        ProgressView().controlSize(.small)
                    } else if run?.succeeded == false {
                        Label("Ponów", systemImage: "arrow.clockwise")
                    } else {
                        Label(
                            operation == .submissions ? "Sprawdź teraz" : "Synchronizuj",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }
                .disabled(isRunning || !isEnabled)
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Wiersz historii

/// Wpis historii przebiegów; nieudany przebieg ma przycisk „Ponów”.
private struct SyncRunRow: View {
    let run: SyncRun
    let isRetrying: Bool
    let canRetry: Bool
    let retry: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var statusIcon: (name: String, color: Color) {
        if run.errorMessage != nil { return ("xmark.circle.fill", .red) }
        if run.failureCount > 0 { return ("exclamationmark.triangle.fill", .orange) }
        return ("checkmark.circle.fill", .green)
    }

    private var summaryText: String {
        var parts: [String] = []
        if run.operation == .submissions {
            parts.append("sprawdzono \(run.fetchedCount)")
            parts.append("przyjęte \(run.insertedCount)")
        } else {
            parts.append("pobrano \(run.fetchedCount)")
            parts.append("nowe \(run.insertedCount)")
        }
        if run.failureCount > 0 { parts.append("niepowodzenia \(run.failureCount)") }
        return parts.joined(separator: " • ")
    }

    private var environmentLabel: String? {
        guard let environment = KSeFEnvironment(rawValue: run.environmentRaw),
              environment != .production else { return nil }
        return environment.displayName
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: statusIcon.name)
                .foregroundStyle(statusIcon.color)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(run.operation.displayName)
                        .font(.headline)
                    Text(run.trigger.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    if let environmentLabel {
                        Text(environmentLabel)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.yellow.opacity(0.25), in: Capsule())
                    }
                }
                if let error = run.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(Self.dateFormatter.string(from: run.startedAt))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !run.succeeded {
                Button {
                    retry()
                } label: {
                    if isRetrying {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Ponów", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRetrying || !canRetry)
                .help(
                    canRetry
                        ? "Uruchom tę operację ponownie"
                        : "Ponowienie wymaga poświadczeń i tego samego środowiska KSeF"
                )
            }
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    SyncCenterView()
        .modelContainer(for: [Invoice.self, SyncRun.self], inMemory: true)
}
