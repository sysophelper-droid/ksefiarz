import SwiftUI
import SwiftData

/// Lista kontrahentów w słowniku — pojedyncze kliknięcie zaznacza,
/// podwójne otwiera edycję (spójnie z listami faktur).
struct ContractorsListView: View {

    @Query(sort: \Contractor.name) private var contractors: [Contractor]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var selection = Set<UUID>()
    @State private var editedContractor: Contractor?
    @State private var verifyingContractor: Contractor?
    @State private var showingNewContractor = false

    private var filtered: [Contractor] {
        guard !searchText.isEmpty else { return contractors }
        return contractors.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.nip.contains(searchText)
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { contractor in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contractor.displayName).font(.headline)
                        HStack(spacing: 8) {
                            if !contractor.nip.isEmpty { Text("NIP: \(contractor.nip)") }
                            if !contractor.city.isEmpty { Text(contractor.city) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        if contractor.isSupplier { RoleBadge(label: "Dostawca") }
                        if contractor.isRecipient { RoleBadge(label: "Odbiorca") }
                    }
                }
                .padding(.vertical, 2)
                .tag(contractor.id)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                Button("Edytuj") {
                    editedContractor = contractors.first { ids.contains($0.id) }
                }
                if ids.count == 1, let contractor = contractors.first(where: { ids.contains($0.id) }),
                   !contractor.nip.filter(\.isNumber).isEmpty {
                    Button("Zweryfikuj w KSeF i wykazie VAT") {
                        verifyingContractor = contractor
                    }
                }
                Button("Usuń ze słownika", role: .destructive) {
                    deleteContractors(ids)
                }
            }
        } primaryAction: { ids in
            editedContractor = contractors.first { ids.contains($0.id) }
        }
        .searchable(text: $searchText, prompt: "Szukaj po nazwie lub NIP")
        .overlay {
            if contractors.isEmpty {
                ContentUnavailableView(
                    "Brak kontrahentów",
                    systemImage: "person.2",
                    description: Text("Dodaj kontrahenta przyciskiem +. Dane można pobrać z wykazu podatników VAT po numerze NIP.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingNewContractor = true
                } label: {
                    Label("Nowy kontrahent", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewContractor) {
            ContractorEditorView(original: nil)
        }
        .sheet(item: $editedContractor) { contractor in
            ContractorEditorView(original: contractor)
        }
        .sheet(item: $verifyingContractor) { contractor in
            ContractorVerificationView(nip: contractor.nip, expectedName: contractor.displayName)
        }
    }

    private func deleteContractors(_ ids: Set<UUID>) {
        for contractor in contractors where ids.contains(contractor.id) {
            modelContext.delete(contractor)
        }
        try? modelContext.save()
    }
}

/// Znaczek roli kontrahenta (Dostawca/Odbiorca).
private struct RoleBadge: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }
}

/// Formularz kontrahenta: sekcje Ogólne / Adres / Kontakt.
/// Edycja na kopii roboczej — Anuluj nie zostawia śladów w bazie.
struct ContractorEditorView: View {

    let original: Contractor?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var working = Contractor()
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    @State private var showingVerification = false

    /// Prefiksy VAT UE wg wykazu w schemie FA(2).
    private static let uePrefixes = ["", "AT", "BE", "BG", "CY", "CZ", "DE", "DK",
        "EE", "EL", "ES", "FI", "FR", "HR", "HU", "IE", "IT", "LT", "LU", "LV",
        "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK", "XI"]

