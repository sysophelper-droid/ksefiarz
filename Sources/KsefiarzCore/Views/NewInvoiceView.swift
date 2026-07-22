import SwiftUI
import SwiftData

/// Formularz wystawiania nowej faktury sprzedażowej, VAT RR (zakupowej)
/// lub korygującej
/// z walidacją pól, pozycjami (FaWiersz), adresami stron i danymi płatności.
/// Pozwala wysłać fakturę do KSeF lub zapisać ją tylko lokalnie.
public struct NewInvoiceView: View {

    /// Faktura korygowana — gdy ustawiona, formularz wystawia korektę (KOR),
    /// a pozycje wyrażają różnicę względem faktury pierwotnej.
    private let correctingInvoice: Invoice?

    /// Faktura edytowana — dozwolone wyłącznie dla faktur zapisanych
    /// tylko lokalnie (niewysłanych do KSeF). Zapis aktualizuje istniejący
    /// rekord zamiast tworzyć nowy.
    private let editingInvoice: Invoice?
    private let initialDraft: InvoiceDraft?
    private let sourceTitle: String?
    private let onCompleted: (() -> Void)?
    /// Wywoływane z utworzoną/zaktualizowaną fakturą po zapisie (lokalnym,
    /// wysyłce online lub offline). Używane m.in. przez konwersję proformy —
    /// pozwala oznaczyć proformę jako rozliczoną numerem powstałej faktury.
    private let onCreatedInvoice: ((Invoice) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Dane firmy użytkownika (sprzedawca) — współdzielone z Ustawieniami.
    @AppStorage(AppSettingsKeys.sellerName) private var sellerName = ""
    @AppStorage(AppSettingsKeys.sellerAddress) private var sellerAddress = ""
    @AppStorage(AppSettingsKeys.nip) private var sellerNIP = ""
    @AppStorage(AppSettingsKeys.bankAccount) private var defaultBankAccount = ""
    @ObservedObject private var tokenStore = TokenStore.shared
    @ObservedObject private var availabilityMonitor = KSeFAvailabilityMonitor.shared
    private var ksefToken: String { tokenStore.token }
    @AppStorage(AppSettingsKeys.environment) private var environmentRaw = KSeFEnvironment.test.rawValue
    @AppStorage(AppSettingsKeys.numberPattern) private var numberPattern = InvoiceNumberGenerator.defaultPattern
    @AppStorage(AppSettingsKeys.prepaidForms) private var prepaidFormsRaw = PaymentFormPolicy.encode(PaymentFormPolicy.defaultPrepaidForms)

    // Pola formularza.
    @State private var invoiceNumber = ""
    @State private var correctionReason = ""
    @State private var issueDate = Date.now
    @State private var hasDueDate = true
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var buyerName = ""
    @State private var buyerNIP = ""
    @State private var buyerAddress = ""
    @State private var paymentForm: PaymentForm = .transfer
    @State private var paymentBankAccount = ""
    @State private var lines: [InvoiceLineDraft] = [InvoiceLineDraft()]
    @State private var notes = ""
    @State private var invoiceType = "VAT"
    @State private var currency = "PLN"
    @State private var exchangeRate = 0.0
    @State private var splitPayment = false
    /// Samofakturowanie (P_17 = 1) — wystawiamy dokument jako nabywca
    /// w imieniu dostawcy; role stron w szkicu są zamieniane jak dla RR,
    /// a zapisany dokument trafia do zakupów.
    @State private var isSelfInvoicing = false
    @State private var hasSaleDate = false
    @State private var saleDate = Date.now
    /// Numery KSeF faktur zaliczkowych (ROZ) — jeden na linię.
    @State private var advanceRefsText = ""

    @State private var marginProcedure = ""
    /// Bloki załącznika FA(3) (element Zalacznik).
    @State private var attachments: [FA3AttachmentBlock] = []
    @State private var isFetchingRate = false
    @State private var nbpRateInfo: String?
    /// Ostatni numer zaproponowany automatycznie — przy zmianie rodzaju
    /// dokumentu numer jest przegenerowywany tylko, jeśli użytkownik
    /// nie wpisał własnego.
    @State private var lastGeneratedNumber = ""

    @AppStorage(AppSettingsKeys.numberPatternZAL) private var numberPatternZAL = ""
    @AppStorage(AppSettingsKeys.numberPatternROZ) private var numberPatternROZ = ""
    @AppStorage(AppSettingsKeys.numberPatternUPR) private var numberPatternUPR = ""
    @AppStorage(AppSettingsKeys.numberPatternKOR) private var numberPatternKOR = ""
    @AppStorage(AppSettingsKeys.numberPatternRR) private var numberPatternRR = ""
    @AppStorage(AppSettingsKeys.numberPatternSF) private var numberPatternSF = ""

    /// Rodzaje dokumentów dostępne przy wystawianiu (korekta ma własny przepływ).
    private static let invoiceTypes: [(raw: String, label: String)] = [
        ("VAT", "Faktura VAT"),
        ("ZAL", "Faktura zaliczkowa (ZAL)"),
        ("ROZ", "Faktura rozliczeniowa (ROZ)"),
        ("UPR", "Faktura uproszczona (UPR)"),
        ("VAT_RR", "Faktura VAT RR (rolnik ryczałtowy)"),
    ]

    /// Procedury marży (Adnotacje/PMarzy w FA(3)).
    private static let marginProcedures: [(raw: String, label: String)] = [
        ("", "(brak)"),
        ("2", "Marża — biura podróży"),
        ("3_1", "Marża — towary używane"),
        ("3_2", "Marża — dzieła sztuki"),
        ("3_3", "Marża — antyki"),
    ]

    /// Waluty do wyboru (KodWaluty wg ISO 4217).
    private static let currencies = ["PLN", "EUR", "USD", "GBP", "CHF", "CZK", "SEK", "NOK", "DKK"]

    // Słowniki — dane tylko podstawiane do pól, wszystko pozostaje edytowalne.
    @Query(sort: \Contractor.name) private var dictionaryContractors: [Contractor]
    @Query(sort: \Product.name) private var dictionaryProducts: [Product]
    @Query(sort: \BankAccount.label) private var dictionaryAccounts: [BankAccount]

    // Stan walidacji i wysyłki.
    @State private var validationErrors: [InvoiceValidationError] = []
    @State private var isSending = false
    @State private var errorMessage: String?
    /// Tryb wystawienia dokumentu: online albo jeden z trybów offline
    /// (offline24 — wybór podatnika; niedostępność/awaria — komunikat MF).
    enum IssueMode: String, CaseIterable, Identifiable {
        case online
        case offline24
        case unavailability
        case failure

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .online: return "Online (wyślij od razu)"
            case .offline24: return "Offline24 (wybór podatnika)"
            case .unavailability: return "Offline — niedostępność KSeF"
            case .failure: return "Tryb awaryjny — awaria KSeF"
            }
        }

