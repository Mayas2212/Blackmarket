import SwiftUI
import SwiftData
import Charts

struct MarketView: View {
    var engine: GameEngine
    @Query private var players: [PlayerState]
    @Query private var priceOverrides: [PriceOverride]
    @State private var selectedCategory: ProductCategory?
    @State private var selectedProduct: ProductDef?
    @State private var selectedCoinID: String?
    @State private var chartDays = 30

    private var player: PlayerState? { players.first }

    private var availableCategories: [ProductCategory] {
        guard let player else { return [] }
        let unlocked = Set(engine.availableProducts(for: player).map(\.category))
        return ProductCategory.allCases.filter { unlocked.contains($0) }
    }

    private var availableProducts: [ProductDef] {
        guard let player else { return [] }
        let all = engine.availableProducts(for: player)
        guard let cat = selectedCategory else { return all }
        return all.filter { $0.category == cat }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                cryptoSection
                categoryFilter
                LazyVStack(spacing: 12) {
                    ForEach(availableProducts) { product in
                        Button { selectedProduct = product } label: {
                            ProductRow(product: product, price: engine.price(for: product.id), trend: trend(for: product.id))
                        }
                        .buttonStyle(PressFeedbackStyle())
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding()
                .animation(.snappy(duration: 0.28), value: availableProducts.map(\.id))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Market")
            .sensoryFeedback(.selection, trigger: selectedCategory)
            .sheet(item: $selectedProduct) { product in
                BuySheet(engine: engine, product: product)
            }
            .sheet(isPresented: Binding(get: { selectedCoinID != nil }, set: { if !$0 { selectedCoinID = nil } })) {
                if let id = selectedCoinID, let coin = GameData.cryptocurrencies.first(where: { $0.id == id }) {
                    CryptoTradeSheet(engine: engine, coin: coin)
                }
            }
        }
    }

    private var cryptoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Crypto Market").font(.headline)
            Text("Simulated coins · prices move once each night").font(.caption).foregroundStyle(.secondary)
            Picker("Chart period", selection: $chartDays) {
                Text("1W").tag(7)
                Text("1M").tag(30)
                Text("3M").tag(90)
            }
            .pickerStyle(.segmented)
            ForEach(GameData.cryptocurrencies, id: \.id) { coin in
                let history = engine.priceHistory(for: coin.id, days: chartDays)
                let percentChange = history.first.flatMap { first in
                    history.last.map { last in first.price == 0 ? 0 : ((last.price / first.price) - 1) * 100 }
                } ?? 0
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(coin.symbol)  \(coin.name)").font(.subheadline.bold())
                        Spacer()
                        Text(Formatters.moneyPrecise(engine.price(for: coin.id))).font(.subheadline.bold())
                        TrendArrow(trend: priceOverrides.first { $0.productID == coin.id }?.trend ?? 0)
                    }
                    Text(history.count > 1 ? "\(chartDays)-day change  \(String(format: "%+.2f%%", percentChange))" : "Trend starts after the next daily close")
                        .font(.caption2.monospacedDigit()).foregroundStyle(history.count > 1 ? (percentChange >= 0 ? Color.green : Color.red) : Color.gray)
                    HStack {
                        Text("You own: \(String(format: "%.5f", engine.cryptoAmount(coin.id))) \(coin.symbol)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Trade") { selectedCoinID = coin.id }.font(.caption.bold()).buttonStyle(.borderedProminent)
                    }
                    PriceLineChart(history: history, color: .orange)
                }
                .padding(12).background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
    }

    private func trend(for productID: String) -> Double {
        priceOverrides.first { $0.productID == productID }?.trend ?? 0
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                categoryChip(nil, title: "All")
                ForEach(availableCategories, id: \.self) { cat in
                    categoryChip(cat, title: cat.rawValue)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func categoryChip(_ cat: ProductCategory?, title: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.28)) { selectedCategory = cat }
        } label: {
            Text(title)
                .font(.subheadline.bold())
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selectedCategory == cat ? Color.green.opacity(0.2) : Color(.secondarySystemBackground))
                .foregroundStyle(selectedCategory == cat ? .green : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(PressFeedbackStyle())
    }
}

struct CryptoTradeSheet: View {
    var engine: GameEngine
    let coin: CryptoDef
    @Environment(\.dismiss) private var dismiss
    @Query private var players: [PlayerState]
    @State private var usdAmount = 100.0
    @State private var coinAmount = 0.01
    private var player: PlayerState? { players.first }
    private var rate: Double { engine.price(for: coin.id) }
    var body: some View {
        NavigationStack {
            Form {
                Section("\(coin.name) · simulated only") {
                    LabeledContent("Rate", value: Formatters.moneyPrecise(rate))
                    LabeledContent("Owned", value: "\(String(format: "%.6f", engine.cryptoAmount(coin.id))) \(coin.symbol)")
                }
                Section("Buy") {
                    TextField("USD amount", value: $usdAmount, format: .number).keyboardType(.decimalPad)
                    Text("Receive about \(String(format: "%.6f", usdAmount / max(rate, 0.000001))) \(coin.symbol)").font(.caption).foregroundStyle(.secondary)
                    Button("Buy \(coin.name)") { if coin.id == "BTC_RATE" { _ = engine.buyBTC(usdAmount: usdAmount) } else { _ = engine.buyCrypto(assetID: coin.id, usdAmount: usdAmount) } }
                        .disabled((player?.cashUSD ?? 0) < usdAmount || usdAmount <= 0)
                }
                Section("Sell") {
                    TextField("Coin amount", value: $coinAmount, format: .number).keyboardType(.decimalPad)
                    Text("Receive about \(Formatters.moneyPrecise(coinAmount * rate))").font(.caption).foregroundStyle(.secondary)
                    Button("Sell \(coin.name)") { if coin.id == "BTC_RATE" { _ = engine.sellBTC(btcAmount: coinAmount) } else { _ = engine.sellCrypto(assetID: coin.id, amount: coinAmount) } }
                        .disabled(engine.cryptoAmount(coin.id) < coinAmount || coinAmount <= 0)
                }
            }
            .navigationTitle("Crypto trade")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct PriceLineChart: View {
    let history: [PriceSnapshot]
    var color: Color = .green
    var body: some View {
        Chart(history) { point in
            AreaMark(x: .value("Day", point.date), y: .value("Price", point.price))
                .foregroundStyle(color.opacity(0.12).gradient)
            LineMark(x: .value("Day", point.date), y: .value("Price", point.price))
                .foregroundStyle(color.gradient).interpolationMethod(.linear)
            PointMark(x: .value("Day", point.date), y: .value("Price", point.price))
                .foregroundStyle(color).symbolSize(16)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    .font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, desiredCount: 3) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Formatters.moneyPrecise(amount)).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 112)
        .animation(.snappy(duration: 0.35), value: history.count)
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
                    Text(product.fixedPrice ? "Fixed-price item" : "Daily market price").font(.caption2).foregroundStyle(.secondary)
                    PriceLineChart(history: engine.priceHistory(for: product.id))
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
