import SwiftUI
import SwiftData
import UserNotifications

/// Sekcje paska bocznego aplikacji.
public enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case sales
    case purchases
    case reports
    case dictionaries
    case automation
    case syncCenter
    case hidden
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Kokpit"
        case .sales: return "Faktury Sprzedaży"
        case .purchases: return "Faktury Zakupu"
        case .reports: return "Raporty"
        case .dictionaries: return "Słowniki"
        case .automation: return "Szablony i cykle"
        case .syncCenter: return "Synchronizacja"
        case .hidden: return "Nieuprawnione / Ukryte"
        case .settings: return "Ustawienia"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .sales: return "arrow.up.doc"
        case .purchases: return "arrow.down.doc"
        case .reports: return "chart.bar.xaxis"
        case .dictionaries: return "text.book.closed"
        case .automation: return "calendar.badge.clock"
        case .syncCenter: return "arrow.triangle.2.circlepath"
        case .hidden: return "eye.slash"
        case .settings: return "gearshape"
        }
    }
}

/// Główny układ okna aplikacji — pasek boczny + zawartość (NavigationSplitView).
/// Odpowiada też za automatyczną synchronizację z KSeF (przy starcie
/// i cyklicznie), bo żyje przez cały czas działania aplikacji.
public struct MainContentView: View {

