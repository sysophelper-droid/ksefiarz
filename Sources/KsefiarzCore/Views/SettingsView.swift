import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Ustawienia aplikacji — dane firmy (z adresem i rachunkiem), token KSeF,
/// środowisko, numeracja, zakres importu oraz kopia zapasowa danych.
public struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var backupStatus: String?

    @AppStorage(AppSettingsKeys.sellerName) private var sellerName = ""
    @AppStorage(AppSettingsKeys.sellerAddress) private var sellerAddress = ""
    @AppStorage(AppSettingsKeys.nip) private var nip = ""
    @AppStorage(AppSettingsKeys.bankAccount) private var bankAccount = ""
    @AppStorage(AppSettingsKeys.taxForm) private var taxFormRaw = TaxForm.kpir.rawValue
    @AppStorage(AppSettingsKeys.ryczaltDefaultRate) private var ryczaltDefaultRateRaw = RyczaltRate.r8_5.rawValue
    @AppStorage(AppSettingsKeys.kpirIncomeTaxMethod) private var kpirIncomeTaxMethodRaw = KPiRIncomeTaxMethod.scale.rawValue
    @AppStorage(AppSettingsKeys.incomeTaxSettlementCycle) private var incomeTaxSettlementCycleRaw = TaxSettlementCycle.monthly.rawValue
    @AppStorage(AppSettingsKeys.vatSettlementCycle) private var vatSettlementCycleRaw = TaxSettlementCycle.monthly.rawValue
    @AppStorage(AppSettingsKeys.isActiveVATPayer) private var isActiveVATPayer = true
    @AppStorage(AppSettingsKeys.pdfBrandingEnabled) private var pdfBrandingEnabled = false
    @AppStorage(AppSettingsKeys.pdfBrandingLogo) private var pdfBrandingLogo = ""
    @AppStorage(AppSettingsKeys.pdfBrandingPrimaryColor) private var pdfBrandingPrimaryColor = InvoicePDFBranding.defaultPrimaryHex
    @AppStorage(AppSettingsKeys.pdfBrandingAccentColor) private var pdfBrandingAccentColor = InvoicePDFBranding.defaultAccentHex
    @AppStorage(AppSettingsKeys.pdfBrandingFooter) private var pdfBrandingFooter = ""
    @AppStorage(AppSettingsKeys.pdfPaymentQR) private var pdfPaymentQR = true
    @AppStorage(AppSettingsKeys.paymentQRRecipientName) private var paymentQRRecipientName = ""
    @State private var isChoosingBrandingLogo = false
    @State private var brandingLogoError: String?
    @ObservedObject private var tokenStore = TokenStore.shared
    @AppStorage(AppSettingsKeys.syncOnLaunch) private var syncOnLaunch = false
    @AppStorage(AppSettingsKeys.autoSync) private var autoSync = false
    @AppStorage(AppSettingsKeys.autoSyncIntervalMinutes) private var autoSyncIntervalMinutes = 60
    @AppStorage(AppSettingsKeys.autoBackup) private var autoBackup = true
    @AppStorage(AppSettingsKeys.autoBackupRotationMode) private var backupRotationModeRaw = AutoBackupService.RotationMode.keepCount.rawValue
    @AppStorage(AppSettingsKeys.autoBackupKeepCount) private var backupKeepCount = 14
    @AppStorage(AppSettingsKeys.autoBackupKeepDays) private var backupKeepDays = 30
    @AppStorage(AppSettingsKeys.notifyNewPurchases) private var notifyNewPurchases = true
    @AppStorage(AppSettingsKeys.notifyDeadlines) private var notifyDeadlines = true
    @AppStorage(AppSettingsKeys.menuBarExtra) private var menuBarExtraEnabled = true

    /// Dostępne interwały automatycznego pobierania.
    static let autoSyncIntervals: [(minutes: Int, label: String)] = [
        (15, "15 minut"),
        (30, "30 minut"),
        (60, "1 godzina"),
        (120, "2 godziny"),
        (180, "3 godziny"),
        (300, "5 godzin"),
        (480, "8 godzin"),
    ]
    @AppStorage(AppSettingsKeys.environment) private var environmentRaw = KSeFEnvironment.test.rawValue
    @AppStorage(AppSettingsKeys.rangeMode) private var rangeModeRaw = DateRangeMode.last3Months.rawValue
    @AppStorage(AppSettingsKeys.rangeFrom) private var rangeFromInterval = Date.now.timeIntervalSince1970 - 30 * 86_400
    @AppStorage(AppSettingsKeys.rangeTo) private var rangeToInterval = Date.now.timeIntervalSince1970
    @AppStorage(AppSettingsKeys.numberPattern) private var numberPattern = InvoiceNumberGenerator.defaultPattern
    @AppStorage(AppSettingsKeys.numberPatternZAL) private var numberPatternZAL = ""
    @AppStorage(AppSettingsKeys.numberPatternROZ) private var numberPatternROZ = ""
    @AppStorage(AppSettingsKeys.numberPatternUPR) private var numberPatternUPR = ""
    @AppStorage(AppSettingsKeys.numberPatternKOR) private var numberPatternKOR = ""
    @AppStorage(AppSettingsKeys.numberPatternRR) private var numberPatternRR = ""
    @AppStorage(AppSettingsKeys.prepaidForms) private var prepaidFormsRaw = PaymentFormPolicy.encode(PaymentFormPolicy.defaultPrepaidForms)
    @AppStorage(AppSettingsKeys.dueSoonDays) private var dueSoonDays = 7

    public init() {}

    // MARK: Zakładki i wyszukiwarka ustawień

    /// Zakładki okna Ustawień (kwadratowe przyciski z ikonami).
    enum SettingsTab: String, CaseIterable, Identifiable {
        case company, ksef, sync, invoices, dashboard, backup

        var id: String { rawValue }
        var title: String {
            switch self {
            case .company: return "Firma"
            case .ksef: return "KSeF"
            case .sync: return "Synchronizacja"
            case .invoices: return "Faktury"
            case .dashboard: return "Kokpit"
            case .backup: return "Kopia zapasowa"
            }
        }
        var icon: String {
            switch self {
            case .company: return "building.2"
            case .ksef: return "key"
            case .sync: return "arrow.triangle.2.circlepath"
            case .invoices: return "doc.text"
            case .dashboard: return "gauge.with.dots.needle.50percent"
            case .backup: return "externaldrive"
            }
        }
    }

    @State private var tab: SettingsTab = .company
    @State private var searchText = ""
    /// Ustawienie wskazane z wyszukiwarki — jego wiersz jest chwilowo
    /// podświetlony po przejściu do zakładki.
    @State private var highlightedSetting: String?

    /// Rejestr ustawień dla wyszukiwarki: etykieta → zakładka.
    private static let searchIndex: [(label: String, tab: SettingsTab)] = [
        ("Nazwa firmy", .company), ("NIP", .company), ("Adres firmy", .company),
        ("Rachunek bankowy (domyślny)", .company),
        ("Forma opodatkowania (KPiR / ryczałt)", .company),
        ("Domyślna stawka ryczałtu", .company),
        ("Skala podatkowa / podatek liniowy", .company),
        ("Cykl rozliczenia PIT", .company),
        ("Czynny podatnik VAT", .company),
        ("Cykl rozliczenia VAT", .company),
        ("Branding PDF", .company), ("Logo na PDF", .company),
        ("Kolory PDF", .company), ("Stopka PDF", .company),
        ("Kod QR płatności (2D ZBP)", .company),
        ("Nazwa odbiorcy na kodzie QR", .company),
        ("Token autoryzacyjny KSeF", .ksef), ("Środowisko KSeF", .ksef),
        ("Certyfikaty KSeF (typ 1 / typ 2)", .ksef),
        ("Import certyfikatu z pliku", .ksef),
        ("Zakres importu z KSeF", .sync), ("Pobierz faktury przy starcie", .sync),
        ("Pobieraj faktury automatycznie", .sync), ("Interwał pobierania", .sync),
        ("Powiadomienia o nowych fakturach zakupowych", .sync),
        ("Powiadomienia o terminach płatności i dosłań", .sync),
        ("Ikona w pasku menu", .sync),
        ("Numeracja faktur (wzorzec numeru)", .invoices),
        ("Formy płatności opłacone z góry", .invoices),
        ("Płatności w najbliższych dniach (widget)", .dashboard),
        ("Eksport danych (kopia ręczna)", .backup), ("Import danych", .backup),
        ("Automatyczna kopia przy starcie", .backup),
        ("Rotacja kopii (liczba / dni)", .backup),
        ("Katalog kopii zapasowych", .backup),
    ]

    private var searchResults: [(label: String, tab: SettingsTab)] {
        Self.searchIndex.filter {
            $0.label.localizedCaseInsensitiveContains(searchText)
                || $0.tab.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Walidacja NIP na żywo — pomaga wychwycić literówki.
    private var isNIPValid: Bool {
        nip.isEmpty || InvoiceValidator.isValidNIP(nip)
    }

    private var rangeMode: DateRangeMode {
        DateRangeMode(rawValue: rangeModeRaw) ?? .last3Months
    }

    /// Wiązania dat własnego zakresu (przechowywanych jako timeInterval).
    private var customFromBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: rangeFromInterval) },
            set: { rangeFromInterval = $0.timeIntervalSince1970 }
        )
    }

    private var customToBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: rangeToInterval) },
            set: { rangeToInterval = $0.timeIntervalSince1970 }
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Pasek zakładek + wyszukiwarka ustawień.
            HStack(alignment: .center, spacing: 4) {
                ForEach(SettingsTab.allCases) { item in
                    Button {
                        tab = item
                        searchText = ""
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.icon)
                                .font(.system(size: 17))
                            Text(item.title)
                                .font(.caption2)
                        }
                        .frame(width: 86, height: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tab == item && searchText.isEmpty ? Color.accentColor : .secondary)
                    .background(
                        tab == item && searchText.isEmpty
                            ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                Spacer()
                // Wyszukiwarka ustawień — wyniki przenoszą do właściwej zakładki.
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Szukaj ustawienia", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .frame(width: 180)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if searchText.isEmpty {
                Form {
                    switch tab {
                    case .company: companySections
                    case .ksef: ksefSections
                    case .sync: syncSections
                    case .invoices: invoiceSections
                    case .dashboard: dashboardSections
                    case .backup: backupSections
                    }
                }
                .formStyle(.grouped)
            } else {
                List {
                    if searchResults.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ForEach(searchResults, id: \.label) { result in
                            Button {
                                tab = result.tab
                                searchText = ""
                                // Podświetlenie wskazanego wiersza, gasnące po chwili.
                                highlightedSetting = result.label
                                Task {
                                    try? await Task.sleep(for: .seconds(3))
                                    if highlightedSetting == result.label {
                                        highlightedSetting = nil
                                    }
                                }
                            } label: {
                                HStack {
                                    Label(result.label, systemImage: result.tab.icon)
                                    Spacer()
                                    Text(result.tab.title)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Ustawienia")
        .fileImporter(
            isPresented: $isChoosingBrandingLogo,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: importBrandingLogo
        )
        .alert("Nie udało się wczytać logo", isPresented: Binding(
            get: { brandingLogoError != nil },
            set: { if !$0 { brandingLogoError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(brandingLogoError ?? "")
        }
    }

    // MARK: Sekcje zakładek

    @ViewBuilder
    private var companySections: some View {
            Section("Twoja firma") {
                TextField("Nazwa firmy", text: $sellerName, prompt: Text("np. ACME Sp. z o.o."))
                .listRowBackground(highlight("Nazwa firmy"))
                TextField("NIP", text: $nip, prompt: Text("10 cyfr, np. 5260250274"))
                .listRowBackground(highlight("NIP"))
                if !isNIPValid {
                    Label("NIP wygląda na nieprawidłowy (błędna suma kontrolna).", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                TextField("Adres", text: $sellerAddress, prompt: Text("ul. Przykładowa 1, 00-001 Warszawa"))
                .listRowBackground(highlight("Adres firmy"))
                TextField("Rachunek bankowy", text: $bankAccount, prompt: Text("26 cyfr (NRB) — na wystawianych fakturach"))
                .listRowBackground(highlight("Rachunek bankowy (domyślny)"))
            }

            Section {
                Picker("Forma rozliczenia", selection: $taxFormRaw) {
                    ForEach(TaxForm.allCases) { form in
                        Text(form.displayName).tag(form.rawValue)
                    }
                }
                .listRowBackground(highlight("Forma opodatkowania (KPiR / ryczałt)"))
                if TaxForm.resolve(taxFormRaw) == .ryczalt {
                    Picker("Domyślna stawka ryczałtu", selection: $ryczaltDefaultRateRaw) {
                        ForEach(RyczaltRate.allCases) { rate in
                            Text(rate.displayName).tag(rate.rawValue)
                        }
                    }
                    .listRowBackground(highlight("Domyślna stawka ryczałtu"))
                } else {
                    Picker("Sposób opodatkowania", selection: $kpirIncomeTaxMethodRaw) {
                        ForEach(KPiRIncomeTaxMethod.allCases) { method in
                            Text(method.displayName).tag(method.rawValue)
                        }
                    }
                    .listRowBackground(highlight("Skala podatkowa / podatek liniowy"))
                }
                Picker("Zaliczka PIT / ryczałt", selection: $incomeTaxSettlementCycleRaw) {
                    ForEach(TaxSettlementCycle.allCases) { cycle in
                        Text(cycle.displayName).tag(cycle.rawValue)
                    }
                }
                .listRowBackground(highlight("Cykl rozliczenia PIT"))
            } header: {
                Text("Podatek dochodowy")
            } footer: {
                Text("Wybór decyduje, którą ewidencję prowadzi aplikacja: KPiR albo ewidencję przychodów (ryczałt). Metoda i cykl rozliczenia PIT/ryczałtu sterują terminarzem oraz roboczą prognozą na Kokpicie. Prognoza nie zastępuje rozliczenia księgowego i nie uwzględnia m.in. składek, ulg ani wcześniejszych wpłat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Czynny podatnik VAT", isOn: $isActiveVATPayer)
                    .listRowBackground(highlight("Czynny podatnik VAT"))
                if isActiveVATPayer {
                    Picker("Rozliczenie VAT", selection: $vatSettlementCycleRaw) {
                        ForEach(TaxSettlementCycle.allCases) { cycle in
                            Text(cycle.displayName).tag(cycle.rawValue)
                        }
                    }
                    .listRowBackground(highlight("Cykl rozliczenia VAT"))
                }
            } header: {
                Text("VAT")
            } footer: {
                Text("JPK_V7 jest zawsze miesięczny, także przy kwartalnym rozliczeniu VAT. Podatnik zwolniony z VAT wyłącza terminy JPK/VAT oraz prognozę VAT na Kokpicie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Używaj brandingu na własnych fakturach", isOn: $pdfBrandingEnabled)
                    .listRowBackground(highlight("Branding PDF"))

                HStack(alignment: .center, spacing: 14) {
                    brandingLogoPreview
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pdfBrandingLogo.isEmpty ? "Brak logo" : "Logo firmy")
                            .font(.callout.weight(.medium))
                        HStack {
                            Button(pdfBrandingLogo.isEmpty ? "Wybierz logo…" : "Zmień logo…") {
                                isChoosingBrandingLogo = true
                            }
                            if !pdfBrandingLogo.isEmpty {
                                Button("Usuń", role: .destructive) {
                                    pdfBrandingLogo = ""
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .disabled(!pdfBrandingEnabled)
                .listRowBackground(highlight("Logo na PDF"))

                ColorPicker("Kolor główny", selection: colorBinding(
                    hex: $pdfBrandingPrimaryColor,
                    fallback: InvoicePDFBranding.defaultPrimaryHex
                ), supportsOpacity: false)
                .disabled(!pdfBrandingEnabled)
                .listRowBackground(highlight("Kolory PDF"))
                ColorPicker("Kolor akcentu", selection: colorBinding(
                    hex: $pdfBrandingAccentColor,
                    fallback: InvoicePDFBranding.defaultAccentHex
                ), supportsOpacity: false)
                .disabled(!pdfBrandingEnabled)
                .listRowBackground(highlight("Kolory PDF"))

                TextField(
                    "Własna stopka",
                    text: $pdfBrandingFooter,
                    prompt: Text("np. Dziękujemy za współpracę • www.twojafirma.pl"),
                    axis: .vertical
                )
                .lineLimit(2...4)
                .disabled(!pdfBrandingEnabled)
                .listRowBackground(highlight("Stopka PDF"))
            } header: {
                Text("Branding wydruków PDF")
            } footer: {
                Text("Logo, kolory i stopka pojawią się tylko na fakturach Twojej firmy. Pobrane faktury kosztowe zachowują wygląd wystawcy. Logo zostanie pomniejszone i zapisane w kopii zapasowej razem z pozostałymi ustawieniami.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Drukuj kod QR płatności na fakturach", isOn: $pdfPaymentQR)
                    .listRowBackground(highlight("Kod QR płatności (2D ZBP)"))
                TextField(
                    "Nazwa odbiorcy na kodzie QR",
                    text: $paymentQRRecipientName,
                    prompt: Text("Pełna nazwa firmy (skracana do 20 znaków)")
                )
                .disabled(!pdfPaymentQR)
                .listRowBackground(highlight("Nazwa odbiorcy na kodzie QR"))
                if paymentQRRecipientName.count > PaymentQRCode.nameMaxLength {
                    Label(
                        "Nazwa dłuższa niż \(PaymentQRCode.nameMaxLength) znaków zostanie skrócona na kodzie.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("Kod QR płatności")
            } footer: {
                Text("Kod QR w standardzie 2D Związku Banków Polskich pozwala odbiorcy zapłacić przez zeskanowanie go aplikacją banku (rachunek, kwota i tytuł uzupełniają się automatycznie). Pojawia się wyłącznie na Twoich fakturach sprzedaży w PLN z podanym rachunkiem i niezerowym saldem — kwota to kwota pozostała do zapłaty. Pole nazwy odbiorcy w tym standardzie ma tylko \(PaymentQRCode.nameMaxLength) znaków; jeśli pełna nazwa firmy się nie mieści, podaj tu czytelny skrót (np. „IT-KRAK”). Puste = pełna nazwa skracana automatycznie na granicy słowa. Nie ma wpływu na kod weryfikacyjny KSeF.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private var ksefSections: some View {
            Section {
                SecureField("Token autoryzacyjny", text: $tokenStore.token, prompt: Text("Token wygenerowany w KSeF"))
                .listRowBackground(highlight("Token autoryzacyjny KSeF"))
                Picker("Środowisko", selection: $environmentRaw) {
                    ForEach(KSeFEnvironment.allCases) { environment in
                        Text(environment.displayName).tag(environment.rawValue)
                    }
                }
                // Każde środowisko ma własny token i certyfikaty w pęku
                // kluczy — zmiana środowiska przełącza je, niczego nie
                // nadpisując.
                .onChange(of: environmentRaw) { _, newValue in
                    tokenStore.switchEnvironment(newValue)
                    KSeFCertificateStore.shared.switchEnvironment(newValue)
                }
            } header: {
                Text("KSeF")
            } footer: {
                Text("Token autoryzacyjny wygenerujesz w Aplikacji Podatnika KSeF 2.0 (środowisko testowe: ksef-test.mf.gov.pl) w sekcji Tokeny. Token musi mieć uprawnienia do przeglądania i wystawiania faktur. Każde środowisko ma osobny token (pęk kluczy) — przełączenie środowiska nie kasuje pozostałych. Do testów użyj środowiska testowego — dane nie trafiają do systemu produkcyjnego. Preferowaną metodą logowania jest certyfikat KSeF (sekcja poniżej); token pozostaje jako zapasowa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            CertificateSettingsSection()
    }

    @ViewBuilder
    private var invoiceSections: some View {
            Section {
                TextField("Wzorzec numeru", text: $numberPattern, prompt: Text(InvoiceNumberGenerator.defaultPattern))
                .listRowBackground(highlight("Numeracja faktur (wzorzec numeru)"))
                LabeledContent("Przykładowy numer") {
                    Text(InvoiceNumberGenerator.preview(pattern: numberPattern))
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                if !numberPattern.trimmingCharacters(in: .whitespaces).isEmpty,
                   !InvoiceNumberGenerator.hasSequenceToken(numberPattern) {
                    Label("Wzorzec nie zawiera licznika {N…} — zostanie automatycznie dopisany na końcu.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                patternRow("Zaliczkowe (ZAL)", text: $numberPatternZAL, example: "ZAL/{NN}/{MM}/{RRRR}")
                patternRow("Rozliczeniowe (ROZ)", text: $numberPatternROZ, example: "ROZ/{NN}/{MM}/{RRRR}")
                patternRow("Uproszczone (UPR)", text: $numberPatternUPR, example: "UPR/{NN}/{MM}/{RRRR}")
                patternRow("Korekty (KOR…)", text: $numberPatternKOR, example: "KOR/{NN}/{MM}/{RRRR}")
                patternRow("Rolnik ryczałtowy (VAT RR)", text: $numberPatternRR, example: "RR/{NN}/{MM}/{RRRR}")
            } header: {
                Text("Numeracja faktur")
            } footer: {
                Text("Pierwszy wzorzec dotyczy faktur VAT. Każdy rodzaj dokumentu może mieć własny wzorzec i własną serię numeracji — puste pole oznacza użycie wzorca faktur VAT. Dostępne symbole: {RRRR} rok, {RR} rok dwucyfrowy, {MM} miesiąc, {DD} dzień, {N}/{NN}/{NNN}… kolejny numer z zerami wiodącymi. Licznik rośnie w obrębie numerów pasujących do wzorca — np. z {MM} resetuje się co miesiąc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            paymentFormsSection
    }

    @ViewBuilder
    private var syncSections: some View {
            Section {
                Picker("Zakres", selection: $rangeModeRaw) {
                    ForEach(DateRangeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                if rangeMode == .custom {
                    DatePicker("Od", selection: customFromBinding, displayedComponents: .date)
                    DatePicker("Do", selection: customToBinding, displayedComponents: .date)
                }
            } header: {
                Text("Zakres importu z KSeF")
            } footer: {
                Text("Zakres ogranicza, które faktury są pobierane przyciskiem „Pobierz z KSeF” — dzięki temu nie ściągasz za każdym razem wszystkiego. Uwaga: API KSeF pozwala na maksymalnie 3 miesiące w jednym zapytaniu. Wyświetlanie na listach i w Kokpicie ma osobne filtry w każdym widoku.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Pobierz faktury z KSeF przy starcie", isOn: $syncOnLaunch)
                .listRowBackground(highlight("Pobierz faktury przy starcie"))
                Toggle("Pobieraj faktury automatycznie", isOn: $autoSync)
                .listRowBackground(highlight("Pobieraj faktury automatycznie"))
                Picker("Interwał pobierania", selection: $autoSyncIntervalMinutes) {
                    ForEach(Self.autoSyncIntervals, id: \.minutes) { interval in
                        Text(interval.label).tag(interval.minutes)
                    }
                }
                .disabled(!autoSync)
                Toggle("Powiadamiaj o nowych fakturach zakupowych", isOn: $notifyNewPurchases)
                .listRowBackground(highlight("Powiadomienia o nowych fakturach zakupowych"))
                Toggle("Powiadamiaj o terminach (płatności i dosłania offline)", isOn: $notifyDeadlines)
                .listRowBackground(highlight("Powiadomienia o terminach płatności i dosłań"))
                .help("Powiadomienie, gdy termin płatności wypada dziś lub jutro oraz gdy mija termin dosłania dokumentu offline do KSeF — raz dziennie na fakturę.")
                Toggle("Ikona w pasku menu", isOn: $menuBarExtraEnabled)
                .listRowBackground(highlight("Ikona w pasku menu"))
                .help("Ikona przy zegarze systemowym: status synchronizacji, kolejka dosłań offline i szybkie „Pobierz z KSeF” — także przy zamkniętym oknie aplikacji.")
            } header: {
                Text("Synchronizacja automatyczna")
            } footer: {
                Text("Pobieranie obejmuje faktury sprzedażowe i zakupowe według zakresu importu powyżej. Automatyczna synchronizacja działa WYŁĄCZNIE na środowisku produkcyjnym (na testowym/demo zaśmiecałaby bazę) i tylko, gdy aplikacja jest uruchomiona; błędy (np. brak sieci) są pomijane po cichu — ręczna synchronizacja z listy pokazuje je wprost i działa na każdym środowisku.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private var dashboardSections: some View {
            Section {
                Stepper(value: $dueSoonDays, in: 1...90) {
                    LabeledContent(
                        "Płatności w najbliższych dniach",
                        value: dueSoonDays == 1 ? "1 dzień" : "\(dueSoonDays) dni"
                    )
                }
            } header: {
                Text("Kokpit")
            } footer: {
                Text("Horyzont widgetu „Płatności w najbliższych dniach” — ile dni naprzód pokazywać nieopłacone faktury z terminem płatności.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private var paymentFormsSection: some View {
            Section {
                ForEach(PaymentForm.allCases) { form in
                    Toggle(form.displayName, isOn: prepaidBinding(for: form))
                }
            } header: {
                Text("Formy płatności opłacone z góry")
            } footer: {
                Text("Faktury z zaznaczoną formą płatności są od razu oznaczane jako opłacone (przy imporcie z KSeF i przy wystawianiu). Formy odznaczone — np. przelew — traktowane są jako odroczone i trafiają do „Do opłacenia”. Ręczne oznaczenia nigdy nie są cofane.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private var backupSections: some View {
            Section {
                HStack(spacing: 12) {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Eksportuj dane…", systemImage: "square.and.arrow.up.on.square")
                    }
                    Button {
                        importBackup()
                    } label: {
                        Label("Importuj dane…", systemImage: "square.and.arrow.down.on.square")
                    }
                }
                if let backupStatus {
                    Label(backupStatus, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Kopia zapasowa i przenoszenie danych")
            } footer: {
                Text("Eksport zapisuje wszystkie faktury (wraz z pozycjami i XML), słowniki oraz ustawienia do jednego pliku JSON — przy migracji na inny komputer wystarczy go zaimportować, bez ponownego pobierania z KSeF. Import pomija faktury, które już są w bazie, a ustawienia uzupełnia tylko tam, gdzie są puste. Token KSeF nie jest zapisywany w kopii (żyje w pęku kluczy) — na nowym komputerze wpisz go ręcznie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Automatyczna kopia przy starcie", isOn: $autoBackup)
                .listRowBackground(highlight("Automatyczna kopia przy starcie"))
                Picker("Rotacja starych kopii", selection: $backupRotationModeRaw) {
                    ForEach(AutoBackupService.RotationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .disabled(!autoBackup)
                if backupRotationModeRaw == AutoBackupService.RotationMode.keepDays.rawValue {
                    Stepper(value: $backupKeepDays, in: 1...365) {
                        LabeledContent(
                            "Przechowuj kopie z ostatnich",
                            value: backupKeepDays == 1 ? "1 dnia" : "\(backupKeepDays) dni"
                        )
                    }
                    .disabled(!autoBackup)
                } else {
                    Stepper(value: $backupKeepCount, in: 1...100) {
                        LabeledContent(
                            "Liczba przechowywanych kopii",
                            value: "\(backupKeepCount)"
                        )
                    }
                    .disabled(!autoBackup)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([AutoBackupService.defaultDirectory])
                } label: {
                    Label("Pokaż katalog kopii w Finderze", systemImage: "folder")
                }
            } header: {
                Text("Automatyczna kopia zapasowa")
            } footer: {
                Text("Raz dziennie, przy pierwszym uruchomieniu aplikacji, pełna kopia (faktury + słowniki + ustawienia) zapisuje się do ~/Library/Application Support/Ksefiarz/Backups/. Rotacja usuwa wyłącznie pliki automatyczne — ręcznych eksportów nie dotyka.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }

    /// Wiersz wzorca numeracji dla rodzaju dokumentu (z podglądem).
    private func patternRow(_ label: String, text: Binding<String>, example: String) -> some View {
        HStack {
            TextField(label, text: text, prompt: Text("puste = wzorzec VAT"))
            if !text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(InvoiceNumberGenerator.preview(pattern: text.wrappedValue))
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    /// Tło wiersza ustawienia wskazanego z wyszukiwarki.
    private func highlight(_ key: String) -> some View {
        Group {
            if highlightedSetting == key {
                Color.accentColor.opacity(0.18)
            } else {
                Color.clear
            }
        }
    }

    /// Miniatura logo w ustawieniach; puste miejsce ma celowy, dokumentowy
    /// charakter i pokazuje użytkownikowi docelowe proporcje znaku na PDF.
    @ViewBuilder
    private var brandingLogoPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.45))
            if let data = Data(base64Encoded: pdfBrandingLogo),
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Image(systemName: "building.2.crop.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 112, height: 58)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }

    /// Wiązanie ColorPicker ↔ zapis #RRGGBB w AppStorage.
    private func colorBinding(hex: Binding<String>, fallback: String) -> Binding<Color> {
        Binding(
            get: { InvoicePDFBranding.color(hex: hex.wrappedValue) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else {
                    hex.wrappedValue = fallback
                    return
                }
                hex.wrappedValue = String(
                    format: "#%02X%02X%02X",
                    Int((rgb.redComponent * 255).rounded()),
                    Int((rgb.greenComponent * 255).rounded()),
                    Int((rgb.blueComponent * 255).rounded())
                )
            }
        )
    }

    /// Importuje obraz z panelu systemowego i zapisuje jego lekką wersję PNG.
    private func importBrandingLogo(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let source = try Data(contentsOf: url)
            guard let normalized = PDFBrandingLogoProcessor.normalizedPNG(from: source) else {
                brandingLogoError = source.count > PDFBrandingLogoProcessor.maximumSourceBytes
                    ? "Plik jest większy niż 10 MB. Wybierz mniejszy obraz."
                    : "Wybrany plik nie jest obsługiwanym obrazem. Użyj PNG, JPEG, HEIC albo TIFF."
                return
            }
            pdfBrandingLogo = normalized.base64EncodedString()
        } catch {
            brandingLogoError = error.localizedDescription
        }
    }

    /// Wiązanie przełącznika „opłacona z góry” dla danej formy płatności.
    private func prepaidBinding(for form: PaymentForm) -> Binding<Bool> {
        Binding(
            get: { PaymentFormPolicy.decode(prepaidFormsRaw).contains(form.rawValue) },
            set: { isOn in
                var forms = PaymentFormPolicy.decode(prepaidFormsRaw)
                if isOn { forms.insert(form.rawValue) } else { forms.remove(form.rawValue) }
                prepaidFormsRaw = PaymentFormPolicy.encode(forms)
            }
        )
    }

    // MARK: Kopia zapasowa

    /// Eksportuje wszystkie faktury, ustawienia i słowniki do pliku JSON.
    private func exportBackup() {
        do {
            let invoiceCount = try modelContext.fetchCount(FetchDescriptor<Invoice>())
            let data = try BackupService.makeCurrentBackup(context: modelContext)
            let date = FA2Format.dateFormatter.string(from: .now)
            let saved = FileExportService.exportData(
                data,
                suggestedName: "ksefiarz-kopia-\(date).json",
                contentType: .json
            )
            // Komunikat sukcesu tylko po faktycznym zapisie — anulowanie
            // panelu nie jest eksportem.
            backupStatus = saved ? "Wyeksportowano \(invoiceCount) faktur." : ""
        } catch {
            backupStatus = "Błąd eksportu: \(error.localizedDescription)"
        }
    }

    /// Importuje dane z pliku kopii zapasowej (z pominięciem duplikatów).
    private func importBackup() {
        guard let data = FileExportService.importData(allowedTypes: [.json]) else { return }
        do {
            let backup = try BackupService.decode(data)
            let existing = try modelContext.fetch(FetchDescriptor<Invoice>())
            let toImport = BackupService.invoicesToImport(from: backup, existing: existing)

            for entry in toImport {
                let invoice = BackupService.makeInvoice(from: entry)
                modelContext.insert(invoice)
                invoice.lines = BackupService.makeLines(for: entry)
                invoice.payments = BackupService.makePayments(for: entry)
            }

            // Ustawienia uzupełniamy wyłącznie tam, gdzie obecne są puste —
            // import nie nadpisuje istniejącej konfiguracji.
            let defaults = UserDefaults.standard
            for (key, value) in backup.settings where BackupService.backedUpSettingsKeys.contains(key) {
                let current = defaults.string(forKey: key) ?? ""
                if current.isEmpty {
                    defaults.set(value, forKey: key)
                }
            }

            // Starsze kopie zapasowe zawierały token KSeF w ustawieniach —
            // taki token trafia do pęku kluczy (nigdy do UserDefaults)
            // i tylko wtedy, gdy żaden token nie jest jeszcze skonfigurowany.
            if let legacyToken = backup.settings[AppSettingsKeys.token],
               !legacyToken.isEmpty, tokenStore.token.isEmpty {
                tokenStore.token = legacyToken
            }

            // Słowniki (kopie od wersji 2) — duplikaty pomijane.
            let newContractors = BackupService.contractorsToImport(
                from: backup,
                existing: try modelContext.fetch(FetchDescriptor<Contractor>())
            )
            newContractors.forEach { modelContext.insert(BackupService.makeContractor(from: $0)) }
            let newProducts = BackupService.productsToImport(
                from: backup,
                existing: try modelContext.fetch(FetchDescriptor<Product>())
            )
            newProducts.forEach { modelContext.insert(BackupService.makeProduct(from: $0)) }
            let newAccounts = BackupService.bankAccountsToImport(
                from: backup,
                existing: try modelContext.fetch(FetchDescriptor<BankAccount>())
            )
            newAccounts.forEach { modelContext.insert(BackupService.makeBankAccount(from: $0)) }
            let newTemplates = BackupService.templatesToImport(
                from: backup, existing: try modelContext.fetch(FetchDescriptor<InvoiceTemplate>())
            )
            newTemplates.compactMap(BackupService.makeTemplate(from:)).forEach(modelContext.insert)
            let newSchedules = BackupService.schedulesToImport(
                from: backup, existing: try modelContext.fetch(FetchDescriptor<RecurringInvoice>())
            )
            newSchedules.compactMap(BackupService.makeSchedule(from:)).forEach(modelContext.insert)
            try? modelContext.save()

            let skipped = backup.invoices.count - toImport.count
            let dictionariesCount = newContractors.count + newProducts.count + newAccounts.count
            let automationCount = newTemplates.count + newSchedules.count
            backupStatus = "Zaimportowano \(toImport.count) faktur"
                + (skipped > 0 ? ", pominięto \(skipped) duplikatów" : "")
                + (dictionariesCount > 0 ? ", \(dictionariesCount) pozycji słowników." : ".")
                + (automationCount > 0 ? " Przywrócono \(automationCount) szablonów i harmonogramów." : "")
        } catch {
            backupStatus = "Błąd importu: nieprawidłowy plik kopii zapasowej."
        }
    }
}
