import SwiftUI
import SwiftData
import UserNotifications

/// Sekcje paska bocznego aplikacji.
public enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case sales
    case purchases
    case proformas
    case reports
    case kpir
    case ryczalt
    case dictionaries
    case automation
    case syncCenter
    case permissions
    case hidden
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Kokpit"
        case .sales: return "Faktury Sprzedaży"
        case .purchases: return "Faktury Zakupu"
        case .proformas: return "Faktury proforma"
        case .reports: return "Raporty"
        case .kpir: return "KPiR"
        case .ryczalt: return "Ewidencja przychodów"
        case .dictionaries: return "Słowniki"
        case .automation: return "Szablony i cykle"
        case .syncCenter: return "Synchronizacja"
        case .permissions: return "Uprawnienia"
        case .hidden: return "Nieuprawnione / Ukryte"
        case .settings: return "Ustawienia"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .sales: return "arrow.up.doc"
        case .purchases: return "arrow.down.doc"
        case .proformas: return "doc.plaintext"
        case .reports: return "chart.bar.xaxis"
        case .kpir: return "books.vertical"
        case .ryczalt: return "list.bullet.rectangle.portrait"
        case .dictionaries: return "text.book.closed"
        case .automation: return "calendar.badge.clock"
        case .syncCenter: return "arrow.triangle.2.circlepath"
        case .permissions: return "person.2.badge.key"
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
    /// Publiczny status dostępności KSeF z API Latarni MF.
    @ObservedObject private var availabilityMonitor = KSeFAvailabilityMonitor.shared

    @Environment(\.modelContext) private var modelContext
    /// Akcja otwierania okna — udostępniana AppKit-owej ikonie w pasku menu
    /// (patrz `MainWindowOpener`), by „Otwórz Ksefiarza” działało po zamknięciu okna.
    @Environment(\.openWindow) private var openWindow
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
    @AppStorage(AppSettingsKeys.autoRenewCertificates) private var autoRenewCertificates = true
    @AppStorage(AppSettingsKeys.taxForm) private var taxFormRaw = TaxForm.kpir.rawValue
    @AppStorage(AppSettingsKeys.reminderEmailsEnabled) private var reminderEmailsEnabled = false
    @AppStorage(AppSettingsKeys.reminderDaysBefore) private var reminderDaysBefore = 3
    @AppStorage(AppSettingsKeys.reminderRepeatDays) private var reminderRepeatDays = 7
    @AppStorage(AppSettingsKeys.reminderDeliveryMode) private var reminderDeliveryModeRaw = MailAutomationService.DeliveryMode.draft.rawValue

    public init() {}

    /// Sekcje widoczne w pasku bocznym. Ewidencja podatkowa zależy od wybranej
    /// formy opodatkowania — KPiR albo ryczałt, nigdy obie naraz.
    private var visibleSections: [SidebarSection] {
        let taxForm = TaxForm.resolve(taxFormRaw)
        return SidebarSection.allCases.filter { section in
            switch section {
            case .kpir: return taxForm == .kpir
            case .ryczalt: return taxForm == .ryczalt
            default: return true
            }
        }
    }

    public var body: some View {
        NavigationSplitView {
            List(visibleSections, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            // Po zmianie formy opodatkowania nie zostawiaj zaznaczenia na
            // ukrytej już ewidencji — przełącz na Kokpit.
            .onChange(of: taxFormRaw) {
                if let current = selection, !visibleSections.contains(current) {
                    selection = .dashboard
                }
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
            case .proformas:
                ProformaListView()
            case .reports:
                ReportsView()
            case .kpir:
                KPiRView()
            case .ryczalt:
                RyczaltView()
            case .dictionaries:
                DictionariesView()
            case .automation:
                InvoiceAutomationView()
            case .syncCenter:
                SyncCenterView()
            case .permissions:
                PermissionsView()
            case .hidden:
                HiddenInvoicesView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 920, minHeight: 580)
        // Udostępnij ikonie w pasku menu akcję otwarcia okna (NSStatusItem
        // nie ma dostępu do środowiskowego `openWindow`) i uruchom kontroler
        // ikony (tu jest dostęp do modelContext — delegat AppKit przy
        // @NSApplicationDelegateAdaptor nie jest gwarantowany).
        .onAppear {
            MainWindowOpener.open = { openWindow(id: "main") }
            MenuBarController.shared.start(context: modelContext)
        }
        // Kopia zapasowa PRZED synchronizacją — utrwala stan sprzed zmian.
        .task {
            if autoBackup { performAutoBackup() }
            await reconcileOutstandingSubmissions(trigger: .launch)
            if syncOnLaunch { await syncBothKinds(trigger: .launch) }
            await postDeadlineNotifications()
            await renewCertificatesIfNeeded()
            await processPaymentReminders()
        }
        // Latarnia MF nie wymaga uwierzytelnienia. Status i komunikaty są
        // odświeżane co minutę; komunikat kończący uzupełnia termin tylko
        // w dokumentach powiązanych z tym samym eventId.
        .task(id: "ksef-availability-\(environmentRaw)") {
            await refreshKSeFAvailability()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await refreshKSeFAvailability()
            }
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
        // Automatyczne przypomnienia e-mail o płatnościach — sprawdzane
        // co 6 godzin (przypomnienia mają ziarnistość dnia; deduplikacja
        // po dacie ostatniego przypomnienia na fakturze).
        .task(id: "payment-reminders-\(reminderEmailsEnabled)") {
            guard reminderEmailsEnabled else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6 * 3600))
                guard !Task.isCancelled else { return }
                await processPaymentReminders()
            }
        }
        // Odnowienie certyfikatów sprawdzane cyklicznie (okno ~30 dni przed
        // wygaśnięciem — wystarczy raz na kilka godzin; deduplikacja
        // gwarantuje jedną próbę na certyfikat na dobę).
        .task(id: "cert-renewal-\(autoRenewCertificates)-\(environmentRaw)") {
            guard autoRenewCertificates else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12 * 3600))
                guard !Task.isCancelled else { return }
                await renewCertificatesIfNeeded()
            }
        }
    }

    /// Pobiera oficjalny status Latarni i aktualizuje daty końca zdarzeń
    /// w oczekujących fakturach offline. Demo nie ma własnej Latarni.
    @MainActor
    private func refreshKSeFAvailability() async {
        let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
        guard let snapshot = await availabilityMonitor.refresh(environment: environment) else {
            return
        }
        let invoices = (try? modelContext.fetch(FetchDescriptor<Invoice>())) ?? []
        let changed = KSeFAvailabilityPolicy.reconcile(
            invoices: invoices,
            messages: snapshot.messages,
            environmentRaw: environment.rawValue
        )
        if changed > 0 {
            try? modelContext.save()
            syncActivity.refreshMenuBarStatus(invoices: invoices)
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

    /// Automatyczne przypomnienia e-mail o płatnościach (C4): silnik wybiera
    /// faktury w oknie przed terminem i cykliczne ponaglenia po terminie,
    /// a wiadomości trafiają do aplikacji Mail jako szkice albo są wysyłane
    /// automatycznie (wg Ustawień). Każde przekazane przypomnienie jest
    /// odnotowywane na fakturze (`collectionReminderAt`) — to jedyna pamięć
    /// doręczeń, wspólna ze ścieżką windykacji. Błąd automatyzacji (np. brak
    /// zgody) przerywa przebieg i jest zgłaszany powiadomieniem raz dziennie.
    @MainActor
    private func processPaymentReminders() async {
        guard reminderEmailsEnabled else { return }
        let invoices = (try? modelContext.fetch(FetchDescriptor<Invoice>())) ?? []
        let contractors = (try? modelContext.fetch(FetchDescriptor<Contractor>())) ?? []
        let result = PaymentReminderEngine.candidates(
            invoices: invoices,
            contractors: contractors,
            settings: PaymentReminderSettings(
                daysBeforeDue: reminderDaysBefore,
                repeatAfterDays: reminderRepeatDays
            )
        )
        guard !result.candidates.isEmpty else { return }
        let mode = MailAutomationService.DeliveryMode(rawValue: reminderDeliveryModeRaw) ?? .draft

        var deliveredNumbers: [String] = []
        var failure: Error?
        for candidate in result.candidates {
            do {
                try MailAutomationService.deliver(
                    recipient: candidate.recipient,
                    subject: candidate.subject,
                    body: candidate.body,
                    mode: mode
                )
                DebtCollectionEngine.record(.reminder, on: [candidate.invoice])
                deliveredNumbers.append(candidate.invoice.invoiceNumber)
            } catch {
                // Zwykle brak zgody na automatyzację — kolejne wywołania
                // skończyłyby się tak samo, więc przerywamy przebieg.
                failure = error
                break
            }
        }
        if !deliveredNumbers.isEmpty {
            try? modelContext.save()
        }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }

        if !deliveredNumbers.isEmpty {
            let content = UNMutableNotificationContent()
            content.title = mode == .send
                ? "Wysłano przypomnienia o płatnościach"
                : "Przygotowano szkice przypomnień w Mail"
            let listed = deliveredNumbers.prefix(5).joined(separator: ", ")
            let suffix = deliveredNumbers.count > 5 ? "…" : ""
            content.body = mode == .send
                ? "Liczba wiadomości: \(deliveredNumbers.count) (\(listed)\(suffix))."
                : "Liczba szkiców: \(deliveredNumbers.count) (\(listed)\(suffix)) — przejrzyj Wersje robocze w Mail i wyślij."
            content.sound = .default
            try? await center.add(UNNotificationRequest(
                identifier: "ksefiarz.reminders.\(UUID().uuidString)",
                content: content,
                trigger: nil
            ))
        }
        if let failure {
            // Jedno powiadomienie o problemie dziennie — cykl co 6 godzin
            // nie powinien czterokrotnie powtarzać tej samej diagnozy.
            let dayKey = ISO8601DateFormatter.string(
                from: .now, timeZone: .current,
                formatOptions: [.withFullDate]
            )
            let lastNotified = UserDefaults.standard.string(
                forKey: AppSettingsKeys.reminderErrorNotifiedDay
            )
            if lastNotified != dayKey {
                UserDefaults.standard.set(dayKey, forKey: AppSettingsKeys.reminderErrorNotifiedDay)
                let content = UNMutableNotificationContent()
                content.title = "Przypomnienia o płatnościach wstrzymane"
                content.body = failure.localizedDescription
                content.sound = .default
                try? await center.add(UNNotificationRequest(
                    identifier: "ksefiarz.reminders.error.\(dayKey)",
                    content: content,
                    trigger: nil
                ))
            }
        }
    }

    /// Automatyczne odnowienie certyfikatów KSeF: gdy któryś zbliża się do
    /// końca ważności (okno ~30 dni), aplikacja sama składa wniosek o nowy
    /// (typ 1 i/lub typ 2) i podmienia go w pęku kluczy. Wymaga WAŻNEGO
    /// certyfikatu typu 1 do zalogowania podpisem XAdES — po jego wygaśnięciu
    /// (albo bez niego) automat nic nie robi. Próby są deduplikowane
    /// (UserDefaults) do jednej na certyfikat na dobę; niepowodzenie nie
    /// narusza dotychczasowego certyfikatu.
    @MainActor
    private func renewCertificatesIfNeeded() async {
        guard autoRenewCertificates, !myNIP.isEmpty else { return }
        let store = KSeFCertificateStore.shared
        // Podpisujący i środowisko USTALONE RAZ, przed sieciowym przebiegiem.
        // W punktach `await` użytkownik mógłby przełączyć środowisko, a zapis
        // typu 1 podmienia certyfikat w magazynie — dlatego wszystkie wnioski
        // podpisujemy tym samym, wciąż ważnym certyfikatem typu 1 (nigdy
        // świeżo wystawionym, który po stronie serwera może nie być aktywny),
        // a nowe certyfikaty zapisujemy pod środowiskiem z chwili startu.
        guard let signer = store.authenticationCertificate else { return }
        let renewalEnvRaw = environmentRaw
        let environment = KSeFEnvironment(rawValue: renewalEnvRaw) ?? .test
        let nip = myNIP

        let attempted = Set(
            UserDefaults.standard.stringArray(forKey: AppSettingsKeys.certificateRenewalAttemptedKeys) ?? []
        )
        let candidates = CertificateRenewalEngine.candidates(
            authentication: signer.info,
            offline: store.offlineCertificate?.info,
            alreadyAttempted: attempted
        )
        guard !candidates.isEmpty else { return }

        let outcomes = await CertificateRenewalCoordinator.run(
            candidates: candidates,
            renew: { type in
                // Bez tokenu: enrollment WYMAGA podpisu XAdES certyfikatem
                // typu 1 (token dostałby 25002), więc token tylko maskowałby
                // porażkę auth i marnował limitowany wniosek.
                let service = KSeFService(
                    environment: environment,
                    nip: nip,
                    authToken: "",
                    certificate: signer
                )
                return try await service.renewCertificate(type: type)
            },
            save: { certificate, type in
                store.save(certificate, type: type, environmentRaw: renewalEnvRaw)
            }
        )

        // Zapamiętaj próby (dedup) niezależnie od wyniku — jedna próba na dobę.
        var updatedAttempted = attempted
        for outcome in outcomes { updatedAttempted.insert(outcome.dedupKey) }
        UserDefaults.standard.set(
            Array(CertificateRenewalEngine.prune(attempted: updatedAttempted)),
            forKey: AppSettingsKeys.certificateRenewalAttemptedKeys
        )

        // Powiadomienia o wyniku (sukces i niepowodzenie).
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        for outcome in outcomes {
            let content = UNMutableNotificationContent()
            content.title = outcome.notificationTitle
            content.body = outcome.notificationBody
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "ksefiarz.certRenewal.\(outcome.dedupKey)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
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
