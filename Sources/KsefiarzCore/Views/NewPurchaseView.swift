import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Formularz faktury kosztowej spoza KSeF — ręczne dodawanie zakupów
/// (faktury zagraniczne, paragony z NIP) dla pełnego obrazu VAT
/// i przepływów. Dokument istnieje wyłącznie lokalnie (bez XML i numeru
/// KSeF), więc pozostaje edytowalny i usuwalny.
public struct NewPurchaseView: View {

    /// Edytowany zakup — wyłącznie ręczny (spoza KSeF).
    private let editingInvoice: Invoice?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Dane firmy użytkownika (nabywca zakupów) — z Ustawień.
    @AppStorage(AppSettingsKeys.sellerName) private var myCompanyName = ""
    @AppStorage(AppSettingsKeys.nip) private var myNIP = ""

    // Pola formularza.
    @State private var documentNumber = ""
    @State private var issueDate = Date.now
    @State private var hasSaleDate = false
    @State private var saleDate = Date.now
    @State private var sellerName = ""
    @State private var sellerTaxID = ""
    @State private var sellerAddress = ""
    @State private var netAmount = 0.0
    @State private var vatAmount = 0.0
    @State private var currency = "PLN"
    @State private var exchangeRate = 0.0
    @State private var paymentForm: PaymentForm = .transfer
    @State private var paymentBankAccount = ""
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var isPaid = false
    @State private var paymentDate = Date.now
    @State private var costCategory = ""
    @State private var notes = ""

    @State private var validationErrors: [ManualPurchaseValidationError] = []
    @State private var isFetchingRate = false
    @State private var nbpRateInfo: String?
    @State private var prefilled = false
    // OCR skanu/PDF (macOS Vision) — wstępne wypełnienie pól formularza.
    @State private var isRecognizingScan = false
    @State private var ocrSummary: String?
    @State private var ocrError: String?
    /// Kategorie użyte na dotychczasowych zakupach — do podpowiedzi.
    @State private var usedCategories: [String] = []

    /// Waluty do wyboru — jak w formularzu sprzedaży.
    private static let currencies = ["PLN", "EUR", "USD", "GBP", "CHF", "CZK", "SEK", "NOK", "DKK"]

    // Słownik kontrahentów (dostawcy) — dane tylko podstawiane do pól.
    @Query(sort: \Contractor.name) private var dictionaryContractors: [Contractor]

    public init(editing: Invoice? = nil) {
        self.editingInvoice = editing
    }

    private var grossAmount: Double {
        ((netAmount + vatAmount) * 100).rounded() / 100
    }

