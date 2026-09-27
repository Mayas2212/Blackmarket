import SwiftUI
import SwiftData

struct HomeView: View {
    var engine: GameEngine
    @Query private var players: [PlayerState]
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var objectives: [DailyObjective]
    @Query private var events: [ActiveMarketEvent]
    @State private var showBTCExchange = false

    private var player: PlayerState? { players.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let player {
                        balanceHeader(player)
                        objectivesSection
                        activeEventsSection
                        activityFeed
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("BLACKMARKET")
            .refreshable { engine.simulateMarketTick() }
            .onAppear { engine.simulateMarketTick() }
            .sheet(isPresented: $showBTCExchange) { BTCExchangeView(engine: engine) }
        }
    }

    private func balanceHeader(_ player: PlayerState) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome back,").font(.subheadline).foregroundStyle(.secondary)
                    Text("@\(player.username)").font(.title2.bold())
                }
                Spacer()
                LevelBadge(level: player.level)
            }
            HStack(spacing: 12) {
                StatPill(icon: "dollarsign.circle.fill", label: "Cash", value: Formatters.money(player.cashUSD), tint: .green)
                Button { showBTCExchange = true } label: {
                    StatPill(icon: "bitcoinsign.circle.fill", label: "BTC (tap to trade)", value: Formatters.btc(player.btc), tint: .orange)
                }
                .buttonStyle(PressFeedbackStyle())
            }
            HStack(spacing: 12) {
                StatPill(icon: "star.fill", label: "Reputation", value: "\(player.reputation)", tint: .yellow)
                StatPill(icon: "person.2.fill", label: "Followers", value: "\(player.followers)", tint: .blue)
            }
        }
        .cardStyle()
    }

    private var objectivesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's Objectives").font(.headline)
            ForEach(objectives.filter { Calendar.current.isDateInToday($0.dateAssigned) }) { obj in
                HStack {
                    Image(systemName: obj.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(obj.isCompleted ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(obj.title).font(.subheadline.bold())
                        Text(obj.objectiveDescription).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(obj.progress)/\(obj.target)").font(.caption.bold())
                }
                .animation(.default, value: obj.progress)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .cardStyle()
        .animation(.snappy(duration: 0.25), value: objectives.count)
    }

    @ViewBuilder
    private var activeEventsSection: some View {
        let active = events.filter { $0.expiresAt >= .now }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Market Events").font(.headline)
                ForEach(active) { event in
                    HStack(spacing: 10) {
                        Image(systemName: event.icon)
                            .foregroundStyle(event.multiplier >= 1 ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.subheadline.bold())
                            Text(event.eventDescription).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
                .cardStyle()
                .animation(.snappy(duration: 0.25), value: events.count)
        }
    }

    private var activityFeed: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity").font(.headline)
            if transactions.isEmpty {
                Text("No activity yet. Head to the Market to start dealing.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(transactions.prefix(15)) { tx in
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: icon(for: tx))
                            .foregroundStyle(tx.total >= 0 ? .green : .red)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(for: tx)).font(.subheadline)
                            Text(Formatters.compactDate(tx.date)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Formatters.moneyPrecise(tx.total))
                            .font(.subheadline.bold())
                            .foregroundStyle(tx.total >= 0 ? .green : .primary)
                    }
                    Divider().padding(.top, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
        .animation(.snappy(duration: 0.28), value: transactions.first?.date)
    }

    private func icon(for tx: TransactionRecord) -> String {
        switch tx.type {
        case .buy: return "arrow.down.circle.fill"
        case .sell, .listingSale: return "arrow.up.circle.fill"
        case .btcTrade: return "bitcoinsign.circle.fill"
        case .event: return "bolt.fill"
        case .admin: return "wrench.fill"
        }
    }

    private func label(for tx: TransactionRecord) -> String {
        if let pid = tx.productID, let product = GameData.product(pid) {
            return "\(tx.type == .buy ? "Bought" : "Sold") \(tx.quantity)x \(product.name)"
        }
        return tx.note.isEmpty ? tx.type.rawValue.capitalized : tx.note
    }
}
