import SwiftUI
import SwiftData

/// Dynamiczna lista faktur (zakupu lub sprzedaży) z filtrami, wyszukiwarką,
/// obsługą płatności (`isPaid`) oraz ukrywania (`isArchivedOrHidden`).
public struct InvoiceListView: View {

    let kind: Invoice.Kind

    @Query private var invoices: [Invoice]
    @Environment(\.modelContext) private var modelContext

    @State private var statusFilter: PaymentStatusFilter = .all
    @State private var syncFilter: KSeFSyncFilter = .all
    @State private var searchText = ""
    @State private var showingNewInvoice = false
    @State private var editedInvoice: Invoice?
    /// Ręczna faktura kosztowa (spoza KSeF): arkusz dodawania i edycji.
    @State private var showingNewPurchase = false
    @State private var editedPurchase: Invoice?
    /// Arkusz samofaktury — wystawienie w imieniu dostawcy z listy zakupów.
    @State private var showingNewSelfInvoice = false
    /// Publiczny, anonimowy import pojedynczego zakupu po danych faktury.
    @State private var showingAnonymousImport = false
    @State private var correctedInvoice: Invoice?
    @State private var duplicatedInvoice: Invoice?
    @State private var emailedInvoice: Invoice?
    /// NIP dłużnika dla arkusza wezwania do zapłaty (nil = arkusz zamknięty).
    @State private var demandBuyerNIP: String?
    @State private var documentTypeFilter: DocumentTypeFilter = .all
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var selection = Set<UUID>()
    @State private var navigationPath: [Invoice] = []
    /// Operacje wczytane z wyciągu bankowego — do arkusza dopasowań.
    @State private var statementTransactions: [BankTransaction] = []
    @State private var showingStatementImport = false
    @State private var showingAccountingPackage = false
    @State private var showingJPKExport = false
    @State private var showingVATUEExport = false
    /// Zamrożony wybór zakupów przekazywany do arkusza przelewów bankowych.
    @State private var bankTransferInvoices: [Invoice] = []
    @State private var showingBankTransferExport = false
    /// Zamrożone zaznaczenie przekazywane do arkusza wysyłki wsadowej.
    @State private var batchSendPreselection = Set<UUID>()
    @State private var showingBatchSend = false

    @AppStorage(AppSettingsKeys.prepaidForms) private var prepaidFormsRaw = PaymentFormPolicy.encode(PaymentFormPolicy.defaultPrepaidForms)

    @AppStorage(AppSettingsKeys.nip) private var myNIP = ""
    @ObservedObject private var tokenStore = TokenStore.shared
    private var ksefToken: String { tokenStore.token }
    @AppStorage(AppSettingsKeys.environment) private var environmentRaw = KSeFEnvironment.test.rawValue
    @AppStorage(AppSettingsKeys.rangeMode) private var rangeModeRaw = DateRangeMode.last3Months.rawValue
    @AppStorage(AppSettingsKeys.rangeFrom) private var rangeFromInterval = Date.now.timeIntervalSince1970 - 30 * 86_400
    @AppStorage(AppSettingsKeys.rangeTo) private var rangeToInterval = Date.now.timeIntervalSince1970

    /// Filtr wyświetlania zapamiętywany osobno dla listy zakupów i sprzedaży.
    @AppStorage private var displayFilterRaw: String

    public init(kind: Invoice.Kind) {
        self.kind = kind
        let raw = kind.rawValue
        _displayFilterRaw = AppStorage(
            wrappedValue: DisplayDateFilter.all.rawValue,
            "filter.list.\(raw)"
        )
        // Pobieramy tylko widoczne faktury danego rodzaju, najnowsze na górze.
        _invoices = Query(
            filter: #Predicate<Invoice> { $0.kindRaw == raw && $0.isArchivedOrHidden == false },
            sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
        )
    }

    /// Zakres dat importu z Ustawień — używany wyłącznie przy synchronizacji.
    private var importRange: (from: Date, to: Date) {
        DateRangeResolver.range(
            mode: DateRangeMode(rawValue: rangeModeRaw) ?? .last3Months,
            customFrom: Date(timeIntervalSince1970: rangeFromInterval),
            customTo: Date(timeIntervalSince1970: rangeToInterval)
        )
    }

