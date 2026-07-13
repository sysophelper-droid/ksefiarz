import SwiftUI
import SwiftData

/// Widok szczegółów faktury — czytelna prezentacja danych (strony z adresami,
/// pozycje, dane płatności), eksport XML/PDF oraz podgląd surowego XML z KSeF.
public struct InvoiceDetailView: View {

    @Bindable var invoice: Invoice

    @AppStorage(AppSettingsKeys.nip) private var myNIP = ""
    @ObservedObject private var tokenStore = TokenStore.shared
    private var ksefToken: String { tokenStore.token }
    @AppStorage(AppSettingsKeys.environment) private var environmentRaw = KSeFEnvironment.test.rawValue

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingCorrectionForm = false
    @State private var showingEditForm = false
    /// Edycja ręcznej faktury kosztowej (spoza KSeF).
    @State private var showingPurchaseEditForm = false
    @State private var showingDeleteConfirmation = false
    /// Kategorie użyte na zakupach — podpowiedzi przy zmianie kategorii.
    @State private var usedCategories: [String] = []
    @State private var showingEmailSheet = false
    @State private var isDownloadingUPO = false
    @State private var isSendingToKSeF = false
    @State private var isCheckingKSeFStatus = false
    @State private var errorMessage: String?
    /// Podgląd surowego XML — domyślnie zwinięty (rzadko potrzebny).
    @State private var isXMLExpanded = false
    @State private var isVerifyingAccount = false
    @State private var accountVerification: (isValid: Bool, message: String)?
    /// Formularz nowej wpłaty (historia wpłat).
    @State private var newPaymentAmount: Double?
    @State private var newPaymentDate = Date.now
    @State private var newPaymentNote = ""

    public init(invoice: Invoice) {
        self.invoice = invoice
    }

    /// Wystawiany przez nas dokument zapisany tylko lokalnie — zwykła
    /// sprzedaż lub zakupowy dokument wystawiany przez nas
    /// (VAT RR, samofaktura).
    private var isEditableLocal: Bool {
        invoice.hasKSeFSubmissionLifecycle && invoice.isLocalOnly
    }

