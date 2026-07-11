import SwiftUI
import SwiftData

/// Arkusz importu wyciągu bankowego: pokazuje operacje z pliku MT940 wraz
/// z propozycjami dopasowania do nieopłaconych faktur. Księgowane są
/// wyłącznie pozycje zatwierdzone przez użytkownika.
struct BankStatementImportView: View {

    let transactions: [BankTransaction]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var invoices: [Invoice]

    @State private var proposals: [PaymentMatchProposal] = []
    @State private var approved: Set<UUID> = []

    /// Szybki dostęp do faktur po identyfikatorze (dla wierszy propozycji).
    private var invoicesByID: [UUID: Invoice] {
        Dictionary(uniqueKeysWithValues: invoices.map { ($0.id, $0) })
    }

    private var matchedCount: Int {
        proposals.filter { $0.invoiceID != nil }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import wyciągu bankowego")
                        .font(.headline)
                    Text("\(transactions.count) operacji, \(matchedCount) z propozycją dopasowania — zaznaczone pozycje zostaną zaksięgowane jako wpłaty.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            List {
                ForEach(proposals) { proposal in
                    proposalRow(proposal)
                }
            }

            Divider()

            HStack {
                Button("Anuluj", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    applyApproved()
                } label: {
                    Text("Zaksięguj zaznaczone (\(approved.count))")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(approved.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 760, minHeight: 460)
        .onAppear {
            proposals = PaymentMatcher.proposals(transactions: transactions, invoices: invoices)
            // Wstępnie zaznaczone tylko pewne dopasowania (numer w tytule);
            // dopasowania po samej kwocie wymagają świadomego kliknięcia.
            approved = Set(
                proposals
                    .filter { $0.confidence == .invoiceNumber }
                    .map(\.id)
            )
        }
    }

    /// Wiersz pojedynczej operacji z propozycją dopasowania.
    @ViewBuilder
    private func proposalRow(_ proposal: PaymentMatchProposal) -> some View {
        let invoice = proposal.invoiceID.flatMap { invoicesByID[$0] }
        HStack(alignment: .center, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { approved.contains(proposal.id) },
                set: { isOn in
                    if isOn { approved.insert(proposal.id) } else { approved.remove(proposal.id) }
                }
            ))
            .labelsHidden()
            .disabled(invoice == nil)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(proposal.transaction.date, style: .date)
                        .font(.callout)
                    Text(
                        proposal.transaction.amount,
                        format: .currency(code: invoice?.currency ?? "PLN")
                    )
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(proposal.transaction.amount >= 0 ? .green : .red)
                }
                Text([proposal.transaction.title, proposal.transaction.counterparty]
                    .filter { !$0.isEmpty }
                    .joined(separator: " — "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)

            VStack(alignment: .trailing, spacing: 2) {
                if let invoice {
                    Text(invoice.invoiceNumber)
                        .font(.callout.weight(.medium))
                    Text("saldo: \(invoice.outstandingAmount, format: .currency(code: invoice.currency)) · \(proposal.confidence.displayName)")
                        .font(.caption)
                        .foregroundStyle(proposal.confidence == .invoiceNumber ? .green : .orange)
                } else {
                    Text("bez dopasowania")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("zaksięguj ręcznie w szczegółach faktury")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 250, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    /// Księguje zatwierdzone propozycje i zamyka arkusz.
    private func applyApproved() {
        let selected = proposals.filter { approved.contains($0.id) }
        PaymentMatcher.apply(selected, invoices: invoices)
        try? modelContext.save()
        dismiss()
    }
}