    /// Filtr wyświetlania tej listy (niezależny od zakresu importu).
    private var displayFilter: DisplayDateFilter {
        DisplayDateFilter(rawValue: displayFilterRaw) ?? .all
    }

    /// Lista po zastosowaniu filtra dat widoku, statusu wysyłki,
    /// statusu płatności i wyszukiwarki.
    private var filteredInvoices: [Invoice] {
        let inRange = displayFilter.apply(to: invoices)
        let bySync = kind == .sales ? syncFilter.apply(to: inRange) : inRange
        let byType = documentTypeFilter.apply(to: bySync)
        return InvoiceFilter.apply(byType, status: statusFilter, searchText: searchText)
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            // Lista z zaznaczaniem (również wielu pozycji); szczegóły otwiera
            // dopiero podwójne kliknięcie — pojedyncze tylko zaznacza.
            List(selection: $selection) {
                ForEach(filteredInvoices) { invoice in
                    listRow(for: invoice)
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                contextMenuContent(for: ids)
            } primaryAction: { ids in
                // Podwójne kliknięcie — otwarcie szczegółów.
                if let id = ids.first, let invoice = invoices.first(where: { $0.id == id }) {
                    navigationPath.append(invoice)
                }
            }
            // Zmiana LICZBY faktur przebudowuje listę od zera — obejście błędu
            // macOS, w którym wiersz wstawiony do żywej listy (np. świeżo
            // wystawiona faktura) renderował się ze zwiniętą wysokością
            // do czasu przełączenia widoku. Filtrowanie nie zmienia tożsamości.
            .id(invoices.count)
            .navigationDestination(for: Invoice.self) { invoice in
                InvoiceDetailView(invoice: invoice)
            }
            .searchable(text: $searchText, prompt: "Szukaj po NIP lub nazwie kontrahenta")
            .navigationTitle(kind == .sales ? "Faktury Sprzedaży" : "Faktury Zakupu")
            .toolbar { toolbarContent }
            .overlay {
                if filteredInvoices.isEmpty {
                    ContentUnavailableView(
                        "Brak faktur",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(
                            kind == .purchase
                                ? "Pobierz faktury zakupowe z KSeF lub zmień kryteria filtrowania."
                                : "Wystaw pierwszą fakturę przyciskiem „+” lub zmień kryteria filtrowania."
                        )
                    )
                }
            }
            .sheet(isPresented: $showingNewInvoice) {
                NewInvoiceView()
            }
            .sheet(item: $editedInvoice) { invoice in
                NewInvoiceView(editing: invoice)
            }
            .sheet(isPresented: $showingNewPurchase) {
                NewPurchaseView()
            }
            .sheet(isPresented: $showingNewSelfInvoice) {
                NewInvoiceView(selfInvoicing: true)
            }
            .sheet(isPresented: $showingAnonymousImport) {
                AnonymousInvoiceImportView()
            }
            .sheet(item: $editedPurchase) { invoice in
                NewPurchaseView(editing: invoice)
            }
            .sheet(item: $correctedInvoice) { invoice in
                NewInvoiceView(correcting: invoice)
            }
            .sheet(isPresented: $showingStatementImport) {
                BankStatementImportView(transactions: statementTransactions)
            }
            .sheet(isPresented: $showingAccountingPackage) {
                AccountingPackageView()
            }
            .sheet(isPresented: $showingJPKExport) {
                JPKExportView()
            }
            .sheet(isPresented: $showingVATUEExport) {
                VATUEExportView()
            }
            .sheet(isPresented: $showingBankTransferExport) {
                BankTransferExportView(invoices: bankTransferInvoices)
            }
            .sheet(isPresented: $showingBatchSend) {
                BatchSendView(preselected: batchSendPreselection)
            }
            .sheet(item: $duplicatedInvoice) { invoice in
                NewInvoiceView(
                    initialDraft: InvoiceAutomationEngine.duplicate(invoice),
                    sourceTitle: "Duplikat faktury"
                )
            }
            .sheet(item: $emailedInvoice) { invoice in
                InvoiceEmailView(invoice: invoice)
            }
            .sheet(isPresented: Binding(
                get: { demandBuyerNIP != nil },
                set: { if !$0 { demandBuyerNIP = nil } }
            )) {
                PaymentDemandView(preselectedBuyerNIP: demandBuyerNIP)
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
    }

    /// Pasek narzędzi listy — wydzielony, bo rozbudowany budowniczy
    /// w `body` przekraczał budżet type-checkera Swifta.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Filtr", selection: $statusFilter) {
                ForEach(PaymentStatusFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
        if kind == .sales {
            ToolbarItem {
                // Filtr statusu wysyłki do KSeF (tylko sprzedaż).
                Picker(selection: $syncFilter) {
                    ForEach(KSeFSyncFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                } label: {
                    Label("KSeF", systemImage: "paperplane")
                }
                .help("Filtruj według statusu wysyłki do KSeF")
            }
        }
        ToolbarItem {
            // Filtr rodzaju dokumentu (VAT/ZAL/ROZ/UPR/korekty).
            Picker(selection: $documentTypeFilter) {
                ForEach(DocumentTypeFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            } label: {
                Label("Rodzaj", systemImage: "doc.on.doc")
            }
            .help("Filtruj według rodzaju dokumentu")
        }
        ToolbarItem {
            // Filtr dat wyświetlania — niezależny od zakresu importu.
            Picker(selection: $displayFilterRaw) {
                ForEach(DisplayDateFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter.rawValue)
                }
            } label: {
                Label("Okres", systemImage: "calendar")
            }
            .help("Okres wyświetlanych faktur")
        }
        ToolbarItemGroup {
            Button {
                FileExportService.exportCSV(of: filteredInvoices, suggestedName: csvFileName)
            } label: {
                Label("Eksportuj CSV", systemImage: "tablecells")
            }
            .disabled(filteredInvoices.isEmpty)
            .help("Eksportuj widoczne faktury do pliku CSV (np. dla księgowości)")
            Button {
                importBankStatement()
            } label: {
                Label("Importuj wyciąg", systemImage: "building.columns")
            }
            .help("Wczytaj wyciąg bankowy (MT940) i dopasuj przelewy do nieopłaconych faktur")
            if kind == .purchase {
                Button {
                    openBankTransferExport(for: bankTransferScope)
                } label: {
                    Label("Przelewy do banku", systemImage: "building.columns.fill")
                }
                .disabled(bankTransferScope.isEmpty)
                .help("Eksportuj zaznaczone (albo wszystkie widoczne) zobowiązania do paczki Elixir-O")
            }
        }
        ToolbarItem {
            Button {
                showingAccountingPackage = true
            } label: {
                Label("Paczka dla księgowości", systemImage: "archivebox")
            }
            .help("Eksportuj wybrany okres do ZIP: zestawienia CSV, XML, PDF i raport braków")
        }
        ToolbarItem {
            Menu {
                Button {
                    showingJPKExport = true
                } label: {
                    Label("JPK_V7M / V7K — ewidencja VAT", systemImage: "doc.badge.gearshape")
                }
                Button {
                    showingVATUEExport = true
                } label: {
                    Label("VAT-UE — informacja podsumowująca", systemImage: "globe.europe.africa")
                }
            } label: {
                Label("Ewidencje", systemImage: "doc.badge.gearshape")
            }
            .help("Eksport ewidencji VAT wybranego miesiąca: JPK_V7M/V7K (sprzedaż + zakup, GTU, procedury, deklaracja miesięczna lub kwartalna) lub VAT-UE (WDT, WNT, usługi UE)")
        }
        if kind == .sales {
            ToolbarItem {
                // Wysyłka wsadowa (sesja batch/ZIP) — masowa wysyłka
                // lokalnych dokumentów, np. po migracji z innego systemu.
                Button {
                    openBatchSend(preselection: selection)
                } label: {
                    Label("Wyślij wsadowo do KSeF", systemImage: "square.and.arrow.up.on.square")
                }
                .help("Wyślij lokalne dokumenty jedną paczką ZIP (sesja wsadowa KSeF) — zaznaczone albo wszystkie kwalifikujące się")
            }
        }
        ToolbarItem {
            Button {
                Task { await syncFromKSeF() }
            } label: {
                if isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Pobierz z KSeF", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isSyncing)
            .help(
                kind == .purchase
                    ? "Pobierz faktury zakupowe z KSeF (zakres dat z Ustawień)"
                    : "Pobierz wystawione faktury sprzedażowe z KSeF (zakres dat z Ustawień)"
            )
        }
        // Jeden przycisk „+” na liście: sprzedaż wystawia fakturę,
        // zakupy dodają dokument kosztowy spoza KSeF.
        ToolbarItem {
            if kind == .sales {
                Button {
                    showingNewInvoice = true
                } label: {
                    Label("Nowa faktura", systemImage: "plus")
                }
                .help("Wystaw nową fakturę")
            } else {
                Menu {
                    Button {
                        showingNewPurchase = true
                    } label: {
                        Label("Dodaj zakup spoza KSeF", systemImage: "doc.badge.plus")
                    }
                    Button {
                        showingNewSelfInvoice = true
                    } label: {
                        Label("Wystaw samofakturę (w imieniu dostawcy)", systemImage: "person.2.badge.gearshape")
                    }
                    Button {
                        showingAnonymousImport = true
                    } label: {
                        Label("Pobierz po numerze KSeF…", systemImage: "number.square")
                    }
                } label: {
                    Label("Dodaj", systemImage: "plus")
                }
                .help("Dodaj zakup spoza KSeF, pobierz pojedynczą fakturę anonimowo po numerze KSeF albo wystaw samofakturę")
            }
        }
    }

    /// Wiersz listy z akcjami swipe — wydzielony, bo rozbudowane wyrażenie
    /// w ForEach przekraczało budżet type-checkera Swifta.
    private func listRow(for invoice: Invoice) -> some View {
        InvoiceRowView(invoice: invoice)
            .tag(invoice.id)
            // Swipe w prawo — przełącz status opłacenia.
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    invoice.isPaid.toggle()
                } label: {
                    Label(
                        invoice.isPaid ? "Nieopłacona" : "Opłacona",
                        systemImage: invoice.isPaid ? "xmark.circle" : "checkmark.circle"
                    )
                }
                .tint(invoice.isPaid ? .orange : .green)
            }
            // Swipe w lewo — ukrycie dotyczy wyłącznie zakupów
            // (ochrona przed nieuprawnionymi fakturami na nasz NIP).
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if kind == .purchase {
                    Button(role: .destructive) {
                        invoice.isArchivedOrHidden = true
                    } label: {
                        Label("Ukryj", systemImage: "eye.slash")
                    }
                }
            }
    }

    // MARK: Menu kontekstowe (pojedyncze i zbiorcze)

    /// Faktury odpowiadające zaznaczonym identyfikatorom.
    private func selectedInvoices(for ids: Set<UUID>) -> [Invoice] {
        invoices.filter { ids.contains($0.id) }
    }

    /// Menu kontekstowe: dla jednej faktury pełny zestaw akcji,
    /// dla wielu — operacje zbiorcze.
    @ViewBuilder
    private func contextMenuContent(for ids: Set<UUID>) -> some View {
        let selected = selectedInvoices(for: ids)

        if selected.count == 1, let invoice = selected.first {
            Button("Otwórz szczegóły") {
                navigationPath.append(invoice)
            }
            Divider()
            Button(invoice.isPaid ? "Oznacz jako nieopłaconą" : "Oznacz jako opłaconą") {
                invoice.isPaid.toggle()
            }
            if kind == .sales {
                Button("Wyślij e-mailem…") {
                    emailedInvoice = invoice
                }
                if invoice.isOverdue {
                    Button("Wezwanie do zapłaty…") {
                        demandBuyerNIP = invoice.buyerNIP
                    }
                }
            }
            // Korekta dostępna dla sprzedaży oraz wystawionych przez nas
            // dokumentów zakupowych (VAT RR, samofaktura).
            if invoice.hasKSeFSubmissionLifecycle, !invoice.isCorrection {
                Button("Wystaw korektę") {
                    correctedInvoice = invoice
                }
                Button("Duplikuj fakturę") {
                    duplicatedInvoice = invoice
                }
            }
            // Faktury tylko lokalne (niewysłane do KSeF) można edytować i usuwać.
            if invoice.hasKSeFSubmissionLifecycle, invoice.isLocalOnly {
                Divider()
                Button("Edytuj fakturę") {
                    editedInvoice = invoice
                }
                Button("Usuń fakturę (lokalna)", role: .destructive) {
                    modelContext.delete(invoice)
                }
            }
            // Ręczne zakupy (spoza KSeF) można edytować i usuwać.
            if invoice.isManualPurchase {
                Divider()
                Button("Edytuj fakturę kosztową") {
                    editedPurchase = invoice
                }
                Button("Usuń fakturę kosztową (lokalna)", role: .destructive) {
                    modelContext.delete(invoice)
                }
            }
            if kind == .purchase {
                Divider()
                Button("Eksportuj przelew do banku…") {
                    openBankTransferExport(for: [invoice])
                }
                Button("Ukryj fakturę (Nieuprawniony zakup)", role: .destructive) {
                    invoice.isArchivedOrHidden = true
                }
            }
        } else if selected.count > 1 {
            Button("Oznacz \(selected.count) jako opłacone") {
                selected.forEach { $0.isPaid = true }
            }
            Button("Oznacz \(selected.count) jako nieopłacone") {
                selected.forEach { $0.isPaid = false }
            }
            // Wysyłka wsadowa zaznaczonych dokumentów lokalnych.
            if !BatchSendEngine.eligible(in: selected).isEmpty {
                Divider()
                Button("Wyślij wsadowo do KSeF…") {
                    openBatchSend(preselection: ids)
                }
            }
            if kind == .purchase {
                Divider()
                Button("Eksportuj \(selected.count) przelewów do banku…") {
                    openBankTransferExport(for: selected)
                }
                Button("Ukryj \(selected.count) faktur (nieuprawnione)", role: .destructive) {
                    selected.forEach { $0.isArchivedOrHidden = true }
                    selection.removeAll()
                }
            }
        }
    }

    /// Nazwa pliku CSV z rodzajem i bieżącą datą.
    private var csvFileName: String {
        let kindName = kind == .purchase ? "zakupy" : "sprzedaz"
        return "faktury_\(kindName)_\(FA2Format.dateFormatter.string(from: .now)).csv"
    }

    /// Pasek narzędzi respektuje multiselect: gdy nic nie zaznaczono,
    /// arkusz dostaje wszystkie aktualnie widoczne dokumenty.
    private var bankTransferScope: [Invoice] {
        guard !selection.isEmpty else { return filteredInvoices }
        return filteredInvoices.filter { selection.contains($0.id) }
    }

    private func openBankTransferExport(for invoices: [Invoice]) {
        bankTransferInvoices = invoices
        showingBankTransferExport = true
    }

    /// Otwiera arkusz wysyłki wsadowej z zamrożonym zaznaczeniem listy.
    private func openBatchSend(preselection: Set<UUID>) {
        batchSendPreselection = preselection
        showingBatchSend = true
    }

    // MARK: Import wyciągu bankowego

    /// Wczytuje plik wyciągu (MT940), parsuje operacje i otwiera arkusz
    /// dopasowań. Banki zapisują wyciągi w różnych kodowaniach i pod
    /// różnymi rozszerzeniami (.sta/.mt940/.txt) — plik może być dowolny.
    private func importBankStatement() {
        guard let data = FileExportService.importAnyData(
            message: "Wybierz plik wyciągu bankowego (MT940)"
        ) else { return }
        let transactions = MT940Parser.parse(MT940Parser.decode(data))
        guard !transactions.isEmpty else {
            errorMessage = "Nie znaleziono operacji w pliku — czy to wyciąg w formacie MT940?"
            return
        }
        statementTransactions = transactions
        showingStatementImport = true
    }

    // MARK: Synchronizacja z KSeF

    /// Pobiera faktury (zakupowe lub sprzedażowe) z zakresu dat ustawionego
    /// w Ustawieniach i zapisuje nowe do bazy.
    @MainActor
    private func syncFromKSeF() async {
        guard !myNIP.isEmpty, !ksefToken.isEmpty || KSeFCertificateStore.shared.authenticationCertificate != nil else {
            errorMessage = KSeFError.missingCredentials.localizedDescription
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
        let service = KSeFService(environment: environment, nip: myNIP, authToken: ksefToken, certificate: KSeFCertificateStore.shared.authenticationCertificate)
        // Zakres importu pochodzi z Ustawień.
        let range = importRange

        do {
            if kind == .sales {
                // Domknięcie wysyłek (kolejka offline + statusy + UPO)
                // z wpisem do historii Centrum synchronizacji.
                let allInvoices = (try? modelContext.fetch(FetchDescriptor<Invoice>())) ?? []
                await SyncCenter.reconcileSubmissions(
                    invoices: allInvoices,
                    environmentRaw: environmentRaw,
                    trigger: .manual,
                    using: service,
                    context: modelContext
                )
            }
            try await InvoiceSyncEngine.sync(
                kind: kind,
                service: service,
                from: range.from,
                to: range.to,
                prepaidForms: PaymentFormPolicy.decode(prepaidFormsRaw),
                context: modelContext,
                trigger: .manual,
                environmentRaw: environmentRaw
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Wiersz listy

/// Pojedynczy wiersz faktury z wizualnym znacznikiem statusu płatności.
struct InvoiceRowView: View {
    let invoice: Invoice

    /// Kontrahent prezentowany w wierszu — dla zakupów sprzedawca, dla sprzedaży nabywca.
    private var contractorName: String {
        invoice.kind == .purchase ? invoice.sellerName : invoice.buyerName
    }

    private var contractorNIP: String {
        invoice.kind == .purchase ? invoice.sellerNIP : invoice.buyerNIP
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(contractorName)
                        .font(.headline)
                        .lineLimit(1)
                    if invoice.isCorrection {
                        Text("KOR")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.purple.opacity(0.18), in: Capsule())
                            .foregroundStyle(.purple)
                            .help("Faktura korygująca")
                    }
                    if invoice.isSelfInvoicing {
                        SelfInvoicingBadge(isPurchase: invoice.kind == .purchase)
                    }
                    // Pełny cykl wysyłki KSeF dotyczy sprzedaży oraz
                    // wystawianych przez nas dokumentów zakupowych.
                    if invoice.hasKSeFSubmissionLifecycle {
                        KSeFSubmissionBadge(invoice: invoice)
                    }
                    if invoice.isManualPurchase {
                        Text("Spoza KSeF")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.gray.opacity(0.18), in: Capsule())
                            .foregroundStyle(.secondary)
                            .help("Faktura kosztowa dodana ręcznie (spoza KSeF)")
                    }
                }
                HStack(spacing: 8) {
                    Text(invoice.invoiceNumber)
                    Text("NIP: \(contractorNIP)")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(invoice.grossAmount, format: .currency(code: invoice.currency))
                    .font(.headline)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Text(invoice.issueDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PaymentBadge(invoice: invoice)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Znacznik samofakturowania (Adnotacje P_17 = 1, art. 106d):
/// na zakupie — samofaktura wystawiona przez nas w imieniu dostawcy,
/// na sprzedaży — dokument wystawiony przez klienta w naszym imieniu.
struct SelfInvoicingBadge: View {
    let isPurchase: Bool

    var body: some View {
        Text("Samofakturowanie")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.teal.opacity(0.18), in: Capsule())
            .foregroundStyle(.teal)
            .help(isPurchase
                ? "Samofaktura — wystawiona przez nas (nabywcę) w imieniu dostawcy (art. 106d)"
                : "Fakturę wystawił nabywca w naszym imieniu (samofakturowanie, art. 106d)")
    }
}

/// Znacznik pełnego cyklu wysyłki KSeF.
struct KSeFSubmissionBadge: View {
    let invoice: Invoice

    private var label: String {
        switch invoice.ksefSubmissionStatus {
        case .local: return "Lokalna"
        case .offlinePending: return "Offline24"
        case .processing: return "KSeF: w toku"
        case .accepted: return "KSeF: przyjęta"
        case .rejected: return "KSeF: odrzucona"
        }
    }

    private var color: Color {
        switch invoice.ksefSubmissionStatus {
        case .local: return .gray
        // Po terminie dosłania kolejka wymaga uwagi użytkownika.
        case .offlinePending:
            if let deadline = invoice.offlineSendDeadline, deadline < .now { return .red }
            return .blue
        case .processing: return .orange
        case .accepted: return .green
        case .rejected: return .red
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .help(invoice.ksefSubmissionStatus.displayName)
    }
}

/// Znacznik (badge) statusu płatności:
/// zielony — opłacona, czerwony — zaległa, pomarańczowy — do opłacenia.
struct PaymentBadge: View {
    let invoice: Invoice

    private var label: String {
        if invoice.isPaid { return "Opłacona" }
        if invoice.isOverdue { return "Zaległa" }
        return invoice.isPartiallyPaid ? "Częściowo" : "Do opłacenia"
    }

    private var color: Color {
        if invoice.isPaid { return .green }
        if invoice.isOverdue { return .red }
        return invoice.isPartiallyPaid ? .teal : .orange
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
