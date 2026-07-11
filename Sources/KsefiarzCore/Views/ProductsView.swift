import SwiftUI
import SwiftData

/// Lista towarów i usług w słowniku — pojedyncze kliknięcie zaznacza,
/// podwójne otwiera edycję (spójnie z listami faktur).
struct ProductsListView: View {

    @Query(sort: \Product.name) private var products: [Product]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var selection = Set<UUID>()
    @State private var editedProduct: Product?
    @State private var showingNewProduct = false

    private var filtered: [Product] {
        guard !searchText.isEmpty else { return products }
        return products.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.sku.localizedCaseInsensitiveContains(searchText)
                || $0.cnPkwiu.contains(searchText)
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { product in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name).font(.headline)
                        HStack(spacing: 8) {
                            Text(product.type.displayName)
                            if !product.sku.isEmpty { Text("SKU: \(product.sku)") }
                            if !product.cnPkwiu.isEmpty { Text("CN/PKWiU: \(product.cnPkwiu)") }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(product.basePriceNet, format: .currency(code: "PLN"))
                            .monospacedDigit()
                        Text("netto, VAT \(product.basePriceVatRate.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .tag(product.id)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                Button("Edytuj") {
                    editedProduct = products.first { ids.contains($0.id) }
                }
                Button("Usuń ze słownika", role: .destructive) {
                    deleteProducts(ids)
                }
            }
        } primaryAction: { ids in
            editedProduct = products.first { ids.contains($0.id) }
        }
        .searchable(text: $searchText, prompt: "Szukaj po nazwie, SKU lub CN/PKWiU")
        .overlay {
            if products.isEmpty {
                ContentUnavailableView(
                    "Brak towarów i usług",
                    systemImage: "shippingbox",
                    description: Text("Dodaj pozycję przyciskiem +. Przy wystawianiu faktury dane słownika są tylko podstawiane — wszystko można zmienić.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingNewProduct = true
                } label: {
                    Label("Nowy towar/usługa", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewProduct) {
            ProductEditorView(original: nil)
        }
        .sheet(item: $editedProduct) { product in
            ProductEditorView(original: product)
        }
    }

    private func deleteProducts(_ ids: Set<UUID>) {
        for product in products where ids.contains(product.id) {
            modelContext.delete(product)
        }
        try? modelContext.save()
    }
}

/// Formularz towaru/usługi: informacje ogólne, księgowanie, cenniki.
/// Edycja na kopii roboczej — Anuluj nie zostawia śladów w bazie.
struct ProductEditorView: View {

    let original: Product?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var working = Product()

    /// Kody GTU ze słownika JPK/FA(2).
    private static let gtuCodes = [""] + (1...13).map { String(format: "GTU_%02d", $0) }

    private var canSave: Bool {
        !working.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        @Bindable var working = working
        VStack(spacing: 0) {
            Form {
                Section("Informacje ogólne") {
                    TextField("Nazwa produktu", text: $working.name, prompt: Text("Nazwa towaru lub usługi"))
                    Picker("Typ", selection: $working.type) {
                        ForEach(Product.ProductType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    TextField("Jednostka", text: $working.unit, prompt: Text("szt."))
                    TextField("Kategoria", text: $working.category)
                    TextField("Kod SKU", text: $working.sku)
                    TextField("Marka", text: $working.brand)
                    TextField("Kod EAN", text: $working.ean)
                }

                Section("Księgowanie") {
                    TextField("CN / PKWiU", text: $working.cnPkwiu,
                              prompt: Text("np. 62.01.11.0 (PKWiU) lub 85234910 (CN)"))
                    Picker("GTU", selection: $working.gtu) {
                        ForEach(Self.gtuCodes, id: \.self) { code in
                            Text(code.isEmpty ? "(brak)" : code).tag(code)
                        }
                    }
                    Toggle("Towar/usługa z załącznika 15", isOn: $working.isAttachment15)
                }

                Section("Cenniki") {
                    PriceRow(
                        label: "Cena bazowa",
                        net: $working.basePriceNet,
                        rate: $working.basePriceVatRate
                    )
                    PriceRow(
                        label: "Cena zakupu",
                        net: $working.purchasePriceNet,
                        rate: $working.purchasePriceVatRate
                    )
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Anuluj", role: .cancel) { dismiss() }
                Spacer()
                Button("Zapisz") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(minWidth: 520, minHeight: 480)
        .navigationTitle(original == nil ? "Nowy towar/usługa" : "Edycja towaru/usługi")
        .onAppear {
            if let original { working.copy(from: original) }
        }
    }

    private func save() {
        if let original {
            original.copy(from: working)
        } else {
            modelContext.insert(working)
        }
        try? modelContext.save()
        dismiss()
    }
}

/// Wiersz cennika: netto + stawka VAT + brutto (edycja brutto przelicza netto).
private struct PriceRow: View {
    let label: String
    @Binding var net: Double
    @Binding var rate: VATRate

    /// Brutto wyliczane ze stawki; wpisanie brutto przelicza netto wstecz.
    private var grossBinding: Binding<Double> {
        Binding(
            get: { ((net * (1 + rate.multiplier)) * 100).rounded() / 100 },
            set: { gross in net = ((gross / (1 + rate.multiplier)) * 100).rounded() / 100 }
        )
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("netto", value: $net, format: .number.precision(.fractionLength(2)))
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
            Text("netto")
                .foregroundStyle(.secondary)
            Picker("", selection: $rate) {
                ForEach(VATRate.allCases) { rate in
                    Text(rate.displayName).tag(rate)
                }
            }
            .labelsHidden()
            .frame(width: 70)
            TextField("brutto", value: grossBinding, format: .number.precision(.fractionLength(2)))
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
            Text("brutto")
                .foregroundStyle(.secondary)
        }
        .font(.body.monospacedDigit())
    }
}

extension Product {
    /// Kopiuje wszystkie pola edytowalne (bez `id`) z innego produktu.
    func copy(from other: Product) {
        name = other.name
        typeRaw = other.typeRaw
        unit = other.unit
        category = other.category
        sku = other.sku
        brand = other.brand
        ean = other.ean
        cnPkwiu = other.cnPkwiu
        gtu = other.gtu
        isAttachment15 = other.isAttachment15
        basePriceNet = other.basePriceNet
        basePriceVatRateRaw = other.basePriceVatRateRaw
        purchasePriceNet = other.purchasePriceNet
        purchasePriceVatRateRaw = other.purchasePriceVatRateRaw
    }
}
