import SwiftUI
import SwiftData

/// Arkusz wysyłki wsadowej do KSeF (sesja batch/ZIP) — masowa wysyłka
/// lokalnych dokumentów zamiast pojedynczych sesji interaktywnych
/// (migracja z innego systemu, zaległości). Obejmuje własną sprzedaż oraz
/// dokumenty zakupowe wystawiane przez nas (VAT RR, samofaktury); dokumenty
/// FA(3) i FA_RR(1) idą w osobnych sesjach (różny formCode paczki).
public struct BatchSendView: View {

    /// Wstępne zaznaczenie przekazane z listy (multiselect).
    private let preselected: Set<UUID>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Wszystkie widoczne faktury — kwalifikację robi `BatchSendEngine`.
    @Query(
        filter: #Predicate<Invoice> { $0.isArchivedOrHidden == false },
        sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
    )
    private var invoices: [Invoice]

    @AppStorage(AppSettingsKeys.nip) private var myNIP = ""
    @ObservedObject private var tokenStore = TokenStore.shared
    @AppStorage(AppSettingsKeys.environment) private var environmentRaw = KSeFEnvironment.test.rawValue

    @State private var selection = Set<UUID>()
    @State private var didInitializeSelection = false
    @State private var isSending = false
    @State private var isReconciling = false
    @State private var progressText = ""
    @State private var results: [ResultRow] = []
    @State private var didFinish = false
    @State private var showingConfirmation = false
    @State private var errorMessage: String?

    public init(preselected: Set<UUID> = []) {
        self.preselected = preselected
    }

    /// Wiersz wyniku wysyłki — stan dokumentu po przetworzeniu paczki.
    struct ResultRow: Identifiable {
        let id: UUID
        let invoiceNumber: String
        let contractor: String
        let status: KSeFSubmissionStatus
        let detail: String
    }

    private var environment: KSeFEnvironment {
        KSeFEnvironment(rawValue: environmentRaw) ?? .test
    }

    private var eligibleInvoices: [Invoice] {
        BatchSendEngine.eligible(in: invoices)
    }

    private var selectedInvoices: [Invoice] {
        eligibleInvoices.filter { selection.contains($0.id) }
    }

    private var hasCredentials: Bool {
        !myNIP.isEmpty && (!tokenStore.token.isEmpty
            || KSeFCertificateStore.shared.authenticationCertificate != nil)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if didFinish {
                resultsList
            } else {
                selectionList
            }
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 460)
        .onAppear(perform: initializeSelection)
        .alert(
            "Wysyłka wsadowa nie powiodła się",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Wysłać \(selectedInvoices.count) dokumentów do KSeF?",
            isPresented: $showingConfirmation
        ) {
            Button("Wyślij paczkę (\(environment.displayName))") {
                Task { await send() }
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text(
                environment == .production
                    ? "Środowisko PRODUKCYJNE — przyjęte faktury stają się dokumentami w obrocie prawnym; zmiana wysłanej faktury wymaga korekty."
                    : "Środowisko: \(environment.displayName). Dokumenty zostaną spakowane do ZIP i przesłane w sesji wsadowej."
            )
        }
    }

