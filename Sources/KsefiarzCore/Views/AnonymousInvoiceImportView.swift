import SwiftData
import SwiftUI

/// Arkusz anonimowego pobrania pojedynczej faktury zakupowej po danych
/// identyfikujących — bez tokenu, certyfikatu i logowania do KSeF.
public struct AnonymousInvoiceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AppSettingsKeys.environment) private var environmentRaw = KSeFEnvironment.test.rawValue
    @AppStorage(AppSettingsKeys.nip) private var myNIP = ""
    @AppStorage(AppSettingsKeys.sellerName) private var myName = ""
    @AppStorage(AppSettingsKeys.prepaidForms) private var prepaidFormsRaw = PaymentFormPolicy.encode(PaymentFormPolicy.defaultPrepaidForms)

    @State private var ksefNumber = ""
    @State private var invoiceNumber = ""
    @State private var buyerIdentifierType: AnonymousInvoiceBuyerIdentifierType = .nip
    @State private var buyerIdentifierValue = ""
    @State private var buyerName = ""
    @State private var buyerHasNoName = false
    @State private var amount = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var loadedDefaults = false

    public init() {}

    private var environment: KSeFEnvironment {
        KSeFEnvironment(rawValue: environmentRaw) ?? .test
    }

    private var parsedAmount: Decimal? {
        KSeFAnonymousAccessService.parseAmountInput(amount)
    }

    private var canImport: Bool {
        !ksefNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (buyerIdentifierType == .none
                || !buyerIdentifierValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && parsedAmount != nil
            && !isImporting
            && resultMessage == nil
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Faktura") {
                    TextField("Numer KSeF", text: $ksefNumber)
                        .textContentType(.none)
                    TextField("Numer faktury nadany przez sprzedawcę", text: $invoiceNumber)
                    TextField("Kwota należności ogółem", text: $amount)
                        .help("Podaj kwotę brutto dokładnie jak na fakturze, np. 123,00")
                }

                Section("Dane nabywcy") {
                    Picker("Rodzaj identyfikatora", selection: $buyerIdentifierType) {
                        ForEach(AnonymousInvoiceBuyerIdentifierType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    if buyerIdentifierType != .none {
                        TextField(identifierPrompt, text: $buyerIdentifierValue)
                    }
                    Toggle("Faktura nie zawiera imienia i nazwiska ani nazwy nabywcy", isOn: $buyerHasNoName)
                    if !buyerHasNoName {
                        TextField("Imię i nazwisko lub nazwa nabywcy", text: $buyerName)
                    }
                }

                Section("Sposób pobrania") {
                    LabeledContent("Środowisko", value: environment.displayName)
                    Text("Pobranie korzysta z publicznej bramki anonimowego dostępu MF. Nie wymaga tokenu ani certyfikatu KSeF i nie wykonuje żadnej operacji zapisu w KSeF.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let resultMessage {
                    Section {
                        Label(resultMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pobierz fakturę po numerze KSeF")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(resultMessage == nil ? "Anuluj" : "Zamknij") { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await importInvoice() }
                    } label: {
                        if isImporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Pobierz i dodaj")
                        }
                    }
                    .disabled(!canImport)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 560)
        .interactiveDismissDisabled(isImporting)
        .onAppear(perform: loadDefaultsOnce)
        .alert(
            "Nie udało się pobrać faktury",
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

    private var identifierPrompt: String {
        switch buyerIdentifierType {
        case .nip: return "NIP nabywcy"
        case .vatUE: return "Numer VAT-UE nabywcy"
        case .other: return "Inny identyfikator nabywcy"
        case .none: return ""
        }
    }

    private func loadDefaultsOnce() {
        guard !loadedDefaults else { return }
        loadedDefaults = true
        buyerIdentifierValue = myNIP
        buyerName = myName
    }

    @MainActor
    private func importInvoice() async {
        guard let grossAmount = parsedAmount else { return }
        isImporting = true
        defer { isImporting = false }

        let request = AnonymousInvoiceAccessRequest(
            ksefNumber: ksefNumber,
            invoiceNumber: invoiceNumber,
            buyerIdentifierType: buyerIdentifierType,
            buyerIdentifierValue: buyerIdentifierValue,
            buyerName: buyerHasNoName ? nil : buyerName,
            grossAmount: grossAmount
        )
        do {
            let service = KSeFAnonymousAccessService(environment: environment)
            let xml = try await service.downloadInvoice(request)
            let result = try AnonymousInvoiceImportEngine.importInvoice(
                xmlData: xml,
                ksefNumber: request.ksefNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                prepaidForms: PaymentFormPolicy.decode(prepaidFormsRaw),
                context: modelContext
            )
            switch result {
            case .inserted:
                resultMessage = "Faktura została pobrana i dodana do zakupów."
            case .alreadyExists:
                resultMessage = "Faktura o tym numerze KSeF jest już w bazie — nie utworzono duplikatu."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
