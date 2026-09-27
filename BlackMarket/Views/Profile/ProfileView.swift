import SwiftUI
import SwiftData

struct ProfileView: View {
    var engine: GameEngine
    @Binding var showAdmin: Bool
    @Query private var players: [PlayerState]
    @Query private var achievementsAll: [AchievementRecord]
    @Query private var listingsAll: [ListingItem]
    @Query private var inventoryAll: [InventoryItem]
    @State private var tapCount = 0
    @State private var showCreateListing = false

    private var player: PlayerState? { players.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let player {
                        header(player)
                        statsRow()
                        achievementsSection
                        myShopSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .sheet(isPresented: $showCreateListing) {
                CreateListingView(engine: engine)
            }
        }
    }

    private func header(_ player: PlayerState) -> some View {
        VStack(spacing: 10) {
            Image(systemName: player.avatarSymbol)
                .font(.system(size: 60))
                .frame(width: 96, height: 96)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
                .onTapGesture { registerSecretTap() }
            Text("@\(player.username)").font(.title3.bold())
            LevelBadge(level: player.level)
            HStack(spacing: 20) {
                VStack { Text("\(player.followers)").bold(); Text("Followers").font(.caption2).foregroundStyle(.secondary) }
                VStack { Text("\(player.following)").bold(); Text("Following").font(.caption2).foregroundStyle(.secondary) }
                VStack { Text("\(player.reputation)").bold(); Text("Reputation").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func statsRow() -> some View {
        let stats = engine.businessStats()
        let player = engine.fetchPlayer()
        return HStack(spacing: 12) {
            StatPill(icon: "banknote.fill", label: "Net Worth", value: Formatters.money(stats.netWorth))
            StatPill(icon: "checkmark.seal.fill", label: "Badges", value: "\(player.badges.count)")
        }
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Achievements").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(GameData.achievements) { def in
                    let unlocked = achievementsAll.first { $0.achievementID == def.id }?.isUnlocked ?? false
                    VStack(spacing: 6) {
                        Image(systemName: def.icon)
                            .font(.title2)
                            .foregroundStyle(unlocked ? .green : .secondary)
                        Text(def.title)
                            .font(.caption2.bold())
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .padding(8)
                    .background(unlocked ? Color.green.opacity(0.12) : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(unlocked ? 1 : 0.5)
                }
            }
        }
        .cardStyle()
    }

    private var myShopSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("My Shop").font(.headline)
                Spacer()
                Button { showCreateListing = true } label: {
                    Label("New Listing", systemImage: "plus.circle.fill")
                }
                .font(.caption.bold())
                .disabled(inventoryAll.isEmpty)
            }
            if listingsAll.isEmpty {
                Text("No active listings. List inventory to sell to the network.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(listingsAll) { listing in
                if let product = GameData.product(listing.productID) {
                    HStack {
                        Image(systemName: product.icon).foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text(product.name).font(.subheadline.bold())
                            Text("x\(listing.quantity) @ \(Formatters.moneyPrecise(listing.price))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Cancel") { engine.cancelListing(listing) }
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .cardStyle()
    }

    /// Tap the avatar 7 times to reveal the hidden developer/admin menu.
    private func registerSecretTap() {
        tapCount += 1
        if tapCount >= 7 {
            tapCount = 0
            showAdmin = true
        }
    }
}

struct CreateListingView: View {
    var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @Query private var inventoryAll: [InventoryItem]
    @State private var selectedProductID: String?
    @State private var quantity = 1
    @State private var price: Double = 0

    private var items: [InventoryItem] { inventoryAll.filter { $0.quantity > 0 } }
    private var currentProductID: String { selectedProductID ?? items.first?.productID ?? "" }
    private var maxQty: Int { items.first { $0.productID == currentProductID }?.quantity ?? 1 }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Product", selection: Binding(
                    get: { currentProductID },
                    set: { selectedProductID = $0; price = engine.price(for: $0) }
                )) {
                    ForEach(items, id: \.productID) { item in
                        if let p = GameData.product(item.productID) {
                            Text("\(p.name) (\(item.quantity) in stock)").tag(item.productID)
                        }
                    }
                }
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...max(maxQty, 1))
                HStack {
                    Text("Price per unit")
                    Spacer()
                    TextField("Price", value: $price, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Button("Create Listing") {
                    if engine.createListing(productID: currentProductID, quantity: quantity, price: price) {
                        engine.incrementObjectiveProgress(matching: { $0.objectiveID == "obj_listing" })
                        dismiss()
                    }
                }
                .disabled(currentProductID.isEmpty || price <= 0)
            }
            .navigationTitle("New Listing")
            .onAppear { if price == 0 { price = engine.price(for: currentProductID) } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
