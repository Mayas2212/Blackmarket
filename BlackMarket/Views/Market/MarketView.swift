import SwiftUI
import SwiftData

struct MarketView: View {
    var engine: GameEngine
    @Query private var players: [PlayerState]
    @Query private var priceOverrides: [PriceOverride]
    @State private var selectedCategory: ProductCategory?
    @State private var selectedProduct: ProductDef?

    private var player: PlayerState? { players.first }

    private var availableProducts: [ProductDef] {
        guard let player else { return [] }
        let all = engine.availableProducts(for: player)
        guard let cat = selectedCategory else { return all }
        return all.filter { $0.category == cat }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                categoryFilter
                LazyVStack(spacing: 12) {
                    ForEach(availableProducts) { product in
                        Button { selectedProduct = product } label: {
                            ProductRow(product: product, price: engine.price(for: product.id), trend: trend(for: product.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Market")
            .sheet(item: $selectedProduct) { product in
                BuySheet(engine: engine, product: product)
            }
        }
    }

    private func trend(for productID: String) -> Double {
        priceOverrides.first { $0.productID == productID }?.trend ?? 0
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                categoryChip(nil, title: "All")
                ForEach(ProductCategory.allCases, id: \.self) { cat in
                    categoryChip(cat, title: cat.rawValue)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func categoryChip(_ cat: ProductCategory?, title: String) -> some View {
        Button {
            withAnimation { selectedCategory = cat }
        } label: {
            Text(title)
                .font(.subheadline.bold())
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selectedCategory == cat ? Color.green.opacity(0.2) : Color(.secondarySystemBackground))
                .foregroundStyle(selectedCategory == cat ? .green : .primary)
                .clipShape(Capsule())
        }
    }
}

struct ProductRow: View {
    let product: ProductDef
    let price: Double
    let trend: Double

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: product.icon)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.green.opacity(0.12))
                .foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name).font(.subheadline.bold()).foregroundStyle(.primary)
                Text(product.category.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Formatters.moneyPrecise(price)).font(.subheadline.bold()).foregroundStyle(.primary)
                TrendArrow(trend: trend)
            }
        }
        .cardStyle()
    }
}

struct BuySheet: View {
    var engine: GameEngine
    let product: ProductDef
    @Environment(\.dismiss) private var dismiss
    @Query private var players: [PlayerState]
    @State private var quantity = 1
    @State private var selectedSupplierID: String?

    private var player: PlayerState? { players.first }
    private var suppliers: [SupplierDef] {
        guard let player else { return [] }
        return engine.availableSuppliers(for: player).filter { $0.productIDs.contains(product.id) }
    }
    private var supplier: SupplierDef? {
        if let id = selectedSupplierID { return suppliers.first { $0.id == id } }
        return suppliers.first
    }
    private var unitPrice: Double {
        engine.price(for: product.id) * (1 - (supplier?.discount ?? 0))
    }
    private var total: Double { unitPrice * Double(quantity) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: product.icon).foregroundStyle(.green)
                        Text(product.name).font(.headline)
                    }
                    Text("Market price: \(Formatters.moneyPrecise(engine.price(for: product.id)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Supplier") {
                    if suppliers.isEmpty {
                        Text("Buying at market rate.").foregroundStyle(.secondary)
                    } else {
                        Picker("Supplier", selection: Binding(
                            get: { selectedSupplierID ?? suppliers.first?.id ?? "" },
                            set: { selectedSupplierID = $0 }
                        )) {
                            ForEach(suppliers) { s in
                                Text("\(s.name) (-\(Int(s.discount * 100))%)").tag(s.id)
                            }
                        }
                    }
                }
                Section("Quantity") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                }
                Section {
                    HStack {
                        Text("Total")
                        Spacer()
                        Text(Formatters.moneyPrecise(total)).bold()
                    }
                }
                Section {
                    Button {
                        if engine.buy(productID: product.id, quantity: quantity, supplier: supplier) {
                            engine.incrementObjectiveProgress(matching: { $0.objectiveID == "obj_buy2" })
                            dismiss()
                        }
                    } label: {
                        Text("Confirm Purchase").frame(maxWidth: .infinity).bold()
                    }
                    .disabled((player?.cashUSD ?? 0) < total)
                }
            }
            .navigationTitle("Buy")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
