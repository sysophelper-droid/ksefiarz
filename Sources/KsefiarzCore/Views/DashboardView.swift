import SwiftUI
import SwiftData
import Charts

/// Kokpit — podsumowanie kwot oraz faktury do opłacenia w najbliższych dniach.
public struct DashboardView: View {

    // Tylko widoczne faktury — ukryte nie fałszują statystyk.
    @Query(
        filter: #Predicate<Invoice> { $0.isArchivedOrHidden == false },
        sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
    )
    private var invoices: [Invoice]

    /// Własny filtr okresu Kokpitu — niezależny od zakresu importu i list.
    @AppStorage("filter.dashboard") private var displayFilterRaw = DisplayDateFilter.currentMonth.rawValue

    /// Horyzont widgetu najbliższych płatności (konfigurowalny w Ustawieniach).
    @AppStorage(AppSettingsKeys.dueSoonDays) private var dueSoonDays = 7

    /// Ścieżka nawigacji — podwójne kliknięcie wiersza płatności otwiera
    /// szczegóły faktury bez przechodzenia do listy zakupów.
    @State private var navigationPath = NavigationPath()

    /// Zaznaczony wiersz najbliższych płatności — spójnie z listami:
    /// pojedyncze kliknięcie zaznacza, podwójne otwiera szczegóły.
    @State private var selectedDueInvoiceID: UUID?

    public init() {}

    /// „1 dzień” / „N dni” — poprawna polska odmiana.
    private var dueSoonDaysLabel: String {
        dueSoonDays == 1 ? "1 dzień" : "\(dueSoonDays) dni"
    }

    private var displayFilter: DisplayDateFilter {
        DisplayDateFilter(rawValue: displayFilterRaw) ?? .currentMonth
    }

