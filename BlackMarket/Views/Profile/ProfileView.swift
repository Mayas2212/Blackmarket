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
    @State private var showSettings = false

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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "gearshape") } } }
            .sheet(isPresented: $showCreateListing) {
                CreateListingView(engine: engine)
            }
            .sheet(isPresented: $showSettings) { SettingsView(engine: engine, showAdmin: $showAdmin) }
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
            Text("\(player.reputation >= 0 ? "★" : "☆")  Trust score · \(player.reputation)")
                .font(.caption.bold()).foregroundStyle(player.reputation >= 0 ? .orange : .red)
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
                            Text(listing.saleCompletesAt.map { "Auto-sale around \(Formatters.compactDate($0))" } ?? "Auto-sale progress continues while you’re away")
                                .font(.caption2).foregroundStyle(.secondary)
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
            if let player {
                player.isDevModeUnlocked = true
                try? engine.context.save()
            }
            showAdmin = true
        }
    }
}

struct SettingsView: View {
    var engine: GameEngine
    @Binding var showAdmin: Bool
    @Environment(\.dismiss) private var dismiss
    @Query private var players: [PlayerState]
    @AppStorage("blackmarket.darkMode") private var darkMode = false
    @AppStorage("blackmarket.accent") private var accent = "green"
    @State private var username = ""
    private var player: PlayerState? { players.first }
    private let avatars = ["person.crop.circle.fill", "person.fill", "person.crop.circle", "person.crop.square.fill", "theatermasks.fill", "star.circle.fill"]
    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Username", text: $username).textInputAutocapitalization(.never)
                    Picker("Avatar", selection: Binding(get: { player?.avatarSymbol ?? avatars[0] }, set: { player?.avatarSymbol = $0; try? engine.context.save() })) {
                        ForEach(avatars, id: \.self) { avatar in Label(avatar.capitalized, systemImage: avatar).tag(avatar) }
                    }
                }
                Section("Appearance") {
                    Toggle("Dark appearance", isOn: $darkMode)
                    Picker("Accent color", selection: $accent) {
                        Text("Green").tag("green"); Text("Blue").tag("blue"); Text("Purple").tag("purple"); Text("Orange").tag("orange")
                    }
                }
                Section("Developer tools") {
                    if player?.isDevModeUnlocked == true {
                        Button("Open developer settings") { dismiss(); showAdmin = true }
                    } else {
                        Text("Tap your profile avatar seven times to unlock developer settings.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section { Text("Market prices update once per day. Crypto and game prices are simulated.").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { save(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
            }
            .onAppear { username = player?.username ?? "" }
            .preferredColorScheme(darkMode ? .dark : .light)
        }
    }
    private func save() {
        if let player { player.username = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "you_underground" : username; try? engine.context.save() }
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
