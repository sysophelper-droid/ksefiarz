import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Księga Przychodów i Rozchodów wyprowadzana z faktur. Widok pokazuje
/// najważniejsze pola robocze, a eksport CSV zachowuje pełny układ 1–19.
public struct KPiRView: View {
    @Query(sort: [SortDescriptor(\Invoice.issueDate)]) private var invoices: [Invoice]

    @State private var year = Calendar.current.component(.year, from: .now)
    /// 0 = cały rok, 1...12 = miesiąc.
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var showExcluded = false
    @State private var selectedInvoiceID: UUID?

    public init() {}

    private var availableYears: [Int] {
        let values = Set(invoices.map { Calendar.current.component(.year, from: KPiREngine.effectiveDate(for: $0)) } + [year])
        return values.sorted(by: >)
    }

    private var rows: [KPiREngine.Row] {
        KPiREngine.rows(
            from: invoices,
            period: .init(year: year, month: month == 0 ? nil : month),
            includeExcluded: showExcluded
        )
    }

    private var summary: KPiREngine.Summary { KPiREngine.summary(for: rows) }

    private var selectedInvoice: Invoice? {
        guard let selectedInvoiceID else { return nil }
        return invoices.first { $0.id == selectedInvoiceID }
    }

    public var body: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider()
            Table(rows, selection: $selectedInvoiceID) {
                TableColumn("Lp.") { row in
                    Text("\(row.ordinal)").monospacedDigit()
                }.width(36)
                TableColumn("Data") { row in
                    Text(row.eventDate, format: .dateTime.day().month().year())
                }.width(min: 86, ideal: 96)
                TableColumn("Dowód") { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.documentNumber).lineLimit(1)
                        if !row.ksefNumber.isEmpty {
                            Text(row.ksefNumber).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }.width(min: 130, ideal: 190)
                TableColumn("Kontrahent") { row in
                    Text(row.contractorTaxID.isEmpty ? row.contractorName : row.contractorTaxID).lineLimit(1)
                }.width(min: 100, ideal: 140)
                TableColumn("Opis") { row in
                    HStack(spacing: 5) {
                        if row.isExcluded { Image(systemName: "nosign").foregroundStyle(.secondary) }
                        Text(row.description).lineLimit(1)
                        if row.warning != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    }
                }.width(min: 150, ideal: 250)
                TableColumn("Kolumna") { row in
                    Text(row.column.displayName).lineLimit(1)
                }.width(min: 150, ideal: 220)
                TableColumn("Kwota PLN") { row in
                    Text(row.amountPLN, format: .currency(code: "PLN"))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }.width(min: 100, ideal: 125)
            }
            .opacity(rows.isEmpty ? 0.35 : 1)
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "Brak wpisów KPiR w okresie",
                        systemImage: "books.vertical",
                        description: Text("Zmień okres albo włącz wyświetlanie wykluczonych dokumentów.")
                    )
                }
            }

            if let invoice = selectedInvoice {
                Divider()
                KPiREntryEditor(invoice: invoice)
                    .frame(minHeight: 180, idealHeight: 210, maxHeight: 250)
            } else {
                Divider()
                Text("Zaznacz wpis, aby poprawić jego klasyfikację księgową.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .navigationTitle("KPiR")
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
            summaryValue("Przychód", summary.revenue, color: .green)
            summaryValue("Koszty", summary.deductibleCosts, color: .orange)
            summaryValue("Dochód", summary.income, color: summary.income >= 0 ? .blue : .red)
            Spacer()
            Text("\(rows.filter { !$0.isExcluded }.count) wpisów")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
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
            Data(KPiRCSVExporter.csv(for: rows).utf8),
            suggestedName: "KPiR_\(suffix).csv",
            contentType: .commaSeparatedText
        )
    }
}

private struct KPiREntryEditor: View {
    @Bindable var invoice: Invoice

    private var automaticDate: Date { invoice.saleDate ?? invoice.issueDate }
    private var automaticAmount: Double {
        (DashboardAnalytics.inPLN(invoice.netAmount, invoice: invoice) * 100).rounded() / 100
    }

    var body: some View {
        Form {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Wyklucz z KPiR", isOn: $invoice.isExcludedFromKPiR)
                    Picker("Kolumna", selection: Binding(
                        get: { KPiREngine.effectiveColumn(for: invoice) },
                        set: { invoice.kpirColumnRaw = $0.rawValue }
                    )) {
                        ForEach(KPiRColumn.choices(for: invoice.kind)) { column in
                            Text(column.displayName).tag(column)
                        }
                    }
                    DatePicker("Data zdarzenia", selection: Binding(
                        get: { invoice.kpirEventDate ?? automaticDate },
                        set: { invoice.kpirEventDate = $0 }
                    ), displayedComponents: .date)
                    Button("Przywróć datę z faktury") { invoice.kpirEventDate = nil }
                        .font(.caption).disabled(invoice.kpirEventDate == nil)
                }
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Opis zdarzenia", text: $invoice.kpirDescription,
                              prompt: Text(KPiREngine.effectiveDescription(for: invoice)))
                    HStack {
                        TextField("Kwota KPiR w PLN", value: $invoice.kpirAmountOverride,
                                  format: .number.precision(.fractionLength(2)))
                        Button("Automatyczna: \(automaticAmount.formatted(.number.precision(.fractionLength(2))))") {
                            invoice.kpirAmountOverride = nil
                        }
                        .font(.caption)
                        .disabled(invoice.kpirAmountOverride == nil)
                    }
                    TextField("Koszt B+R (kol. 18)", value: $invoice.kpirResearchDevelopmentCost,
                              format: .number.precision(.fractionLength(2)))
                    TextField("Uwagi (kol. 19)", text: $invoice.kpirNotes)
                    if let warning = KPiREngine.rows(
                        from: [invoice],
                        period: .init(year: Calendar.current.component(.year, from: KPiREngine.effectiveDate(for: invoice))),
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
