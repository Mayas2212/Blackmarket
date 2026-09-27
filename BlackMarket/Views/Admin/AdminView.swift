import SwiftUI
import SwiftData

/// Hidden developer/admin panel. Reached by tapping the profile avatar 7 times.
/// Intended for testing only.
struct AdminView: View {
    var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @Query private var players: [PlayerState]
    @State private var cashAmount: Double = 1000
    @State private var btcAmount: Double = 0.1
    @State private var repAmount: Int = 100
    @State private var selectedProductID = GameData.products.first?.id ?? ""
    @State private var spawnQty = 5
    @State private var newPrice: Double = 0
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Currency") {
                    Stepper("Cash amount: \(Formatters.money(cashAmount))", value: $cashAmount, in: -100000...100000, step: 100)
                    Button("Add Cash") { engine.adminAddCash(cashAmount) }
                    Stepper("BTC amount: \(String(format: "%.2f", btcAmount))", value: $btcAmount, in: -10...10, step: 0.1)
                    Button("Add BTC") { engine.adminAddBTC(btcAmount) }
                }
                Section("Reputation & Level") {
                    Stepper("Reputation: \(repAmount)", value: $repAmount, in: 0...5000, step: 50)
                    Button("Set Reputation") { engine.adminSetReputation(repAmount) }
                    ForEach(SellerLevel.allCases, id: \.self) { level in
                        Button("Unlock \(level.title)") { engine.adminUnlockLevel(level) }
                    }
                }
                Section("Inventory") {
                    Picker("Product", selection: $selectedProductID) {
                        ForEach(GameData.products) { p in Text(p.name).tag(p.id) }
                    }
                    Stepper("Quantity: \(spawnQty)", value: $spawnQty, in: 1...999)
                    Button("Spawn Item") { engine.adminSpawnItem(productID: selectedProductID, quantity: spawnQty) }
                }
                Section("Pricing") {
                    HStack {
                        Text("New price")
                        Spacer()
                        TextField("Price", value: $newPrice, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Button("Set Price for Selected Product") { engine.adminSetPrice(productID: selectedProductID, price: newPrice) }
                }
                Section("Market Events") {
                    Button("Trigger Random Event") { engine.triggerRandomEvent() }
                }
                Section("Danger Zone") {
                    Button(role: .destructive) { confirmReset = true } label: {
                        Text("Reset All Data")
                    }
                }
            }
            .navigationTitle("Dev / Admin")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .alert("Reset all game data?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { engine.adminResetAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }
}
