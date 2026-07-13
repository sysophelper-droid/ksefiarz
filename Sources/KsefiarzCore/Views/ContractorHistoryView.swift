import SwiftData
import SwiftUI

/// Jedna karta współpracy z kontrahentem: salda, zachowanie płatnicze i pełna
/// lista widocznych dokumentów sprzedaży oraz zakupu.
struct ContractorHistoryView: View {

    let contractor: Contractor

    @Query(sort: \Invoice.issueDate, order: .reverse) private var allInvoices: [Invoice]
    @Environment(\.dismiss) private var dismiss

    @State private var selection = Set<UUID>()
    @State private var openedInvoice: Invoice?

    private var history: ContractorHistory {
        ContractorHistory(invoices: allInvoices, contractorNIP: contractor.nip)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(20)

            Divider()

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    HistoryMetricCard(
                        title: "Dokumenty",
                        value: "\(history.invoices.count)",
                        subtitle: "\(history.salesCount) sprzedaży · \(history.purchaseCount) zakupu",
                        systemImage: "doc.text.magnifyingglass",
                        tint: .blue
                    )
                    HistoryMetricCard(
                        title: "Średni czas płatności",
                        value: averagePaymentText,
                        subtitle: paymentTimeSubtitle,
                        systemImage: "clock",
                        tint: .indigo
                    )
                    HistoryMetricCard(
                        title: "Terminowość",
                        value: timelinessText,
                        subtitle: timelinessSubtitle,
                        systemImage: "checkmark.circle",
                        tint: scoreColor
                    )
                    HistoryMetricCard(
                        title: "Scoring",
                        value: history.score.displayName,
                        subtitle: "na podstawie faktur sprzedaży",
                        systemImage: "gauge.with.dots.needle.50percent",
                        tint: scoreColor
                    )
                }
                .padding(20)
            }

            if !history.balances.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Saldo")
                        .font(.headline)
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(history.balances, id: \.currency) { balance in
                                CurrencyBalanceCard(balance: balance)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            Divider()
            documents
        }
        .frame(minWidth: 920, minHeight: 640)
        .sheet(item: $openedInvoice) { invoice in
            InvoiceDetailView(invoice: invoice)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(contractor.displayName)
                    .font(.title2.bold())
                HStack(spacing: 12) {
                    Text("NIP: \(contractor.nip)")
                    if !contractor.city.isEmpty { Text(contractor.city) }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Zamknij") { dismiss() }
        }
    }

    private var documents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wszystkie dokumenty")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            if history.invoices.isEmpty {
                ContentUnavailableView(
                    "Brak dokumentów",
                    systemImage: "doc.text",
                    description: Text("Nie znaleziono widocznych faktur powiązanych z NIP-em kontrahenta.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(history.invoices) { invoice in
                        ContractorDocumentRow(invoice: invoice)
                            .tag(invoice.id)
                    }
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if ids.count == 1 {
                        Button("Otwórz szczegóły") { openInvoice(ids) }
                    }
                } primaryAction: { ids in
                    openInvoice(ids)
                }
            }
        }
    }

    private var averagePaymentText: String {
        guard let days = history.averagePaymentDays else { return "—" }
        return days.formatted(.number.precision(.fractionLength(days.rounded() == days ? 0 : 1))) + " dni"
    }

    private var paymentTimeSubtitle: String {
        history.paymentTimeSampleCount == 0
            ? "brak faktur z datą pełnej zapłaty"
            : "próba: \(history.paymentTimeSampleCount)"
    }

    private var timelinessText: String {
        guard let rate = history.onTimeRate else { return "—" }
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }

    private var timelinessSubtitle: String {
        history.timelinessSampleCount == 0
            ? "brak faktur z terminem do oceny"
            : "\(history.onTimeCount) z \(history.timelinessSampleCount) terminowo"
    }

    private var scoreColor: Color {
        switch history.score {
        case .excellent: return .green
        case .good: return .teal
        case .needsAttention: return .orange
        case .poor: return .red
        case .unrated: return .secondary
        }
    }

    private func openInvoice(_ ids: Set<UUID>) {
        guard ids.count == 1 else { return }
        openedInvoice = history.invoices.first { ids.contains($0.id) }
    }
}

private struct HistoryMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 190, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CurrencyBalanceCard: View {
    let balance: ContractorHistory.CurrencyBalance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(balance.currency)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 18) {
                balanceValue("Należności", value: balance.receivables, color: .green)
                balanceValue("Zobowiązania", value: balance.payables, color: .orange)
                balanceValue("Netto", value: balance.net, color: balance.net < 0 ? .red : .blue)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func balanceValue(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: balance.currency))
                .font(.subheadline.bold())
                .foregroundStyle(color)
        }
    }
}

private struct ContractorDocumentRow: View {
    let invoice: Invoice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: invoice.kind == .sales ? "arrow.up.right.circle" : "arrow.down.left.circle")
                .foregroundStyle(invoice.kind == .sales ? .green : .blue)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(invoice.invoiceNumber)
                        .font(.headline)
                    Text(invoice.kind.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                Text(invoice.issueDate, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(invoice.grossAmount, format: .currency(code: invoice.currency))
                    .font(.headline)
                Text(paymentStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(paymentStatusColor)
            }
        }
        .padding(.vertical, 3)
    }

    private var paymentStatus: String {
        if invoice.isPaid { return "Opłacona" }
        if invoice.grossAmount < 0 { return "Korekta" }
        if invoice.isPartiallyPaid { return "Częściowo" }
        if invoice.isOverdue { return "Zaległa" }
        return "Do zapłaty"
    }

    private var paymentStatusColor: Color {
        if invoice.isPaid { return .green }
        if invoice.isOverdue { return .red }
        return .orange
    }
}
