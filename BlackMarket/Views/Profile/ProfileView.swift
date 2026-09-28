import SwiftUI
import SwiftData

struct ProfileView: View {
    var engine: GameEngine
    @Binding var showAdmin: Bool
    @Query private var players: [PlayerState]
    @Query private var achievementsAll: [AchievementRecord]
    @Query private var listingsAll: [ListingItem]
    @Query private var inventoryAll: [InventoryItem]
    @Query private var messageRecords: [MessageRecord]
    @Query private var shippingRecords: [ShippingOrder]
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
                .padding(.bottom, 100)
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
            HStack {
                Label("Buyer trust", systemImage: "checkmark.seal.fill").font(.caption.bold())
                Spacer()
                Text("\(player.trustScore)/100 · \(trustLabel(player.trustScore))")
                    .font(.caption.bold()).foregroundStyle(trustColor(player.trustScore))
            }
            ProgressView(value: Double(player.trustScore), total: 100).tint(trustColor(player.trustScore))
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("\(player.loginStreak)-day check-in streak").font(.caption.bold())
                Spacer()
                Text("\(player.referralCount) referrals").font(.caption).foregroundStyle(.secondary)
            }
            Text("Career reputation · \(player.reputation)").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func trustLabel(_ score: Int) -> String {
        switch score {
        case ..<25: "At risk"
        case ..<50: "Rebuilding"
        case ..<80: "Steady"
        default: "Trusted"
        }
    }

    private func trustColor(_ score: Int) -> Color {
        score < 30 ? .red : (score < 65 ? .orange : .green)
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
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Storage", systemImage: "shippingbox")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(engine.storageUsed()) / \(engine.storageCapacity(for: player)) · Lv. \(player?.storageLevel ?? 0)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(engine.storageUsed() >= engine.storageCapacity(for: player) ? .orange : .secondary)
                }
                ProgressView(value: min(1, Double(engine.storageUsed()) / Double(max(engine.storageCapacity(for: player), 1))))
                    .tint(engine.storageUsed() >= engine.storageCapacity(for: player) ? .orange : .green)
                HStack {
                    Text("On hand and incoming orders use space.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let player, player.storageLevel < 10 {
                        let cost = engine.storageUpgradeCost(for: player)
                        Button("Upgrade · \(Formatters.money(cost))") { _ = engine.upgradeStorage() }
                            .font(.caption.bold())
                            .disabled(player.cashUSD < cost)
                    } else {
                        Text("Max level").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(11)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if listingsAll.isEmpty {
                Text("No active listings. List inventory to sell to the network.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(listingsAll) { listing in
                if let product = GameData.product(listing.productID) {
                    let status = listingStatus(listing)
                    HStack {
                        Image(systemName: product.icon).foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text(listing.claimedAsAuthentic == true && product.isCounterfeit ? (product.publicAlias ?? "Collector item") : product.name).font(.subheadline.bold())
                            Text("x\(listing.quantity) @ \(Formatters.moneyPrecise(listing.price))").font(.caption).foregroundStyle(.secondary)
                            if listing.claimedAsAuthentic == true { Text("Listed as authentic · verification risk").font(.caption2).foregroundStyle(.orange) }
                            Text(status)
                                .font(.caption2).foregroundStyle(status.contains("Offer") || status.contains("Message") ? .orange : .gray)
                        }
                        Spacer()
                        Button(engine.canStore(listing.quantity) ? "Cancel" : "Storage full") { _ = engine.cancelListing(listing) }
                            .font(.caption).foregroundStyle(.red)
                            .disabled(!engine.canStore(listing.quantity))
                    }
                }
            }
        }
        .cardStyle()
    }

    private func listingStatus(_ listing: ListingItem) -> String {
        if let order = shippingRecords.first(where: { $0.isSale && $0.listingCreatedAt == listing.createdAt && !$0.isComplete }) {
            return "Shipping · arrives \(Formatters.compactDate(order.arrivesAt))"
        }
        let thread = messageRecords.filter { $0.listingCreatedAt == listing.createdAt }.sorted { $0.date < $1.date }
        let latestOffer = thread.last(where: { !$0.isFromPlayer && $0.listingProductID == listing.productID })
        if let latestOffer,
           let lastPlayerReply = thread.last(where: { $0.isFromPlayer && $0.npcID == latestOffer.npcID && $0.date > latestOffer.date }),
           lastPlayerReply.text.hasPrefix("Thanks, but I’ll pass") {
            return "Offer declined · listing is still live"
        }
        if latestOffer?.isDelivered == true {
            return "Offer received · open Messages to negotiate"
        }
        if let date = listing.saleCompletesAt, date > .now {
            return "Waiting for buyer activity around \(Formatters.compactDate(date))"
        }
        return "Live · waiting for a buyer"
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
    @AppStorage("blackmarket.devSettingsOn") private var devSettingsOn = false
    @AppStorage("blackmarket.messageSounds") private var messageSounds = true
    @AppStorage("blackmarket.buyerNotifications") private var buyerNotifications = false
    @State private var username = ""
    @State private var confirmReset = false
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
                Section("Messages") {
                    Toggle("Message sounds", isOn: $messageSounds)
                    Toggle("Buyer notifications", isOn: $buyerNotifications)
                    Text("Buyers can contact you about active profile listings while the app is closed. Notifications are delivered by iOS.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Developer tools") {
                    if player?.isDevModeUnlocked == true {
                        Toggle("Enable developer settings", isOn: $devSettingsOn)
                        Button("Open developer settings") { dismiss(); showAdmin = true }
                        Text("When enabled, developer mode can skip package delivery waits.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Tap your profile avatar seven times to unlock developer settings.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section { Text("Market prices update once per day. Crypto and game prices are simulated.").font(.caption).foregroundStyle(.secondary) }
                Section("Game data") {
                    Button("Reset game progress", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { save(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
            }
            .onAppear { username = player?.username ?? "" }
            .onChange(of: buyerNotifications) { _, enabled in
                guard enabled else { MessageNotifications.cancelPending(); return }
                Task {
                    let allowed = await MessageNotifications.requestAuthorization()
                    if allowed { engine.schedulePendingMessageNotifications() }
                    else { buyerNotifications = false }
                }
            }
            .confirmationDialog("Reset all progress?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset game", role: .destructive) {
                    engine.adminResetAllData()
                    username = engine.fetchPlayer().username
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes your cash, inventory, listings, contacts, messages, objectives, and achievements.")
            }
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
    @State private var claimAsAuthentic = true

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
                if GameData.product(currentProductID)?.isCounterfeit == true {
                    Toggle("List as authentic", isOn: $claimAsAuthentic)
                    Text("A higher asking price can pay off, but buyers may inspect the item, reverse payment, and leave a poor review.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Price per unit")
                    Spacer()
                    TextField("Price", value: $price, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Button("Create Listing") {
                    if engine.createListing(productID: currentProductID, quantity: quantity, price: price, claimedAsAuthentic: claimAsAuthentic) {
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
