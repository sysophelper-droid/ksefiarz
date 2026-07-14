import SwiftUI
import SwiftData

/// Prezenter globalnej wyszukiwarki ⌘K — pozwala otworzyć paletę z menu
/// aplikacji (Commands w `InvoiceApp`) i z dowolnego widoku. Wzorzec jak
/// `MainWindowOpener`: AppKit/Commands nie mają dostępu do stanu widoku.
@MainActor
public final class GlobalSearchPresenter: ObservableObject {
    public static let shared = GlobalSearchPresenter()
    @Published public var isPresented = false

    private init() {}

    /// Otwiera paletę; najpierw przywraca okno główne (⌘K działa też,
    /// gdy użytkownik zamknął okno, a aplikacja żyje w pasku menu).
    public func present() {
        MainWindowOpener.open?()
        isPresented = true
    }
}

/// Skok z wyszukiwarki do konkretnego ustawienia: zakładka + chwilowo
/// podświetlony wiersz (mechanizm wyszukiwarki ustawień).
public struct SettingsJump: Equatable, Sendable {
    public let tabRaw: String
    public let highlight: String?

    public init(tabRaw: String, highlight: String?) {
        self.tabRaw = tabRaw
        self.highlight = highlight
    }
}

/// Most nawigacyjny do okna Ustawień — `SettingsView` konsumuje
/// oczekujący skok przy pojawieniu się i przy każdej zmianie.
@MainActor
public final class SettingsNavigator: ObservableObject {
    public static let shared = SettingsNavigator()
    @Published public var pendingJump: SettingsJump?

    private init() {}
}

/// Cel nawigacji wybrany w palecie — wykonuje go `MainContentView`
/// PO zamknięciu arkusza palety (arkusz nie może sam prezentować
/// kolejnego arkusza w trakcie własnego zamykania).
enum GlobalSearchAction {
    case section(SidebarSection)
    case invoice(Invoice)
    case proforma(Proforma)
    case contractor(Contractor)
    case setting(SettingsJump)
}

/// Paleta globalnej wyszukiwarki (⌘K): szybki skok do faktury, proformy,
/// kontrahenta, ustawienia albo sekcji aplikacji. Faktury ukryte są poza
/// wynikami (ochrona jak w statystykach). Ranking w `GlobalSearchEngine`.
struct GlobalSearchView: View {

    let onOpen: (GlobalSearchAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Invoice.issueDate, order: .reverse) private var invoices: [Invoice]
    @Query(sort: \Proforma.issueDate, order: .reverse) private var proformas: [Proforma]
    @Query(sort: \Contractor.name) private var contractors: [Contractor]
    @AppStorage(AppSettingsKeys.taxForm) private var taxFormRaw = TaxForm.kpir.rawValue

    @State private var query = ""
    @FocusState private var isSearchFieldFocused: Bool

    /// Kolejność grup w wynikach.
    private static let kindOrder: [GlobalSearchEngine.Kind] = [
        .section, .invoice, .proforma, .contractor, .setting,
    ]

    /// Sekcje aplikacji widoczne przy bieżącej formie opodatkowania
    /// (KPiR albo ryczałt — jak w pasku bocznym).
    private var visibleSections: [SidebarSection] {
        let taxForm = TaxForm.resolve(taxFormRaw)
        return SidebarSection.allCases.filter { section in
            switch section {
            case .kpir: return taxForm == .kpir
            case .ryczalt: return taxForm == .ryczalt
            default: return true
            }
        }
    }

    private var sectionItems: [GlobalSearchEngine.Item] {
        visibleSections.map { section in
            GlobalSearchEngine.Item(
                kind: .section,
                id: "section-\(section.rawValue)",
                title: section.title,
                subtitle: "Sekcja aplikacji",
                keywords: ["sekcja"]
            )
        }
    }

    private var settingItems: [GlobalSearchEngine.Item] {
        SettingsView.searchIndex.map { entry in
            GlobalSearchEngine.Item(
                kind: .setting,
                id: "setting-\(entry.tab.rawValue)|\(entry.label)",
                title: entry.label,
                subtitle: "Ustawienia → \(entry.tab.title)",
                keywords: [entry.tab.title, "ustawienia"]
            )
        }
    }

    private var allItems: [GlobalSearchEngine.Item] {
        sectionItems
            + invoices.filter { !$0.isArchivedOrHidden }.map(GlobalSearchEngine.item(for:))
            + proformas.map(GlobalSearchEngine.item(for:))
            + contractors.map(GlobalSearchEngine.item(for:))
            + settingItems
    }

    /// Wyniki w kolejności rankingu (puste zapytanie = sekcje aplikacji).
    private var results: [GlobalSearchEngine.Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return sectionItems }
        return GlobalSearchEngine.search(trimmed, in: allItems)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Szukaj faktury, kontrahenta, ustawienia…",
                    text: $query
                )
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    if let first = results.first { open(first) }
                }
                Button("Anuluj") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider()

            if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                resultsList
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .onAppear { isSearchFieldFocused = true }
        .onExitCommand { dismiss() }
    }

    private var resultsList: some View {
        List {
            ForEach(Self.kindOrder, id: \.self) { kind in
                let group = results.filter { $0.kind == kind }
                if !group.isEmpty {
                    Section(kind.displayName) {
                        ForEach(group) { item in
                            resultRow(item)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func resultRow(_ item: GlobalSearchEngine.Item) -> some View {
        Button {
            open(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.kind.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Zamienia pozycję wyniku na akcję nawigacji i zamyka paletę.
    private func open(_ item: GlobalSearchEngine.Item) {
        guard let action = action(for: item) else { return }
        onOpen(action)
        dismiss()
    }

    private func action(for item: GlobalSearchEngine.Item) -> GlobalSearchAction? {
        switch item.kind {
        case .section:
            let raw = String(item.id.dropFirst("section-".count))
            guard let section = SidebarSection(rawValue: raw) else { return nil }
            return .section(section)
        case .invoice:
            guard let invoice = invoices.first(where: { $0.id.uuidString == item.id }) else {
                return nil
            }
            return .invoice(invoice)
        case .proforma:
            guard let proforma = proformas.first(where: { $0.id.uuidString == item.id }) else {
                return nil
            }
            return .proforma(proforma)
        case .contractor:
            guard let contractor = contractors.first(where: { $0.id.uuidString == item.id }) else {
                return nil
            }
            return .contractor(contractor)
        case .setting:
            let payload = String(item.id.dropFirst("setting-".count))
            guard let separator = payload.firstIndex(of: "|") else { return nil }
            let tabRaw = String(payload[payload.startIndex..<separator])
            let label = String(payload[payload.index(after: separator)...])
            return .setting(SettingsJump(tabRaw: tabRaw, highlight: label))
        }
    }
}
