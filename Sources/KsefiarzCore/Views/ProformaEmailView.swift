import SwiftUI
import SwiftData

/// Arkusz wysyłki proformy e-mailem. Adresat podpowiadany ze słownika
/// kontrahentów (po NIP nabywcy, jeśli podany), edytowalny temat i treść,
/// załącznik PDF (polski albo dwujęzyczny). Wiadomość otwiera się w Mail;
/// po przekazaniu na proformie zapisywana jest informacja o wysłaniu.
public struct ProformaEmailView: View {

    let proforma: Proforma

    @Query private var contractors: [Contractor]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var recipient = ""
    @State private var subject = ""
    @State private var body_ = ""
    @State private var language: InvoiceEmailComposer.Language = .polish
    @State private var bilingualPDF = false
    @State private var errorMessage: String?
    @State private var prefilled = false

    public init(proforma: Proforma) {
        self.proforma = proforma
    }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Wiadomość") {
                    TextField("Do", text: $recipient, prompt: Text("adres@kontrahenta.pl"))
                    Picker("Język szablonu", selection: $language) {
                        ForEach(InvoiceEmailComposer.Language.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    TextField("Temat", text: $subject)
                    TextEditor(text: $body_)
                        .frame(minHeight: 160)
                        .font(.body)
                }
                Section("Załącznik") {
                    Toggle("PDF dwujęzyczny (PL/EN)", isOn: $bilingualPDF)
                        .help("Etykiety na wydruku w obu językach — dla kontrahentów zagranicznych.")
                }
                if let sentAt = proforma.emailSentAt {
                    Section {
                        Label {
                            Text("Proformę przekazano już do wysyłki ")
                                + Text(sentAt, style: .date)
                                + Text(proforma.emailSentTo.isEmpty ? "" : " na adres \(proforma.emailSentTo)")
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
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 440)
        .navigationTitle("Wyślij proformę e-mailem")
        .onAppear { prefillIfNeeded() }
        .onChange(of: language) { _, newLanguage in
            let templates = EmailTemplates.fromDefaults()
            subject = Self.defaultSubject(for: proforma, language: newLanguage, templates: templates)
            body_ = Self.defaultBody(for: proforma, language: newLanguage, templates: templates)
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

    private func prefillIfNeeded() {
        guard !prefilled else { return }
        prefilled = true
        let transient = proforma.transientInvoice()
        recipient = InvoiceEmailComposer.recipient(for: transient, contractors: contractors)
        language = InvoiceEmailComposer.preferredLanguage(for: transient, contractors: contractors)
        bilingualPDF = language == .english
        let templates = EmailTemplates.fromDefaults()
        subject = Self.defaultSubject(for: proforma, language: language, templates: templates)
        body_ = Self.defaultBody(for: proforma, language: language, templates: templates)
    }

    /// Generuje PDF proformy (z przejściowej faktury) i otwiera okno Mail.
    private func composeEmail() {
        let transient = proforma.transientInvoice()
        guard let pdf = InvoicePDFGenerator.pdfData(for: transient, bilingual: bilingualPDF) else {
            errorMessage = InvoiceEmailError.missingPDF.localizedDescription
            return
        }
        let sanitized = proforma.proformaNumber
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        do {
            try InvoiceEmailService.composeDocument(
                recipient: recipient.trimmingCharacters(in: .whitespaces),
                subject: subject,
                body: body_,
                attachmentName: "Proforma-\(sanitized).pdf",
                attachmentData: pdf
            )
            proforma.emailSentAt = .now
            proforma.emailSentTo = recipient.trimmingCharacters(in: .whitespaces)
            try? modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Szablony treści (proforma, nie faktura)

    /// Temat wiadomości proformy — własny szablon z Ustawień albo
    /// wbudowany domyślny (wartości symboli z przejściowej faktury).
    static func defaultSubject(
        for proforma: Proforma,
        language: InvoiceEmailComposer.Language,
        templates: EmailTemplates = EmailTemplates()
    ) -> String {
        templates.subject(kind: .proforma, for: proforma.transientInvoice(), language: language)
    }

    /// Treść wiadomości proformy — własny szablon z Ustawień albo
    /// wbudowany domyślny.
    static func defaultBody(
        for proforma: Proforma,
        language: InvoiceEmailComposer.Language,
        templates: EmailTemplates = EmailTemplates()
    ) -> String {
        templates.body(kind: .proforma, for: proforma.transientInvoice(), language: language)
    }
}