    private var rangeLabel: String {
        guard let range = displayFilter.range() else { return "wszystkie faktury" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: range.from)) – \(formatter.string(from: range.to))"
    }

    private var metrics: DashboardMetrics {
        DashboardMetrics(invoices: displayFilter.apply(to: invoices), dueSoonDays: dueSoonDays)
    }

    /// Rozszerzona analityka: VAT liczony z okresu Kokpitu; przepływy,
    /// wiekowanie i porównania miesięczne — ze wszystkich widocznych faktur.
    private var analytics: DashboardAnalytics {
        DashboardAnalytics(invoices: invoices, periodInvoices: displayFilter.apply(to: invoices))
    }

    /// Etykieta miesiąca na osi wykresów, np. „lip 26”.
    private static let monthLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLL yy"
        formatter.locale = Locale(identifier: "pl_PL")
        return formatter
    }()

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            dashboardContent
                .navigationDestination(for: Invoice.self) { invoice in
                    InvoiceDetailView(invoice: invoice)
                }
        }
    }

    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Informacja o analizowanym zakresie dat (z Ustawień).
                Label("Analizowany okres: \(rangeLabel)", systemImage: "calendar")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                // Karty z podsumowaniem kwot.
                LazyVGrid(columns: columns, spacing: 16) {
                    StatCard(
                        title: "Zakupy do opłacenia",
                        value: metrics.purchasesToPayGross.formatted(.currency(code: "PLN")),
                        icon: "arrow.down.doc",
                        color: .orange
                    )
                    StatCard(
                        title: "Należności (sprzedaż)",
                        value: metrics.salesAwaitingGross.formatted(.currency(code: "PLN")),
                        icon: "arrow.up.doc",
                        color: .blue
                    )
                    StatCard(
                        title: "Faktury zaległe",
                        value: "\(metrics.overdueCount)",
                        icon: "exclamationmark.triangle",
                        color: .red
                    )
                    StatCard(
                        title: "Nieopłacone łącznie",
                        value: "\(metrics.unpaidCount)",
                        icon: "tray.full",
                        color: .purple
                    )
                }

                // Najbliższe płatności (horyzont z Ustawień).
                GroupBox {
                    if metrics.dueSoonInvoices.isEmpty {
                        ContentUnavailableView(
                            "Brak płatności w ciągu \(dueSoonDaysLabel)",
                            systemImage: "checkmark.seal",
                            description: Text("Wszystkie najbliższe zobowiązania są opłacone.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(metrics.dueSoonInvoices) { invoice in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(invoice.kind == .purchase ? invoice.sellerName : invoice.buyerName)
                                            .font(.headline)
                                        Text(invoice.invoiceNumber)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(invoice.grossAmount, format: .currency(code: invoice.currency))
                                            .monospacedDigit()
                                            .fontWeight(.semibold)
                                        if let due = invoice.paymentDueDate {
                                            Text("Termin: \(due, style: .date)")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 6)
                                // Cały wiersz klikalny; pojedyncze kliknięcie
                                // zaznacza (podświetlenie), podwójne otwiera
                                // szczegóły — spójnie z listami faktur.
                                .contentShape(Rectangle())
                                .background(
                                    selectedDueInvoiceID == invoice.id
                                        ? Color.accentColor.opacity(0.15)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .onTapGesture(count: 2) {
                                    navigationPath.append(invoice)
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    selectedDueInvoiceID = invoice.id
                                })
                                .help("Podwójne kliknięcie otwiera szczegóły faktury")
                                if invoice.id != metrics.dueSoonInvoices.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                } label: {
                    Label("Płatności w najbliższych: \(dueSoonDaysLabel)", systemImage: "calendar.badge.clock")
                        .font(.headline)
                }

                // VAT w analizowanym okresie.
                LazyVGrid(columns: columns, spacing: 16) {
                    StatCard(
                        title: "VAT należny (sprzedaż)",
                        value: analytics.vatDue.formatted(.currency(code: "PLN")),
                        icon: "plus.forwardslash.minus",
                        color: .blue
                    )
                    StatCard(
                        title: "VAT naliczony (zakupy)",
                        value: analytics.vatInput.formatted(.currency(code: "PLN")),
                        icon: "minus.forwardslash.plus",
                        color: .teal
                    )
                    StatCard(
                        title: analytics.vatBalance >= 0 ? "VAT do zapłaty (saldo)" : "VAT do zwrotu (saldo)",
                        value: abs(analytics.vatBalance).formatted(.currency(code: "PLN")),
                        icon: "scalemass",
                        color: analytics.vatBalance >= 0 ? .orange : .green
                    )
                }

                cashFlowSection
                agingSection
                monthComparisonSection
            }
            .padding(20)
        }
        .navigationTitle("Kokpit")
        .toolbar {
            ToolbarItem {
                // Filtr okresu analiz — zapamiętywany osobno dla Kokpitu.
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
}

extension DashboardView {

    /// Przepływy pieniężne z ewidencji wpłat — słupki wpływów i wydatków
    /// per miesiąc (ostatnie 6 miesięcy, kwoty w PLN).
    private var cashFlowSection: some View {
        GroupBox {
            let cashFlow = analytics.cashFlow
            if cashFlow.allSatisfy({ $0.inflow == 0 && $0.outflow == 0 }) {
                ContentUnavailableView(
                    "Brak zaksięgowanych wpłat",
                    systemImage: "chart.bar",
                    description: Text("Przepływy liczone są z ewidencji wpłat — księguj wpłaty w szczegółach faktur albo importuj wyciągi MT940.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(cashFlow, id: \.month) { point in
                        BarMark(
                            x: .value("Miesiąc", Self.monthLabelFormatter.string(from: point.month)),
                            y: .value("Kwota", point.inflow)
                        )
                        .foregroundStyle(by: .value("Rodzaj", "Wpływy"))
                        .position(by: .value("Rodzaj", "Wpływy"))
                        BarMark(
                            x: .value("Miesiąc", Self.monthLabelFormatter.string(from: point.month)),
                            y: .value("Kwota", point.outflow)
                        )
                        .foregroundStyle(by: .value("Rodzaj", "Wydatki"))
                        .position(by: .value("Rodzaj", "Wydatki"))
                    }
                }
                .chartForegroundStyleScale(["Wpływy": Color.green, "Wydatki": Color.orange])
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount, format: .number.notation(.compactName).locale(Locale(identifier: "pl_PL")))
                            }
                        }
                    }
                }
                .frame(height: 180)
                .padding(.top, 6)
            }
        } label: {
            Label("Przepływy pieniężne — ostatnie 6 miesięcy (wg ewidencji wpłat, PLN)", systemImage: "chart.bar.xaxis")
                .font(.headline)
        }
    }

    /// Struktura wiekowa nieopłaconych faktur (saldo w PLN):
    /// należności (sprzedaż) i zobowiązania (zakupy) per przedział.
    private var agingSection: some View {
        GroupBox {
            let aging = analytics.aging
            if aging.allSatisfy({ $0.receivables == 0 && $0.payables == 0 }) {
                ContentUnavailableView(
                    "Brak nieopłaconych faktur",
                    systemImage: "checkmark.seal",
                    description: Text("Wszystkie widoczne faktury są opłacone.")
                )
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        Text("Przedział").gridColumnAlignment(.leading)
                        Text("Należności (sprzedaż)")
                        Text("Zobowiązania (zakupy)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(aging, id: \.label) { bucket in
                        GridRow {
                            Text(bucket.label)
                                .gridColumnAlignment(.leading)
                                .foregroundStyle(bucket.label == "Przed terminem" ? .primary : Color.red)
                            Text(bucket.receivables, format: .currency(code: "PLN")).monospacedDigit()
                            Text(bucket.payables, format: .currency(code: "PLN")).monospacedDigit()
                        }
                        .font(.callout)
                    }
                    Divider()
                    GridRow {
                        Text("Razem").gridColumnAlignment(.leading).fontWeight(.semibold)
                        Text(aging.reduce(0) { $0 + $1.receivables }, format: .currency(code: "PLN"))
                            .monospacedDigit().fontWeight(.semibold)
                        Text(aging.reduce(0) { $0 + $1.payables }, format: .currency(code: "PLN"))
                            .monospacedDigit().fontWeight(.semibold)
                    }
                    .font(.callout)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label("Struktura wiekowa nieopłaconych (saldo, PLN)", systemImage: "hourglass")
                .font(.headline)
        }
    }

    /// Porównanie bieżącego i poprzedniego miesiąca (po dacie wystawienia).
    private var monthComparisonSection: some View {
        GroupBox {
            let current = analytics.currentMonth
            let previous = analytics.previousMonth
            Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text(Self.monthLabelFormatter.string(from: previous.month))
                    Text(Self.monthLabelFormatter.string(from: current.month))
                    Text("Zmiana")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()
                comparisonRow("Sprzedaż brutto", previous: previous.salesGross, current: current.salesGross)
                comparisonRow("Zakupy brutto", previous: previous.purchasesGross, current: current.purchasesGross)
                comparisonRow("VAT należny", previous: previous.vatDue, current: current.vatDue)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Porównanie miesięczne (PLN)", systemImage: "arrow.left.arrow.right")
                .font(.headline)
        }
    }

    /// Wiersz porównania: poprzedni miesiąc, bieżący i zmiana procentowa.
    private func comparisonRow(_ title: String, previous: Double, current: Double) -> some View {
        GridRow {
            Text(title).gridColumnAlignment(.leading)
            Text(previous, format: .currency(code: "PLN")).monospacedDigit()
            Text(current, format: .currency(code: "PLN")).monospacedDigit()
            if let change = DashboardAnalytics.MonthSummary.change(from: previous, to: current) {
                Text("\(change >= 0 ? "▲" : "▼") \(abs(change).formatted(.number.precision(.fractionLength(0))))%")
                    .foregroundStyle(change >= 0 ? .green : .red)
                    .monospacedDigit()
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}

/// Karta statystyki w Kokpicie.
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
