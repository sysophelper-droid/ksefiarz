import SwiftUI
import SwiftData

/// Archiwum faktur ukrytych jako nieuprawnione / niezweryfikowane.
/// Faktury z tej sekcji nie są uwzględniane w rozliczeniach ani statystykach.
public struct HiddenInvoicesView: View {

    @Query(
        filter: #Predicate<Invoice> { $0.isArchivedOrHidden == true },
        sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
    )
    private var invoices: [Invoice]

    @Environment(\.modelContext) private var modelContext

    public init() {}

    public var body: some View {
        NavigationStack {
            List(invoices) { invoice in
                NavigationLink(value: invoice) {
                    InvoiceRowView(invoice: invoice)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        invoice.isArchivedOrHidden = false
                    } label: {
                        Label("Przywróć", systemImage: "eye")
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(invoice)
                    } label: {
                        Label("Usuń", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button("Przywróć do rozliczeń") {
                        invoice.isArchivedOrHidden = false
                    }
                    Divider()
                    Button("Usuń trwale", role: .destructive) {
                        modelContext.delete(invoice)
                    }
                }
            }
            .navigationDestination(for: Invoice.self) { invoice in
                InvoiceDetailView(invoice: invoice)
            }
            .navigationTitle("Nieuprawnione / Ukryte")
            .overlay {
                if invoices.isEmpty {
                    ContentUnavailableView(
                        "Brak ukrytych faktur",
                        systemImage: "eye.slash",
                        description: Text("Faktury oznaczone jako nieuprawnione pojawią się w tym miejscu.")
                    )
                }
            }
        }
    }
}
