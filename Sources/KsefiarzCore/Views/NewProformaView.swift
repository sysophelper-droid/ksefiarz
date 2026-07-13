import SwiftUI
import SwiftData

/// Formularz wystawiania i edycji faktury proforma (dokument handlowy).
/// Proforma NIE idzie do KSeF — formularz nie ma trybów wysyłki/offline,
/// załączników ani danych typowo podatkowych. Zapisuje dokument lokalnie;
/// rozliczenie właściwą fakturą VAT odbywa się osobno („Konwertuj na fakturę").
public struct NewProformaView: View {

    /// Edytowana proforma (nil = nowa). Rozliczonej proformy nie edytujemy.
    private let editingProforma: Proforma?
    private let onCompleted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Dane firmy użytkownika (sprzedawca) — współdzielone z Ustawieniami.
    @AppStorage(AppSettingsKeys.sellerName) private var sellerName = ""
    @AppStorage(AppSettingsKeys.sellerAddress) private var sellerAddress = ""
    @AppStorage(AppSettingsKeys.nip) private var sellerNIP = ""
    @AppStorage(AppSettingsKeys.bankAccount) private var defaultBankAccount = ""
    @AppStorage(AppSettingsKeys.numberPatternPRO) private var numberPatternPRO = ""

    // Pola formularza.
    @State private var proformaNumber = ""
    @State private var issueDate = Date.now
    @State private var hasValidUntil = false
    @State private var validUntil = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var buyerName = ""
    @State private var buyerNIP = ""
    @State private var buyerAddress = ""
    @State private var paymentForm: PaymentForm = .transfer
    @State private var paymentBankAccount = ""
    @State private var hasDueDate = true
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var lines: [InvoiceLineDraft] = [InvoiceLineDraft()]
    @State private var notes = ""
    @State private var currency = "PLN"
    @State private var exchangeRate = 0.0
    @State private var isPaid = false
    @State private var isFetchingRate = false
    @State private var nbpRateInfo: String?
    @State private var validationErrors: [ProformaValidationError] = []

    /// Waluty do wyboru (jak na fakturze).
    private static let currencies = ["PLN", "EUR", "USD", "GBP", "CHF", "CZK", "SEK", "NOK", "DKK"]

    @Query(sort: \Contractor.name) private var dictionaryContractors: [Contractor]
    @Query(sort: \Product.name) private var dictionaryProducts: [Product]
    @Query(sort: \BankAccount.label) private var dictionaryAccounts: [BankAccount]

    public init(editing: Proforma? = nil, onCompleted: (() -> Void)? = nil) {
        self.editingProforma = editing
        self.onCompleted = onCompleted
    }

    private var totalNet: Double { lines.reduce(0) { $0 + $1.netAmount } }
    private var totalVat: Double { lines.reduce(0) { $0 + $1.vatAmount } }
    private var totalGross: Double { totalNet + totalVat }

