import SwiftUI
import SwiftData

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