        /// Powód offline zapisywany na fakturze (nil dla trybu online).
        var offlineReason: Invoice.OfflineReason? {
            switch self {
            case .online: return nil
            case .offline24: return .offline24
            case .unavailability: return .unavailability
            case .failure: return .failure
            }
        }
    }

    /// Wybrany tryb wystawienia — tryby offline tworzą dokument lokalnie
    /// z kodami QR i kolejką dosłania (termin zależny od trybu).
    @State private var issueMode: IssueMode = .online
    /// Komunikat po automatycznym przejściu w tryb offline (brak sieci).
    @State private var offlineInfoMessage: String?
    @State private var offlineInfoTitle = "Faktura wystawiona offline"
    @State private var showingTemplateName = false
    @State private var templateName = ""

    /// Używamy wyłącznie odczytu dla aktualnie wybranego środowiska — wynik
    /// sprzed przełączenia TEST/PRD nie może podpowiedzieć błędnego trybu.
    private var availabilitySnapshot: KSeFAvailabilitySnapshot? {
        guard let environment = KSeFEnvironment(rawValue: environmentRaw),
              availabilityMonitor.lastError == nil,
              let snapshot = availabilityMonitor.snapshot,
              snapshot.environment == environment,
              Date.now.timeIntervalSince(snapshot.fetchedAt) < 5 * 60
        else { return nil }
        return snapshot
    }

    private var availabilitySuggestion: KSeFOfflineSuggestion? {
        availabilitySnapshot.flatMap(KSeFAvailabilityPolicy.currentSuggestion)
    }

    private var isTotalKSeFFailure: Bool {
        availabilitySnapshot.map(KSeFAvailabilityPolicy.isTotalFailure) ?? false
    }

    private var upcomingMaintenance: KSeFAvailabilityMessage? {
        availabilitySnapshot.flatMap { KSeFAvailabilityPolicy.upcomingMaintenance(from: $0) }
    }

    /// Jawny komunikat dla każdego przypadku, w którym automat nie może
    /// bezpiecznie zinterpretować statusu (błąd, stary odczyt lub nowy kod MF).
    private var availabilityWarning: String? {
        guard let environment = KSeFEnvironment(rawValue: environmentRaw),
              environment.availabilityBaseURL != nil
        else { return nil }
        // Cisza tylko podczas PIERWSZEGO odczytu (brak stanu do pokazania).
        // Kolejne odświeżenia nie chowają ostrzeżenia — inaczej sekcja
        // migałaby co minutę, dopóki Latarnia pozostaje nieosiągalna.
        if availabilityMonitor.isRefreshing,
           availabilityMonitor.snapshot == nil,
           availabilityMonitor.lastError == nil { return nil }
        if let error = availabilityMonitor.lastError { return error }
        guard let snapshot = availabilityMonitor.snapshot,
              snapshot.environment == environment
        else { return "Brak aktualnego odczytu Latarni KSeF." }
        guard Date.now.timeIntervalSince(snapshot.fetchedAt) < 5 * 60 else {
            return "Ostatni odczyt Latarni KSeF jest nieaktualny."
        }
        if case .unknown(let code) = snapshot.status {
            return "Latarnia KSeF zwróciła nieznany status „\(code)”."
        }
        if (snapshot.status == .maintenance || snapshot.status == .failure),
           KSeFAvailabilityPolicy.currentSuggestion(from: snapshot) == nil {
            return "Status Latarni wskazuje zdarzenie, ale brakuje rozpoznawalnego komunikatu MF."
        }
        return nil
    }

    /// Kontrahent z historii wystawionych faktur (odrębny od słownika `Contractor`).
    private struct HistoryContractor: Identifiable {
        let id: String // NIP
        let name: String
        let nip: String
        let address: String
    }

    @State private var contractors: [HistoryContractor] = []

    public init(
        correcting: Invoice? = nil,
        editing: Invoice? = nil,
        initialDraft: InvoiceDraft? = nil,
        sourceTitle: String? = nil,
        selfInvoicing: Bool = false,
        onCompleted: (() -> Void)? = nil,
        onCreatedInvoice: ((Invoice) -> Void)? = nil
    ) {
        self.correctingInvoice = correcting
        self.editingInvoice = editing
        self.initialDraft = initialDraft
        self.sourceTitle = sourceTitle
        self.onCompleted = onCompleted
        self.onCreatedInvoice = onCreatedInvoice
        // Wejście „Wystaw samofakturę” z listy zakupów otwiera formularz
        // z włączonym trybem samofakturowania.
        _isSelfInvoicing = State(initialValue: selfInvoicing)
    }

    /// Czy formularz dotyczy dokumentu korygującego (nowa korekta
    /// lub edycja lokalnie zapisanej korekty).
    private var isCorrectionDocument: Bool {
        correctingInvoice != nil || (editingInvoice?.isCorrection ?? false)
    }

    private var totalNet: Double { lines.reduce(0) { $0 + $1.netAmount } }
    private var totalVat: Double { lines.reduce(0) { $0 + $1.vatAmount } }
    private var totalGross: Double { totalNet + totalVat }
    private var isRR: Bool { invoiceType == "VAT_RR" }
    /// Tryby z zamianą ról stron: kontrahent jest sprzedawcą (Podmiot1),
    /// a nasza firma nabywcą (Podmiot2) — VAT RR oraz samofakturowanie.
    private var swapsParties: Bool { isRR || isSelfInvoicing }

    /// Dane korekty zbudowane z faktury korygowanej (nowa korekta)
    /// lub z pól edytowanej korekty.
    private var correctionInfo: InvoiceCorrectionInfo? {
        if let original = correctingInvoice {
            return InvoiceCorrectionInfo(
                originalNumber: original.invoiceNumber,
                originalIssueDate: original.issueDate,
                originalKsefNumber: original.ksefId,
                reason: correctionReason.isEmpty ? nil : correctionReason
            )
        }
        if let editing = editingInvoice, editing.isCorrection {
            return InvoiceCorrectionInfo(
                originalNumber: editing.correctedInvoiceNumber ?? "",
                originalIssueDate: editing.correctedInvoiceIssueDate ?? editing.issueDate,
                originalKsefNumber: editing.correctedInvoiceKsefId,
                reason: correctionReason.isEmpty ? nil : correctionReason
            )
        }
        return nil
    }

    /// Szkic faktury zbudowany z bieżących pól formularza.
    private var draft: InvoiceDraft {
        InvoiceDraft(
            invoiceNumber: invoiceNumber,
            issueDate: issueDate,
            sellerName: swapsParties ? buyerName : sellerName,
            sellerNIP: swapsParties ? buyerNIP : sellerNIP,
            sellerAddress: swapsParties ? buyerAddress : sellerAddress,
            buyerName: swapsParties ? sellerName : buyerName,
            buyerNIP: swapsParties ? sellerNIP : buyerNIP,
            buyerAddress: swapsParties ? sellerAddress : buyerAddress,
            lines: lines,
            paymentDueDate: hasDueDate ? dueDate : nil,
            paymentForm: paymentForm,
            paymentBankAccount: paymentBankAccount,
            notes: notes,
            invoiceType: invoiceType,
            currency: currency,
            exchangeRate: exchangeRate,
            splitPayment: splitPayment,
            isSelfInvoicing: isSelfInvoicing && !isRR,
            saleDate: hasSaleDate ? saleDate : nil,
            advanceInvoiceRefs: advanceRefsText
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            marginProcedure: marginProcedure,
            attachments: attachments,
            correction: correctionInfo
        )
    }

    /// Pobiera kurs średni NBP z dnia poprzedzającego datę sprzedaży
    /// (lub wystawienia) — zgodnie z art. 31a ustawy o VAT. Kurs ląduje
    /// w polu, które nadal można edytować ręcznie.
    @MainActor
    private func fetchNBPRate() async {
        isFetchingRate = true
        defer { isFetchingRate = false }
        let baseDate = hasSaleDate ? saleDate : issueDate
        let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: baseDate) ?? baseDate
        do {
            let rate = try await NBPExchangeRateService().midRate(currency: currency, onOrBefore: dayBefore)
            exchangeRate = rate.mid
            nbpRateInfo = "Kurs NBP z \(rate.effectiveDate) (tabela \(rate.tableNumber))."
        } catch {
            nbpRateInfo = error.localizedDescription
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                if let correction = correctionInfo {
                    Section("Korekta") {
                        LabeledContent("Faktura korygowana", value: correction.originalNumber)
                        LabeledContent("Data wystawienia oryginału") {
                            Text(correction.originalIssueDate, style: .date)
                        }
                        if let ksefId = correction.originalKsefNumber {
                            LabeledContent("Numer KSeF oryginału", value: ksefId)
                        }
                        TextField("Przyczyna korekty", text: $correctionReason, prompt: Text("np. błędna cena pozycji"))
                        Text("Pozycje korekty wyrażają RÓŻNICĘ względem faktury pierwotnej — kwoty mogą być ujemne (np. zwrot).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Dane faktury") {
                    TextField("Numer faktury", text: $invoiceNumber, prompt: Text("np. FV/2026/06/001"))
                    DatePicker("Data wystawienia", selection: $issueDate, displayedComponents: .date)
                    if correctionInfo == nil {
                        Picker("Rodzaj dokumentu", selection: $invoiceType) {
                            ForEach(Self.invoiceTypes, id: \.raw) { type in
                                Text(type.label).tag(type.raw)
                            }
                        }
                    }
                    if !isRR {
                        // Korekta dziedziczy adnotację z dokumentu pierwotnego —
                        // przełącznik jest wtedy tylko informacyjny.
                        Toggle("Samofakturowanie — wystawiam jako nabywca w imieniu dostawcy", isOn: $isSelfInvoicing)
                            .disabled(isCorrectionDocument)
                        if isSelfInvoicing {
                            Text("Faktura dostanie adnotację „samofakturowanie” (P_17, art. 106d ustawy o VAT) i trafi do zakupów. Wysyłka wymaga uprawnienia „Samofakturowanie” nadanego Twojej firmie przez dostawcę w KSeF (sekcja Uprawnienia po jego stronie) — KSeF sprawdzi tę relację przy przyjęciu dokumentu.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(
                        isRR ? "Wspólna data nabycia (P_4A)" : invoiceType == "ZAL"
                            ? "Data otrzymania zaliczki (P_6)"
                            : "Data sprzedaży / dostawy (P_6)",
                        isOn: $hasSaleDate
                    )
                    if hasSaleDate {
                        DatePicker("Data", selection: $saleDate, displayedComponents: .date)
                    }
                    if invoiceType == "ROZ" {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Numery KSeF faktur zaliczkowych (jeden na linię)")
                            TextEditor(text: $advanceRefsText)
                                .frame(minHeight: 48)
                                .font(.body.monospaced())
                        }
                    }
                    Picker("Waluta", selection: $currency) {
                        ForEach(Self.currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    if !CurrencyCode.isPLN(currency) {
                        HStack {
                            TextField(
                                "Kurs PLN (do przeliczenia VAT)",
                                value: $exchangeRate,
                                format: .number.precision(.fractionLength(4))
                            )
                            Button {
                                Task { await fetchNBPRate() }
                            } label: {
                                if isFetchingRate {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("NBP", systemImage: "arrow.down.circle")
                                }
                            }
                            .disabled(isFetchingRate)
                            .help("Pobierz kurs średni NBP z ostatniego dnia roboczego przed datą wystawienia/sprzedaży (art. 31a ustawy o VAT). Kurs można też wpisać ręcznie.")
                        }
                        if let nbpRateInfo {
                            Text(nbpRateInfo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !isRR {
                        Picker("Procedura marży", selection: $marginProcedure) {
                            ForEach(Self.marginProcedures, id: \.raw) { procedure in
                                Text(procedure.label).tag(procedure.raw)
                            }
                        }
                    }
                }

                Section(swapsParties ? "Nabywca (Twoja firma)" : "Sprzedawca (Twoja firma)") {
                    TextField("Nazwa firmy", text: $sellerName)
                    TextField("NIP", text: $sellerNIP)
                    TextField("Adres", text: $sellerAddress, prompt: Text("ul. Przykładowa 1, 00-001 Warszawa"))
                }

                Section(
                    isRR ? "Dostawca — rolnik ryczałtowy"
                        : isSelfInvoicing ? "Sprzedawca — dostawca (samofakturowanie)"
                        : "Nabywca"
                ) {
                    // Dla RR i samofakturowania wybieramy dostawcę;
                    // dla zwykłej faktury odbiorcę.
                    let recipients = dictionaryContractors.filter { swapsParties ? $0.isSupplier : $0.isRecipient }
                    if !recipients.isEmpty {
                        Menu {
                            ForEach(recipients) { contractor in
                                Button("\(contractor.displayName) (NIP: \(contractor.nip))") {
                                    buyerName = contractor.displayName
                                    buyerNIP = contractor.nip
                                    buyerAddress = contractor.invoiceAddress
                                }
                            }
                        } label: {
                            Label("Wybierz ze słownika kontrahentów", systemImage: "text.book.closed")
                        }
                    }
                    if !contractors.isEmpty {
                        // Szybkie wypełnienie danymi kontrahenta z poprzednich faktur.
                        Menu {
                            ForEach(contractors) { contractor in
                                Button("\(contractor.name) (NIP: \(contractor.nip))") {
                                    buyerName = contractor.name
                                    buyerNIP = contractor.nip
                                    buyerAddress = contractor.address
                                }
                            }
                        } label: {
                            Label("Wybierz kontrahenta z historii", systemImage: "person.crop.rectangle.stack")
                        }
                    }
                    TextField(
                        isRR ? "Imię i nazwisko / nazwa rolnika"
                            : isSelfInvoicing ? "Nazwa dostawcy" : "Nazwa nabywcy",
                        text: $buyerName
                    )
                    TextField(
                        isRR ? "NIP rolnika" : isSelfInvoicing ? "NIP dostawcy" : "NIP nabywcy",
                        text: $buyerNIP
                    )
                    TextField(
                        isRR ? "Adres rolnika" : isSelfInvoicing ? "Adres dostawcy" : "Adres nabywcy",
                        text: $buyerAddress,
                        // Dostawca jest w dokumencie sprzedawcą (Podmiot1) —
                        // schema FA(3) wymaga jego adresu.
                        prompt: Text(swapsParties ? "wymagany" : "opcjonalnie")
                    )
                }

                Section("Pozycje") {
                    ForEach($lines) { $line in
                        InvoiceLineEditor(
                            line: $line,
                            products: dictionaryProducts,
                            currencyCode: currency,
                            isRR: isRR,
                            canDelete: lines.count > 1
                        ) {
                            lines.removeAll { $0.id == line.id }
                        }
                    }
                    Button {
                        lines.append(InvoiceLineDraft(vatRate: isRR ? .rr : .standard))
                    } label: {
                        Label("Dodaj pozycję", systemImage: "plus.circle")
                    }
                }

                Section("Uwagi") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 56)
                        .font(.body)
                    Text("Dopisek drukowany na fakturze (w XML: stopka faktury) — np. podstawa zwolnienia z VAT, informacja o mechanizmie podzielonej płatności.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !isRR {
                    Section("Załącznik do faktury (FA(3))") {
                        ForEach($attachments) { $block in
                            AttachmentBlockEditor(block: $block) {
                                attachments.removeAll { $0.id == block.id }
                            }
                        }
                        Button {
                            attachments.append(FA3AttachmentBlock())
                        } label: {
                            Label("Dodaj blok załącznika", systemImage: "paperclip")
                        }
                        if !attachments.isEmpty {
                            Text("⚠️ Wystawianie faktur z załącznikiem wymaga wcześniejszego zgłoszenia w e-Urzędzie Skarbowym (wymóg KSeF 2.0). Każdy blok musi mieć co najmniej jedną parę metadanych.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Podsumowanie") {
                    LabeledContent("Razem netto") {
                        Text(totalNet, format: .currency(code: currency)).monospacedDigit()
                    }
                    LabeledContent(isRR ? "Zryczałtowany zwrot podatku" : "Razem VAT") {
                        Text(totalVat, format: .currency(code: currency)).monospacedDigit()
                    }
                    LabeledContent("Do zapłaty (brutto)") {
                        Text(totalGross, format: .currency(code: currency))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    if !CurrencyCode.isPLN(currency), exchangeRate > 0 {
                        LabeledContent("VAT w PLN (kurs \(exchangeRate.formatted(.number.precision(.fractionLength(4)))))") {
                            Text(totalVat * exchangeRate, format: .currency(code: "PLN"))
                                .monospacedDigit()
                        }
                    }
                }

                Section("Płatność") {
                    Picker("Forma płatności", selection: $paymentForm) {
                        ForEach(PaymentForm.allCases) { form in
                            Text(form.displayName).tag(form)
                        }
                    }
                    HStack {
                        TextField(
                            isRR ? "Rachunek rolnika"
                                : isSelfInvoicing ? "Rachunek dostawcy" : "Numer rachunku bankowego",
                            text: $paymentBankAccount,
                            prompt: Text("26 cyfr (NRB)")
                        )
                        // Słownik własnych rachunków tylko, gdy odbiorcą
                        // płatności jest nasza firma (zwykła sprzedaż).
                        if !swapsParties, !dictionaryAccounts.isEmpty {
                            Menu {
                                ForEach(dictionaryAccounts) { account in
                                    Button(account.displayName) {
                                        paymentBankAccount = account.accountNumber
                                    }
                                }
                            } label: {
                                Image(systemName: "text.book.closed")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Podstaw rachunek ze słownika")
                        }
                    }
                    Toggle("Termin płatności", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Termin", selection: $dueDate, displayedComponents: .date)
                    }
                    if !isRR {
                        Toggle("Mechanizm podzielonej płatności (MPP)", isOn: $splitPayment)
                    }
                    if !isRR, lines.contains(where: \.isAttachment15) {
                        Text("Pozycje z załącznika 15 — MPP jest obowiązkowy, gdy kwota brutto przekracza 15 000 zł.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                // Lista błędów walidacji prezentowana bezpośrednio w formularzu.
                if !validationErrors.isEmpty {
                    Section {
                        ForEach(validationErrors, id: \.self) { error in
                            Label(error.errorDescription ?? "", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }
                }

                if let suggestion = availabilitySuggestion {
                    Section("Status KSeF — komunikat MF") {
                        Label(suggestion.title, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(suggestion.text)
                            .font(.callout)
                        if let deadline = suggestion.deadline {
                            Text("Proponowany termin dosłania: \(deadline.formatted(date: .long, time: .omitted)).")
                                .font(.callout.weight(.semibold))
                        } else {
                            Text(suggestion.reason.deadlineDescription.capitalized + ". Termin pojawi się automatycznie po komunikacie MF o zakończeniu zdarzenia.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Button("Użyj: \(suggestion.reason.displayName)") {
                            issueMode = issueMode(for: suggestion.reason)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if isTotalKSeFFailure {
                    Section("Status KSeF — awaria całkowita") {
                        Label("MF ogłosiło awarię całkowitą KSeF", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text("Nie wystawiaj tu faktury ustrukturyzowanej offline. Dokumentów z okresu awarii całkowitej nie dosyła się później do KSeF; Ksefiarz nie obsługuje tego odrębnego trybu.")
                            .font(.callout)
                    }
                } else if let warning = availabilityWarning {
                    Section("Status KSeF") {
                        Label("Nie można automatycznie dobrać trybu", systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                        Text(warning + " W razie problemów wybierz tryb offline ręcznie po sprawdzeniu komunikatu MF.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if let maintenance = upcomingMaintenance {
                    Section("Zaplanowana niedostępność KSeF") {
                        Label(maintenance.title, systemImage: "calendar.badge.clock")
                        Text("Od \(maintenance.start.formatted(date: .long, time: .shortened)) do \((maintenance.end ?? maintenance.start).formatted(date: .long, time: .shortened)). Podpowiedź trybu offline pojawi się automatycznie po rozpoczęciu przerwy.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Pasek przycisków akcji. `fixedSize` na przyciskach i pickerze
            // zapobiega obcinaniu etykiet („Zapisz jak…”, „Wystaw i…”) —
            // arkusz rozszerza się do pełnych podpisów zamiast je skracać.
            HStack {
                Button("Anuluj", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .fixedSize()
                if !isCorrectionDocument {
                    Button("Zapisz jako szablon") {
                        templateName = buyerName.isEmpty ? "Nowy szablon" : buyerName
                        showingTemplateName = true
                    }
                    .fixedSize()
                    .disabled(isSending)
                }
                Spacer(minLength: 12)
                Picker("Tryb", selection: $issueMode) {
                    ForEach(IssueMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .fixedSize()
                .disabled(isSending)
                .help("Tryby offline tworzą dokument od razu (z kodami QR na wydruku) i dosyłają go automatycznie. Termin dosłania: offline24 — następny dzień roboczy; niedostępność KSeF — następny dzień roboczy po jej zakończeniu; awaria KSeF — 7 dni roboczych od jej zakończenia (komunikaty MF w BIP).")
                Button("Zapisz lokalnie") { saveLocally() }
                    .fixedSize()
                    .disabled(isSending)
                Button {
                    if let reason = issueMode.offlineReason {
                        issueOffline(reason: reason)
                    } else {
                        Task { await sendToKSeF() }
                    }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(issueMode == .online ? "Wystaw i wyślij do KSeF" : "Wystaw offline (doślij później)")
                    }
                }
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSending || isTotalKSeFFailure)
            }
            .padding()
        }
        .navigationTitle(formTitle)
        .frame(minWidth: 820, minHeight: 700)
        // Pozycja z załącznika 15 (ze słownika) podpowiada włączenie MPP;
        // użytkownik może je wyłączyć ręcznie.
        .onChange(of: lines.contains(where: \.isAttachment15)) { _, hasAttachment15 in
            if hasAttachment15 { splitPayment = true }
        }
        // Zmiana rodzaju dokumentu przegenerowuje numer (każdy rodzaj ma
        // własną serię), ale nie nadpisuje numeru wpisanego ręcznie.
        .onChange(of: invoiceType) { _, _ in
            if isRR {
                paymentForm = .transfer
                paymentBankAccount = ""
                attachments = []
                splitPayment = false
                marginProcedure = ""
                // FA_RR(1) nie ma adnotacji P_17 — tryby się wykluczają.
                isSelfInvoicing = false
                for index in lines.indices {
                    lines[index].vatRate = .rr
                    lines[index].ossRate = nil
                }
            } else {
                for index in lines.indices where lines[index].vatRate == .rr || lines[index].vatRate == .rrHistorical {
                    lines[index].vatRate = .standard
                }
            }
            loadContractors()
            guard editingInvoice == nil else { return }
            prefillInvoiceNumber(force: true)
        }
        // Przełączenie samofakturowania zmienia strony, serię numeracji
        // i odbiorcę płatności (płacimy dostawcy — nie podstawiamy
        // własnego rachunku).
        .onChange(of: isSelfInvoicing) { _, enabled in
            if enabled {
                if paymentBankAccount == defaultBankAccount { paymentBankAccount = "" }
            } else if paymentBankAccount.isEmpty, !isRR {
                paymentBankAccount = defaultBankAccount
            }
            loadContractors()
            guard editingInvoice == nil else { return }
            prefillInvoiceNumber(force: true)
        }
        .onAppear {
            prefillFromEditedInvoice()
            prefillFromCorrectedInvoice()
            prefillFromInitialDraft()
            if paymentBankAccount.isEmpty, !swapsParties { paymentBankAccount = defaultBankAccount }
            prefillInvoiceNumber()
            loadContractors()
        }
        .task(id: "invoice-ksef-availability-\(environmentRaw)") {
            let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
            _ = await availabilityMonitor.refresh(environment: environment)
        }
        .alert("Nazwa szablonu", isPresented: $showingTemplateName) {
            TextField("np. Miesięczna obsługa", text: $templateName)
            Button("Anuluj", role: .cancel) {}
            Button("Zapisz") { saveTemplate() }
                .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Szablon zachowa kontrahenta, pozycje i płatność. Numer oraz daty będą nadawane przy użyciu.")
        }
        .alert(
            "Nie udało się wysłać faktury",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            offlineInfoTitle,
            isPresented: Binding(
                get: { offlineInfoMessage != nil },
                set: { if !$0 { offlineInfoMessage = nil; onCompleted?(); dismiss() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(offlineInfoMessage ?? "")
        }
    }

    // MARK: Akcje

    private func issueMode(for reason: Invoice.OfflineReason) -> IssueMode {
        switch reason {
        case .offline24: return .offline24
        case .unavailability: return .unavailability
        case .failure: return .failure
        }
    }

    private var formTitle: String {
        if editingInvoice != nil {
            if isRR { return "Edycja faktury VAT RR" }
            return isSelfInvoicing ? "Edycja samofaktury" : "Edycja faktury"
        }
        if let sourceTitle { return sourceTitle }
        if isRR { return isCorrectionDocument ? "Korekta faktury VAT RR" : "Nowa faktura VAT RR" }
        if isSelfInvoicing {
            return isCorrectionDocument
                ? "Korekta samofaktury"
                : "Nowa samofaktura (w imieniu dostawcy)"
        }
        return isCorrectionDocument ? "Faktura korygująca" : "Nowa faktura"
    }

    private func prefillFromInitialDraft() {
        guard let initial = initialDraft, buyerName.isEmpty else { return }
        invoiceNumber = initial.invoiceNumber
        issueDate = initial.issueDate
        invoiceType = initial.invoiceType
        isSelfInvoicing = initial.isSelfInvoicing
        if initial.isRR || initial.isSelfInvoicing {
            // W szkicu sprzedawcą jest kontrahent (rolnik/dostawca) —
            // do pól formularza wraca po stronie kontrahenta.
            buyerName = initial.sellerName
            buyerNIP = initial.sellerNIP
            buyerAddress = initial.sellerAddress
        } else {
            sellerName = initial.sellerName
            sellerNIP = initial.sellerNIP
            sellerAddress = initial.sellerAddress
            buyerName = initial.buyerName
            buyerNIP = initial.buyerNIP
            buyerAddress = initial.buyerAddress
        }
        lines = initial.lines.isEmpty
            ? [InvoiceLineDraft(vatRate: initial.isRR ? .rr : .standard)]
            : initial.lines
        paymentForm = initial.paymentForm ?? .transfer
        paymentBankAccount = initial.paymentBankAccount
        notes = initial.notes
        currency = initial.currency
        exchangeRate = initial.exchangeRate
        splitPayment = initial.splitPayment
        if let due = initial.paymentDueDate { hasDueDate = true; dueDate = due } else { hasDueDate = false }
        if let sale = initial.saleDate { hasSaleDate = true; saleDate = sale } else { hasSaleDate = false }
        advanceRefsText = initial.advanceInvoiceRefs.joined(separator: "\n")
        marginProcedure = initial.marginProcedure
        attachments = initial.attachments
    }

    private func saveTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(InvoiceTemplate(name: name, preset: InvoicePreset(draft: draft)))
        try? modelContext.save()
    }

    /// Przy edycji wypełnia formularz wszystkimi danymi zapisanej faktury.
    private func prefillFromEditedInvoice() {
        guard let editing = editingInvoice, invoiceNumber.isEmpty else { return }
        invoiceNumber = editing.invoiceNumber
        issueDate = editing.issueDate
        invoiceType = InvoiceDraft.baseType(for: editing.documentTypeRaw)
        isSelfInvoicing = editing.isSelfInvoicing && !editing.isRR
        // Dokumenty z zamianą ról (RR, samofaktura) trzymają kontrahenta
        // po stronie sprzedawcy.
        let swapped = editing.isRR || editing.isSelfIssuedPurchase
        buyerName = swapped ? editing.sellerName : editing.buyerName
        buyerNIP = swapped ? editing.sellerNIP : editing.buyerNIP
        buyerAddress = swapped ? editing.sellerAddress : editing.buyerAddress
        paymentForm = editing.paymentForm ?? .transfer
        paymentBankAccount = editing.paymentBankAccount ?? (swapped ? "" : defaultBankAccount)
        correctionReason = editing.correctionReason ?? ""
        if let due = editing.paymentDueDate {
            hasDueDate = true
            dueDate = due
        } else {
            hasDueDate = false
        }
        notes = editing.notes
        marginProcedure = editing.marginProcedureRaw
        currency = editing.currency
        exchangeRate = editing.exchangeRate
        splitPayment = editing.splitPayment
        if let sale = editing.saleDate {
            hasSaleDate = true
            saleDate = sale
        }
        advanceRefsText = editing.advanceInvoiceRefs.joined(separator: "\n")
        attachments = .decoded(from: editing.attachmentJSON)
        let storedLines = editing.sortedLines.map { line in
            InvoiceLineDraft(
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                vatRate: VATRate(rawValue: line.vatRate) ?? .standard,
                cnPkwiu: line.cnPkwiu,
                gtu: line.gtu,
                procedure: line.procedure,
                ossRate: line.ossRate,
                rrQuality: line.rrQuality
            )
        }
        if !storedLines.isEmpty {
            lines = storedLines
        }
    }

    /// Przy korekcie wypełnia formularz danymi faktury pierwotnej.
    /// Typ oryginału decyduje o rodzaju korekty (ZAL→KOR_ZAL, ROZ→KOR_ROZ).
    private func prefillFromCorrectedInvoice() {
        guard let original = correctingInvoice, buyerName.isEmpty else { return }
        invoiceType = InvoiceDraft.baseType(for: original.documentTypeRaw)
        // Korekta samofaktury pozostaje samofakturą (adnotacja P_17
        // i role stron jak w dokumencie pierwotnym). Sprzedaż z adnotacją
        // samofakturowania korygujemy już jako zwykłą własną korektę.
        isSelfInvoicing = original.isSelfIssuedPurchase && !original.isRR
        let swapped = original.isRR || original.isSelfIssuedPurchase
        buyerName = swapped ? original.sellerName : original.buyerName
        buyerNIP = swapped ? original.sellerNIP : original.buyerNIP
        buyerAddress = swapped ? original.sellerAddress : original.buyerAddress
        paymentForm = original.paymentForm ?? .transfer
        paymentBankAccount = original.paymentBankAccount ?? (swapped ? "" : defaultBankAccount)
        marginProcedure = original.marginProcedureRaw
        currency = original.currency
        exchangeRate = original.exchangeRate
        splitPayment = original.splitPayment
        // Pozycje oryginału jako punkt wyjścia do edycji różnic.
        let originalLines = original.sortedLines.map { line in
            InvoiceLineDraft(
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                vatRate: VATRate(rawValue: line.vatRate) ?? .standard,
                cnPkwiu: line.cnPkwiu,
                gtu: line.gtu,
                procedure: line.procedure,
                ossRate: line.ossRate,
                rrQuality: line.rrQuality
            )
        }
        if !originalLines.isEmpty {
            lines = originalLines
        }
    }

    /// Wzorzec numeracji właściwy dla bieżącego rodzaju dokumentu —
    /// pusty wzorzec danego typu dziedziczy wzorzec faktur VAT.
    private var patternForCurrentType: String {
        let specific: String
        if correctionInfo != nil {
            specific = numberPatternKOR
        } else if isSelfInvoicing {
            // Samofaktury mają jedną własną serię niezależnie od rodzaju
            // dokumentu — numerację zwykle określa umowa z dostawcą.
            specific = numberPatternSF
        } else {
            switch invoiceType {
            case "ZAL": specific = numberPatternZAL
            case "ROZ": specific = numberPatternROZ
            case "UPR": specific = numberPatternUPR
            case "VAT_RR": specific = numberPatternRR
            default: specific = ""
            }
        }
        let trimmed = specific.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? numberPattern : trimmed
    }

    /// Czy dokument należy do serii numeracji bieżącego trybu formularza:
    /// RR, samofaktury (nasze zakupowe dokumenty samofakturowania) albo
    /// zwykła sprzedaż. Sprzedaż z adnotacją samofakturowania (numer nadał
    /// klient według własnej serii) nie wchodzi do żadnej naszej serii.
    private func belongsToCurrentSeries(_ invoice: Invoice) -> Bool {
        if isRR { return invoice.isRR }
        if isSelfInvoicing { return invoice.isSelfIssuedPurchase && !invoice.isRR }
        return invoice.kind == .sales && !invoice.isSelfInvoicing
    }

    /// Proponuje kolejny numer według wzorca rodzaju dokumentu — każdy
    /// rodzaj ma własną serię (licznik rośnie w obrębie numerów pasujących
    /// do danego wzorca).
    private func prefillInvoiceNumber(force: Bool = false) {
        if force {
            // Przegenerowanie tylko, gdy numeru nie zmienił użytkownik.
            guard invoiceNumber == lastGeneratedNumber || invoiceNumber.isEmpty else { return }
        } else {
            guard invoiceNumber.isEmpty else { return }
        }
        let existing = (try? modelContext.fetch(FetchDescriptor<Invoice>()))?
            .filter { belongsToCurrentSeries($0) }
            .map(\.invoiceNumber) ?? []
        invoiceNumber = InvoiceNumberGenerator.nextNumber(
            pattern: patternForCurrentType,
            existing: existing,
            date: issueDate
        )
        lastGeneratedNumber = invoiceNumber
    }

    /// Buduje listę kontrahentów z historii faktur sprzedażowych (unikalnie po NIP).
    private func loadContractors() {
        let descriptor = FetchDescriptor<Invoice>(
            sortBy: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
        )
        // Historia kontrahentów: dla trybów z zamianą ról (RR, samofaktura)
        // dostawcy z naszych dokumentów zakupowych, inaczej odbiorcy sprzedaży.
        let historyInvoices = ((try? modelContext.fetch(descriptor)) ?? []).filter {
            if isRR { return $0.isRR }
            if isSelfInvoicing { return $0.isSelfIssuedPurchase }
            return $0.kind == .sales
        }
        var seen = Set<String>()
        contractors = historyInvoices.compactMap { invoice in
            let nip = swapsParties ? invoice.sellerNIP : invoice.buyerNIP
            guard !nip.isEmpty, !seen.contains(nip) else { return nil }
            seen.insert(nip)
            return HistoryContractor(
                id: nip,
                name: swapsParties ? invoice.sellerName : invoice.buyerName,
                nip: nip,
                address: swapsParties ? invoice.sellerAddress : invoice.buyerAddress
            )
        }
    }

    /// Waliduje formularz; zwraca true, gdy dane są poprawne.
    /// Obejmuje blokadę duplikatu numeru: numer nie może należeć do żadnego
    /// dokumentu już zapisanego w bazie (przy edycji własny numer faktury
    /// jest oczywiście dozwolony).
    private func validate() -> Bool {
        validationErrors = InvoiceValidator.validate(draft, existingNumbers: existingNumbers())
        return validationErrors.isEmpty
    }

    /// Znormalizowane numery dokumentów z tej samej serii w bazie,
    /// z wyłączeniem dokumentu właśnie edytowanego.
    private func existingNumbers() -> Set<String> {
        let all = ((try? modelContext.fetch(FetchDescriptor<Invoice>())) ?? []).filter {
            belongsToCurrentSeries($0)
        }
        return Set(
            all.filter { $0.id != editingInvoice?.id }
                .map { InvoiceValidator.normalizedNumber($0.invoiceNumber) }
        )
    }

    /// Zapisuje fakturę lokalnie (bez wysyłki do KSeF) — np. tryb roboczy/offline.
    private func saveLocally() {
        guard validate() else { return }
        let xml = FA2XMLGenerator.generateXML(for: draft)
        let invoice = persist(ksefId: nil, sessionReference: nil, xml: xml)
        onCreatedInvoice?(invoice)
        onCompleted?()
        dismiss()
    }

    /// Wystawia dokument w trybie offline: XML i jego skrót powstają teraz
    /// (są podstawą kodów QR na wydruku), a dosłanie do KSeF wykona się
    /// automatycznie. Dosyłany jest DOKŁADNIE ten zapisany XML.
    /// - Parameters:
    ///   - reason: powód offline (offline24 / niedostępność / awaria) —
    ///     decyduje o terminie dosłania,
    ///   - automatic: true, gdy tryb offline włączył się sam po nieudanej
    ///     wysyłce online (brak sieci) — pokazuje komunikat informacyjny
    ///     zamiast natychmiastowego zamknięcia formularza.
    private func issueOffline(reason: Invoice.OfflineReason, automatic: Bool = false) {
        guard validate() else { return }
        let xml = FA2XMLGenerator.generateXML(for: draft)
        let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
        let invoice = persist(
            ksefId: nil,
            sessionReference: nil,
            submissionStatus: .offlinePending,
            environmentRaw: environment.rawValue,
            xml: xml
        )
        invoice.isOfflineMode = true
        invoice.offlineReason = reason
        invoice.offlineHashBase64 = KSeFCrypto.sha256Base64(Data(xml.utf8))
        if let suggestion = availabilitySuggestion, suggestion.reason == reason {
            KSeFAvailabilityPolicy.apply(suggestion, to: invoice)
        }
        try? modelContext.save()
        onCreatedInvoice?(invoice)

        let deadline = invoice.offlineSendDeadline
            .map { FA2Format.dateFormatter.string(from: $0) } ?? reason.deadlineDescription
        if automatic {
            offlineInfoTitle = "Faktura wystawiona: \(reason.displayName)"
            let source = reason == .offline24
                ? "Brak połączenia z KSeF nie był potwierdzony aktywnym komunikatem MF, dlatego zastosowano offline24."
                : "Aktywny komunikat Latarni MF potwierdził właściwy tryb i powiązał dokument ze zdarzeniem."
            offlineInfoMessage = "Wysyłka online nie powiodła się, więc dokument został wystawiony offline. \(source) Zostanie dosłany automatycznie — termin: \(deadline). Na wydruku znajdą się wymagane kody QR."
        } else {
            onCompleted?()
            dismiss()
        }
    }

    /// Czy błąd wysyłki wynika z braku łączności (a nie z odrzucenia przez
    /// KSeF) — tylko wtedy automatycznie przechodzimy w tryb offline24.
    private func isConnectivityError(_ error: Error) -> Bool {
        if error is URLError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }

    /// Wysyła fakturę do KSeF i zapisuje ją z nadanym numerem referencyjnym.
    @MainActor
    private func sendToKSeF() async {
        guard validate() else { return }
        guard !sellerNIP.isEmpty, !ksefToken.isEmpty || KSeFCertificateStore.shared.authenticationCertificate != nil else {
            errorMessage = KSeFError.missingCredentials.localizedDescription
            return
        }
        isSending = true
        defer { isSending = false }

        let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
        let service = KSeFService(environment: environment, nip: sellerNIP, authToken: ksefToken, certificate: KSeFCertificateStore.shared.authenticationCertificate)

        do {
            let result = try await service.sendInvoice(draft)
            let invoice = persist(
                ksefId: result.ksefNumber,
                sessionReference: result.sessionReferenceNumber,
                invoiceReference: result.invoiceReferenceNumber,
                submissionStatus: result.processingResult.status,
                environmentRaw: environment.rawValue,
                xml: result.xml
            )
            invoice.ksefStatusCode = result.processingResult.statusCode
            invoice.ksefStatusDescription = result.processingResult.description
            invoice.ksefLastCheckedAt = .now
            invoice.ksefAcceptedAt = result.processingResult.acquisitionDate
            try? modelContext.save()
            // Przy numerze nadanym od razu próbujemy również zachować UPO.
            // Brak gotowego UPO nie blokuje wysyłki — automat ponowi próbę.
            if result.ksefNumber != nil {
                _ = try? await InvoiceSubmissionStatusEngine.refresh(invoice, using: service)
                try? modelContext.save()
            }
            onCreatedInvoice?(invoice)
            onCompleted?()
            dismiss()
        } catch {
            // Brak łączności z KSeF nie blokuje wystawienia: dokument
            // przechodzi w tryb wskazany przez aktywny komunikat MF, a przy
            // braku takiego komunikatu — w offline24.
            if isConnectivityError(error) {
                issueOffline(reason: availabilitySuggestion?.reason ?? .offline24, automatic: true)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Zapisuje szkic: aktualizuje edytowaną fakturę lub tworzy nową.
    @discardableResult
    private func persist(
        ksefId: String?,
        sessionReference: String?,
        invoiceReference: String? = nil,
        submissionStatus: KSeFSubmissionStatus? = nil,
        environmentRaw: String = "",
        xml: String
    ) -> Invoice {
        let invoice: Invoice
        if let editing = editingInvoice {
            update(
                editing,
                ksefId: ksefId,
                sessionReference: sessionReference,
                invoiceReference: invoiceReference,
                submissionStatus: submissionStatus,
                environmentRaw: environmentRaw,
                xml: xml
            )
            invoice = editing
        } else {
            invoice = insertInvoice(
                ksefId: ksefId,
                sessionReference: sessionReference,
                invoiceReference: invoiceReference,
                submissionStatus: submissionStatus,
                environmentRaw: environmentRaw,
                xml: xml
            )
        }
        // Jawny zapis zamiast czekania na autosave: faktura (zwłaszcza
        // z nadanym numerem KSeF) musi natychmiast trafić na dysk,
        // a @Query list odświeża się dopiero przy zapisie kontekstu.
        try? modelContext.save()
        return invoice
    }

    /// Aktualizuje lokalnie zapisaną fakturę danymi z formularza.
    private func update(
        _ invoice: Invoice,
        ksefId: String?,
        sessionReference: String?,
        invoiceReference: String?,
        submissionStatus: KSeFSubmissionStatus?,
        environmentRaw: String,
        xml: String
    ) {
        invoice.invoiceNumber = draft.invoiceNumber
        invoice.issueDate = draft.issueDate
        invoice.sellerName = draft.sellerName
        invoice.sellerNIP = draft.sellerNIP
        invoice.sellerAddress = draft.sellerAddress
        invoice.buyerName = draft.buyerName
        invoice.buyerNIP = draft.buyerNIP
        invoice.buyerAddress = draft.buyerAddress
        invoice.netAmount = draft.netAmount
        invoice.vatAmount = draft.vatAmount
        invoice.grossAmount = draft.grossAmount
        invoice.paymentDueDate = draft.paymentDueDate
        invoice.paymentForm = draft.paymentForm
        invoice.paymentBankAccount = draft.paymentBankAccount.isEmpty ? nil : draft.paymentBankAccount
        invoice.correctionReason = draft.correction?.reason
        invoice.notes = draft.notes
        invoice.documentTypeRaw = draft.documentType
        invoice.currency = CurrencyCode.normalizedOrPLN(draft.currency)
        invoice.exchangeRate = draft.exchangeRate
        invoice.splitPayment = draft.splitPayment
        invoice.saleDate = draft.saleDate
        invoice.advanceInvoiceRefs = draft.advanceInvoiceRefs
        invoice.marginProcedureRaw = draft.marginProcedure
        invoice.isSelfInvoicing = draft.isSelfInvoicing
        // Zmiana trybu przy edycji (np. włączenie samofakturowania) może
        // przenieść dokument między sprzedażą a zakupami.
        invoice.kind = draft.isRR || draft.isSelfInvoicing ? .purchase : .sales
        invoice.attachmentJSON = draft.attachments.encodedJSON()
        invoice.rawXmlContent = xml
        if let ksefId { invoice.ksefId = ksefId }
        if let sessionReference { invoice.ksefSessionReference = sessionReference }
        if let invoiceReference { invoice.ksefInvoiceReference = invoiceReference }
        if let submissionStatus { invoice.ksefSubmissionStatus = submissionStatus }
        if !environmentRaw.isEmpty { invoice.ksefEnvironmentRaw = environmentRaw }
        invoice.lines = draft.lines.enumerated().map { offset, line in
            InvoiceLine(
                index: offset + 1,
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                netAmount: line.netAmount,
                vatRate: line.vatRate.rawValue,
                vatAmount: line.vatAmount,
                cnPkwiu: line.cnPkwiu,
                gtu: line.gtu,
                procedure: line.procedure,
                ossRate: line.ossRate,
                rrQuality: line.rrQuality
            )
        }
        PaymentFormPolicy.apply(to: invoice, prepaidForms: PaymentFormPolicy.decode(prepaidFormsRaw))
    }

    /// Zapisuje model SwiftData z bieżącego szkicu wraz z pozycjami.
    private func insertInvoice(
        ksefId: String?,
        sessionReference: String?,
        invoiceReference: String?,
        submissionStatus: KSeFSubmissionStatus?,
        environmentRaw: String,
        xml: String
    ) -> Invoice {
        let invoice = Invoice(
            ksefId: ksefId,
            invoiceNumber: draft.invoiceNumber,
            issueDate: draft.issueDate,
            sellerName: draft.sellerName,
            sellerNIP: draft.sellerNIP,
            sellerAddress: draft.sellerAddress,
            buyerName: draft.buyerName,
            buyerNIP: draft.buyerNIP,
            buyerAddress: draft.buyerAddress,
            netAmount: draft.netAmount,
            vatAmount: draft.vatAmount,
            grossAmount: draft.grossAmount,
            paymentDueDate: draft.paymentDueDate,
            paymentForm: draft.paymentForm,
            paymentBankAccount: draft.paymentBankAccount.isEmpty ? nil : draft.paymentBankAccount,
            rawXmlContent: xml,
            documentType: draft.documentType,
            correctionReason: draft.correction?.reason,
            correctedInvoiceNumber: draft.correction?.originalNumber,
            correctedInvoiceKsefId: draft.correction?.originalKsefNumber,
            correctedInvoiceIssueDate: draft.correction?.originalIssueDate,
            ksefSessionReference: sessionReference,
            ksefInvoiceReference: invoiceReference,
            ksefSubmissionStatus: submissionStatus,
            ksefEnvironmentRaw: environmentRaw,
            notes: draft.notes,
            currency: draft.currency,
            exchangeRate: draft.exchangeRate,
            splitPayment: draft.splitPayment,
            saleDate: draft.saleDate,
            advanceInvoiceRefs: draft.advanceInvoiceRefs,
            marginProcedure: draft.marginProcedure,
            isSelfInvoicing: draft.isSelfInvoicing,
            kind: draft.isRR || draft.isSelfInvoicing ? .purchase : .sales
        )
        invoice.attachmentJSON = draft.attachments.encodedJSON()
        modelContext.insert(invoice)
        // Pozycje przypisywane po wstawieniu do kontekstu (relacja SwiftData).
        invoice.lines = draft.lines.enumerated().map { offset, line in
            InvoiceLine(
                index: offset + 1,
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                netAmount: line.netAmount,
                vatRate: line.vatRate.rawValue,
                vatAmount: line.vatAmount,
                cnPkwiu: line.cnPkwiu,
                gtu: line.gtu,
                procedure: line.procedure,
                ossRate: line.ossRate,
                rrQuality: line.rrQuality
            )
        }
        // Forma płatności „z góry” (np. gotówka) → faktura od razu opłacona.
        PaymentFormPolicy.apply(to: invoice, prepaidForms: PaymentFormPolicy.decode(prepaidFormsRaw))
        return invoice
    }
}

// MARK: - Edytor pozycji

/// Wiersz edycji pojedynczej pozycji faktury.
struct InvoiceLineEditor: View {
    @Binding var line: InvoiceLineDraft
    var products: [Product] = []
    /// Waluta faktury — kwota brutto pozycji jest w tej walucie.
    var currencyCode: String = "PLN"
    /// VAT RR ma osobne stawki i wymagane pole klasy/jakości (P_6C).
    var isRR: Bool = false
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Nazwa towaru lub usługi", text: $line.name)
                    .textFieldStyle(.roundedBorder)
                if !products.isEmpty {
                    // Podstawienie towaru/usługi ze słownika — wypełnia nazwę,
                    // jednostkę, cenę, stawkę VAT i CN/PKWiU; wszystko można
                    // potem zmienić ręcznie.
                    Menu {
                        ForEach(products) { product in
                            Button("\(product.name) — \(product.basePriceNet.formatted(.currency(code: "PLN"))) netto") {
                                line.apply(product: product)
                                if isRR {
                                    line.vatRate = .rr
                                    line.ossRate = nil
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "text.book.closed")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Podstaw towar/usługę ze słownika")
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!canDelete)
                .help("Usuń pozycję")
            }
            HStack(spacing: 8) {
                TextField("Ilość", value: $line.quantity, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                TextField("J.m.", text: $line.unit)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                TextField("Cena netto", value: $line.unitNetPrice, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Picker(isRR ? "Zwrot" : "VAT", selection: $line.vatRate) {
                    ForEach(VATRate.allCases.filter { rate in
                        isRR ? (rate == .rr || rate == .rrHistorical) : (rate != .rr && rate != .rrHistorical)
                    }) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .frame(width: 110)
                .disabled(line.ossRate != nil)
                if !isRR {
                    TextField("OSS %", value: $line.ossRate, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .help("Procedura OSS (dział XII rozdz. 6a): stawka VAT państwa konsumpcji (P_12_XII). Wypełnienie zastępuje polską stawkę VAT; puste pole = zwykła pozycja.")
                }
                Spacer()
                Text(line.grossAmount, format: .currency(code: currencyCode))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if isRR {
                    TextField("Klasa / jakość", text: $line.rrQuality, prompt: Text("np. klasa I"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
                TextField("CN / PKWiU", text: $line.cnPkwiu, prompt: Text("CN / PKWiU"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .help("Kod CN (towary, same cyfry) lub PKWiU (format z kropkami)")
                if !isRR {
                    TextField("GTU", text: $line.gtu, prompt: Text("GTU"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .help("Kod GTU pozycji, np. GTU_12")
                    Picker("", selection: $line.procedure) {
                        Text("(procedura)").tag("")
                        ForEach(InvoiceLineDraft.procedures, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .help("Oznaczenie procedury pozycji (np. WSTO_EE — sprzedaż wysyłkowa OSS, IED — interfejs elektroniczny)")
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edytor bloku załącznika FA(3)

/// Edycja jednego bloku danych załącznika (element BlokDanych):
/// nagłówek, pary metadanych (wymagana co najmniej jedna — XSD),
/// akapity tekstu oraz prosta tabela wpisywana tekstowo.
struct AttachmentBlockEditor: View {
    @Binding var block: FA3AttachmentBlock
    let onDelete: () -> Void

    /// Tekstowa reprezentacja akapitów — jedna linia = jeden akapit.
    @State private var paragraphsText: String
    /// Tekstowa reprezentacja tabeli: pierwsza linia to nagłówki kolumn
    /// rozdzielone znakiem |, kolejne linie to wiersze.
    @State private var tableText: String

    init(block: Binding<FA3AttachmentBlock>, onDelete: @escaping () -> Void) {
        _block = block
        self.onDelete = onDelete
        _paragraphsText = State(initialValue: block.wrappedValue.paragraphs.joined(separator: "\n"))
        _tableText = State(initialValue: Self.serializeTable(block.wrappedValue.tables.first))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Nagłówek bloku", text: $block.header, prompt: Text("Nagłówek bloku (opcjonalny)"))
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Usuń blok załącznika")
            }

            ForEach($block.metadata) { $meta in
                HStack(spacing: 8) {
                    TextField("Klucz", text: $meta.key, prompt: Text("Klucz"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    TextField("Wartość", text: $meta.value, prompt: Text("Wartość"))
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        block.metadata.removeAll { $0.id == meta.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(block.metadata.count <= 1)
                    .help("Usuń parę metadanych")
                }
            }
            Button {
                block.metadata.append(FA3AttachmentBlock.Meta())
            } label: {
                Label("Dodaj metadane", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .font(.caption)

            TextEditor(text: $paragraphsText)
                .frame(minHeight: 44)
                .font(.body)
                .onChange(of: paragraphsText) { _, newValue in
                    block.paragraphs = newValue
                        .split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            Text("Część tekstowa: każda linia to osobny akapit (maks. 10 akapitów po 512 znaków).")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $tableText)
                .frame(minHeight: 44)
                .font(.system(.body, design: .monospaced))
                .onChange(of: tableText) { _, newValue in
                    block.tables = Self.parseTable(from: newValue).map { [$0] } ?? []
                }
            Text("Tabela (opcjonalna): pierwsza linia to nagłówki kolumn rozdzielone znakiem |, kolejne linie to wiersze (maks. 20 kolumn).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// Tabela → tekst edytora (nagłówki | ... \n wiersze | ...).
    private static func serializeTable(_ table: FA3AttachmentBlock.Table?) -> String {
        guard let table, !table.columns.isEmpty else { return "" }
        var linesText = [table.columns.joined(separator: " | ")]
        linesText += table.rows.map { $0.joined(separator: " | ") }
        return linesText.joined(separator: "\n")
    }

    /// Tekst edytora → tabela; pusty tekst = brak tabeli.
    private static func parseTable(from text: String) -> FA3AttachmentBlock.Table? {
        let rows = text
            .split(separator: "\n")
            .map { $0.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.allSatisfy(\.isEmpty) }
        guard let columns = rows.first else { return nil }
        return FA3AttachmentBlock.Table(
            columns: columns,
            rows: Array(rows.dropFirst())
        )
    }
}