    /// Szkic proformy zbudowany z bieżących pól formularza.
    private var draft: ProformaDraft {
        ProformaDraft(
            proformaNumber: proformaNumber,
            issueDate: issueDate,
            validUntil: hasValidUntil ? validUntil : nil,
            sellerName: sellerName,
            sellerNIP: sellerNIP,
            sellerAddress: sellerAddress,
            buyerName: buyerName,
            buyerNIP: buyerNIP,
            buyerAddress: buyerAddress,
            lines: lines,
            paymentDueDate: hasDueDate ? dueDate : nil,
            paymentForm: paymentForm,
            paymentBankAccount: paymentBankAccount,
            notes: notes,
            currency: currency,
            exchangeRate: exchangeRate,
            isPaid: isPaid
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Dane proformy") {
                    TextField("Numer proformy", text: $proformaNumber, prompt: Text("np. PF/2026/07/001"))
                    DatePicker("Data wystawienia", selection: $issueDate, displayedComponents: .date)
                    Toggle("Ważna do (termin oferty)", isOn: $hasValidUntil)
                    if hasValidUntil {
                        DatePicker("Ważna do", selection: $validUntil, displayedComponents: .date)
                    }
                    Picker("Waluta", selection: $currency) {
                        ForEach(Self.currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    if currency != "PLN" {
                        HStack {
                            TextField(
                                "Kurs PLN (informacyjnie)",
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
                            .help("Pobierz kurs średni NBP z ostatniego dnia roboczego przed datą wystawienia. Kurs można też wpisać ręcznie.")
                        }
                        if let nbpRateInfo {
                            Text(nbpRateInfo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Sprzedawca (Twoja firma)") {
                    TextField("Nazwa firmy", text: $sellerName)
                    TextField("NIP", text: $sellerNIP)
                    TextField("Adres", text: $sellerAddress, prompt: Text("ul. Przykładowa 1, 00-001 Warszawa"))
                }

                Section("Nabywca") {
                    let recipients = dictionaryContractors.filter { $0.isRecipient }
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
                    TextField("Nazwa nabywcy", text: $buyerName)
                    TextField("NIP nabywcy", text: $buyerNIP, prompt: Text("opcjonalnie (konsument bez NIP)"))
                    TextField("Adres nabywcy", text: $buyerAddress, prompt: Text("opcjonalnie"))
                }

                Section("Pozycje") {
                    ForEach($lines) { $line in
                        ProformaLineEditor(
                            line: $line,
                            products: dictionaryProducts,
                            currencyCode: currency,
                            canDelete: lines.count > 1
                        ) {
                            lines.removeAll { $0.id == line.id }
                        }
                    }
                    Button {
                        lines.append(InvoiceLineDraft())
                    } label: {
                        Label("Dodaj pozycję", systemImage: "plus.circle")
                    }
                }

                Section("Uwagi") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 56)
                        .font(.body)
                    Text("Dopisek drukowany na proformie — np. warunki oferty, termin realizacji.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Podsumowanie") {
                    LabeledContent("Razem netto") {
                        Text(totalNet, format: .currency(code: currency)).monospacedDigit()
                    }
                    LabeledContent("Razem VAT") {
                        Text(totalVat, format: .currency(code: currency)).monospacedDigit()
                    }
                    LabeledContent("Do zapłaty (brutto)") {
                        Text(totalGross, format: .currency(code: currency))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                }

                Section("Płatność") {
                    Picker("Forma płatności", selection: $paymentForm) {
                        ForEach(PaymentForm.allCases) { form in
                            Text(form.displayName).tag(form)
                        }
                    }
                    HStack {
                        TextField("Numer rachunku bankowego", text: $paymentBankAccount, prompt: Text("26 cyfr (NRB)"))
                        if !dictionaryAccounts.isEmpty {
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
                    Toggle("Proforma opłacona (np. wpłacona zaliczka)", isOn: $isPaid)
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
                    .fixedSize()
                Spacer(minLength: 12)
                Button {
                    save()
                } label: {
                    Text(editingProforma == nil ? "Wystaw proformę" : "Zapisz zmiany")
                }
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(editingProforma == nil ? "Nowa proforma" : "Edycja proformy")
        .frame(minWidth: 780, minHeight: 640)
        .onAppear {
            prefillFromEditedProforma()
            if paymentBankAccount.isEmpty { paymentBankAccount = defaultBankAccount }
            prefillProformaNumber()
        }
    }

    // MARK: Akcje

    /// Pobiera kurs średni NBP z dnia poprzedzającego datę wystawienia.
    @MainActor
    private func fetchNBPRate() async {
        isFetchingRate = true
        defer { isFetchingRate = false }
        let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: issueDate) ?? issueDate
        do {
            let rate = try await NBPExchangeRateService().midRate(currency: currency, onOrBefore: dayBefore)
            exchangeRate = rate.mid
            nbpRateInfo = "Kurs NBP z \(rate.effectiveDate) (tabela \(rate.tableNumber))."
        } catch {
            nbpRateInfo = error.localizedDescription
        }
    }

    private func prefillFromEditedProforma() {
        guard let editing = editingProforma, proformaNumber.isEmpty else { return }
        proformaNumber = editing.proformaNumber
        issueDate = editing.issueDate
        if let validUntil = editing.validUntil {
            hasValidUntil = true
            self.validUntil = validUntil
        }
        buyerName = editing.buyerName
        buyerNIP = editing.buyerNIP
        buyerAddress = editing.buyerAddress
        paymentForm = editing.paymentForm ?? .transfer
        paymentBankAccount = editing.paymentBankAccount ?? defaultBankAccount
        if let due = editing.paymentDueDate {
            hasDueDate = true
            dueDate = due
        } else {
            hasDueDate = false
        }
        notes = editing.notes
        currency = editing.currency
        exchangeRate = editing.exchangeRate
        isPaid = editing.isPaid
        let storedLines = editing.sortedLines.map { line in
            InvoiceLineDraft(
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                vatRate: VATRate(rawValue: line.vatRate) ?? .standard,
                cnPkwiu: line.cnPkwiu
            )
        }
        if !storedLines.isEmpty { lines = storedLines }
    }

    /// Wzorzec numeracji proform (pusty → domyślny „PF/…").
    private var proformaPattern: String {
        let trimmed = numberPatternPRO.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? InvoiceNumberGenerator.defaultProformaPattern : trimmed
    }

    /// Proponuje kolejny numer proformy w obrębie istniejącej serii.
    private func prefillProformaNumber() {
        guard proformaNumber.isEmpty else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<Proforma>()))?
            .map(\.proformaNumber) ?? []
        proformaNumber = InvoiceNumberGenerator.nextNumber(
            pattern: proformaPattern,
            existing: existing,
            date: issueDate
        )
    }

    /// Znormalizowane numery proform z bazy, bez dokumentu edytowanego.
    private func existingNumbers() -> Set<String> {
        let all = (try? modelContext.fetch(FetchDescriptor<Proforma>())) ?? []
        return Set(
            all.filter { $0.id != editingProforma?.id }
                .map { InvoiceValidator.normalizedNumber($0.proformaNumber) }
        )
    }

    private func validate() -> Bool {
        validationErrors = ProformaValidator.validate(draft, existingNumbers: existingNumbers())
        return validationErrors.isEmpty
    }

    /// Zapisuje proformę: aktualizuje edytowaną albo tworzy nową.
    private func save() {
        guard validate() else { return }
        if let editing = editingProforma {
            update(editing)
        } else {
            insert()
        }
        try? modelContext.save()
        onCompleted?()
        dismiss()
    }

    private func applyScalars(to proforma: Proforma) {
        proforma.proformaNumber = draft.proformaNumber
        proforma.issueDate = draft.issueDate
        proforma.validUntil = draft.validUntil
        proforma.sellerName = draft.sellerName
        proforma.sellerNIP = draft.sellerNIP
        proforma.sellerAddress = draft.sellerAddress
        proforma.buyerName = draft.buyerName
        proforma.buyerNIP = draft.buyerNIP.trimmingCharacters(in: .whitespaces)
        proforma.buyerAddress = draft.buyerAddress
        proforma.netAmount = draft.netAmount
        proforma.vatAmount = draft.vatAmount
        proforma.grossAmount = draft.grossAmount
        proforma.currency = draft.currency
        proforma.exchangeRate = draft.exchangeRate
        proforma.isPaid = draft.isPaid
        proforma.paymentDueDate = draft.paymentDueDate
        proforma.paymentForm = draft.paymentForm
        proforma.paymentBankAccount = draft.paymentBankAccount.isEmpty ? nil : draft.paymentBankAccount
        proforma.notes = draft.notes
    }

    private func makeLines() -> [ProformaLine] {
        draft.lines.enumerated().map { offset, line in
            ProformaLine(
                index: offset + 1,
                name: line.name,
                unit: line.unit,
                quantity: line.quantity,
                unitNetPrice: line.unitNetPrice,
                netAmount: line.netAmount,
                vatRate: line.vatRate.rawValue,
                vatAmount: line.vatAmount,
                cnPkwiu: line.cnPkwiu
            )
        }
    }

    private func insert() {
        let proforma = Proforma(
            proformaNumber: draft.proformaNumber,
            issueDate: draft.issueDate,
            validUntil: draft.validUntil,
            sellerName: draft.sellerName,
            sellerNIP: draft.sellerNIP,
            sellerAddress: draft.sellerAddress,
            buyerName: draft.buyerName,
            buyerNIP: draft.buyerNIP.trimmingCharacters(in: .whitespaces),
            buyerAddress: draft.buyerAddress,
            netAmount: draft.netAmount,
            vatAmount: draft.vatAmount,
            grossAmount: draft.grossAmount,
            currency: draft.currency,
            exchangeRate: draft.exchangeRate,
            isPaid: draft.isPaid,
            paymentDueDate: draft.paymentDueDate,
            paymentForm: draft.paymentForm,
            paymentBankAccount: draft.paymentBankAccount.isEmpty ? nil : draft.paymentBankAccount,
            notes: draft.notes
        )
        modelContext.insert(proforma)
        // Pozycje przypisywane po wstawieniu do kontekstu (relacja SwiftData).
        proforma.lines = makeLines()
    }

    private func update(_ proforma: Proforma) {
        applyScalars(to: proforma)
        proforma.lines = makeLines()
    }
}

// MARK: - Edytor pozycji proformy

/// Lekki wiersz edycji pozycji proformy (bez pól podatkowych GTU/OSS/procedur).
struct ProformaLineEditor: View {
    @Binding var line: InvoiceLineDraft
    var products: [Product] = []
    var currencyCode: String = "PLN"
    let canDelete: Bool
    let onDelete: () -> Void

    /// Stawki VAT dostępne na proformie (bez stawek zryczałtowanego zwrotu RR).
    private var vatRates: [VATRate] {
        VATRate.allCases.filter { $0 != .rr && $0 != .rrHistorical }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Nazwa towaru lub usługi", text: $line.name)
                    .textFieldStyle(.roundedBorder)
                if !products.isEmpty {
                    Menu {
                        ForEach(products) { product in
                            Button("\(product.name) — \(product.basePriceNet.formatted(.currency(code: "PLN"))) netto") {
                                line.apply(product: product)
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
                Picker("VAT", selection: $line.vatRate) {
                    ForEach(vatRates) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .frame(width: 110)
                TextField("CN / PKWiU", text: $line.cnPkwiu, prompt: Text("opcjonalnie"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Spacer()
                Text(line.grossAmount, format: .currency(code: currencyCode))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
