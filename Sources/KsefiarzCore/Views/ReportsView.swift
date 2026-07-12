import SwiftUI
import SwiftData
import Charts

/// Raporty sprzedaży i kosztów: najlepsi kontrahenci, przychody per
/// towar/usługa oraz koszty per kategoria. Liczby dostarcza `ReportsEngine`
/// (kwoty w PLN); okres analizy wybierany jak w Kokpicie.
public struct ReportsView: View {

    // Tylko widoczne faktury — ukryte nie fałszują raportów.
    @Query(
        filter: #Predicate<Invoice> { $0.isArchivedOrHidden == false },
        sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
    )
    private var invoices: [Invoice]

    /// Filtr okresu raportów — zapamiętywany osobno (jak filtr Kokpitu).
    @AppStorage("filter.reports") private var displayFilterRaw = DisplayDateFilter.currentYear.rawValue

    /// Ile pozycji pokazują tabele rankingów.
    private static let tableLimit = 15
    /// Ile słupków mieści wykres kontrahentów.
    private static let chartLimit = 8

    public init() {}

    private var displayFilter: DisplayDateFilter {
        DisplayDateFilter(rawValue: displayFilterRaw) ?? .currentYear
    }

    private var rangeLabel: String {
        guard let range = displayFilter.range() else { return "wszystkie faktury" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: range.from)) – \(formatter.string(from: range.to))"
    }

    /// Faktury z analizowanego okresu.
    private var periodInvoices: [Invoice] {
        displayFilter.apply(to: invoices)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Analizowany okres: \(rangeLabel)", systemImage: "calendar")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                topContractorsSection
                productsSection
                costsSection
            }
            .padding(20)
        }
        .navigationTitle("Raporty")
        .toolbar {
            ToolbarItem {
                Picker(selection: $displayFilterRaw) {
                    ForEach(DisplayDateFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter.rawValue)
                    }
                } label: {
                    Label("Okres", systemImage: "calendar")
                }
                .help("Okres analizowanych faktur")
            }
        }
    }

    // MARK: Top kontrahenci (sprzedaż)

    private var topContractorsSection: some View {
        GroupBox {
            let contractors = ReportsEngine.topContractors(in: periodInvoices, limit: Self.tableLimit)
            if contractors.isEmpty {
                ContentUnavailableView(
                    "Brak sprzedaży w okresie",
                    systemImage: "person.2",
                    description: Text("Wystaw faktury sprzedażowe albo zmień okres analizy.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Chart(Array(contractors.prefix(Self.chartLimit))) { contractor in
                        BarMark(
                            x: .value("Brutto", contractor.grossPLN),
                            y: .value("Kontrahent", shortName(contractor.name))
                        )
                        .foregroundStyle(Color.blue.gradient)
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount, format: .number.notation(.compactName).locale(Locale(identifier: "pl_PL")))
                                }
                            }
                        }
                    }
                    .frame(height: CGFloat(min(contractors.count, Self.chartLimit)) * 28 + 30)

                    Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 6) {
                        GridRow {
                            Text("Kontrahent").gridColumnAlignment(.leading)
                            Text("NIP").gridColumnAlignment(.leading)
                            Text("Faktury")
                            Text("Netto")
                            Text("Brutto")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        Divider()
                        ForEach(contractors) { contractor in
                            GridRow {
                                Text(contractor.name)
                                    .gridColumnAlignment(.leading)
                                    .lineLimit(1)
                                Text(contractor.nip.isEmpty ? "—" : contractor.nip)
                                    .gridColumnAlignment(.leading)
                                    .foregroundStyle(.secondary)
                                Text("\(contractor.invoiceCount)").monospacedDigit()
                                Text(contractor.netPLN, format: .currency(code: "PLN")).monospacedDigit()
                                Text(contractor.grossPLN, format: .currency(code: "PLN")).monospacedDigit()
                            }
                            .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6)
            }
        } label: {
            Label("Top kontrahenci — sprzedaż (PLN)", systemImage: "person.2")
                .font(.headline)
        }
    }

    // MARK: Przychody per towar/usługa

    private var productsSection: some View {
        GroupBox {
            let products = ReportsEngine.revenueByProduct(in: periodInvoices, limit: Self.tableLimit)
            if products.isEmpty {
                ContentUnavailableView(
                    "Brak pozycji sprzedaży w okresie",
                    systemImage: "shippingbox",
                    description: Text("Przychody liczone są z pozycji faktur sprzedażowych.")
                )
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        Text("Towar / usługa").gridColumnAlignment(.leading)
                        Text("Ilość")
                        Text("Netto")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(products) { product in
                        GridRow {
                            Text(product.name)
                                .gridColumnAlignment(.leading)
                                .lineLimit(1)
                            Text(FA2Format.quantity(product.quantity)).monospacedDigit()
                            Text(product.netPLN, format: .currency(code: "PLN")).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label("Przychody per towar/usługa (netto, PLN)", systemImage: "shippingbox")
                .font(.headline)
        }
    }

    // MARK: Koszty per kategoria

    private var costsSection: some View {
        GroupBox {
            let categories = ReportsEngine.costsByCategory(in: periodInvoices)
            if categories.isEmpty {
                ContentUnavailableView(
                    "Brak zakupów w okresie",
                    systemImage: "tag",
                    description: Text("Kategorie kosztów przypisuje się w szczegółach faktury zakupowej albo przy ręcznym dodawaniu zakupu spoza KSeF.")
                )
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        Text("Kategoria").gridColumnAlignment(.leading)
                        Text("Faktury")
                        Text("Netto")
                        Text("VAT")
                        Text("Brutto")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(categories) { category in
                        GridRow {
                            Text(category.category)
                                .gridColumnAlignment(.leading)
                                .foregroundStyle(category.category == CostCategories.none ? .secondary : .primary)
                            Text("\(category.invoiceCount)").monospacedDigit()
                            Text(category.netPLN, format: .currency(code: "PLN")).monospacedDigit()
                            Text(category.vatPLN, format: .currency(code: "PLN")).monospacedDigit()
                            Text(category.grossPLN, format: .currency(code: "PLN")).monospacedDigit()
                        }
                        .font(.callout)
                    }
                    Divider()
                    GridRow {
                        Text("Razem").gridColumnAlignment(.leading).fontWeight(.semibold)
                        Text("\(categories.reduce(0) { $0 + $1.invoiceCount })")
                            .monospacedDigit().fontWeight(.semibold)
                        Text(categories.reduce(0) { $0 + $1.netPLN }, format: .currency(code: "PLN"))
                            .monospacedDigit().fontWeight(.semibold)
                        Text(categories.reduce(0) { $0 + $1.vatPLN }, format: .currency(code: "PLN"))
                            .monospacedDigit().fontWeight(.semibold)
                        Text(categories.reduce(0) { $0 + $1.grossPLN }, format: .currency(code: "PLN"))
                            .monospacedDigit().fontWeight(.semibold)
                    }
                    .font(.callout)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label("Koszty per kategoria (PLN)", systemImage: "tag")
                .font(.headline)
        }
    }

    /// Skrócona nazwa na oś wykresu — długie nazwy firm łamały układ.
    private func shortName(_ name: String) -> String {
        name.count > 24 ? String(name.prefix(22)) + "…" : name
    }
}
