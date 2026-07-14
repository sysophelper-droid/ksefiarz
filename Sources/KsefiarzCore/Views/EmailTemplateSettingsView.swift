import SwiftUI

/// Sekcja Ustawień „Szablony wiadomości e-mail” (F5): edycja własnego
/// wzoru tematu i treści per rodzaj wiadomości i język. Pola pokazują
/// zawsze OBOWIĄZUJĄCY szablon (własny albo wbudowany); zapis tekstu
/// identycznego z wbudowanym czyści klucz (wraca „domyślny”), dzięki
/// czemu przyszłe zmiany wbudowanych wzorów nie są zamrażane.
struct EmailTemplateSettingsSection: View {

    /// Etykieta z wyszukiwarki ustawień do chwilowego podświetlenia.
    var highlightedLabel: String?

    /// Etykieta sekcji w indeksie wyszukiwarki ustawień.
    static let searchLabel = "Szablony e-mail (temat / treść wiadomości)"

    @State private var kind: EmailTemplateKind = .invoice
    @State private var language: InvoiceEmailComposer.Language = .polish
    @State private var subject = ""
    @State private var bodyText = ""

    private var defaultSubject: String {
        EmailTemplate.defaultSubjectTemplate(kind: kind, language: language)
    }

    private var defaultBody: String {
        EmailTemplate.defaultBodyTemplate(kind: kind, language: language)
    }

    private var isCustomized: Bool {
        subject != defaultSubject || bodyText != defaultBody
    }

    var body: some View {
        Section {
            Picker("Rodzaj wiadomości", selection: $kind) {
                ForEach(EmailTemplateKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .listRowBackground(highlightBackground)
            Picker("Język", selection: $language) {
                ForEach(InvoiceEmailComposer.Language.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            TextField("Temat", text: $subject)
            TextEditor(text: $bodyText)
                .frame(minHeight: 190)
                .font(.body)
            HStack {
                if isCustomized {
                    Label("Własny wzór", systemImage: "pencil.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else {
                    Label("Szablon domyślny", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                Button("Przywróć domyślny") {
                    subject = defaultSubject
                    bodyText = defaultBody
                }
                .disabled(!isCustomized)
            }
        } header: {
            Text("Szablony wiadomości e-mail")
        } footer: {
            Text(Self.footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: load)
        .onChange(of: kind) { load() }
        .onChange(of: language) { load() }
        // Zapis przy każdej zmianie — zapis wartości świeżo wczytanej jest
        // neutralny (ten sam tekst albo wyczyszczenie klucza domyślnego),
        // więc nie potrzeba flagi „w trakcie ładowania”.
        .onChange(of: subject) { save() }
        .onChange(of: bodyText) { save() }
    }

    private static var footerText: String {
        let legend = EmailTemplate.placeholderLegend
            .map { "\($0.symbol) \($0.description)" }
            .joined(separator: ", ")
        return "Szablony obowiązują przy wysyłce faktur i proform e-mailem "
            + "oraz w automatycznych przypomnieniach o płatnościach. "
            + "Dostępne symbole: \(legend). "
            + "Wiersz, którego wszystkie symbole są puste (np. „Termin "
            + "płatności: {termin}.” dla faktury bez terminu), jest pomijany "
            + "w wiadomości. Nierozpoznany symbol zostaje w treści dosłownie."
    }

    private var highlightBackground: some View {
        Group {
            if highlightedLabel == Self.searchLabel {
                Color.accentColor.opacity(0.18)
            } else {
                Color.clear
            }
        }
    }

    /// Wczytuje obowiązujący szablon wybranej kombinacji do pól edycji.
    private func load() {
        let defaults = UserDefaults.standard
        let subjectKey = EmailTemplate.storageKey(kind: kind, field: "subject", language: language)
        let bodyKey = EmailTemplate.storageKey(kind: kind, field: "body", language: language)
        let storedSubject = defaults.string(forKey: subjectKey) ?? ""
        let storedBody = defaults.string(forKey: bodyKey) ?? ""
        subject = storedSubject.isEmpty ? defaultSubject : storedSubject
        bodyText = storedBody.isEmpty ? defaultBody : storedBody
    }

    /// Utrwala pola: tekst równy wbudowanemu wzorowi czyści klucz.
    private func save() {
        let defaults = UserDefaults.standard
        let subjectKey = EmailTemplate.storageKey(kind: kind, field: "subject", language: language)
        let bodyKey = EmailTemplate.storageKey(kind: kind, field: "body", language: language)
        if subject == defaultSubject || subject.trimmingCharacters(in: .whitespaces).isEmpty {
            defaults.removeObject(forKey: subjectKey)
        } else {
            defaults.set(subject, forKey: subjectKey)
        }
        if bodyText == defaultBody || bodyText.trimmingCharacters(in: .whitespaces).isEmpty {
            defaults.removeObject(forKey: bodyKey)
        } else {
            defaults.set(bodyText, forKey: bodyKey)
        }
    }
}