    private var canSave: Bool {
        !working.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !working.nip.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        @Bindable var working = working
        VStack(spacing: 0) {
            Form {
                Section("Ogólne") {
                    TextField("Nazwa firmy", text: $working.name, prompt: Text("Pełna nazwa"))
                    TextField("Nazwa — ciąg dalszy", text: $working.nameLine2)
                    HStack {
                        TextField("Identyfikator (NIP)", text: $working.nip, prompt: Text("10 cyfr"))
                        Button {
                            Task { await lookupByNIP() }
                        } label: {
                            if isLookingUp {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Pobierz dane", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(isLookingUp || working.nip.filter(\.isNumber).count != 10)
                        .help("Pobiera nazwę i adres z wykazu podatników VAT (Biała lista)")
                        Button {
                            showingVerification = true
                        } label: {
                            Label("Zweryfikuj", systemImage: "checkmark.shield")
                        }
                        .disabled(working.nip.filter(\.isNumber).count != 10)
                        .help("Sprawdza status VAT (Biała lista) i relację uprawnień w KSeF")
                    }
                    if let lookupMessage {
                        Text(lookupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Prefiks UE", selection: $working.uePrefix) {
                        ForEach(Self.uePrefixes, id: \.self) { prefix in
                            Text(prefix.isEmpty ? "(brak)" : prefix).tag(prefix)
                        }
                    }
                    Toggle("Dostawca", isOn: $working.isSupplier)
                    Toggle("Odbiorca", isOn: $working.isRecipient)
                    Toggle("Kontrahent jest osobą fizyczną", isOn: $working.isNaturalPerson)
                    Toggle("Zgoda na otrzymywanie e-faktur", isOn: $working.consentsToEInvoices)
                    Toggle("Zgoda na przetwarzanie w celach marketingowych", isOn: $working.consentsToMarketing)
                    Toggle("Dokumenty dwujęzyczne (PL/EN)", isOn: $working.prefersBilingualDocuments)
                        .help("Kontrahent zagraniczny: PDF faktury będzie dwujęzyczny (polsko-angielski), a e-mail z fakturą dostanie angielski szablon treści.")
                }

                // Każde pole w osobnym wierszu — ściśnięte HStacki łamały
                // etykiety w formularzu .grouped (np. „Lo-kal”).
                Section("Adres") {
                    TextField("Ulica", text: $working.street)
                    TextField("Numer domu", text: $working.houseNumber)
                    TextField("Numer lokalu", text: $working.apartmentNumber)
                    TextField("Kod pocztowy", text: $working.postalCode, prompt: Text("00-000"))
                    TextField("Miejscowość", text: $working.city)
                    TextField("Kraj", text: $working.countryName)
                    TextField("Symbol kraju", text: $working.countryCode, prompt: Text("PL"))
                }

                Section("Kontakt") {
                    TextField("Telefon 1", text: $working.phone1)
                    TextField("Telefon 2", text: $working.phone2)
                    TextField("Faks", text: $working.fax)
                    Picker("Komunikator", selection: $working.messenger) {
                        Text("(brak)").tag("")
                        ForEach(Contractor.messengers, id: \.self) { messenger in
                            Text(messenger).tag(messenger)
                        }
                    }
                    TextField("Adres komunikatora", text: $working.messengerAddress,
                              prompt: Text("np. numer telefonu, @nick lub e-mail"))
                        .disabled(working.messenger.isEmpty)
                    TextField("Adres e-mail", text: $working.email)
                    TextField("E-mail (faktury)", text: $working.invoiceEmail)
                    TextField("WWW", text: $working.website)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Uwagi")
                        TextEditor(text: $working.notes)
                            .frame(minHeight: 60)
                            .font(.body)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Anuluj", role: .cancel) { dismiss() }
                Spacer()
                Button("Zapisz") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(minWidth: 620, minHeight: 620)
        .navigationTitle(original == nil ? "Nowy kontrahent" : "Edycja kontrahenta")
        .onAppear {
            if let original { working.copy(from: original) }
        }
        .sheet(isPresented: $showingVerification) {
            ContractorVerificationView(nip: working.nip, expectedName: working.displayName)
        }
    }

    /// Pobiera nazwę i adres z wykazu podatników VAT i podstawia do formularza.
    @MainActor
    private func lookupByNIP() async {
        isLookingUp = true
        defer { isLookingUp = false }
        do {
            let result = try await ContractorLookupService().lookup(nip: working.nip)
            working.name = result.name
            working.nip = result.nip
            working.street = result.street
            working.houseNumber = result.houseNumber
            working.apartmentNumber = result.apartmentNumber
            working.postalCode = result.postalCode
            working.city = result.city
            lookupMessage = result.vatStatus.isEmpty
                ? "Pobrano dane z wykazu podatników VAT."
                : "Pobrano dane z wykazu podatników VAT (status: \(result.vatStatus))."
        } catch {
            lookupMessage = error.localizedDescription
        }
    }

    private func save() {
        if let original {
            original.copy(from: working)
        } else {
            modelContext.insert(working)
        }
        try? modelContext.save()
        dismiss()
    }
}

extension Contractor {
    /// Kopiuje wszystkie pola edytowalne (bez `id`) z innego kontrahenta.
    func copy(from other: Contractor) {
        name = other.name
        nameLine2 = other.nameLine2
        nip = other.nip
        uePrefix = other.uePrefix
        isSupplier = other.isSupplier
        isRecipient = other.isRecipient
        isNaturalPerson = other.isNaturalPerson
        consentsToEInvoices = other.consentsToEInvoices
        consentsToMarketing = other.consentsToMarketing
        street = other.street
        houseNumber = other.houseNumber
        apartmentNumber = other.apartmentNumber
        postalCode = other.postalCode
        city = other.city
        countryName = other.countryName
        countryCode = other.countryCode
        phone1 = other.phone1
        phone2 = other.phone2
        fax = other.fax
        messenger = other.messenger
        messengerAddress = other.messengerAddress
        email = other.email
        invoiceEmail = other.invoiceEmail
        website = other.website
        notes = other.notes
        prefersBilingualDocuments = other.prefersBilingualDocuments
    }
}
