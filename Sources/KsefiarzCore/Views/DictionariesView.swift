import SwiftUI
import SwiftData

/// Słowniki aplikacji: kontrahenci, towary/usługi, rachunki bankowe.
/// Dane słowników są tylko podstawiane do faktur — na fakturze wszystko
/// pozostaje edytowalne ręcznie.
public struct DictionariesView: View {

    /// Zakładki słowników.
    enum Tab: String, CaseIterable, Identifiable {
        case contractors
        case products
        case bankAccounts

        var id: String { rawValue }
        var title: String {
            switch self {
            case .contractors: return "Kontrahenci"
            case .products: return "Towary i usługi"
            case .bankAccounts: return "Rachunki bankowe"
            }
        }
    }

    @State private var tab: Tab = .contractors

    public init() {}

    public var body: some View {
        Group {
            switch tab {
            case .contractors: ContractorsListView()
            case .products: ProductsListView()
            case .bankAccounts: BankAccountsListView()
            }
        }
        .navigationTitle("Słowniki")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Słownik", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}
