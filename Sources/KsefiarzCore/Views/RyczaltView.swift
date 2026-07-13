import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Ewidencja przychodów (ryczałt) wyprowadzana z faktur sprzedaży. Widok
/// pokazuje przychód i szacowany ryczałt z podziałem na stawki, a eksport CSV
/// zachowuje pełny 17-kolumnowy układ wzoru z 2026 r. (Dz.U. 2025 poz. 1294).
public struct RyczaltView: View {
    @Query(sort: [SortDescriptor(\Invoice.issueDate)]) private var invoices: [Invoice]

    @AppStorage(AppSettingsKeys.ryczaltDefaultRate) private var defaultRateRaw = RyczaltRate.r8_5.rawValue

    @State private var year = Calendar.current.component(.year, from: .now)
    /// 0 = cały rok, 1...12 = miesiąc.
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var showExcluded = false
    @State private var selectedInvoiceID: UUID?

    public init() {}

    private var defaultRate: RyczaltRate { RyczaltEngine.defaultRate(fromSetting: defaultRateRaw) }

    private var availableYears: [Int] {
        let values = Set(invoices.filter { $0.kind == .sales }
            .map { Calendar.current.component(.year, from: RyczaltEngine.effectiveDate(for: $0)) } + [year])
        return values.sorted(by: >)
    }

    private var rows: [RyczaltEngine.Row] {
        RyczaltEngine.rows(
            from: invoices,
            period: .init(year: year, month: month == 0 ? nil : month),
            defaultRate: defaultRate,
            includeExcluded: showExcluded
        )
    }

    private var summary: RyczaltEngine.Summary { RyczaltEngine.summary(for: rows) }

    private var selectedInvoice: Invoice? {
        guard let selectedInvoiceID else { return nil }
        return invoices.first { $0.id == selectedInvoiceID }
    }

    public var body: some View {
        VStack(spacing: 0) {
            summaryBar
            if !summary.usedRates.isEmpty {
                Divider()
                rateBreakdown
            }
            Divider()
            Table(rows, selection: $selectedInvoiceID) {
                TableColumn("Lp.") { row in
                    Text("\(row.ordinal)").monospacedDigit()
                }.width(36)
                TableColumn("Data") { row in
                    Text(row.revenueDate, format: .dateTime.day().month().year())
                }.width(min: 86, ideal: 96)
                TableColumn("Dowód") { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.documentNumber).lineLimit(1)
                        if !row.ksefNumber.isEmpty {
                            Text(row.ksefNumber).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }.width(min: 130, ideal: 200)
                TableColumn("Kontrahent") { row in
                    Text(row.contractorTaxID.isEmpty ? "—" : row.contractorTaxID).lineLimit(1)
                }.width(min: 100, ideal: 140)
                TableColumn("Stawka") { row in
                    HStack(spacing: 5) {
                        if row.isExcluded { Image(systemName: "nosign").foregroundStyle(.secondary) }
                        Text(row.rate.displayName).monospacedDigit()
                        if row.warning != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    }
                }.width(min: 80, ideal: 100)
                TableColumn("Przychód PLN") { row in
                    Text(row.amountPLN, format: .currency(code: "PLN"))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }.width(min: 100, ideal: 130)
                TableColumn("Ryczałt (szac.)") { row in
                    Text(row.estimatedTax, format: .currency(code: "PLN"))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }.width(min: 100, ideal: 120)
            }
            .opacity(rows.isEmpty ? 0.35 : 1)
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "Brak przychodów w okresie",
                        systemImage: "list.bullet.rectangle.portrait",
                        description: Text("Zmień okres albo włącz wyświetlanie wykluczonych dokumentów.")
                    )
                }
            }

            if let invoice = selectedInvoice {
                Divider()
                RyczaltEntryEditor(invoice: invoice, defaultRate: defaultRate)
                    .frame(minHeight: 210, idealHeight: 240, maxHeight: 290)
            } else {
                Divider()
                Text("Zaznacz wpis, aby poprawić stawkę, datę lub kwotę przychodu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .navigationTitle("Ewidencja przychodów")
        .toolbar {
            ToolbarItemGroup {
                Picker("Rok", selection: $year) {
                    ForEach(availableYears, id: \.self) { Text(String($0)).tag($0) }
                }.frame(width: 90)
                Picker("Miesiąc", selection: $month) {
                    Text("Cały rok").tag(0)
                    ForEach(1...12, id: \.self) { value in
                        Text(Calendar.current.monthSymbols[value - 1].capitalized).tag(value)
                    }
                }.frame(width: 150)
                Toggle("Pokaż wykluczone", isOn: $showExcluded)
                    .toggleStyle(.checkbox)
                Button(action: exportCSV) {
                    Label("Eksportuj CSV", systemImage: "square.and.arrow.down")
                }
                .disabled(rows.allSatisfy(\.isExcluded))
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 24) {
            summaryValue("Przychód", summary.totalRevenue, color: .green)
            summaryValue("Ryczałt (szac.)", summary.estimatedTax, color: .blue)
            Spacer()
            Text("\(rows.filter { !$0.isExcluded }.count) wpisów")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    /// Podział przychodu i szacowanego ryczałtu na poszczególne stawki.
    private var rateBreakdown: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(summary.usedRates) { rate in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rate.displayName).font(.caption.weight(.semibold)).monospacedDigit()
                        Text(summary.revenueByRate[rate] ?? 0, format: .currency(code: "PLN"))
                            .font(.callout).monospacedDigit()
                        Text("ryczałt: " + (summary.taxByRate[rate] ?? 0).formatted(.currency(code: "PLN")))
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
    }

    private func summaryValue(_ title: String, _ value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: "PLN"))
                .font(.headline).monospacedDigit().foregroundStyle(color)
        }
    }

    private func exportCSV() {
        let suffix = month == 0 ? String(year) : String(format: "%04d-%02d", year, month)
        _ = FileExportService.exportData(
            Data(RyczaltCSVExporter.csv(for: rows).utf8),
            suggestedName: "EwidencjaPrzychodow_\(suffix).csv",
            contentType: .commaSeparatedText
        )
    }
}

