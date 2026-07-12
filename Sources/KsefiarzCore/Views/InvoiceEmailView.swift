import SwiftUI
import SwiftData

/// Arkusz wysyłki faktury e-mailem: adresat podpowiadany ze słownika
/// kontrahentów (adres fakturowy ma pierwszeństwo), edytowalny temat
/// i treść, załączniki PDF/XML. Wiadomość otwiera się w aplikacji Mail;
/// po przekazaniu na fakturze zapisywana jest informacja o wysłaniu.
public struct InvoiceEmailView: View {

    let invoice: Invoice

    @Query private var contractors: [Contractor]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var recipient = ""
    @State private var subject = ""
    @State private var body_ = ""
    @State private var includePDF = true
    @State private var includeXML = true
    /// Język szablonu treści (angielski dla kontrahentów zagranicznych).
    @State private var language: InvoiceEmailComposer.Language = .polish
    /// PDF w układzie dwujęzycznym PL/EN.
    @State private var bilingualPDF = false
    @State private var errorMessage: String?
    @State private var prefilled = false

    public init(invoice: Invoice) {
        self.invoice = invoice
    }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Wiadomość") {
                    TextField("Do", text: $recipient, prompt: Text("adres@kontrahenta.pl"))
                    if recipient.isEmpty {
                        Text("Kontrahent nie ma adresu e-mail w słowniku — wpisz adres ręcznie albo uzupełnij słownik (pole „E-mail do faktur”).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Język szablonu", selection: $language) {
                        ForEach(InvoiceEmailComposer.Language.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .help("Zmiana języka podstawia temat i treść od nowa (własne poprawki zostaną zastąpione). Angielski jest podpowiadany, gdy kontrahent ma w słowniku włączone dokumenty dwujęzyczne.")
                    TextField("Temat", text: $subject)
                    TextEditor(text: $body_)
                        .frame(minHeight: 160)
                        .font(.body)
                }
                Section("Załączniki") {
                    Toggle("PDF faktury", isOn: $includePDF)
                    Toggle("PDF dwujęzyczny (PL/EN)", isOn: $bilingualPDF)
                        .disabled(!includePDF)
                        .help("Etykiety na wydruku w obu językach — dla kontrahentów zagranicznych.")
                    Toggle("XML e-Faktury (FA)", isOn: $includeXML)
                        .disabled((invoice.rawXmlContent ?? "").isEmpty)
                    if (invoice.rawXmlContent ?? "").isEmpty {
                        Text("Faktura nie ma zapisanego dokumentu XML.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let sentAt = invoice.emailSentAt {
                    Section {
                        Label {
                            Text("Fakturę przekazano już do wysyłki ")
                                + Text(sentAt, style: .date)
                                + Text(invoice.emailSentTo.isEmpty ? "" : " na adres \(invoice.emailSentTo)")
                                + Text(".")
                        } icon: {
                            Image(systemName: "envelope.badge.fill")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text("Wiadomość otworzy się w aplikacji Mail — tam zatwierdzisz wysyłkę.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Anuluj") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    composeEmail()
                } label: {
                    Label("Otwórz w Mail", systemImage: "envelope")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!includePDF && !includeXML)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 480)
        .navigationTitle("Wyślij fakturę e-mailem")
        .onAppear { prefillIfNeeded() }
        // Zmiana języka podstawia szablon od nowa (pola dalej edytowalne).
        .onChange(of: language) { _, newLanguage in
            subject = InvoiceEmailComposer.defaultSubject(for: invoice, language: newLanguage)
            body_ = InvoiceEmailComposer.defaultBody(for: invoice, language: newLanguage)
        }
        .alert(
            "Nie udało się przygotować wiadomości",
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

    /// Wypełnia pola domyślnymi wartościami (raz, przy otwarciu arkusza).
    /// Kontrahent z włączonymi dokumentami dwujęzycznymi dostaje od razu
    /// angielski szablon i dwujęzyczny PDF.
    private func prefillIfNeeded() {
        guard !prefilled else { return }
        prefilled = true
        recipient = InvoiceEmailComposer.recipient(for: invoice, contractors: contractors)
        language = InvoiceEmailComposer.preferredLanguage(for: invoice, contractors: contractors)
        bilingualPDF = language == .english
        subject = InvoiceEmailComposer.defaultSubject(for: invoice, language: language)
        body_ = InvoiceEmailComposer.defaultBody(for: invoice, language: language)
        includeXML = !(invoice.rawXmlContent ?? "").isEmpty
    }

    /// Otwiera okno wiadomości w Mail i zapisuje informację o wysłaniu.
    private func composeEmail() {
        do {
            try InvoiceEmailService.compose(
                invoice: invoice,
                recipient: recipient.trimmingCharacters(in: .whitespaces),
                subject: subject,
                body: body_,
                includePDF: includePDF,
                includeXML: includeXML,
                bilingualPDF: bilingualPDF
            )
            invoice.emailSentAt = .now
            invoice.emailSentTo = recipient.trimmingCharacters(in: .whitespaces)
            try? modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
