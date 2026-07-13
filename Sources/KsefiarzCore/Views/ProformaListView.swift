import SwiftUI
import SwiftData

/// Filtr listy proform według stanu rozliczenia.
enum ProformaListFilter: String, CaseIterable, Identifiable {
    case all
    case open
    case converted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "Wszystkie"
        case .open: return "Do rozliczenia"
        case .converted: return "Rozliczone"
        }
    }
}

/// Lista faktur proforma — dokumentów handlowych spoza KSeF, z konwersją
/// do właściwej faktury VAT. Ten sam wzorzec interakcji co listy faktur:
/// pojedyncze kliknięcie zaznacza, podwójne otwiera szczegóły.
public struct ProformaListView: View {

    @Query(sort: [SortDescriptor(\Proforma.issueDate, order: .reverse)])
    private var proformas: [Proforma]
    @Environment(\.modelContext) private var modelContext

    @State private var statusFilter: ProformaListFilter = .all
    @State private var searchText = ""
    @State private var showingNewProforma = false
    @State private var editedProforma: Proforma?
    @State private var convertingProforma: Proforma?
    @State private var selection = Set<UUID>()
    @State private var navigationPath: [Proforma] = []

    public init() {}

    private var filteredProformas: [Proforma] {
        proformas.filter { proforma in
            switch statusFilter {
            case .all: return true
            case .open: return !proforma.isConverted
            case .converted: return proforma.isConverted
            }
        }.filter { proforma in
            let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            guard !query.isEmpty else { return true }
            return proforma.buyerName.lowercased().contains(query)
                || proforma.buyerNIP.lowercased().contains(query)
                || proforma.proformaNumber.lowercased().contains(query)
        }
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            List(selection: $selection) {
                ForEach(filteredProformas) { proforma in
                    ProformaRowView(proforma: proforma)
                        .tag(proforma.id)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                proforma.isPaid.toggle()
                            } label: {
                                Label(
                                    proforma.isPaid ? "Nieopłacona" : "Opłacona",
                                    systemImage: proforma.isPaid ? "xmark.circle" : "checkmark.circle"
                                )
                            }
                            .tint(proforma.isPaid ? .orange : .green)
                        }
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                contextMenuContent(for: ids)
            } primaryAction: { ids in
                if let id = ids.first, let proforma = proformas.first(where: { $0.id == id }) {
                    navigationPath.append(proforma)
                }
            }
            .id(proformas.count)
            .navigationDestination(for: Proforma.self) { proforma in
                ProformaDetailView(proforma: proforma)
            }
            .searchable(text: $searchText, prompt: "Szukaj po numerze, NIP lub nazwie nabywcy")
            .navigationTitle("Faktury proforma")
            .toolbar { toolbarContent }
            .overlay {
                if filteredProformas.isEmpty {
                    ContentUnavailableView(
                        "Brak proform",
                        systemImage: "doc.plaintext",
                        description: Text("Wystaw proformę przyciskiem „+”. Proforma to dokument handlowy — nie idzie do KSeF; po zapłacie rozliczysz ją właściwą fakturą VAT.")
                    )
                }
            }
            .sheet(isPresented: $showingNewProforma) {
                NewProformaView()
            }
            .sheet(item: $editedProforma) { proforma in
                NewProformaView(editing: proforma)
            }
            .sheet(item: $convertingProforma) { proforma in
                NewInvoiceView(
                    initialDraft: proforma.invoiceDraft(),
                    sourceTitle: "Faktura z proformy \(proforma.proformaNumber)",
                    onCreatedInvoice: { invoice in
                        proforma.markConverted(toInvoiceNumber: invoice.invoiceNumber)
                        try? modelContext.save()
                    }
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Filtr", selection: $statusFilter) {
                ForEach(ProformaListFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
        ToolbarItem {
            Button {
                showingNewProforma = true
            } label: {
                Label("Nowa proforma", systemImage: "plus")
            }
            .help("Wystaw nową fakturę proforma")
        }
    }

    /// Faktury odpowiadające zaznaczonym identyfikatorom.
    private func selectedProformas(for ids: Set<UUID>) -> [Proforma] {
        proformas.filter { ids.contains($0.id) }
    }

    @ViewBuilder
    private func contextMenuContent(for ids: Set<UUID>) -> some View {
        let selected = selectedProformas(for: ids)
        if selected.count == 1, let proforma = selected.first {
            Button("Otwórz szczegóły") {
                navigationPath.append(proforma)
            }
            Divider()
            Button(proforma.isPaid ? "Oznacz jako nieopłaconą" : "Oznacz jako opłaconą") {
                proforma.isPaid.toggle()
            }
            if !proforma.isConverted {
                Button("Konwertuj na fakturę VAT…") {
                    convertingProforma = proforma
                }
                Divider()
                Button("Edytuj proformę") {
                    editedProforma = proforma
                }
            }
            Button("Usuń proformę", role: .destructive) {
                modelContext.delete(proforma)
            }
        } else if selected.count > 1 {
            Button("Oznacz \(selected.count) jako opłacone") {
                selected.forEach { $0.isPaid = true }
            }
            Button("Oznacz \(selected.count) jako nieopłacone") {
                selected.forEach { $0.isPaid = false }
            }
            Divider()
            Button("Usuń \(selected.count) proform", role: .destructive) {
                selected.forEach { modelContext.delete($0) }
                selection.removeAll()
            }
        }
    }
}

// MARK: - Wiersz listy

/// Pojedynczy wiersz proformy ze znacznikami rozliczenia i płatności.
struct ProformaRowView: View {
    let proforma: Proforma

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(proforma.buyerName.isEmpty ? "(brak nabywcy)" : proforma.buyerName)
                        .font(.headline)
                        .lineLimit(1)
                    if proforma.isConverted {
                        Text("Rozliczona")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                            .help("Rozliczona fakturą \(proforma.convertedInvoiceNumber)")
                    } else if proforma.isExpired() {
                        Text("Po terminie ważności")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.gray.opacity(0.18), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Text(proforma.proformaNumber)
                    if !proforma.buyerNIP.isEmpty {
                        Text("NIP: \(proforma.buyerNIP)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(proforma.grossAmount, format: .currency(code: proforma.currency))
                    .font(.headline)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Text(proforma.issueDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProformaPaymentBadge(proforma: proforma)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Znacznik statusu płatności proformy.
struct ProformaPaymentBadge: View {
    let proforma: Proforma

    private var label: String {
        if proforma.isPaid { return "Opłacona" }
        if proforma.isOverdue { return "Zaległa" }
        return "Do zapłaty"
    }

    private var color: Color {
        if proforma.isPaid { return .green }
        if proforma.isOverdue { return .red }
        return .orange
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
