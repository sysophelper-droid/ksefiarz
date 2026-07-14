import SwiftUI
import SwiftData
import AppKit

/// Windykacja należności: wybór dłużnika z zaległymi fakturami
/// sprzedażowymi (kandydaci ze struktury wiekowej) i dokument ścieżki
/// eskalacji — przypomnienie o płatności, wezwanie do zapłaty (odsetki
/// według konfigurowalnej stopy rocznej), nota odsetkowa albo dane do
/// pozwu EPU (e-sąd). PDF do zapisu lub wysyłki e-mailem (adresat ze
/// słownika kontrahentów); utworzenie dokumentu jest odnotowywane na
/// fakturach i buduje status windykacji.
public struct PaymentDemandView: View {

    /// NIP dłużnika zaznaczonego na starcie (np. z menu listy sprzedaży).
    private let preselectedBuyerNIP: String?

    @Query private var unpaidSales: [Invoice]
    @Query private var contractors: [Contractor]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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
    @State private var infoMessage: String?
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
        // Przypomnienie i dane EPU nie naliczają kwoty odsetek.
        PaymentDemandEngine.items(
            for: selectedInvoices,
            annualRatePercent: kind.includesInterest ? interestRate : 0
        )
    }

    /// Najdalej posunięta sugestia eskalacji dla faktur dłużnika.
    private var suggestion: DebtCollectionSuggestion? {
        debtorInvoices
            .compactMap { DebtCollectionEngine.suggestion(for: $0) }
            .max { $0.action.stage < $1.action.stage }
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

    // MARK: Dane do pozwu EPU

    private var epuParties: DebtCollectionEngine.EPUParties {
        let debtor = debtorInvoices.first
        return DebtCollectionEngine.EPUParties(
            claimantName: sellerName,
            claimantNIP: sellerNIP,
            claimantAddress: sellerAddress,
            claimantBankAccount: defaultBankAccount,
            defendantName: debtor?.buyerName ?? "",
            defendantNIP: selectedBuyerNIP,
            defendantAddress: debtor?.buyerAddress ?? ""
        )
    }

    private var epuEligibility: (
        eligible: [PaymentDemandItem],
        omissions: [(invoiceNumber: String, reason: String)]
    ) {
        DebtCollectionEngine.epuEligibleItems(from: items)
    }

    /// Data ostatniego wezwania wśród zaznaczonych faktur (dowód w pozwie).
    private var latestDemandDate: Date? {
        selectedInvoices.compactMap(\.collectionDemandAt).max()
    }

    private var epuWarnings: [String] {
        DebtCollectionEngine.epuWarnings(
            parties: epuParties,
            items: epuEligibility.eligible,
            demandSentAt: latestDemandDate
        )
    }

    private var epuText: String {
        let eligibility = epuEligibility
        return DebtCollectionEngine.epuText(
            parties: epuParties,
            items: eligibility.eligible,
            demandSentAt: latestDemandDate,
            omissions: eligibility.omissions
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
        .navigationTitle("Windykacja należności")
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
        .alert(
            "Gotowe",
            isPresented: Binding(
                get: { infoMessage != nil },
                set: { if !$0 { infoMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
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
                if kind != .epu {
                    TextField("Numer dokumentu", text: $documentNumber, prompt: Text("opcjonalny, np. WZ/1/2026"))
                }
                Picker("Dłużnik", selection: $selectedBuyerNIP) {
                    ForEach(debtors, id: \.nip) { debtor in
                        Text("\(debtor.name) (\(debtor.nip.isEmpty ? "bez NIP" : debtor.nip))")
                            .tag(debtor.nip)
                    }
                }
                if kind.includesInterest {
                    TextField("Stopa odsetek rocznych (%)", value: $interestRate, format: .number)
                        .help("Odsetki ustawowe za opóźnienie w transakcjach handlowych: stopa referencyjna NBP + 8 p.p. — sprawdź aktualne obwieszczenie MF.")
                }
                if kind == .demand {
                    TextField("Termin zapłaty (dni od otrzymania)", value: $paymentDays, format: .number)
                }
                if let suggestion {
                    Label {
                        Text("Sugerowany krok: \(suggestion.action.displayName). \(suggestion.reason)")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "arrow.up.right.circle")
                            .foregroundStyle(.orange)
                    }
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
                            if invoice.collectionStage != .none {
                                Text(invoice.collectionStage.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(.orange.opacity(0.2)))
                            }
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
            if kind == .epu {
                epuSection
            } else if !items.isEmpty {
                Section("Podsumowanie") {
                    ForEach(PaymentDemandEngine.totals(of: items), id: \.currency) { total in
                        LabeledContent("Należność główna (\(total.currency))") {
                            Text(total.outstanding, format: .currency(code: total.currency)).monospacedDigit()
                        }
                        if kind.includesInterest {
                            LabeledContent("Odsetki na dziś (\(total.currency))") {
                                Text(total.interest, format: .currency(code: total.currency)).monospacedDigit()
                            }
                        }
                        LabeledContent("Razem (\(total.currency))") {
                            Text(
                                kind == .interestNote ? total.interest : total.outstanding + total.interest,
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

    @ViewBuilder
    private var epuSection: some View {
        Section("Dane do pozwu EPU (e-sąd)") {
            let eligibility = epuEligibility
            LabeledContent("Wartość przedmiotu sporu") {
                Text("\(DebtCollectionEngine.epuDisputeValue(of: eligibility.eligible)) zł")
                    .monospacedDigit()
            }
            LabeledContent("Opłata od pozwu (EPU)") {
                Text("\(DebtCollectionEngine.epuCourtFee(disputeValue: DebtCollectionEngine.epuDisputeValue(of: eligibility.eligible))) zł")
                    .monospacedDigit()
            }
            ForEach(epuWarnings, id: \.self) { warning in
                Label {
                    Text(warning).font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            ForEach(eligibility.omissions, id: \.invoiceNumber) { omission in
                Label {
                    Text("\(omission.invoiceNumber) — \(omission.reason)").font(.caption)
                } icon: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
            }
            Text(epuText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bottomBar: some View {
        HStack {
            Text(kind == .epu
                ? "EPU nie przyjmuje załączników — dane przepisz do formularza pozwu na e-sad.gov.pl."
                : "Kandydatów podpowiada struktura wiekowa Kokpitu — dokument obejmuje zaznaczone faktury po terminie.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Anuluj") { dismiss() }
                .keyboardShortcut(.cancelAction)
            if kind == .epu {
                Button {
                    copyEPUData()
                } label: {
                    Label("Kopiuj dane", systemImage: "doc.on.doc")
                }
                .disabled(epuEligibility.eligible.isEmpty || sellerName.isEmpty)
                Button {
                    saveEPUData()
                } label: {
                    Label("Zapisz TXT", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(epuEligibility.eligible.isEmpty || sellerName.isEmpty)
            } else {
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
        }
        .padding()
    }

    private func prefillIfNeeded() {
        guard !prefilled else { return }
        prefilled = true
        selectedBuyerNIP = preselectedBuyerNIP ?? debtors.first?.nip ?? ""
        selectedInvoiceIDs = Set(debtorInvoices.map(\.id))
        // Startowy rodzaj dokumentu podąża za sugestią eskalacji.
        if let suggested = suggestion?.action {
            switch suggested {
            case .reminder: kind = .reminder
            case .demand: kind = .demand
            case .interestNote: kind = .interestNote
            case .epu: kind = .epu
            }
        }
    }

    /// Odnotowanie działania windykacyjnego na zaznaczonych fakturach —
    /// od tego zapisu zależy status windykacji i wstrzymanie miękkich
    /// przypomnień po formalnym wezwaniu.
    private func recordCollectionAction() {
        DebtCollectionEngine.record(kind.collectionAction, on: selectedInvoices)
        try? modelContext.save()
    }

    private var suggestedFileName: String {
        let prefix: String
        switch kind {
        case .reminder: prefix = "Przypomnienie"
        case .demand: prefix = "Wezwanie"
        case .interestNote: prefix = "Nota_odsetkowa"
        case .epu: prefix = "EPU_dane_pozwu"
        }
        let debtor = (debtorInvoices.first?.buyerName ?? "dluznik")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let ext = kind == .epu ? "txt" : "pdf"
        return "\(prefix)_\(debtor)_\(FA2Format.dateFormatter.string(from: .now)).\(ext)"
    }

    private func savePDF() {
        guard let pdf = PaymentDemandPDFGenerator.pdfData(for: document) else {
            errorMessage = "Nie udało się wygenerować dokumentu PDF."
            return
        }
        if FileExportService.exportData(pdf, suggestedName: suggestedFileName, contentType: .pdf) {
            recordCollectionAction()
            dismiss()
        }
    }

    private func saveEPUData() {
        if FileExportService.exportData(
            Data(epuText.utf8),
            suggestedName: suggestedFileName,
            contentType: .plainText
        ) {
            recordCollectionAction()
            dismiss()
        }
    }

    private func copyEPUData() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(epuText, forType: .string)
        recordCollectionAction()
        infoMessage = "Dane pozwu EPU skopiowane do schowka."
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
        let body: String
        switch kind {
        case .reminder:
            body = "Dzień dobry,\n\nw załączeniu przekazujemy przypomnienie o płatności zaległych faktur. Jeżeli płatność została już zrealizowana, prosimy zignorować tę wiadomość.\n\nPozdrawiamy\n\(sellerName)"
        case .interestNote:
            body = "Dzień dobry,\n\nw załączeniu przekazujemy notę odsetkową z tytułu opóźnienia w zapłacie faktur.\n\nPozdrawiamy\n\(sellerName)"
        default:
            body = "Dzień dobry,\n\nw załączeniu przekazujemy wezwanie do zapłaty zaległych należności wraz z naliczonymi odsetkami. Prosimy o uregulowanie płatności w terminie \(paymentDays) dni.\n\nPozdrawiamy\n\(sellerName)"
        }
        do {
            try InvoiceEmailService.composeDocument(
                recipient: recipient,
                subject: subject,
                body: body,
                attachmentName: suggestedFileName,
                attachmentData: pdf
            )
            recordCollectionAction()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