    /// Szkic zbudowany z bieżących pól formularza.
    private var draft: ManualPurchaseDraft {
        ManualPurchaseDraft(
            documentNumber: documentNumber,
            issueDate: issueDate,
            saleDate: hasSaleDate ? saleDate : nil,
            sellerName: sellerName,
            sellerTaxID: sellerTaxID,
            sellerAddress: sellerAddress,
            buyerName: myCompanyName,
            buyerNIP: myNIP,
            netAmount: netAmount,
            vatAmount: vatAmount,
            currency: currency,
            exchangeRate: exchangeRate,
            paymentDueDate: hasDueDate ? dueDate : nil,
            paymentForm: paymentForm,
            paymentBankAccount: paymentBankAccount,
            costCategory: costCategory,
            notes: notes,
            isPaid: isPaid,
            paymentDate: isPaid ? paymentDate : nil
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                ocrSection

                Section("Dokument") {
                    TextField("Numer dokumentu", text: $documentNumber,
                              prompt: Text("np. numer faktury albo paragonu z NIP"))
                    DatePicker("Data wystawienia", selection: $issueDate, displayedComponents: .date)
                    Toggle("Data sprzedaży / wykonania usługi", isOn: $hasSaleDate)
                    if hasSaleDate {
                        DatePicker("Data", selection: $saleDate, displayedComponents: .date)
                    }
                    categoryField
                    Picker("Waluta", selection: $currency) {
                        ForEach(Self.currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    if currency != "PLN" {
                        HStack {
                            TextField(
                                "Kurs PLN (do przeliczeń i JPK)",
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
                            .help("Pobierz kurs średni NBP z ostatniego dnia roboczego przed datą wystawienia/sprzedaży. Kurs można też wpisać ręcznie.")
                        }
                        if let nbpRateInfo {
                            Text(nbpRateInfo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Sprzedawca") {
                    let suppliers = dictionaryContractors.filter(\.isSupplier)
                    if !suppliers.isEmpty {
                        Menu {
                            ForEach(suppliers) { contractor in
                                Button("\(contractor.displayName) (NIP: \(contractor.nip))") {
                                    sellerName = contractor.displayName
                                    sellerTaxID = contractor.uePrefix.isEmpty
                                        ? contractor.nip
                                        : contractor.uePrefix + contractor.nip
                                    sellerAddress = contractor.invoiceAddress
                                }
                            }
                        } label: {
                            Label("Wybierz ze słownika kontrahentów", systemImage: "text.book.closed")
                        }
                    }
                    TextField("Nazwa sprzedawcy", text: $sellerName)
                    TextField("NIP / VAT ID", text: $sellerTaxID,
                              prompt: Text("np. 1234567890 albo DE123456789 (może być puste)"))
                    TextField("Adres", text: $sellerAddress, prompt: Text("opcjonalnie"))
                }

                Section("Kwoty") {
                    TextField("Netto", value: $netAmount,
                              format: .number.precision(.fractionLength(2)))
                    TextField("VAT", value: $vatAmount,
                              format: .number.precision(.fractionLength(2)))
                    LabeledContent("Brutto (netto + VAT)") {
                        Text(grossAmount, format: .currency(code: currency))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    if currency != "PLN", exchangeRate > 0 {
                        LabeledContent("Brutto w PLN (kurs \(exchangeRate.formatted(.number.precision(.fractionLength(4)))))") {
                            Text(grossAmount * exchangeRate, format: .currency(code: "PLN"))
                                .monospacedDigit()
                        }
                    }
                    Text("Faktura zagraniczna bez polskiego VAT: wpisz VAT = 0 (całość w polu Netto).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Płatność") {
                    Picker("Forma płatności", selection: $paymentForm) {
                        ForEach(PaymentForm.allCases) { form in
                            Text(form.displayName).tag(form)
                        }
                    }
                    TextField("Numer rachunku do przelewu", text: $paymentBankAccount,
                              prompt: Text("opcjonalnie"))
                    Toggle("Termin płatności", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Termin", selection: $dueDate, displayedComponents: .date)
                    }
                    Toggle("Opłacona", isOn: $isPaid)
                    if isPaid {
                        DatePicker("Data zapłaty", selection: $paymentDate, displayedComponents: .date)
                    }
                }

                Section("Uwagi") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 56)
                        .font(.body)
                }

                if !validationErrors.isEmpty {
                    Section {
                        ForEach(validationErrors, id: \.self) { error in
                            Label(error.errorDescription ?? "", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Anuluj", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Dokument spoza KSeF — zapis wyłącznie lokalny.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(editingInvoice == nil ? "Dodaj zakup" : "Zapisz zmiany") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(editingInvoice == nil ? "Faktura kosztowa (spoza KSeF)" : "Edycja zakupu")
        .frame(minWidth: 560, minHeight: 620)
        .onAppear {
            prefillIfNeeded()
            loadUsedCategories()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            recognizeScan(at: url)
            return true
        }
    }

    /// Sekcja OCR — wczytanie skanu/PDF papierowej faktury i wstępne
    /// wypełnienie pól (macOS Vision, przetwarzanie w całości lokalne).
    private var ocrSection: some View {
        Section {
            HStack {
                Button {
                    guard let url = FileExportService.importFileURL(
                        allowedTypes: [.pdf, .png, .jpeg, .tiff, .heic],
                        message: "Wybierz PDF albo zdjęcie/skan faktury kosztowej"
                    ) else { return }
                    recognizeScan(at: url)
                } label: {
                    if isRecognizingScan {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Rozpoznawanie…")
                        }
                    } else {
                        Label("Wczytaj ze skanu / PDF (OCR)", systemImage: "doc.viewfinder")
                    }
                }
                .disabled(isRecognizingScan)
                .help("Rozpoznaje dane z papierowej faktury (PDF, PNG, JPEG, TIFF, HEIC) i wstępnie wypełnia formularz. Plik można też upuścić na okno. Przetwarzanie odbywa się lokalnie (macOS Vision).")
                Spacer()
                Text("Rozpoznane dane zweryfikuj przed zapisem.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let ocrSummary {
                Label(ocrSummary, systemImage: "text.viewfinder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let ocrError {
                Label(ocrError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Uruchamia OCR pliku i nanosi rozpoznane pola na formularz.
    private func recognizeScan(at url: URL) {
        guard !isRecognizingScan else { return }
        isRecognizingScan = true
        ocrSummary = nil
        ocrError = nil
        Task { @MainActor in
            defer { isRecognizingScan = false }
            do {
                let lines = try await InvoiceOCRService.recognizeTextLines(at: url)
                let extraction = InvoiceOCRParser.parse(lines: lines, ownNIP: myNIP)
                apply(extraction)
            } catch {
                ocrError = error.localizedDescription
            }
        }
    }

    /// Nanosi rozpoznane pola na stan formularza — tylko pola rozpoznane;
    /// reszta (nabywca, status opłacenia, uwagi, kategoria) bez zmian.
    private func apply(_ extraction: InvoiceOCRExtraction) {
        guard !extraction.isEmpty else {
            ocrError = "Nie rozpoznano żadnych pól faktury — uzupełnij dane ręcznie."
            return
        }
        let current = draft
        var merged = extraction.applied(to: current)
        // Zmiana waluty unieważnia kurs — dotyczył poprzedniej waluty.
        if merged.currency != current.currency {
            merged.exchangeRate = 0
            nbpRateInfo = nil
        }
        fill(from: merged)
        ocrSummary = "Rozpoznano: \(extraction.recognizedFieldNames.joined(separator: ", "))."
    }

    /// Pole kategorii kosztu z podpowiedziami (użyte + typowe).
    private var categoryField: some View {
        HStack {
            TextField("Kategoria kosztu", text: $costCategory,
                      prompt: Text("np. Paliwo i transport"))
            Menu {
                if !usedCategories.isEmpty {
                    Section("Użyte") {
                        ForEach(usedCategories, id: \.self) { category in
                            Button(category) { costCategory = category }
                        }
                    }
                }
                Section("Typowe") {
                    ForEach(CostCategories.suggestions, id: \.self) { category in
                        Button(category) { costCategory = category }
                    }
                }
            } label: {
                Image(systemName: "tag")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Podstaw kategorię z listy — grupuje koszty w raportach")
        }
    }

    /// Kategorie użyte na dotychczasowych zakupach.
    private func loadUsedCategories() {
        let purchaseRaw = Invoice.Kind.purchase.rawValue
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate { $0.kindRaw == purchaseRaw }
        )
        usedCategories = CostCategories.used(in: (try? modelContext.fetch(descriptor)) ?? [])
    }

    /// Przy edycji wypełnia formularz danymi zapisanego zakupu.
    private func prefillIfNeeded() {
        guard !prefilled else { return }
        prefilled = true
        guard let editing = editingInvoice else { return }
        fill(from: ManualPurchaseDraft(from: editing))
    }

    /// Wypełnia pola formularza wartościami szkicu — wspólne dla prefillu
    /// edycji i wyniku OCR.
    private func fill(from draft: ManualPurchaseDraft) {
        documentNumber = draft.documentNumber
        issueDate = draft.issueDate
        if let sale = draft.saleDate { hasSaleDate = true; saleDate = sale }
        sellerName = draft.sellerName
        sellerTaxID = draft.sellerTaxID
        sellerAddress = draft.sellerAddress
        netAmount = draft.netAmount
        vatAmount = draft.vatAmount
        currency = draft.currency
        exchangeRate = draft.exchangeRate
        if let due = draft.paymentDueDate { hasDueDate = true; dueDate = due }
        paymentForm = draft.paymentForm ?? .transfer
        paymentBankAccount = draft.paymentBankAccount
        costCategory = draft.costCategory
        notes = draft.notes
        isPaid = draft.isPaid
        if let paid = draft.paymentDate { paymentDate = paid }
    }

    /// Pobiera kurs średni NBP z dnia poprzedzającego datę sprzedaży
    /// (lub wystawienia) — jak w formularzu sprzedaży.
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

    /// Waliduje i zapisuje zakup (nowy albo edytowany).
    private func save() {
        let draft = draft
        validationErrors = draft.validate()
        guard validationErrors.isEmpty else { return }
        if let editing = editingInvoice {
            draft.apply(to: editing)
        } else {
            modelContext.insert(draft.makeInvoice())
        }
        try? modelContext.save()
        dismiss()
    }
}