    // MARK: Sekcje

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Wysyłka wsadowa do KSeF (ZIP)", systemImage: "square.and.arrow.up.on.square")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(environment.displayName)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (environment == .production ? Color.red : Color.blue).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(environment == .production ? .red : .blue)
                    .help("Środowisko KSeF z Ustawień")
            }
            Text(
                "Zaznaczone dokumenty lokalne zostaną wysłane w jednej paczce "
                + "(osobne sesje dla FA(3) i FA_RR(1)) zamiast pojedynczo. "
                + "Kolejka offline ma własną, automatyczną ścieżkę dosłań i nie wchodzi do paczki."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var selectionList: some View {
        List {
            if eligibleInvoices.isEmpty {
                ContentUnavailableView(
                    "Brak dokumentów do wysyłki",
                    systemImage: "tray",
                    description: Text("Wysyłce wsadowej podlegają wyłącznie dokumenty zapisane lokalnie, jeszcze nie przekazane do KSeF.")
                )
            } else {
                Section {
                    ForEach(eligibleInvoices) { invoice in
                        Toggle(isOn: toggleBinding(for: invoice.id)) {
                            invoiceRow(invoice)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(isSending)
                    }
                } header: {
                    HStack {
                        Text("Dokumenty lokalne (\(selection.count) z \(eligibleInvoices.count))")
                        Spacer()
                        Button(selection.count == eligibleInvoices.count ? "Odznacz wszystkie" : "Zaznacz wszystkie") {
                            if selection.count == eligibleInvoices.count {
                                selection.removeAll()
                            } else {
                                selection = Set(eligibleInvoices.map(\.id))
                            }
                        }
                        .buttonStyle(.link)
                        .disabled(isSending)
                    }
                }
            }
        }
    }

    private func invoiceRow(_ invoice: Invoice) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(invoice.invoiceNumber).font(.body.weight(.medium))
                    Text(invoice.documentTypeRaw)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.gray.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                    if invoice.isSelfIssuedPurchase {
                        Text(invoice.isRR ? "VAT RR" : "Samofaktura")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.teal.opacity(0.15), in: Capsule())
                            .foregroundStyle(.teal)
                    }
                }
                Text(invoice.isSelfIssuedPurchase ? invoice.sellerName : invoice.buyerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(invoice.grossAmount, format: .currency(code: invoice.currency))
                    .monospacedDigit()
                Text(invoice.issueDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resultsList: some View {
        List {
            Section("Wynik wysyłki") {
                ForEach(results) { row in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.invoiceNumber).font(.body.weight(.medium))
                            Text(row.contractor)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(statusLabel(row.status))
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(statusColor(row.status).opacity(0.18), in: Capsule())
                                .foregroundStyle(statusColor(row.status))
                            if !row.detail.isEmpty {
                                Text(row.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }
            if results.contains(where: { $0.status == .processing }) {
                Section {
                    Label(
                        "Część dokumentów jest nadal przetwarzana — statusy domknie automatyczna synchronizacja albo przycisk „Sprawdź teraz”.",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if isSending || isReconciling {
                ProgressView().controlSize(.small)
                Text(progressText.isEmpty ? "Przygotowanie paczki…" : progressText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !hasCredentials {
                Label(
                    "Uzupełnij NIP oraz certyfikat lub token KSeF w Ustawieniach.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            } else if didFinish {
                Text(summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if didFinish {
                if results.contains(where: { $0.status == .processing }) {
                    Button("Sprawdź teraz") {
                        Task { await reconcile() }
                    }
                    .disabled(isReconciling)
                }
                Button("Zamknij") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Anuluj") { dismiss() }
                    .disabled(isSending)
                Button("Wyślij \(selection.count) dokumentów…") {
                    showingConfirmation = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty || isSending || !hasCredentials)
            }
        }
        .padding()
    }

    // MARK: Logika widoku

    private func toggleBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isOn in
                if isOn { selection.insert(id) } else { selection.remove(id) }
            }
        )
    }

    /// Wstępne zaznaczenie: przecięcie przekazanego multiselectu z dokumentami
    /// kwalifikującymi się; bez przekazania — wszystkie kwalifikujące się.
    private func initializeSelection() {
        guard !didInitializeSelection else { return }
        didInitializeSelection = true
        let eligibleIDs = Set(eligibleInvoices.map(\.id))
        let preselectedEligible = preselected.intersection(eligibleIDs)
        selection = preselectedEligible.isEmpty ? eligibleIDs : preselectedEligible
    }

    private var summaryText: String {
        let accepted = results.filter { $0.status == .accepted }.count
        let rejected = results.filter { $0.status == .rejected }.count
        let processing = results.filter { $0.status == .processing }.count
        let local = results.filter { $0.status == .local }.count
        var parts = ["Przyjęte: \(accepted)"]
        if rejected > 0 { parts.append("odrzucone: \(rejected)") }
        if processing > 0 { parts.append("w toku: \(processing)") }
        if local > 0 { parts.append("niedostarczone (lokalne): \(local)") }
        return parts.joined(separator: ", ")
    }

    private func statusLabel(_ status: KSeFSubmissionStatus) -> String {
        switch status {
        case .accepted: return "Przyjęta"
        case .rejected: return "Odrzucona"
        case .processing: return "W toku"
        case .local: return "Niedostarczona"
        case .offlinePending: return "Offline"
        }
    }

    private func statusColor(_ status: KSeFSubmissionStatus) -> Color {
        switch status {
        case .accepted: return .green
        case .rejected: return .red
        case .processing: return .orange
        case .local: return .gray
        case .offlinePending: return .blue
        }
    }

    /// Pełny przebieg: plan (walidacja + XML + grupy schem), sesja wsadowa
    /// per grupa, naniesienie wyników i pobranie UPO dla przyjętych.
    @MainActor
    private func send() async {
        guard hasCredentials else { return }
        isSending = true
        defer { isSending = false }

        let plan = BatchSendEngine.plan(for: selectedInvoices)
        var rows: [ResultRow] = plan.excluded.map { exclusion in
            ResultRow(
                id: exclusion.invoice.id,
                invoiceNumber: exclusion.invoice.invoiceNumber,
                contractor: exclusion.invoice.buyerName,
                status: .local,
                detail: "Pominięta — \(exclusion.reason)"
            )
        }
        guard !plan.groups.isEmpty else {
            results = rows
            didFinish = true
            errorMessage = plan.excluded.isEmpty
                ? "Brak dokumentów do wysyłki."
                : "Żaden z zaznaczonych dokumentów nie przeszedł walidacji."
            return
        }

        let service = KSeFService(
            environment: environment,
            nip: myNIP,
            authToken: tokenStore.token,
            certificate: KSeFCertificateStore.shared.authenticationCertificate
        )

        for (groupIndex, group) in plan.groups.enumerated() {
            let groupLabel = plan.groups.count > 1
                ? " [\(group.schema.systemCode), paczka \(groupIndex + 1)/\(plan.groups.count)]"
                : ""
            do {
                _ = try await BatchSendEngine.send(
                    group: group,
                    environmentRaw: environmentRaw,
                    using: service
                ) { phase in
                    progressText = phaseDescription(phase) + groupLabel
                }
                try? modelContext.save()
            } catch {
                // Dokumenty tej grupy pozostały nietknięte (lokalne) —
                // błąd pokazujemy, a pozostałe grupy nie są wysyłane.
                errorMessage = error.localizedDescription
                break
            }
        }

        // UPO dla dokumentów przyjętych w tej paczce (wspólna ścieżka domykania).
        progressText = "Pobieranie UPO…"
        _ = await InvoiceSubmissionStatusEngine.refreshOutstanding(
            plan.candidates.map(\.invoice),
            environmentRaw: environmentRaw,
            using: service
        )
        try? modelContext.save()

        rows.append(contentsOf: plan.candidates.map { resultRow(for: $0.invoice) })
        results = rows
        didFinish = true
    }

    /// Domknięcie sesji „w toku" na żądanie (poza automatyczną synchronizacją).
    @MainActor
    private func reconcile() async {
        guard hasCredentials else { return }
        isReconciling = true
        defer { isReconciling = false }
        progressText = "Sprawdzanie stanu sesji wsadowej…"

        let service = KSeFService(
            environment: environment,
            nip: myNIP,
            authToken: tokenStore.token,
            certificate: KSeFCertificateStore.shared.authenticationCertificate
        )
        let pendingIDs = Set(results.filter { $0.status == .processing }.map(\.id))
        let pendingInvoices = invoices.filter { pendingIDs.contains($0.id) }
        _ = await BatchSendEngine.reconcilePending(
            pendingInvoices,
            environmentRaw: environmentRaw,
            using: service
        )
        _ = await InvoiceSubmissionStatusEngine.refreshOutstanding(
            pendingInvoices,
            environmentRaw: environmentRaw,
            using: service
        )
        try? modelContext.save()

        results = results.map { row in
            guard pendingIDs.contains(row.id),
                  let invoice = pendingInvoices.first(where: { $0.id == row.id }) else {
                return row
            }
            return resultRow(for: invoice)
        }
    }

    private func resultRow(for invoice: Invoice) -> ResultRow {
        let detail: String
        switch invoice.ksefSubmissionStatus {
        case .accepted:
            detail = invoice.ksefId ?? ""
        default:
            detail = invoice.ksefStatusDescription ?? ""
        }
        return ResultRow(
            id: invoice.id,
            invoiceNumber: invoice.invoiceNumber,
            contractor: invoice.isSelfIssuedPurchase ? invoice.sellerName : invoice.buyerName,
            status: invoice.ksefSubmissionStatus,
            detail: detail
        )
    }

    private func phaseDescription(_ phase: KSeFBatchPhase) -> String {
        switch phase {
        case .openingSession:
            return "Otwieranie sesji wsadowej…"
        case .uploadingPart(let index, let count):
            return count > 1
                ? "Przesyłanie części paczki \(index)/\(count)…"
                : "Przesyłanie paczki…"
        case .closingSession:
            return "Zamykanie sesji…"
        case .waitingForProcessing(let attempt):
            return "Przetwarzanie paczki przez KSeF… (próba \(attempt))"
        case .fetchingResults:
            return "Pobieranie wyników…"
        }
    }
}
