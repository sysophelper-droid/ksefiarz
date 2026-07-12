import SwiftUI
import SwiftData

/// Eksport informacji podsumowującej VAT-UE(5): wybór miesiąca, dane podmiotu
/// (kod urzędu), podgląd zestawień WDT/WNT/usługi i ostrzeżeń, zapis pliku XML.
public struct VATUEExportView: View {

    @Query private var invoices: [Invoice]
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKeys.sellerName) private var sellerName = ""
    @AppStorage(AppSettingsKeys.nip) private var sellerNIP = ""
    @AppStorage(AppSettingsKeys.jpkTaxOfficeCode) private var taxOfficeCode = ""

    @State private var year: Int
    @State private var month: Int

    public init() {
        // Domyślnie poprzedni miesiąc — VAT-UE składa się do 25. dnia
        // miesiąca następującego po rozliczanym.
        let previous = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        let components = Calendar.current.dateComponents([.year, .month], from: previous)
        _year = State(initialValue: components.year ?? 2026)
        _month = State(initialValue: components.month ?? 1)
    }

    private var options: VATUEOptions {
        VATUEOptions(
            year: year,
            month: month,
            sellerNIP: sellerNIP,
            sellerName: sellerName,
            taxOfficeCode: taxOfficeCode
        )
    }

    private var result: VATUEResult {
        VATUEGenerator.generate(invoices: invoices, options: options)
    }

    private var isReady: Bool {
        let normalizedName = sellerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return InvoiceValidator.isValidNIP(sellerNIP)
            && !normalizedName.isEmpty && normalizedName.count <= 240
            && taxOfficeCode.filter(\.isNumber).count == 4
    }

    public var body: some View {
        let result = self.result
        VStack(spacing: 0) {
            Form {
                Section("Okres rozliczeniowy") {
                    Picker("Rok", selection: $year) {
                        ForEach(2021...Calendar.current.component(.year, from: .now), id: \.self) {
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
                        .help("Czterocyfrowy kod urzędu skarbowego (KodUrzedu) — wspólny z JPK_V7M.")
                }
                Section("Podsumowanie") {
                    summaryRow(
                        "WDT (część C)", count: result.wdt.count, total: result.totalWDT,
                        help: "Wewnątrzwspólnotowe dostawy towarów"
                    )
                    summaryRow(
                        "WNT (część D)", count: result.wnt.count, total: result.totalWNT,
                        help: "Wewnątrzwspólnotowe nabycia towarów"
                    )
                    summaryRow(
                        "Usługi (część E)", count: result.services.count, total: result.totalServices,
                        help: "Wewnątrzwspólnotowe świadczenie usług"
                    )
                }
                if !result.isEmpty {
                    Section("Kontrahenci") {
                        ForEach(entryRows(result), id: \.self) { row in
                            Text(row).font(.caption).monospacedDigit()
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
                Text("Plik zweryfikuj przed wysyłką (bramka e-Deklaracje). Eksport tworzy kandydatów na podstawie numeru VAT UE, kodu CN/PKWiU i — dla sprzedaży — stawki 0%. Potwierdź warunki WDT/WNT lub art. 28b; import usług i OSS pozostają poza VAT-UE.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Anuluj") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    let name = String(format: "VAT-UE_%04d-%02d.xml", year, month)
                    if FileExportService.exportData(Data(result.xml.utf8), suggestedName: name, contentType: .xml) {
                        dismiss()
                    }
                } label: {
                    Label("Zapisz VAT-UE", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isReady || result.isEmpty)
                .help(isReady ? "Zapisuje plik XML VAT-UE(5)" : "Uzupełnij dane podmiotu (prawidłowa nazwa i NIP w Ustawieniach, kod urzędu powyżej)")
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 560)
        .navigationTitle("Eksport VAT-UE")
    }

    private func summaryRow(_ title: String, count: Int, total: Int, help: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Text("\(count) kontr.")
                    .foregroundStyle(.secondary)
                Text(Double(total), format: .currency(code: "PLN"))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
        }
        .help(help)
    }

    /// Wiersze podglądu: kraj + numer VAT + kwota per część.
    private func entryRows(_ result: VATUEResult) -> [String] {
        func rows(_ entries: [VATUEEntry], label: String) -> [String] {
            entries.map { "\(label)  \($0.countryCode) \($0.vatNumber)  →  \($0.amountPLN) zł" }
        }
        return rows(result.wdt, label: "WDT")
            + rows(result.wnt, label: "WNT")
            + rows(result.services, label: "USŁ")
    }
}
