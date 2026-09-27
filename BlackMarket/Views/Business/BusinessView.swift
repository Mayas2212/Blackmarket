import SwiftUI
import SwiftData
import Charts

struct BusinessView: View {
    var engine: GameEngine
    @Query private var players: [PlayerState]
    @Query private var listingsAll: [ListingItem]
    @Query private var inventoryAll: [InventoryItem]
    @Query(sort: \TransactionRecord.date) private var transactionsAll: [TransactionRecord]

    private var player: PlayerState? { players.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let player {
                        levelProgress(player)
                        statsGrid
                        profitChart
                        inventoryBreakdown
                        activeListingsSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Business")
        }
    }

    private func levelProgress(_ player: PlayerState) -> some View {
        let current = player.level
        let next = SellerLevel(rawValue: current.rawValue + 1)
        let progress: Double = {
            guard let next else { return 1 }
            let range = Double(next.repRequired - current.repRequired)
            let done = Double(player.reputation - current.repRequired)
            return range > 0 ? min(1, max(0, done / range)) : 1
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                LevelBadge(level: current)
                Spacer()
                if let next {
                    Text("Next: \(next.title)").font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: progress).tint(.green)
            Text("\(player.reputation) reputation").font(.caption2).foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var statsGrid: some View {
        let stats = engine.businessStats()
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatPill(icon: "arrow.up.circle.fill", label: "Revenue (30d)", value: Formatters.money(stats.revenue), tint: .green)
            StatPill(icon: "arrow.down.circle.fill", label: "Expenses (30d)", value: Formatters.money(stats.expenses), tint: .red)
            StatPill(icon: "chart.line.uptrend.xyaxis", label: "Profit (30d)", value: Formatters.money(stats.profit), tint: stats.profit >= 0 ? .green : .red)
            StatPill(icon: "percent", label: "Margin", value: Formatters.percent(stats.margin), tint: .blue)
            StatPill(icon: "shippingbox.fill", label: "Inventory Value", value: Formatters.money(stats.inventoryValue), tint: .orange)
            StatPill(icon: "banknote.fill", label: "Net Worth", value: Formatters.money(stats.netWorth), tint: .green)
        }
    }

    private var profitChart: some View {
        let series = engine.dailyProfitSeries()
        return VStack(alignment: .leading, spacing: 10) {
            Text("Daily Profit (14d)").font(.headline)
            Chart(series, id: \.date) { entry in
                BarMark(
                    x: .value("Day", entry.date, unit: .day),
                    y: .value("Profit", entry.profit)
                )
                .foregroundStyle(entry.profit >= 0 ? Color.green : Color.red)
            }
            .frame(height: 180)
        }
        .cardStyle()
    }

    private var inventoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inventory").font(.headline)
            if inventoryAll.isEmpty {
                Text("No inventory on hand.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(inventoryAll, id: \.productID) { item in
                if let product = GameData.product(item.productID) {
                    HStack {
                        Image(systemName: product.icon).foregroundStyle(.green)
                        Text(product.name).font(.subheadline)
                        Spacer()
                        Text("x\(item.quantity)").font(.caption).foregroundStyle(.secondary)
                        Text(Formatters.money(engine.price(for: item.productID) * Double(item.quantity))).font(.subheadline.bold())
                    }
                }
            }
        }
        .cardStyle()
    }

    private var activeListingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Listings").font(.headline)
            if listingsAll.isEmpty {
                Text("No active listings.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(listingsAll) { listing in
                if let product = GameData.product(listing.productID) {
                    HStack {
                        Image(systemName: product.icon).foregroundStyle(.blue)
                        Text(product.name).font(.subheadline)
                        Spacer()
                        Text("x\(listing.quantity) @ \(Formatters.moneyPrecise(listing.price))").font(.caption)
                    }
                }
            }
        }
        .cardStyle()
    }
}