    @State private var selection: SidebarSection? = .dashboard
    /// Wspólny stan synchronizacji — dzielony z ikoną w pasku menu.
    @ObservedObject private var syncActivity = SyncActivity.shared

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var tokenStore = TokenStore.shared
    @AppStorage(AppSettingsKeys.nip) private var myNIP = ""
    @AppStorage(AppSettingsKeys.environment) private var environmentRaw = KSeFEnvironment.test.rawValue
    @AppStorage(AppSettingsKeys.rangeMode) private var rangeModeRaw = DateRangeMode.last3Months.rawValue
    @AppStorage(AppSettingsKeys.rangeFrom) private var rangeFromInterval = Date.now.timeIntervalSince1970 - 30 * 86_400
    @AppStorage(AppSettingsKeys.rangeTo) private var rangeToInterval = Date.now.timeIntervalSince1970
    @AppStorage(AppSettingsKeys.prepaidForms) private var prepaidFormsRaw = PaymentFormPolicy.encode(PaymentFormPolicy.defaultPrepaidForms)
    @AppStorage(AppSettingsKeys.syncOnLaunch) private var syncOnLaunch = false
    @AppStorage(AppSettingsKeys.autoSync) private var autoSync = false
    @AppStorage(AppSettingsKeys.autoSyncIntervalMinutes) private var autoSyncIntervalMinutes = 60
    @AppStorage(AppSettingsKeys.lastSyncAt) private var lastSyncAt = 0.0
    @AppStorage(AppSettingsKeys.autoBackup) private var autoBackup = true
    @AppStorage(AppSettingsKeys.autoBackupRotationMode) private var backupRotationModeRaw = AutoBackupService.RotationMode.keepCount.rawValue
    @AppStorage(AppSettingsKeys.autoBackupKeepCount) private var backupKeepCount = 14
    @AppStorage(AppSettingsKeys.autoBackupKeepDays) private var backupKeepDays = 30
    @AppStorage(AppSettingsKeys.notifyNewPurchases) private var notifyNewPurchases = true
    @AppStorage(AppSettingsKeys.notifyDeadlines) private var notifyDeadlines = true

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
            .navigationTitle("Ksefiarz")
            // Status synchronizacji — żeby było widać, że automatyka żyje.
            .safeAreaInset(edge: .bottom) {
                if syncActivity.isSyncing || lastSyncAt > 0 {
                    HStack(spacing: 6) {
                        if syncActivity.isSyncing {
                            ProgressView().controlSize(.small)
                            Text("Synchronizuję…")
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Synchronizacja: ")
                                + Text(Date(timeIntervalSince1970: lastSyncAt), style: .relative)
                                + Text(" temu")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard:
                DashboardView()
            case .sales:
                InvoiceListView(kind: .sales)
            case .purchases:
                InvoiceListView(kind: .purchase)
            case .reports:
                ReportsView()
            case .dictionaries:
                DictionariesView()
            case .automation:
                InvoiceAutomationView()
            case .syncCenter:
                SyncCenterView()
            case .hidden:
                HiddenInvoicesView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 920, minHeight: 580)
        // Kopia zapasowa PRZED synchronizacją — utrwala stan sprzed zmian.
        .task {
            if autoBackup { performAutoBackup() }
            await reconcileOutstandingSubmissions(trigger: .launch)
            if syncOnLaunch { await syncBothKinds(trigger: .launch) }
            await postDeadlineNotifications()
        }
        // Powiadomienia o terminach (płatności, dosłania offline) —
        // sprawdzane co 30 minut; deduplikacja gwarantuje jedno
        // powiadomienie danego rodzaju na fakturę dziennie.
        .task(id: "deadline-notifications-\(notifyDeadlines)") {
            guard notifyDeadlines else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30 * 60))
                guard !Task.isCancelled else { return }
                await postDeadlineNotifications()
            }
        }
        // Cykliczne pobieranie, dopóki aplikacja działa. Zmiana przełącznika
        // lub interwału w Ustawieniach restartuje pętlę (zmiana `id` taska).
        .task(id: "\(autoSync)-\(autoSyncIntervalMinutes)") {
            guard autoSync, autoSyncIntervalMinutes > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(autoSyncIntervalMinutes * 60))
                guard !Task.isCancelled else { return }
                await syncBothKinds(trigger: .automatic)
            }
        }
        // Wysyłki w toku i UPO są domykane niezależnie od ustawień importu.
        // Dzięki temu numer KSeF pojawia się bez ręcznego odświeżania także
        // wtedy, gdy automatyczna synchronizacja faktur jest wyłączona.
        .task(id: "ksef-follow-up-\(environmentRaw)") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await reconcileOutstandingSubmissions(trigger: .automatic)
            }
        }
    }

    /// Automatyczna kopia zapasowa: jeden plik dziennie z rotacją wg Ustawień.
    /// Błąd nie blokuje startu aplikacji — trafia tylko do logu systemowego.
    private func performAutoBackup() {
        let mode = AutoBackupService.RotationMode(rawValue: backupRotationModeRaw) ?? .keepCount
        do {
            try AutoBackupService.performIfNeeded(
                directory: AutoBackupService.defaultDirectory,
                mode: mode,
                keepCount: backupKeepCount,
                keepDays: backupKeepDays
            ) {
                try BackupService.makeCurrentBackup(context: modelContext)
            }
        } catch {
            NSLog("Ksefiarz: automatyczna kopia zapasowa nie powiodła się: %@",
                  String(describing: error))
        }
    }

    /// Pobiera faktury sprzedażowe i zakupowe zgodnie z zakresem dat
    /// z Ustawień. Działa w tle — błędy (np. brak sieci) są ciche;
    /// ręczna synchronizacja z listy pokazuje je wprost.
    /// WYŁĄCZNIE na środowisku produkcyjnym — automat na środowisku
    /// testowym zaśmiecał bazę fakturami testowymi (12.06.2026);
    /// na test/demo synchronizuj ręcznie z listy.
    @MainActor
    private func syncBothKinds(trigger: SyncRun.Trigger) async {
        guard environmentRaw == KSeFEnvironment.production.rawValue else { return }
        guard !myNIP.isEmpty, !tokenStore.token.isEmpty || KSeFCertificateStore.shared.authenticationCertificate != nil, !syncActivity.isSyncing else { return }
        syncActivity.isSyncing = true
        defer { syncActivity.isSyncing = false }

        let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
        let service = KSeFService(environment: environment, nip: myNIP, authToken: tokenStore.token, certificate: KSeFCertificateStore.shared.authenticationCertificate)
        await reconcileOutstandingSubmissions(using: service, trigger: trigger)
        let range = DateRangeResolver.range(
            mode: DateRangeMode(rawValue: rangeModeRaw) ?? .last3Months,
            customFrom: Date(timeIntervalSince1970: rangeFromInterval),
            customTo: Date(timeIntervalSince1970: rangeToInterval)
        )
        let prepaidForms = PaymentFormPolicy.decode(prepaidFormsRaw)

        for kind in [Invoice.Kind.sales, .purchase] {
            let inserted = (try? await InvoiceSyncEngine.sync(
                kind: kind,
                service: service,
                from: range.from,
                to: range.to,
                prepaidForms: prepaidForms,
                context: modelContext,
                trigger: trigger,
                environmentRaw: environmentRaw
            )) ?? 0
            if kind == .purchase, inserted > 0, notifyNewPurchases {
                await postNewPurchasesNotification(count: inserted)
            }
        }
    }

    /// Ponawia statusy wysyłek niezależnie od automatycznego importu faktur.
    /// Działa również na test/demo, ale wyłącznie dla rekordów zapisanych
    /// z aktualnie wybranym środowiskiem.
    @MainActor
    private func reconcileOutstandingSubmissions(trigger: SyncRun.Trigger) async {
        guard !myNIP.isEmpty, !tokenStore.token.isEmpty || KSeFCertificateStore.shared.authenticationCertificate != nil else { return }
        let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
        let service = KSeFService(
            environment: environment,
            nip: myNIP,
            authToken: tokenStore.token,
            certificate: KSeFCertificateStore.shared.authenticationCertificate
        )
        await reconcileOutstandingSubmissions(using: service, trigger: trigger)
    }

    @MainActor
    private func reconcileOutstandingSubmissions(using service: KSeFService, trigger: SyncRun.Trigger) async {
        let allInvoices = (try? modelContext.fetch(FetchDescriptor<Invoice>())) ?? []
        // Kolejka offline24 (bajt w bajt zapisany XML), statusy wysyłek
        // i UPO — z wpisem do historii Centrum synchronizacji, gdy było
        // co robić.
        await SyncCenter.reconcileSubmissions(
            invoices: allInvoices,
            environmentRaw: environmentRaw,
            trigger: trigger,
            using: service,
            context: modelContext
        )
        // Świeże liczniki dla ikony w pasku menu (kolejka mogła się domknąć).
        syncActivity.refreshMenuBarStatus(
            invoices: (try? modelContext.fetch(FetchDescriptor<Invoice>())) ?? []
        )
    }

    /// Powiadomienia o terminach płatności (dziś/jutro) i dosłań offline.
    /// Doręczone klucze są zapamiętywane (UserDefaults) i przycinane,
    /// żeby to samo powiadomienie nie wracało w kolejnych przebiegach.
    @MainActor
    private func postDeadlineNotifications() async {
        guard notifyDeadlines else { return }
        let invoices = (try? modelContext.fetch(FetchDescriptor<Invoice>())) ?? []
        let delivered = Set(
            UserDefaults.standard.stringArray(forKey: AppSettingsKeys.deadlineNotifiedKeys) ?? []
        )
        let pending = DeadlineNotificationEngine.pending(
            invoices: invoices, alreadyDelivered: delivered
        )
        guard !pending.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }

        var updatedDelivered = delivered
        for notification in pending {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "ksefiarz.deadline.\(notification.key)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
            updatedDelivered.insert(notification.key)
        }
        UserDefaults.standard.set(
            Array(DeadlineNotificationEngine.prune(delivered: updatedDelivered)),
            forKey: AppSettingsKeys.deadlineNotifiedKeys
        )
    }

    /// Powiadomienie systemowe o nowych fakturach zakupowych z synchronizacji.
    private func postNewPurchasesNotification(count: Int) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Nowe faktury zakupowe"
        content.body = count == 1
            ? "Pobrano 1 nową fakturę zakupową z KSeF."
            : "Pobrano \(count) nowych faktur zakupowych z KSeF."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "ksefiarz.newPurchases.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

#Preview {
    MainContentView()
        .modelContainer(for: Invoice.self, inMemory: true)
}
