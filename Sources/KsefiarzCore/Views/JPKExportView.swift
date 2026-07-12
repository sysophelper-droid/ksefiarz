import SwiftUI
import SwiftData

/// Eksport ewidencji VAT do pliku JPK_V7M: wybór miesiąca, dane podmiotu
/// (kod urzędu, e-mail), podgląd sum i ostrzeżeń, zapis pliku XML.
public struct JPKExportView: View {

    @Query private var invoices: [Invoice]
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKeys.sellerName) private var sellerName = ""
    @AppStorage(AppSettingsKeys.nip) private var sellerNIP = ""
    @AppStorage(AppSettingsKeys.jpkTaxOfficeCode) private var taxOfficeCode = ""
    @AppStorage(AppSettingsKeys.jpkEmail) private var email = ""

    @State private var year: Int
    @State private var month: Int
    @State private var purpose = 1
    @State private var includeDeclaration = true
    @State private var previousExcess = 0

    public init() {
        // Domyślnie poprzedni miesiąc — JPK składa się do 25. dnia
        // miesiąca następującego po rozliczanym.
        let previous = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        let components = Calendar.current.dateComponents([.year, .month], from: previous)
        _year = State(initialValue: components.year ?? 2026)
        _month = State(initialValue: components.month ?? 1)
    }

    private var options: JPKV7Options {
        JPKV7Options(
            year: year,
            month: month,
            sellerNIP: sellerNIP,
            sellerName: sellerName,
            email: email,
            taxOfficeCode: taxOfficeCode,
            purpose: purpose,
            previousExcess: previousExcess,
            includeDeclaration: includeDeclaration
        )
    }

    private var result: JPKV7Result {
        JPKV7Generator.generate(invoices: invoices, options: options)
    }

    private var isReady: Bool {
        !sellerNIP.isEmpty && !sellerName.isEmpty && !email.isEmpty
            && taxOfficeCode.filter(\.isNumber).count == 4
    }

    public var body: some View {
        let result = self.result
        VStack(spacing: 0) {
            Form {
                Section("Okres rozliczeniowy") {
                    Picker("Rok", selection: $year) {
                        ForEach(2022...Calendar.current.component(.year, from: .now), id: \.self) {
                            Text(String($0)).tag($0)
                        }
                    }
                    Picker("Miesiąc", selection: $month) {
                        ForEach(1...12, id: \.self) { value in
                            Text(Calendar.current.monthSymbols[value - 1]).tag(value)
                        }
                    }
                }
                Section("Podmiot") {
                    LabeledContent("Podatnik", value: sellerName.isEmpty ? "uzupełnij w Ustawieniach" : sellerName)
                    LabeledContent("NIP", value: sellerNIP.isEmpty ? "uzupełnij w Ustawieniach" : sellerNIP)
                    TextField("Kod urzędu skarbowego", text: $taxOfficeCode, prompt: Text("np. 1219"))
                        .help("Czterocyfrowy kod urzędu skarbowego (KodUrzedu) — lista kodów na podatki.gov.pl")
                    TextField("E-mail podatnika", text: $email, prompt: Text("adres@firma.pl"))
                }
                Section("Deklaracja") {
                    Picker("Cel złożenia", selection: $purpose) {
                        Text("Złożenie (1)").tag(1)
                        Text("Korekta (2)").tag(2)
                    }
                    Toggle("Dołącz część deklaracyjną (VAT-7)", isOn: $includeDeclaration)
                        .help("Korekta samej ewidencji może być składana bez deklaracji.")
                    if includeDeclaration {
                        TextField(
                            "Nadwyżka z poprzedniej deklaracji (P_39, zł)",
                            value: $previousExcess,
                            format: .number
                        )
                        .help("Kwota nadwyżki podatku naliczonego nad należnym przeniesiona z poprzedniego okresu (P_62 poprzedniej deklaracji).")
                    }
                }
                Section("Podsumowanie") {
                    LabeledContent("Wiersze sprzedaży", value: "\(result.salesCount)")
                    LabeledContent("Wiersze zakupów", value: "\(result.purchaseCount)")
                    LabeledContent("Podatek należny") {
                        Text(result.outputVAT, format: .currency(code: "PLN")).monospacedDigit()
                    }
                    LabeledContent("Podatek naliczony") {
                        Text(result.inputVAT, format: .currency(code: "PLN")).monospacedDigit()
                    }
                    if includeDeclaration {
                        LabeledContent(result.amountDue > 0 ? "Do wpłaty (P_51)" : "Do przeniesienia (P_62)") {
                            Text(
                                Double(result.amountDue > 0 ? result.amountDue : result.excessCarried),
                                format: .currency(code: "PLN")
                            )
                            .monospacedDigit()
                            .fontWeight(.semibold)
                        }
                    }
                }
                if !result.warnings.isEmpty {
                    Section("Do weryfikacji (\(result.warnings.count))") {
                        ForEach(result.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text("Plik zweryfikuj przed wysyłką (np. w e-mikrofirmie) — okres przypisywany po dacie sprzedaży/wystawienia, zakupy jako pozostałe nabycia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Anuluj") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    let name = String(format: "JPK_V7M_%04d-%02d.xml", year, month)
                    if FileExportService.exportData(Data(result.xml.utf8), suggestedName: name, contentType: .xml) {
                        dismiss()
                    }
                } label: {
                    Label("Zapisz JPK_V7M", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isReady || (result.salesCount == 0 && result.purchaseCount == 0))
                .help(isReady ? "Zapisuje plik XML JPK_V7M(2)" : "Uzupełnij dane podmiotu (nazwa i NIP w Ustawieniach, kod urzędu i e-mail powyżej)")
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 560)
        .navigationTitle("Eksport JPK_V7M")
    }
}
