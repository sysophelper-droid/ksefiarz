import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Arkusz eksportu zobowiązań zakupowych do pliku Elixir-O (paczka
/// przelewów). Użytkownik wybiera rachunek obciążany, datę, kodowanie oraz
/// dokumenty. Zapis pliku nie oznacza faktur jako opłaconych — bank dopiero
/// po imporcie pokazuje i autoryzuje dyspozycje.
public struct BankTransferExportView: View {

    @Query(sort: \BankAccount.label) private var accounts: [BankAccount]
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKeys.sellerName) private var companyName = ""
    @AppStorage(AppSettingsKeys.sellerAddress) private var companyAddress = ""

    private let rejections: [ElixirPaymentExporter.Rejection]

    @State private var transfers: [ElixirPaymentExporter.Transfer]
    @State private var selectedIDs: Set<UUID>
    @State private var sourceAccount: String
    @State private var executionDate = Date.now
    @State private var encoding: ElixirPaymentExporter.TextEncoding = .utf8
    @State private var errorMessage: String?

    public init(invoices: [Invoice]) {
        let preparation = ElixirPaymentExporter.prepare(invoices: invoices)
        self.rejections = preparation.rejections
        _transfers = State(initialValue: preparation.transfers)
        _selectedIDs = State(initialValue: Set(preparation.transfers.map(\.id)))
        _sourceAccount = State(
            initialValue: UserDefaults.standard.string(forKey: AppSettingsKeys.bankAccount) ?? ""
        )
    }

    private var selectedTransfers: [ElixirPaymentExporter.Transfer] {
        transfers.filter { selectedIDs.contains($0.id) }
    }

    private var selectedTotal: Double {
        selectedTransfers.reduce(0) { $0 + $1.amount }
    }

    private var plnAccounts: [BankAccount] {
        accounts.filter { CurrencyCode.isPLN($0.currency) }
    }

    private var canExport: Bool {
        !selectedTransfers.isEmpty
            && selectedTransfers.count <= ElixirPaymentExporter.maxTransfersPerFile
            && ElixirPaymentExporter.isValidNRB(sourceAccount)
            && !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Parametry paczki") {
                    DatePicker(
                        "Data realizacji",
                        selection: $executionDate,
                        in: Calendar.current.startOfDay(for: .now)...,
                        displayedComponents: .date
                    )
                    Picker("Kodowanie pliku", selection: $encoding) {
                        ForEach(ElixirPaymentExporter.TextEncoding.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .help("Wybierz kodowanie obsługiwane przez swój bank. UTF-8 działa m.in. w mBanku; systemy korporacyjne często wymagają Windows-1250 albo ISO-8859-2.")
                }

                Section("Rachunek zleceniodawcy") {
                    TextField(
                        "Rachunek obciążany (NRB)",
                        text: $sourceAccount,
                        prompt: Text("26 cyfr — konto firmowe w PLN")
                    )
                    if !plnAccounts.isEmpty {
                        Menu("Wybierz rachunek PLN ze słownika") {
                            ForEach(plnAccounts) { account in
                                Button(account.displayName) {
                                    sourceAccount = account.accountNumber
                                }
                            }
                        }
                    }
                    if !sourceAccount.isEmpty && !ElixirPaymentExporter.isValidNRB(sourceAccount) {
                        Label(
                            "Niepoprawny NRB lub suma kontrolna rachunku.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    LabeledContent("Zleceniodawca", value: companyName.isEmpty ? "uzupełnij w Ustawieniach" : companyName)
                }

                Section("Przelewy do eksportu (\(selectedTransfers.count)/\(transfers.count))") {
                    if selectedTransfers.count > ElixirPaymentExporter.maxTransfersPerFile {
                        Label(
                            "W jednej paczce wybierz maksymalnie \(ElixirPaymentExporter.maxTransfersPerFile) przelewów.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    if transfers.isEmpty {
                        ContentUnavailableView(
                            "Brak poprawnych zobowiązań",
                            systemImage: "banknote",
                            description: Text("Sprawdź przyczyny pominięcia poniżej.")
                        )
                    } else {
                        ForEach(transfers) { transfer in
                            transferRow(transfer)
                        }
                    }
                }

                if !rejections.isEmpty {
                    Section("Pominięte dokumenty (\(rejections.count))") {
                        ForEach(rejections) { rejection in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rejection.invoiceNumber)
                                    .fontWeight(.semibold)
                                Text(rejection.reason)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Liczba dyspozycji", value: "\(selectedTransfers.count)")
                    LabeledContent("Suma") {
                        Text(selectedTotal, format: .currency(code: "PLN"))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                } footer: {
                    Text("Plik Elixir-O nie zawiera nagłówka. Każdy przelew zostanie zapisany jako osobny rekord, a operacje MPP z kodem 53 i komunikatem VAT. Po imporcie zweryfikuj dyspozycje w banku przed autoryzacją. Sam eksport nie oznacza faktur jako opłaconych.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Anuluj", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    exportFile()
                } label: {
                    Label("Zapisz plik Elixir…", systemImage: "building.columns.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canExport)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 600)
        .navigationTitle("Przelewy do banku — Elixir-O")
        .alert(
            "Nie można zapisać pliku przelewów",
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

    @ViewBuilder
    private func transferRow(_ transfer: ElixirPaymentExporter.Transfer) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { selectedIDs.contains(transfer.id) },
                    set: { selected in
                        if selected { selectedIDs.insert(transfer.id) }
                        else { selectedIDs.remove(transfer.id) }
                    }
                )
            )
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(transfer.recipientName)
                    .fontWeight(.semibold)
                Text("Faktura \(transfer.invoiceNumber) · \(transfer.recipientAccount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if transfer.usesSplitPayment {
                    HStack {
                        Label("MPP", systemImage: "arrow.left.arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                        TextField(
                            "VAT",
                            value: vatBinding(for: transfer.id),
                            format: .number.precision(.fractionLength(2))
                        )
                        .frame(width: 90)
                        Text("zł VAT")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Przy płatności częściowej kwota VAT jest podpowiadana proporcjonalnie — zweryfikuj ją przed eksportem.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(transfer.amount, format: .currency(code: "PLN"))
                .monospacedDigit()
                .fontWeight(.semibold)
        }
        .opacity(selectedIDs.contains(transfer.id) ? 1 : 0.55)
    }

    private func vatBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { transfers.first(where: { $0.id == id })?.vatAmount ?? 0 },
            set: { value in
                guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
                transfers[index].vatAmount = value
            }
        )
    }

    private func exportFile() {
        do {
            let data = try ElixirPaymentExporter.data(
                for: selectedTransfers,
                options: .init(
                    sourceAccount: sourceAccount,
                    sourceName: companyName,
                    sourceAddress: companyAddress,
                    executionDate: executionDate,
                    encoding: encoding
                )
            )
            let saved = FileExportService.exportData(
                data,
                suggestedName: "przelewy_\(FA2Format.dateFormatter.string(from: executionDate)).pli",
                contentType: UTType(filenameExtension: "pli", conformingTo: .plainText) ?? .plainText
            )
            if saved { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