    public var body: some View {
        Form {
            Section("Faktura") {
                LabeledContent("Numer faktury", value: invoice.invoiceNumber)
                if invoice.isSelfInvoicing {
                    LabeledContent("Samofakturowanie") {
                        Text(invoice.kind == .purchase
                            ? "Wystawiona przez nas (nabywcę) w imieniu dostawcy — art. 106d"
                            : "Wystawiona przez nabywcę w naszym imieniu — art. 106d")
                            .foregroundStyle(.teal)
                    }
                }
                LabeledContent("Numer KSeF") {
                    if let ksefId = invoice.ksefId {
                        Text(ksefId)
                    } else if invoice.ksefSubmissionStatus == .processing {
                        Text("Oczekuje na nadanie")
                            .foregroundStyle(.orange)
                    } else if invoice.ksefSubmissionStatus == .offlinePending {
                        Text("\(invoice.offlineReason.displayName) — zostanie nadany po dosłaniu")
                            .foregroundStyle(.blue)
                    } else if invoice.ksefSubmissionStatus == .rejected {
                        Text("Nie nadano — dokument odrzucony")
                            .foregroundStyle(.red)
                    } else {
                        Label("Tylko lokalnie — nie wysłano do KSeF", systemImage: "externaldrive")
                            .foregroundStyle(.secondary)
                    }
                }
                if invoice.ksefSubmissionStatus == .offlinePending {
                    // Tryb offline można doprecyzować do czasu dosłania —
                    // gdy MF ogłosiło awarię/niedostępność, termin liczy
                    // się od jej zakończenia (dokument XML bez zmian).
                    LabeledContent("Tryb offline") {
                        Picker("", selection: Binding(
                            get: { invoice.offlineReason },
                            set: { invoice.offlineReason = $0 }
                        )) {
                            ForEach(Invoice.OfflineReason.allCases, id: \.self) { reason in
                                Text(reason.displayName).tag(reason)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .help("Powód wystawienia offline — decyduje o terminie dosłania (offline24: następny dzień roboczy; niedostępność: następny dzień roboczy po zakończeniu; awaria: 7 dni roboczych od zakończenia).")
                    }
                    if invoice.offlineReason != .offline24 {
                        LabeledContent(
                            invoice.offlineReason == .failure
                                ? "Zakończenie awarii (komunikat MF)"
                                : "Zakończenie niedostępności (komunikat MF)"
                        ) {
                            HStack(spacing: 8) {
                                if let ended = invoice.offlineEventEndedAt {
                                    DatePicker("", selection: Binding(
                                        get: { ended },
                                        set: { invoice.offlineEventEndedAt = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                    Button("Wyczyść") { invoice.offlineEventEndedAt = nil }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                } else {
                                    Text("zdarzenie trwa")
                                        .foregroundStyle(.secondary)
                                    Button("Wpisz datę zakończenia") {
                                        invoice.offlineEventEndedAt = Calendar.current.startOfDay(for: .now)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    LabeledContent("Termin dosłania do KSeF") {
                        HStack(spacing: 8) {
                            if let deadline = invoice.offlineSendDeadline {
                                Text(deadline, style: .date)
                                    .foregroundStyle(deadline < .now ? .red : .primary)
                                if deadline < .now {
                                    Label("po terminie", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            } else {
                                Text(invoice.offlineReason.deadlineDescription)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                Task { await sendOfflineNow() }
                            } label: {
                                if isSendingToKSeF {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Doślij teraz", systemImage: "paperplane")
                                }
                            }
                            .disabled(isSendingToKSeF)
                            .help("Dosyła zapisany dokument XML do KSeF (poza automatyczną kolejką).")
                        }
                    }
                }
                if invoice.hasKSeFSubmissionLifecycle {
                    LabeledContent("Status KSeF") {
                        KSeFSubmissionBadge(invoice: invoice)
                    }
                    if let reference = invoice.ksefInvoiceReference {
                        LabeledContent("Referencja wysyłki", value: reference)
                    }
                    if let description = invoice.ksefStatusDescription, !description.isEmpty {
                        LabeledContent("Odpowiedź KSeF", value: description)
                    }
                    if let checkedAt = invoice.ksefLastCheckedAt {
                        LabeledContent("Ostatnie sprawdzenie") {
                            Text(checkedAt, style: .relative)
                        }
                    }
                }
                LabeledContent("Data wystawienia") {
                    Text(invoice.issueDate, style: .date)
                }
                switch invoice.documentTypeRaw {
                case "KOR":
                    LabeledContent("Rodzaj dokumentu", value: "Faktura korygująca (KOR)")
                case "ZAL":
                    LabeledContent("Rodzaj dokumentu", value: "Faktura zaliczkowa (ZAL)")
                case "ROZ":
                    LabeledContent("Rodzaj dokumentu", value: "Faktura rozliczeniowa (ROZ)")
                case "VAT_RR":
                    LabeledContent("Rodzaj dokumentu", value: "Faktura VAT RR")
                case "KOR_VAT_RR":
                    LabeledContent("Rodzaj dokumentu", value: "Korekta faktury VAT RR")
                default:
                    EmptyView()
                }
                if let saleDate = invoice.saleDate {
                    LabeledContent(
                        invoice.documentTypeRaw == "ZAL" ? "Data otrzymania zaliczki"
                            : invoice.isRR ? "Data nabycia" : "Data sprzedaży / dostawy"
                    ) {
                        Text(saleDate, style: .date)
                    }
                }
                if invoice.currency != "PLN" {
                    LabeledContent("Waluta", value: invoice.currency)
                    if invoice.exchangeRate > 0 {
                        LabeledContent(
                            "Kurs PLN",
                            value: invoice.exchangeRate.formatted(.number.precision(.fractionLength(4)))
                        )
                    }
                }
                if invoice.splitPayment {
                    LabeledContent("Mechanizm podzielonej płatności") {
                        Text("MPP")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.indigo.opacity(0.18), in: Capsule())
                            .foregroundStyle(.indigo)
                    }
                }
                if invoice.documentTypeRaw == "ROZ", !invoice.advanceInvoiceRefs.isEmpty {
                    LabeledContent("Rozlicza zaliczki") {
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(invoice.advanceInvoiceRefs, id: \.self) { ref in
                                Text(ref).font(.caption.monospaced())
                            }
                        }
                    }
                }
                LabeledContent("Status") {
                    PaymentBadge(invoice: invoice)
                }
                // Kategoria kosztu (tylko zakupy) — grupuje wydatki
                // w raportach; edytowalna także dla faktur z KSeF
                // (to lokalna metadana, nie treść dokumentu).
                if invoice.kind == .purchase {
                    LabeledContent("Kategoria kosztu") {
                        HStack(spacing: 6) {
                            TextField("", text: Binding(
                                get: { invoice.costCategory },
                                set: { invoice.costCategory = $0 }
                            ), prompt: Text(CostCategories.none))
                            .labelsHidden()
                            .frame(maxWidth: 240)
                            Menu {
                                if !usedCategories.isEmpty {
                                    Section("Użyte") {
                                        ForEach(usedCategories, id: \.self) { category in
                                            Button(category) { invoice.costCategory = category }
                                        }
                                    }
                                }
                                Section("Typowe") {
                                    ForEach(CostCategories.suggestions, id: \.self) { category in
                                        Button(category) { invoice.costCategory = category }
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
                }
                if let sentAt = invoice.emailSentAt {
                    LabeledContent("Wysłano e-mailem") {
                        Text(sentAt, style: .date)
                            + Text(invoice.emailSentTo.isEmpty ? "" : " → \(invoice.emailSentTo)")
                    }
                }
            }

            if invoice.isCorrection {
                Section("Dane korekty") {
                    LabeledContent("Koryguje fakturę", value: invoice.correctedInvoiceNumber ?? "—")
                    if let originalDate = invoice.correctedInvoiceIssueDate {
                        LabeledContent("Data faktury korygowanej") {
                            Text(originalDate, style: .date)
                        }
                    }
                    if let originalKsef = invoice.correctedInvoiceKsefId {
                        LabeledContent("Numer KSeF korygowanej", value: originalKsef)
                    }
                    if let reason = invoice.correctionReason, !reason.isEmpty {
                        LabeledContent("Przyczyna korekty", value: reason)
                    }
                }
            }

            Section("Sprzedawca") {
                LabeledContent("Nazwa", value: invoice.sellerName)
                LabeledContent("NIP", value: invoice.sellerNIP)
                if !invoice.sellerAddress.isEmpty {
                    LabeledContent("Adres", value: invoice.sellerAddress)
                }
            }

            Section("Nabywca") {
                LabeledContent("Nazwa", value: invoice.buyerName)
                LabeledContent("NIP", value: invoice.buyerNIP)
                if !invoice.buyerAddress.isEmpty {
                    LabeledContent("Adres", value: invoice.buyerAddress)
                }
            }

            if !invoice.lines.isEmpty {
                Section("Pozycje") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                        GridRow {
                            Text("Lp.").gridColumnAlignment(.trailing)
                            Text("Nazwa")
                            Text("Ilość").gridColumnAlignment(.trailing)
                            Text("Cena netto").gridColumnAlignment(.trailing)
                            Text("Wartość netto").gridColumnAlignment(.trailing)
                            Text("VAT").gridColumnAlignment(.trailing)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        Divider()
                        ForEach(invoice.sortedLines, id: \.persistentModelID) { line in
                            GridRow {
                                Text("\(line.index)")
                                VStack(alignment: .leading, spacing: 1) {
                                    // Pełna nazwa pozycji — zawijana, nigdy
                                    // nie przycinana (dokument księgowy).
                                    Text(line.name)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if !line.cnPkwiu.isEmpty || !line.gtu.isEmpty {
                                        Text([
                                            line.cnPkwiu.isEmpty ? nil : "CN/PKWiU: \(line.cnPkwiu)",
                                            line.gtu.isEmpty ? nil : line.gtu,
                                        ].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text("\(FA2Format.quantity(line.quantity)) \(line.unit)")
                                Text(line.unitNetPrice, format: .currency(code: invoice.currency)).monospacedDigit()
                                Text(line.netAmount, format: .currency(code: invoice.currency)).monospacedDigit()
                                // Pozycja OSS pokazuje stawkę państwa konsumpcji.
                                Text(line.ossRate.map { "OSS \(FA2Format.percent($0))%" }
                                    ?? VATRate(rawValue: line.vatRate)?.displayName
                                    ?? line.vatRate)
                            }
                            .font(.callout)
                        }
                    }
                }
            }

            if !invoice.notes.isEmpty {
                Section("Uwagi") {
                    Text(invoice.notes)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }

            attachmentSection

            Section("Kwoty") {
                LabeledContent("Netto") {
                    Text(invoice.netAmount, format: .currency(code: invoice.currency)).monospacedDigit()
                }
                LabeledContent("VAT") {
                    Text(invoice.vatAmount, format: .currency(code: invoice.currency)).monospacedDigit()
                }
                LabeledContent("Brutto") {
                    Text(invoice.grossAmount, format: .currency(code: invoice.currency))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
            }

            Section("Płatność") {
                if let form = invoice.paymentForm {
                    LabeledContent("Forma płatności", value: form.displayName)
                }
                if let due = invoice.paymentDueDate {
                    LabeledContent("Termin płatności") {
                        Text(due, style: .date)
                            .foregroundStyle(invoice.isOverdue ? .red : .primary)
                    }
                }
                if let paidDate = invoice.paymentDate {
                    LabeledContent("Data zapłaty") {
                        Text(paidDate, style: .date)
                    }
                }
                if let account = invoice.paymentBankAccount, !account.isEmpty {
                    LabeledContent("Rachunek do przelewu") {
                        HStack(spacing: 8) {
                            Text(account)
                                .monospaced()
                                .textSelection(.enabled)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(account, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Skopiuj numer rachunku")
                        }
                    }
                    // Weryfikacja rachunku sprzedawcy w wykazie podatników VAT —
                    // tylko zakupy (to my płacimy na ten rachunek).
                    if invoice.kind == .purchase {
                        HStack(spacing: 8) {
                            Button {
                                Task { await verifyAccountOnWhitelist(account) }
                            } label: {
                                if isVerifyingAccount {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Sprawdź rachunek na białej liście", systemImage: "checkmark.shield")
                                }
                            }
                            .disabled(isVerifyingAccount)
                            .help("Sprawdza, czy rachunek figuruje w wykazie podatników VAT sprzedawcy (istotne przy przelewach powyżej 15 000 zł)")
                            if let accountVerification {
                                Label(
                                    accountVerification.message,
                                    systemImage: accountVerification.isValid
                                        ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                                )
                                .foregroundStyle(accountVerification.isValid ? .green : .red)
                                .font(.callout)
                            }
                        }
                    }
                }
                if invoice.paymentForm == nil, invoice.paymentDueDate == nil,
                   invoice.paymentBankAccount == nil {
                    Text("Faktura nie zawiera danych płatności.")
                        .foregroundStyle(.secondary)
                }
            }

            paymentsSection

            Section("Akcje") {
                HStack(spacing: 12) {
                    Button {
                        invoice.isPaid.toggle()
                    } label: {
                        Label(
                            invoice.isPaid ? "Oznacz jako nieopłaconą" : "Oznacz jako opłaconą",
                            systemImage: invoice.isPaid ? "xmark.circle" : "checkmark.circle"
                        )
                    }

                    if invoice.hasKSeFSubmissionLifecycle, !invoice.isCorrection {
                        Button {
                            showingCorrectionForm = true
                        } label: {
                            Label("Wystaw korektę", systemImage: "arrow.uturn.backward.circle")
                        }
                    }

                    if invoice.kind == .sales {
                        Button {
                            showingEmailSheet = true
                        } label: {
                            Label("Wyślij e-mailem", systemImage: "envelope")
                        }
                        .help("Otwórz wiadomość z fakturą (PDF/XML) w aplikacji Mail — adresat ze słownika kontrahentów")
                    }

                    if invoice.hasKSeFSubmissionLifecycle, invoice.ksefInvoiceReference != nil {
                        Button {
                            Task { await refreshKSeFStatus() }
                        } label: {
                            if isCheckingKSeFStatus {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Sprawdź status KSeF", systemImage: "arrow.clockwise.circle")
                            }
                        }
                        .disabled(isCheckingKSeFStatus)
                    }

                    // Ukrywanie dotyczy wyłącznie faktur zakupowych —
                    // chroni przed nieuprawnionymi fakturami na nasz NIP.
                    if invoice.kind == .purchase {
                        Button(role: .destructive) {
                            invoice.isArchivedOrHidden.toggle()
                        } label: {
                            Label(
                                invoice.isArchivedOrHidden
                                    ? "Przywróć fakturę"
                                    : "Ukryj fakturę (Nieuprawniony zakup)",
                                systemImage: invoice.isArchivedOrHidden ? "eye" : "eye.slash"
                            )
                        }
                    }
                }

                // Ręczna faktura kosztowa (spoza KSeF): edycja i usunięcie.
                if invoice.isManualPurchase {
                    HStack(spacing: 12) {
                        Button {
                            showingPurchaseEditForm = true
                        } label: {
                            Label("Edytuj zakup", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Usuń", systemImage: "trash")
                        }
                    }
                }

                // Faktura zapisana tylko lokalnie: edycja, wysyłka, usunięcie.
                // Faktury wysłane do KSeF są niezmienialne (dokument urzędowy).
                if isEditableLocal {
                    HStack(spacing: 12) {
                        Button {
                            Task { await sendToKSeF() }
                        } label: {
                            if isSendingToKSeF {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Wyślij do KSeF", systemImage: "paperplane")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSendingToKSeF)

                        Button {
                            showingEditForm = true
                        } label: {
                            Label("Edytuj", systemImage: "pencil")
                        }
                        .disabled(isSendingToKSeF)

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Usuń", systemImage: "trash")
                        }
                        .disabled(isSendingToKSeF)
                    }
                }
            }

            // Surowy XML na samym dole, domyślnie zwinięty — do zaglądania
            // w razie potrzeby, bez zaśmiecania widoku.
            Section {
                DisclosureGroup(isExpanded: $isXMLExpanded) {
                    if let xml = invoice.rawXmlContent, !xml.isEmpty {
                        ScrollView([.vertical, .horizontal]) {
                            Text(xml)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(minHeight: 160, maxHeight: 320)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("Brak dokumentu XML dla tej faktury.")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Dokument XML (KSeF)", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.headline)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(invoice.invoiceNumber)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    FileExportService.exportXML(of: invoice)
                } label: {
                    Label("Eksportuj XML", systemImage: "doc.badge.arrow.up")
                }
                .disabled((invoice.rawXmlContent ?? "").isEmpty)
                .help("Zapisz oryginalny dokument XML e-Faktury")

                Menu {
                    Button("PDF (polski)") {
                        FileExportService.exportPDF(of: invoice)
                    }
                    Button("PDF dwujęzyczny (PL/EN)") {
                        FileExportService.exportPDF(of: invoice, bilingual: true)
                    }
                } label: {
                    Label("Eksportuj PDF", systemImage: "doc.richtext")
                }
                .help("Zapisz fakturę jako PDF — wariant polski albo dwujęzyczny (PL/EN) dla kontrahentów zagranicznych")

                if invoice.ksefSubmissionStatus == .accepted,
                   invoice.ksefSessionReference != nil, invoice.ksefId != nil {
                    Button {
                        Task { await downloadUPO() }
                    } label: {
                        if isDownloadingUPO {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Pobierz UPO", systemImage: "checkmark.seal")
                        }
                    }
                    .disabled(isDownloadingUPO)
                    .help("Pobierz Urzędowe Poświadczenie Odbioru (XML) z KSeF")
                }
            }
        }
        .sheet(isPresented: $showingEmailSheet) {
            InvoiceEmailView(invoice: invoice)
        }
        .sheet(isPresented: $showingCorrectionForm) {
            NewInvoiceView(correcting: invoice)
        }
        .sheet(isPresented: $showingEditForm) {
            NewInvoiceView(editing: invoice)
        }
        .sheet(isPresented: $showingPurchaseEditForm) {
            NewPurchaseView(editing: invoice)
        }
        .onAppear {
            guard invoice.kind == .purchase else { return }
            let purchaseRaw = Invoice.Kind.purchase.rawValue
            let descriptor = FetchDescriptor<Invoice>(
                predicate: #Predicate { $0.kindRaw == purchaseRaw }
            )
            usedCategories = CostCategories.used(in: (try? modelContext.fetch(descriptor)) ?? [])
        }
        .confirmationDialog(
            "Usunąć fakturę \(invoice.invoiceNumber)?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Usuń", role: .destructive) {
                modelContext.delete(invoice)
                dismiss()
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Faktura istnieje tylko lokalnie — usunięcie jest nieodwracalne.")
        }
        .alert(
            "Operacja nie powiodła się",
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

    /// Wysyła lokalnie zapisaną fakturę do KSeF i zapisuje nadane numery.
    @MainActor
    private func sendToKSeF() async {
        guard !myNIP.isEmpty, !ksefToken.isEmpty || KSeFCertificateStore.shared.authenticationCertificate != nil else {
            errorMessage = KSeFError.missingCredentials.localizedDescription
            return
        }
        isSendingToKSeF = true
        defer { isSendingToKSeF = false }

        let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
        let service = KSeFService(environment: environment, nip: myNIP, authToken: ksefToken, certificate: KSeFCertificateStore.shared.authenticationCertificate)
        do {
            let result = try await service.sendInvoice(InvoiceDraft(from: invoice))
            invoice.ksefId = result.ksefNumber
            invoice.ksefSessionReference = result.sessionReferenceNumber
            invoice.ksefInvoiceReference = result.invoiceReferenceNumber
            invoice.ksefSubmissionStatus = result.processingResult.status
            invoice.ksefStatusCode = result.processingResult.statusCode
            invoice.ksefStatusDescription = result.processingResult.description
            invoice.ksefLastCheckedAt = .now
            invoice.ksefAcceptedAt = result.processingResult.acquisitionDate
            invoice.ksefEnvironmentRaw = environment.rawValue
            invoice.rawXmlContent = result.xml
            // Jawny zapis — numery z KSeF muszą natychmiast trafić na dysk
            // (bez nich nie pobierzemy UPO), a listy odświeżają się
            // dopiero przy zapisie kontekstu.
            try? modelContext.save()
            if result.ksefNumber != nil {
                _ = try? await InvoiceSubmissionStatusEngine.refresh(invoice, using: service)
                try? modelContext.save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Załącznik FA(3)

    /// Załącznik FA(3) — bloki danych z metadanymi, tekstem i tabelami.
    @ViewBuilder
    private var attachmentSection: some View {
        let blocks = [FA3AttachmentBlock].decoded(from: invoice.attachmentJSON)
        if !blocks.isEmpty {
            Section("Załącznik do faktury") {
                ForEach(blocks) { block in
                    VStack(alignment: .leading, spacing: 6) {
                        if !block.header.isEmpty {
                            Text(block.header)
                                .font(.callout.weight(.semibold))
                        }
                        ForEach(block.metadata) { meta in
                            LabeledContent(meta.key, value: meta.value)
                                .font(.callout)
                        }
                        ForEach(block.paragraphs, id: \.self) { paragraph in
                            Text(paragraph)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        ForEach(Array(block.tables.enumerated()), id: \.offset) { _, table in
                            attachmentTableView(table)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// Tabela załącznika w układzie siatki (nagłówek + wiersze + suma).
    private func attachmentTableView(_ table: FA3AttachmentBlock.Table) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !table.description.isEmpty {
                Text(table.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    ForEach(table.columns, id: \.self) { column in
                        Text(column)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                        }
                    }
                    .font(.callout)
                }
                if !table.summary.isEmpty {
                    Divider()
                    GridRow {
                        ForEach(Array(table.summary.enumerated()), id: \.offset) { _, cell in
                            Text(cell).fontWeight(.semibold)
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }

    // MARK: Historia wpłat

    /// Ewidencja wpłat: saldo, lista wpłat (ręcznych i z wyciągów)
    /// oraz formularz księgowania kolejnej wpłaty.
    private var paymentsSection: some View {
        Section {
            LabeledContent("Wpłacono") {
                Text(invoice.paidAmount, format: .currency(code: invoice.currency))
                    .monospacedDigit()
            }
            LabeledContent("Pozostaje do zapłaty") {
                Text(invoice.outstandingAmount, format: .currency(code: invoice.currency))
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(invoice.outstandingAmount > 0.005 ? .orange : .green)
            }
            ForEach(invoice.sortedPayments, id: \.id) { payment in
                HStack(spacing: 8) {
                    Image(systemName: payment.source == .bankImport
                        ? "building.columns" : "person")
                        .foregroundStyle(.secondary)
                        .help("Źródło: \(payment.source.displayName)")
                    Text(payment.date, style: .date)
                    if !payment.note.isEmpty {
                        Text(payment.note)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(payment.note)
                    }
                    Spacer()
                    Text(payment.amount, format: .currency(code: invoice.currency))
                        .monospacedDigit()
                    Button(role: .destructive) {
                        PaymentLedger.remove(payment, from: invoice)
                        try? modelContext.save()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Usuń wpłatę (usunięcie wpłaty domykającej saldo cofa znacznik „opłacona”)")
                }
            }
            // Formularz nowej wpłaty — kwota domyślnie równa saldu.
            HStack(spacing: 8) {
                TextField(
                    "Kwota",
                    value: $newPaymentAmount,
                    format: .number.precision(.fractionLength(2)),
                    prompt: Text(invoice.outstandingAmount, format: .number.precision(.fractionLength(2)))
                )
                .frame(width: 90)
                DatePicker("", selection: $newPaymentDate, displayedComponents: .date)
                    .labelsHidden()
                TextField("Opis (np. tytuł przelewu)", text: $newPaymentNote)
                Button {
                    registerPayment()
                } label: {
                    Label("Zaksięguj wpłatę", systemImage: "plus.circle")
                }
                .disabled((newPaymentAmount ?? invoice.outstandingAmount) <= 0)
            }
        } header: {
            HStack {
                Text("Historia wpłat")
                if invoice.isPartiallyPaid {
                    Text("częściowo opłacona")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.teal.opacity(0.18), in: Capsule())
                        .foregroundStyle(.teal)
                }
            }
        } footer: {
            Text("Wpłaty częściowe zmniejszają saldo; pełne pokrycie kwoty brutto oznacza fakturę jako opłaconą automatycznie. Wpłaty można też księgować hurtowo importem wyciągu bankowego (MT940) z listy faktur.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Księguje wpłatę z formularza; pusta kwota = całe saldo.
    private func registerPayment() {
        let amount = newPaymentAmount ?? invoice.outstandingAmount
        guard amount > 0 else { return }
        PaymentLedger.register(
            amount: amount,
            date: newPaymentDate,
            note: newPaymentNote.trimmingCharacters(in: .whitespaces),
            on: invoice
        )
        try? modelContext.save()
        newPaymentAmount = nil
        newPaymentNote = ""
        newPaymentDate = .now
    }

    /// Ręczne dosłanie dokumentu offline24 — wysyła zapisany XML bajt w bajt
    /// (jego skrót widnieje w kodach QR na przekazanym egzemplarzu).
    @MainActor
    private func sendOfflineNow() async {
        guard !myNIP.isEmpty, !ksefToken.isEmpty || KSeFCertificateStore.shared.authenticationCertificate != nil else {
            errorMessage = KSeFError.missingCredentials.localizedDescription
            return
        }
        isSendingToKSeF = true
        defer { isSendingToKSeF = false }

        let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
        let service = KSeFService(environment: environment, nip: myNIP, authToken: ksefToken, certificate: KSeFCertificateStore.shared.authenticationCertificate)
        do {
            _ = try await OfflineQueueEngine.send(invoice, using: service)
            try? modelContext.save()
            if invoice.ksefId != nil {
                _ = try? await InvoiceSubmissionStatusEngine.refresh(invoice, using: service)
                try? modelContext.save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sprawdza rachunek sprzedawcy w wykazie podatników VAT (biała lista).
    @MainActor
    private func verifyAccountOnWhitelist(_ account: String) async {
        isVerifyingAccount = true
        defer { isVerifyingAccount = false }
        do {
            let onList = try await ContractorLookupService().verifyAccount(
                nip: invoice.sellerNIP, account: account
            )
            accountVerification = onList
                ? (true, "Rachunek na białej liście (stan na dziś).")
                : (false, "Rachunku BRAK na białej liście — zweryfikuj przed przelewem!")
        } catch {
            accountVerification = (false, error.localizedDescription)
        }
    }

    /// Pobiera UPO z KSeF i zapisuje przez panel zapisu.
    @MainActor
    private func downloadUPO() async {
        guard let sessionReference = invoice.ksefSessionReference,
              let ksefNumber = invoice.ksefId else { return }
        guard !myNIP.isEmpty, !ksefToken.isEmpty || KSeFCertificateStore.shared.authenticationCertificate != nil else {
            errorMessage = KSeFError.missingCredentials.localizedDescription
            return
        }
        isDownloadingUPO = true
        defer { isDownloadingUPO = false }

        do {
            let upo: Data
            if let cached = invoice.upoXmlContent, !cached.isEmpty {
                upo = Data(cached.utf8)
            } else {
                try ensureMatchingEnvironment()
                let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
                let service = KSeFService(environment: environment, nip: myNIP, authToken: ksefToken, certificate: KSeFCertificateStore.shared.authenticationCertificate)
                upo = try await service.downloadUPO(
                    sessionReference: sessionReference,
                    ksefNumber: ksefNumber
                )
                invoice.upoXmlContent = String(decoding: upo, as: UTF8.self)
                try? modelContext.save()
            }
            FileExportService.exportData(
                upo,
                suggestedName: "UPO_\(invoice.invoiceNumber.replacingOccurrences(of: "/", with: "-")).xml",
                contentType: .xml
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ponawia odczyt statusu i — po przyjęciu — automatycznie zachowuje UPO.
    @MainActor
    private func refreshKSeFStatus() async {
        guard !myNIP.isEmpty, !ksefToken.isEmpty || KSeFCertificateStore.shared.authenticationCertificate != nil else {
            errorMessage = KSeFError.missingCredentials.localizedDescription
            return
        }
        do {
            try ensureMatchingEnvironment()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        isCheckingKSeFStatus = true
        defer { isCheckingKSeFStatus = false }

        let environment = KSeFEnvironment(rawValue: environmentRaw) ?? .test
        let service = KSeFService(environment: environment, nip: myNIP, authToken: ksefToken, certificate: KSeFCertificateStore.shared.authenticationCertificate)
        do {
            _ = try await InvoiceSubmissionStatusEngine.refresh(invoice, using: service)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureMatchingEnvironment() throws {
        guard invoice.ksefEnvironmentRaw.isEmpty
                || invoice.ksefEnvironmentRaw == environmentRaw else {
            throw KSeFError.badStatus(
                code: 0,
                message: "Faktura została wysłana do środowiska \(invoice.ksefEnvironmentRaw). Przełącz środowisko w Ustawieniach, aby sprawdzić jej status."
            )
        }
    }
}
