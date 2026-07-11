import SwiftUI
import SwiftData

/// Lista rachunków bankowych w słowniku — pojedyncze kliknięcie zaznacza,
/// podwójne otwiera edycję (spójnie z listami faktur).
struct BankAccountsListView: View {

    @Query(sort: \BankAccount.label) private var accounts: [BankAccount]
    @Environment(\.modelContext) private var modelContext

    @State private var selection = Set<UUID>()
    @State private var editedAccount: BankAccount?
    @State private var showingNewAccount = false

    /// Globalny numer rachunku podstawiany do nowych faktur (Ustawienia).
    @AppStorage(AppSettingsKeys.bankAccount) private var defaultBankAccount = ""

    var body: some View {
        List(selection: $selection) {
            ForEach(accounts) { account in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(account.label.isEmpty ? account.accountNumber : account.label)
                                .font(.headline)
                            if account.accountNumber == defaultBankAccount {
                                Text("domyślny")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.orange)
                                    .help("Ten numer jest podstawiany do nowych faktur")
                            }
                        }
                        HStack(spacing: 8) {
                            if !account.label.isEmpty { Text(account.accountNumber) }
                            if !account.bankName.isEmpty { Text(account.bankName) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(account.currency)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 2)
                .tag(account.id)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                Button("Edytuj") {
                    editedAccount = accounts.first { ids.contains($0.id) }
                }
                Button("Ustaw jako domyślny dla nowych faktur") {
                    if let account = accounts.first(where: { ids.contains($0.id) }) {
                        defaultBankAccount = account.accountNumber
                    }
                }
                Button("Usuń ze słownika", role: .destructive) {
                    deleteAccounts(ids)
                }
            }
        } primaryAction: { ids in
            editedAccount = accounts.first { ids.contains($0.id) }
        }
        .overlay {
            if accounts.isEmpty {
                ContentUnavailableView(
                    "Brak rachunków bankowych",
                    systemImage: "banknote",
                    description: Text("Dodaj rachunek przyciskiem +. Wybrany rachunek można podstawić do faktury przy wystawianiu.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingNewAccount = true
                } label: {
                    Label("Nowy rachunek", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewAccount) {
            BankAccountEditorView(original: nil)
        }
        .sheet(item: $editedAccount) { account in
            BankAccountEditorView(original: account)
        }
    }

    private func deleteAccounts(_ ids: Set<UUID>) {
        for account in accounts where ids.contains(account.id) {
            modelContext.delete(account)
        }
        try? modelContext.save()
    }
}

/// Formularz rachunku bankowego.
/// Edycja na kopii roboczej — Anuluj nie zostawia śladów w bazie.
struct BankAccountEditorView: View {

    let original: BankAccount?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var working = BankAccount()

    private static let currencies = ["PLN", "EUR", "USD", "GBP", "CHF"]

    private var canSave: Bool {
        !working.accountNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        @Bindable var working = working
        VStack(spacing: 0) {
            Form {
                TextField("Identyfikator", text: $working.label,
                          prompt: Text("np. Firmowy PLN"))
                TextField("Numer rachunku bankowego", text: $working.accountNumber,
                          prompt: Text("26 cyfr (NRB) lub IBAN"))
                TextField("Nazwa banku", text: $working.bankName)
                TextField("SWIFT", text: $working.swift, prompt: Text("Kod BIC/SWIFT"))
                Picker("Waluta konta", selection: $working.currency) {
                    ForEach(Self.currencies, id: \.self) { currency in
                        Text(currency).tag(currency)
                    }
                }
                TextField("Numer rachunku VAT", text: $working.vatAccountNumber,
                          prompt: Text("Rachunek VAT (split payment) — opcjonalny"))
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
        .frame(minWidth: 480, minHeight: 340)
        .navigationTitle(original == nil ? "Nowy rachunek bankowy" : "Edycja rachunku")
        .onAppear {
            if let original { working.copy(from: original) }
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

extension BankAccount {
    /// Kopiuje wszystkie pola edytowalne (bez `id`) z innego rachunku.
    func copy(from other: BankAccount) {
        label = other.label
        accountNumber = other.accountNumber
        bankName = other.bankName
        swift = other.swift
        currency = other.currency
        vatAccountNumber = other.vatAccountNumber
    }
}