private struct RyczaltEntryEditor: View {
    @Bindable var invoice: Invoice
    let defaultRate: RyczaltRate

    private var automaticDate: Date { invoice.saleDate ?? invoice.issueDate }
    private var automaticAmount: Double {
        (DashboardAnalytics.inPLN(invoice.netAmount, invoice: invoice) * 100).rounded() / 100
    }

    var body: some View {
        Form {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Wyklucz z ewidencji", isOn: $invoice.isExcludedFromRyczalt)
                    Picker("Stawka ryczałtu", selection: Binding(
                        get: { RyczaltEngine.effectiveRate(for: invoice, default: defaultRate) },
                        set: { invoice.ryczaltRateRaw = $0.rawValue }
                    )) {
                        ForEach(RyczaltRate.allCases) { rate in
                            Text(rate.displayName).tag(rate)
                        }
                    }
                    Button("Przywróć stawkę domyślną (\(defaultRate.displayName))") {
                        invoice.ryczaltRateRaw = ""
                    }
                    .font(.caption).disabled(invoice.ryczaltRateRaw.isEmpty)
                }
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker("Data wpisu", selection: Binding(
                        get: { invoice.ryczaltEntryDate ?? RyczaltEngine.effectiveDate(for: invoice) },
                        set: { invoice.ryczaltEntryDate = $0 }
                    ), displayedComponents: .date)
                    Button("Przywróć datę wpisu z daty przychodu") {
                        invoice.ryczaltEntryDate = nil
                    }
                    .font(.caption).disabled(invoice.ryczaltEntryDate == nil)
                    DatePicker("Data uzyskania przychodu", selection: Binding(
                        get: { invoice.ryczaltEventDate ?? automaticDate },
                        set: { invoice.ryczaltEventDate = $0 }
                    ), displayedComponents: .date)
                    Button("Przywróć datę z faktury") { invoice.ryczaltEventDate = nil }
                        .font(.caption).disabled(invoice.ryczaltEventDate == nil)
                    HStack {
                        TextField("Kwota przychodu w PLN", value: $invoice.ryczaltAmountOverride,
                                  format: .number.precision(.fractionLength(2)))
                        Button("Automatyczna: \(automaticAmount.formatted(.number.precision(.fractionLength(2))))") {
                            invoice.ryczaltAmountOverride = nil
                        }
                        .font(.caption)
                        .disabled(invoice.ryczaltAmountOverride == nil)
                    }
                    TextField("Uwagi (kol. 17)", text: $invoice.ryczaltNotes)
                    if let warning = RyczaltEngine.rows(
                        from: [invoice],
                        period: .init(year: Calendar.current.component(.year, from: RyczaltEngine.effectiveDate(for: invoice))),
                        defaultRate: defaultRate,
                        includeExcluded: true
                    ).first?.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
