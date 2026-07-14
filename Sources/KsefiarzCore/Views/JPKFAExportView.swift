import SwiftUI
import SwiftData

/// Eksport JPK_FA(4) — pełnego JPK faktur sprzedaży przekazywanego
/// NA ŻĄDANIE organu podatkowego (kontrola, czynności sprawdzające,
/// postępowanie podatkowe). Wybór zakresu dat wystawienia, strukturalny
/// adres podmiotu (wymóg XSD), podgląd sum kontrolnych i ostrzeżeń,
/// zapis pliku XML.
public struct JPKFAExportView: View {

    @Query private var invoices: [Invoice]
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKeys.sellerName) private var sellerName = ""
    @AppStorage(AppSettingsKeys.nip) private var sellerNIP = ""
    @AppStorage(AppSettingsKeys.jpkTaxOfficeCode) private var taxOfficeCode = ""
    @AppStorage(AppSettingsKeys.jpkFAWojewodztwo) private var wojewodztwo = ""
    @AppStorage(AppSettingsKeys.jpkFAPowiat) private var powiat = ""
    @AppStorage(AppSettingsKeys.jpkFAGmina) private var gmina = ""
    @AppStorage(AppSettingsKeys.jpkFAUlica) private var ulica = ""
    @AppStorage(AppSettingsKeys.jpkFANrDomu) private var nrDomu = ""
    @AppStorage(AppSettingsKeys.jpkFANrLokalu) private var nrLokalu = ""
    @AppStorage(AppSettingsKeys.jpkFAMiejscowosc) private var miejscowosc = ""
    @AppStorage(AppSettingsKeys.jpkFAKodPocztowy) private var kodPocztowy = ""

    @State private var dateFrom: Date
    @State private var dateTo: Date

    public init() {
        // Domyślnie poprzedni miesiąc kalendarzowy — typowy zakres żądania.
        let calendar = Calendar.current
        let previous = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now
        let components = calendar.dateComponents([.year, .month], from: previous)
        let start = calendar.date(from: components) ?? .now
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        _dateFrom = State(initialValue: start)
        _dateTo = State(initialValue: end)
    }

    private var options: JPKFAOptions {
        JPKFAOptions(
            dateFrom: dateFrom,
            dateTo: dateTo,
            sellerNIP: sellerNIP,
            sellerName: sellerName,
            taxOfficeCode: taxOfficeCode,
            wojewodztwo: wojewodztwo,
            powiat: powiat,
            gmina: gmina,
            ulica: ulica,
            nrDomu: nrDomu,
            nrLokalu: nrLokalu,
            miejscowosc: miejscowosc,
            kodPocztowy: kodPocztowy
        )
    }

    private var result: JPKFAResult {
        JPKFAGenerator.generate(invoices: invoices, options: options)
    }

    private var isReady: Bool {
        options.isReadyForExport
    }

    public var body: some View {
        let result = self.result
        VStack(spacing: 0) {
            Form {
                Section("Okres (daty wystawienia faktur)") {
                    DatePicker("Od", selection: $dateFrom, displayedComponents: .date)
                    DatePicker("Do", selection: $dateTo, displayedComponents: .date)
                    if dateFrom > dateTo {
                        Label("Data początkowa jest późniejsza niż końcowa.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text("Zakres dopasuj do wezwania organu — JPK_FA obejmuje wyłącznie wystawione faktury sprzedaży (bez zakupów, samofaktur wystawionych dla dostawców i faktur VAT RR).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Podmiot") {
                    LabeledContent("Podatnik", value: sellerName.isEmpty ? "uzupełnij w Ustawieniach" : sellerName)
                    LabeledContent("NIP", value: sellerNIP.isEmpty ? "uzupełnij w Ustawieniach" : sellerNIP)
                    TextField("Kod urzędu skarbowego", text: $taxOfficeCode, prompt: Text("np. 1219"))
                        .help("Czterocyfrowy kod urzędu skarbowego (KodUrzedu) — wspólny z eksportem JPK_V7")
                }
                Section("Adres podmiotu (wymagany przez strukturę)") {
                    TextField("Województwo", text: $wojewodztwo, prompt: Text("np. małopolskie"))
                    TextField("Powiat", text: $powiat, prompt: Text("np. Kraków"))
                    TextField("Gmina", text: $gmina, prompt: Text("np. Kraków"))
                    TextField("Ulica (opcjonalnie)", text: $ulica)
                    TextField("Nr domu", text: $nrDomu)
                    TextField("Nr lokalu (opcjonalnie)", text: $nrLokalu)
                    TextField("Miejscowość", text: $miejscowosc)
                    TextField("Kod pocztowy", text: $kodPocztowy, prompt: Text("np. 30-001"))
                }
                Section("Podsumowanie") {
                    LabeledContent("Faktury", value: "\(result.invoiceCount)")
                    LabeledContent("Wartość faktur (suma P_15)") {
                        Text(result.invoiceTotal, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }
                    LabeledContent("Wiersze faktur", value: "\(result.lineCount)")
                    if result.orderCount > 0 {
                        LabeledContent("Zamówienia (faktury zaliczkowe)", value: "\(result.orderCount)")
                    }
                    if !result.currencies.isEmpty {
                        LabeledContent("Waluty", value: result.currencies.joined(separator: ", "))
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
                Text("JPK na żądanie przekazuje się elektronicznie (np. Klient JPK WEB) albo na nośniku — nie e-mailem. Plik nie podlega korekcie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Anuluj") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    let name = "JPK_FA_\(formatter.string(from: dateFrom))_\(formatter.string(from: dateTo)).xml"
                    if FileExportService.exportData(Data(result.xml.utf8), suggestedName: name, contentType: .xml) {
                        dismiss()
                    }
                } label: {
                    Label("Zapisz JPK_FA", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isReady || !result.isSchemaReady)
                .help(exportHelp(for: result))
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 620)
        .navigationTitle("Eksport JPK_FA (na żądanie)")
    }

    private func exportHelp(for result: JPKFAResult) -> String {
        if !isReady {
            return "Uzupełnij dane podmiotu (prawidłowa nazwa i NIP w Ustawieniach, kod urzędu i pełny adres powyżej)"
        }
        if result.invoiceCount == 0 {
            return "Brak faktur sprzedaży w wybranym okresie"
        }
        if result.lineCount == 0 {
            return "Plik bez pozycji FakturaWiersz nie jest zgodny z XSD JPK_FA(4)"
        }
        return "Zapisuje plik XML JPK_FA(4)"
    }
}
