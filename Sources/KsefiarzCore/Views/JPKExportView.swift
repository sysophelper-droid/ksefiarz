import SwiftUI
import SwiftData

/// Eksport ewidencji VAT do pliku JPK_V7M (miesięczny) lub JPK_V7K
/// (kwartalny — mały podatnik): wybór wariantu i miesiąca, dane podmiotu
/// (kod urzędu, e-mail), podgląd sum i ostrzeżeń, zapis pliku XML.
///
/// W wariancie kwartalnym ewidencję składa się co miesiąc, a część
/// deklaracyjną raz na kwartał — w pliku ostatniego miesiąca kwartału.
public struct JPKExportView: View {

    @Query private var invoices: [Invoice]
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKeys.sellerName) private var sellerName = ""
    @AppStorage(AppSettingsKeys.nip) private var sellerNIP = ""
    @AppStorage(AppSettingsKeys.jpkTaxOfficeCode) private var taxOfficeCode = ""
    @AppStorage(AppSettingsKeys.jpkEmail) private var email = ""

    @State private var variant: JPKV7Variant = .monthly
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

    // Miesiąc kończący kwartał (3, 6, 9, 12) — tylko wtedy V7K niesie deklarację.
    private var isQuarterEndMonth: Bool { month % 3 == 0 }
    private var quarterNumber: Int { (month - 1) / 3 + 1 }
    private var declarationApplies: Bool { variant == .monthly || isQuarterEndMonth }
    private var schemaVersion: Int {
        variant.schema(year: year, month: month).formVariant
    }

    private var options: JPKV7Options {
        JPKV7Options(
            variant: variant,
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
                Section("Wariant rozliczenia") {
                    Picker("Rozliczenie VAT", selection: $variant) {
                        ForEach(JPKV7Variant.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .help("Miesięczny (JPK_V7M) lub kwartalny (JPK_V7K — mały podatnik rozliczający VAT kwartalnie).")
                    if variant == .quarterly {
                        Text(quarterHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                if declarationApplies {
                    Section(variant == .quarterly ? "Deklaracja (za \(quarterNumber). kwartał)" : "Deklaracja") {
                        Picker("Cel złożenia", selection: $purpose) {
                            Text("Złożenie (1)").tag(1)
                            Text("Korekta (2)").tag(2)
                        }
                        Toggle(
                            variant == .quarterly ? "Dołącz część deklaracyjną (VAT-7K)" : "Dołącz część deklaracyjną (VAT-7)",
                            isOn: $includeDeclaration
                        )
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
                } else {
                    Section("Deklaracja") {
                        Label(
                            "Deklarację VAT-7K za \(quarterNumber). kwartał złożysz z ewidencją ostatniego miesiąca kwartału (\(Calendar.current.monthSymbols[quarterNumber * 3 - 1])). Ten plik zawiera samą ewidencję.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Section(variant == .quarterly && declarationApplies ? "Podsumowanie — ewidencja (miesiąc)" : "Podsumowanie") {
                    LabeledContent("Wiersze sprzedaży", value: "\(result.salesCount)")
                    LabeledContent("Wiersze zakupów", value: "\(result.purchaseCount)")
                    LabeledContent("Podatek należny") {
                        Text(result.outputVAT, format: .currency(code: "PLN")).monospacedDigit()
                    }
                    LabeledContent("Podatek naliczony") {
                        Text(result.inputVAT, format: .currency(code: "PLN")).monospacedDigit()
                    }
                }
                if result.hasDeclaration {
                    Section(variant == .quarterly ? "Deklaracja — za \(quarterNumber). kwartał" : "Rozliczenie deklaracji") {
                        if variant == .quarterly {
                            LabeledContent("Podatek należny kwartału") {
                                Text(result.declarationOutputVAT, format: .currency(code: "PLN")).monospacedDigit()
                            }
                            LabeledContent("Podatek naliczony kwartału") {
                                Text(result.declarationInputVAT, format: .currency(code: "PLN")).monospacedDigit()
                            }
                        }
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
                    let name = variant.fileTag + String(format: "_%04d-%02d.xml", year, month)
                    if FileExportService.exportData(Data(result.xml.utf8), suggestedName: name, contentType: .xml) {
                        dismiss()
                    }
                } label: {
                    Label("Zapisz \(variant.fileTag)", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isReady || (result.salesCount == 0 && result.purchaseCount == 0))
                .help(isReady ? "Zapisuje plik XML \(variant.fileTag)(\(schemaVersion))" : "Uzupełnij dane podmiotu (nazwa i NIP w Ustawieniach, kod urzędu i e-mail powyżej)")
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 560)
        .navigationTitle("Eksport \(variant.fileTag)")
    }

    /// Podpowiedź o roli miesiąca w kwartale (V7K).
    private var quarterHint: String {
        let lastMonthName = Calendar.current.monthSymbols[quarterNumber * 3 - 1]
        if isQuarterEndMonth {
            return "\(quarterNumber). kwartał — ostatni miesiąc kwartału: plik zawiera ewidencję tego miesiąca oraz deklarację VAT-7K za cały kwartał."
        } else {
            return "\(quarterNumber). kwartał — miesiąc w trakcie kwartału: plik zawiera samą ewidencję. Deklarację VAT-7K złożysz z ewidencją za \(lastMonthName)."
        }
    }
}
