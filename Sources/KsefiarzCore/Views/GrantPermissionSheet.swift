import SwiftUI

/// Arkusz nadania uprawnienia KSeF. Pola dopasowują się do rodzaju podmiotu;
/// walidacja (NIP/PESEL, opis, zakresy) blokuje wysłanie niepoprawnego szkicu.
struct GrantPermissionSheet: View {

    /// Wywoływane po zatwierdzeniu — rzuca błąd przy niepowodzeniu operacji.
    let onGrant: (PermissionGrantDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = PermissionGrantDraft()
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var validationErrors: [String] { draft.validationErrors() }

    var body: some View {
        VStack(spacing: 0) {
            Text("Nadaj uprawnienie")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            Divider()

            Form {
                subjectSection
                identifierSection
                scopeSection
                Section("Opis") {
                    TextField("Opis nadania", text: $draft.description, prompt: Text("np. Biuro rachunkowe Kowalski"))
                    Text("Wymagany przez KSeF (co najmniej 5 znaków). Pomaga rozpoznać dostęp na liście.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if !validationErrors.isEmpty {
                    Label(validationErrors.first ?? "", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Anuluj", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Nadaj")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || !draft.isValid)
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 520)
    }

    // MARK: Sekcje

    private var subjectSection: some View {
        Section("Komu nadajesz") {
            Picker("Rodzaj", selection: $draft.subjectKind) {
                ForEach(KSeFGrantSubjectKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            Text(draft.subjectKind.help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var identifierSection: some View {
        Section("Podmiot") {
            if draft.subjectKind == .person {
                Picker("Identyfikator", selection: $draft.identifierType) {
                    ForEach(KSeFPermissionIdentifierType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                TextField(
                    draft.identifierType.displayName,
                    text: $draft.identifierValue,
                    prompt: Text(draft.identifierType == .nip ? "10 cyfr" : "11 cyfr")
                )
                TextField("Imię", text: $draft.firstName)
                TextField("Nazwisko", text: $draft.lastName)
            } else {
                TextField("NIP", text: $draft.identifierValue, prompt: Text("10 cyfr"))
                TextField("Nazwa podmiotu", text: $draft.subjectName, prompt: Text("np. Biuro Rachunkowe Kowalski Sp. z o.o."))
            }
        }
    }

    @ViewBuilder
    private var scopeSection: some View {
        switch draft.subjectKind {
        case .entity:
            Section("Zakres uprawnień") {
                ForEach(KSeFInvoiceScope.allCases) { scope in
                    Toggle(scope.displayName, isOn: binding(for: scope))
                }
                Toggle("Może delegować dalej", isOn: $draft.canDelegate)
            }
        case .person:
            Section("Zakres uprawnień") {
                ForEach(KSeFPersonScope.allCases) { scope in
                    Toggle(scope.displayName, isOn: binding(for: scope))
                }
            }
        case .authorization:
            Section("Uprawnienie podmiotowe") {
                Picker("Rodzaj", selection: $draft.authorizationScope) {
                    ForEach(KSeFAuthorizationScope.allCases) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
            }
        }
    }

    // MARK: Bindings zakresów (zbiory)

    private func binding(for scope: KSeFInvoiceScope) -> Binding<Bool> {
        Binding(
            get: { draft.invoiceScopes.contains(scope) },
            set: { on in
                if on { draft.invoiceScopes.insert(scope) } else { draft.invoiceScopes.remove(scope) }
            }
        )
    }

    private func binding(for scope: KSeFPersonScope) -> Binding<Bool> {
        Binding(
            get: { draft.personScopes.contains(scope) },
            set: { on in
                if on { draft.personScopes.insert(scope) } else { draft.personScopes.remove(scope) }
            }
        )
    }

    // MARK: Wysłanie

    @MainActor
    private func submit() async {
        guard draft.isValid, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await onGrant(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
