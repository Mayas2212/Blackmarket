import SwiftUI
import SwiftData

/// Simulated in-game BTC exchange. Never touches real Bitcoin or real payments.
struct BTCExchangeView: View {
    var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @Query private var players: [PlayerState]
    @Query private var overrides: [PriceOverride]
    @State private var usdInput: Double = 100
    @State private var btcInput: Double = 0.01

    private var player: PlayerState? { players.first }
    private var trend: Double { overrides.first { $0.productID == "BTC_RATE" }?.trend ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Simulated Rate")
                        Spacer()
                        Text(Formatters.moneyPrecise(engine.btcRate())).bold()
                    }
                    HStack {
                        Text("24h Trend")
                        Spacer()
                        TrendArrow(trend: trend)
                    }
                    Text("This is a simulated in-game currency only. It never connects to real Bitcoin or real payments.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section("Buy BTC") {
                    HStack {
                        Text("USD")
                        Spacer()
                        TextField("USD", value: $usdInput, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Text("≈ \(Formatters.btc(usdInput / max(engine.btcRate(), 1)))").font(.caption).foregroundStyle(.secondary)
                    Button("Buy BTC") { _ = engine.buyBTC(usdAmount: usdInput) }
                        .disabled((player?.cashUSD ?? 0) < usdInput || usdInput <= 0)
                }
                Section("Sell BTC") {
                    HStack {
                        Text("BTC")
                        Spacer()
                        TextField("BTC", value: $btcInput, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Text("≈ \(Formatters.moneyPrecise(btcInput * engine.btcRate()))").font(.caption).foregroundStyle(.secondary)
                    Button("Sell BTC") { _ = engine.sellBTC(btcAmount: btcInput) }
                        .disabled((player?.btc ?? 0) < btcInput || btcInput <= 0)
                }
            }
            .navigationTitle("BTC Exchange")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
