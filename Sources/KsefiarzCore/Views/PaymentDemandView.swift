import SwiftUI
import SwiftData

/// Wezwanie do zapłaty / nota odsetkowa: wybór dłużnika z zaległymi
/// fakturami sprzedażowymi (kandydaci ze struktury wiekowej), naliczenie
/// odsetek według konfigurowalnej stopy rocznej, PDF do zapisu albo
/// wysyłki e-mailem (adresat ze słownika kontrahentów).
public struct PaymentDemandView: View {

    /// NIP dłużnika zaznaczonego na starcie (np. z menu listy sprzedaży).
    private let preselectedBuyerNIP: String?

    @Query private var unpaidSales: [Invoice]
    @Query private var contractors: [Contractor]
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKeys.sellerName) private var sellerName = ""
    @AppStorage(AppSettingsKeys.sellerAddress) private var sellerAddress = ""
    @AppStorage(AppSettingsKeys.nip) private var sellerNIP = ""
    @AppStorage(AppSettingsKeys.bankAccount) private var defaultBankAccount = ""
    /// Odsetki ustawowe za opóźnienie w transakcjach handlowych — stopa
    /// zmienia się co pół roku (obwieszczenia MF); wartość edytowalna.
    @AppStorage(AppSettingsKeys.demandInterestRate) private var interestRate = 13.0
    @AppStorage(AppSettingsKeys.demandPaymentDays) private var paymentDays = 7

    @State private var selectedBuyerNIP = ""
    @State private var selectedInvoiceIDs = Set<UUID>()
    @State private var kind: PaymentDemandKind = .demand
    @State private var documentNumber = ""
    @State private var errorMessage: String?
    @State private var prefilled = false

    public init(preselectedBuyerNIP: String? = nil) {
        self.preselectedBuyerNIP = preselectedBuyerNIP
        // Nieopłacone, widoczne faktury sprzedażowe — zaległość (termin)
        // filtrowana w widoku, bo #Predicate nie zna daty bieżącej.
        let salesRaw = Invoice.Kind.sales.rawValue
        _unpaidSales = Query(
            filter: #Predicate<Invoice> { invoice in
                invoice.kindRaw == salesRaw
                    && invoice.isPaid == false
                    && invoice.isArchivedOrHidden == false
            },
            sort: [SortDescriptor(\Invoice.paymentDueDate)]
        )
    }

    /// Dłużnicy z co najmniej jedną zaległą fakturą (saldo > 0).
    private var debtors: [(nip: String, name: String)] {
        var seen = Set<String>()
        return overdueInvoices.compactMap { invoice in
            guard seen.insert(invoice.buyerNIP).inserted else { return nil }
            return (invoice.buyerNIP, invoice.buyerName)
        }
        .sorted { $0.name < $1.name }
    }

    private var overdueInvoices: [Invoice] {
        unpaidSales.filter { $0.isOverdue && $0.outstandingAmount > 0 }
    }

    private var debtorInvoices: [Invoice] {
        overdueInvoices.filter { $0.buyerNIP == selectedBuyerNIP }
    }

    private var selectedInvoices: [Invoice] {
        debtorInvoices.filter { selectedInvoiceIDs.contains($0.id) }
    }

    private var items: [PaymentDemandItem] {
        PaymentDemandEngine.items(for: selectedInvoices, annualRatePercent: interestRate)
    }

    private var document: PaymentDemandDocument {
        let debtor = debtorInvoices.first
        return PaymentDemandDocument(
            kind: kind,
            number: documentNumber,
            sellerName: sellerName,
            sellerAddress: sellerAddress,
            sellerNIP: sellerNIP,
            bankAccount: defaultBankAccount,
            buyerName: debtor?.buyerName ?? "",
            buyerNIP: selectedBuyerNIP,
            buyerAddress: debtor?.buyerAddress ?? "",
            items: items,
            annualRatePercent: interestRate,
            paymentDays: paymentDays
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            if debtors.isEmpty {
                ContentUnavailableView(
                    "Brak zaległych należności",
                    systemImage: "checkmark.seal",
                    description: Text("Żadna faktura sprzedażowa nie jest po terminie płatności.")
                )
                .frame(minHeight: 300)
            } else {
                form
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 640, minHeight: 540)
        .navigationTitle("Wezwanie do zapłaty")
        .onAppear { prefillIfNeeded() }
        .alert(
            "Nie udało się przygotować dokumentu",
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

    private var form: some View {
        Form {
            Section("Dokument") {
                Picker("Rodzaj", selection: $kind) {
                    ForEach(PaymentDemandKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                TextField("Numer dokumentu", text: $documentNumber, prompt: Text("opcjonalny, np. WZ/1/2026"))
                Picker("Dłużnik", selection: $selectedBuyerNIP) {
                    ForEach(debtors, id: \.nip) { debtor in
                        Text("\(debtor.name) (\(debtor.nip.isEmpty ? "bez NIP" : debtor.nip))")
                            .tag(debtor.nip)
                    }
                }
                TextField("Stopa odsetek rocznych (%)", value: $interestRate, format: .number)
                    .help("Odsetki ustawowe za opóźnienie w transakcjach handlowych: stopa referencyjna NBP + 8 p.p. — sprawdź aktualne obwieszczenie MF.")
                if kind == .demand {
                    TextField("Termin zapłaty (dni od otrzymania)", value: $paymentDays, format: .number)
                }
            }
            Section("Zaległe faktury dłużnika") {
                ForEach(debtorInvoices) { invoice in
                    Toggle(isOn: Binding(
                        get: { selectedInvoiceIDs.contains(invoice.id) },
                        set: { included in
                            if included {
                                selectedInvoiceIDs.insert(invoice.id)
                            } else {
                                selectedInvoiceIDs.remove(invoice.id)
                            }
                        }
                    )) {
                        HStack {
                            Text(invoice.invoiceNumber)
                            Spacer()
                            if let due = invoice.paymentDueDate {
                                Text("termin: \(due, format: .dateTime.day().month().year())")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                            Text(invoice.outstandingAmount, format: .currency(code: invoice.currency))
                                .monospacedDigit()
                        }
                    }
                }
            }
            if !items.isEmpty {
                Section("Podsumowanie") {
                    ForEach(PaymentDemandEngine.totals(of: items), id: \.currency) { total in
                        LabeledContent("Należność główna (\(total.currency))") {
                            Text(total.outstanding, format: .currency(code: total.currency)).monospacedDigit()
                        }
                        LabeledContent("Odsetki na dziś (\(total.currency))") {
                            Text(total.interest, format: .currency(code: total.currency)).monospacedDigit()
                        }
                        LabeledContent("Razem (\(total.currency))") {
                            Text(
                                kind == .demand ? total.outstanding + total.interest : total.interest,
                                format: .currency(code: total.currency)
                            )
                            .monospacedDigit()
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: selectedBuyerNIP) { _, _ in
            selectedInvoiceIDs = Set(debtorInvoices.map(\.id))
        }
    }

    private var bottomBar: some View {
        HStack {
            Text("Kandydatów podpowiada struktura wiekowa Kokpitu — dokument obejmuje zaznaczone faktury po terminie.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Anuluj") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                savePDF()
            } label: {
                Label("Zapisz PDF", systemImage: "square.and.arrow.down")
            }
            .disabled(items.isEmpty || sellerName.isEmpty)
            Button {
                sendByEmail()
            } label: {
                Label("Wyślij e-mailem", systemImage: "envelope")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(items.isEmpty || sellerName.isEmpty)
        }
        .padding()
    }

    private func prefillIfNeeded() {
        guard !prefilled else { return }
        prefilled = true
        selectedBuyerNIP = preselectedBuyerNIP ?? debtors.first?.nip ?? ""
        selectedInvoiceIDs = Set(debtorInvoices.map(\.id))
    }

    private var suggestedFileName: String {
        let prefix = kind == .demand ? "Wezwanie" : "Nota_odsetkowa"
        let debtor = (debtorInvoices.first?.buyerName ?? "dluznik")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        return "\(prefix)_\(debtor)_\(FA2Format.dateFormatter.string(from: .now)).pdf"
    }

    private func savePDF() {
        guard let pdf = PaymentDemandPDFGenerator.pdfData(for: document) else {
            errorMessage = "Nie udało się wygenerować dokumentu PDF."
            return
        }
        if FileExportService.exportData(pdf, suggestedName: suggestedFileName, contentType: .pdf) {
            dismiss()
        }
    }

    private func sendByEmail() {
        guard let pdf = PaymentDemandPDFGenerator.pdfData(for: document) else {
            errorMessage = "Nie udało się wygenerować dokumentu PDF."
            return
        }
        // Adresat jak przy wysyłce faktur: adres fakturowy ze słownika,
        // w drugiej kolejności ogólny (dopasowanie po NIP dłużnika).
        let buyerNIP = selectedBuyerNIP.filter(\.isNumber)
        let matching = contractors.filter { $0.nip.filter(\.isNumber) == buyerNIP && !buyerNIP.isEmpty }
        let recipient = matching.first(where: { !$0.invoiceEmail.isEmpty })?.invoiceEmail
            ?? matching.first(where: { !$0.email.isEmpty })?.email
            ?? ""
        let subject = "\(kind.displayName) — \(sellerName)"
        let body = kind == .demand
            ? "Dzień dobry,\n\nw załączeniu przekazujemy wezwanie do zapłaty zaległych należności wraz z naliczonymi odsetkami. Prosimy o uregulowanie płatności w terminie \(paymentDays) dni.\n\nPozdrawiamy\n\(sellerName)"
            : "Dzień dobry,\n\nw załączeniu przekazujemy notę odsetkową z tytułu opóźnienia w zapłacie faktur.\n\nPozdrawiamy\n\(sellerName)"
        do {
            try InvoiceEmailService.composeDocument(
                recipient: recipient,
                subject: subject,
                body: body,
                attachmentName: suggestedFileName,
                attachmentData: pdf
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
