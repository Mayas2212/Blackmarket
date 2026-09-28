import SwiftUI
import SwiftData

struct NetworkView: View {
    var engine: GameEngine
    @Query private var followed: [FollowedNPC]
    @Query private var players: [PlayerState]
    @State private var selectedNPC: NPCDef?

    private var contacts: [NPCDef] {
        var byID = Dictionary(uniqueKeysWithValues: (players.first.map { engine.availableContacts(for: $0) } ?? GameData.npcs).map { ($0.id, $0) })
        for relation in followed {
            if let npc = GameData.npc(relation.npcID) { byID[npc.id] = npc }
        }
        return byID.values.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Your Network") {
                    ForEach(contacts) { npc in
                        Button { selectedNPC = npc } label: {
                            NPCRow(npc: npc, isFollowing: followed.first { $0.npcID == npc.id }?.isFollowing ?? false)
                        }
                        .buttonStyle(PressFeedbackStyle())
                    }
                    Color.clear.frame(height: 88).listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Network")
            .sheet(item: $selectedNPC) { NPCChatView(engine: engine, npc: $0) }
        }
    }
}

struct MessagesView: View {
    var engine: GameEngine
    @Query private var followed: [FollowedNPC]
    @Query(sort: \MessageRecord.date, order: .reverse) private var allMessages: [MessageRecord]
    @State private var selectedNPC: NPCDef?

    private var latestMessageByContact: [String: MessageRecord] {
        var latest: [String: MessageRecord] = [:]
        for message in allMessages where message.isDelivered {
            if (latest[message.npcID]?.date ?? .distantPast) < message.date {
                latest[message.npcID] = message
            }
        }
        return latest
    }

    private var contactIDs: [String] {
        let latestDates = latestMessageByContact.mapValues(\.date)
        let ids = Set(followed.filter(\.isFollowing).map(\.npcID) + Array(latestMessageByContact.keys))
        return ids.sorted { first, second in
            let firstDate = latestDates[first] ?? .distantPast
            let secondDate = latestDates[second] ?? .distantPast
            if firstDate != secondDate { return firstDate > secondDate }
            return (GameData.npc(first)?.name ?? first) < (GameData.npc(second)?.name ?? second)
        }
    }

    private func latestMessage(for id: String) -> MessageRecord? {
        latestMessageByContact[id]
    }

    private func roleColor(for npc: NPCDef) -> Color {
        switch npc.kind {
        case .buyer: return .green
        case .seller: return .blue
        case .rival: return .orange
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Your conversations") {
                    if contactIDs.isEmpty {
                        ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right", description: Text("Visit Network and start a conversation with a buyer or seller."))
                    }
                    ForEach(contactIDs, id: \.self) { id in
                        if let npc = GameData.npc(id) {
                            Button { selectedNPC = npc } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: npc.avatarSymbol).font(.title2).foregroundStyle(.green)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(npc.name).font(.subheadline.bold()).foregroundStyle(.primary)
                                        HStack(spacing: 6) {
                                            Text(npc.kind.rawValue.capitalized)
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 7).padding(.vertical, 3)
                                                .background(roleColor(for: npc).opacity(0.12))
                                                .foregroundStyle(roleColor(for: npc))
                                                .clipShape(Capsule())
                                            Text(latestMessage(for: id)?.text ?? npc.bio)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    if let message = latestMessage(for: id) {
                                        Text(Formatters.compactDate(message.date))
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(PressFeedbackStyle())
                        }
                    }
                    Color.clear.frame(height: 88).listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Messages")
            .sheet(item: $selectedNPC) { NPCChatView(engine: engine, npc: $0) }
        }
    }
}

struct NPCRow: View {
    let npc: NPCDef
    let isFollowing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: npc.avatarSymbol)
                .font(.title)
                .frame(width: 48, height: 48)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(npc.name).font(.subheadline.bold()).foregroundStyle(.primary)
                Text(npc.bio).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(npc.kind.rawValue.capitalized)
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(kindColor.opacity(0.15))
                .foregroundStyle(kindColor)
                .clipShape(Capsule())
            if isFollowing { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
        }
        .padding(.vertical, 4)
    }

    private var kindColor: Color {
        switch npc.kind {
        case .buyer: return .green
        case .seller: return .blue
        case .rival: return .orange
        }
    }
}

private enum ChatAction: Equatable { case home, browsingStock, negotiatingPurchase, readyToPurchase, choosingItem, negotiatingSale, readyToShip, shipping, waitingForReply }

struct NPCChatView: View {
    var engine: GameEngine
    let npc: NPCDef
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var followedAll: [FollowedNPC]
    @Query private var reviewsAll: [ReviewRecord]
    @Query private var messagesAll: [MessageRecord]
    @Query private var inventoryAll: [InventoryItem]
    @Query private var stockAll: [NPCStockItem]
    @Query private var listingAll: [ListingItem]
    @Query private var shippingAll: [ShippingOrder]
    @Query private var players: [PlayerState]
    @AppStorage("blackmarket.devSettingsOn") private var devMode = false
    @State private var action: ChatAction = .home
    @State private var activeProductID: String?
    @State private var activeStockID: PersistentIdentifier?
    @State private var targetPrice = 0.0
    @State private var agreedPrice = 0.0
    @State private var negotiationCount = 0
    @State private var purchaseQuantity = 1
    @State private var saleQuantity = 1
    @State private var pendingAction: ChatAction?
    @State private var lastSeenMessageCount = 0

    private var player: PlayerState? { players.first }
    private var isFollowing: Bool { followedAll.first { $0.npcID == npc.id }?.isFollowing ?? false }
    private var reviews: [ReviewRecord] { reviewsAll.filter { $0.npcID == npc.id && $0.isAboutPlayer != true } }
    private var messages: [MessageRecord] { messagesAll.filter { $0.npcID == npc.id && $0.isDelivered }.sorted { $0.date < $1.date } }
    private var sellableItems: [InventoryItem] { inventoryAll.filter { $0.quantity > 0 } }
    private var stockItems: [NPCStockItem] { stockAll.filter { $0.npcID == npc.id && $0.quantity > 0 } }
    private var activeStock: NPCStockItem? { stockAll.first { $0.persistentModelID == activeStockID && $0.quantity > 0 } }
    private var shipments: [ShippingOrder] { shippingAll.filter { $0.npcID == npc.id && !$0.isComplete } }
    private var purchasesToReview: [ShippingOrder] { shippingAll.filter { $0.npcID == npc.id && !$0.isSale && $0.isComplete && $0.reviewed != true } }
    private var rating: Double { reviews.isEmpty ? Double(npc.baseRatingSeed) : Double(reviews.map(\.rating).reduce(0, +)) / Double(reviews.count) }
    private var reputation: String { String(format: "★ %.1f reputation", rating) }
    private var incomingOffer: MessageRecord? {
        guard npc.kind == .buyer,
              let message = messages.last(where: { !$0.isFromPlayer && $0.listingProductID != nil }),
              let productID = message.listingProductID,
              let createdAt = message.listingCreatedAt,
              listingAll.contains(where: { $0.productID == productID && $0.createdAt == createdAt && $0.quantity > 0 }) else { return nil }
        let replies = messages.filter { $0.isFromPlayer && $0.npcID == message.npcID && $0.listingCreatedAt == createdAt && $0.date > message.date }
        if replies.contains(where: { $0.text.hasPrefix("Thanks, but I’ll pass") }) { return nil }
        return message
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contactHeader
                Divider()
                if !shipments.isEmpty { shippingBanner }
                if !purchasesToReview.isEmpty { sellerReviewPrompt }
                conversation
                quickReplyPanel
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                _ = engine.deliverQueuedMessages()
                lastSeenMessageCount = messages.count
                if npc.kind == .seller { _ = engine.stock(for: npc.id) }
                restoreDeal()
            }
            .onChange(of: messages.count) { _, count in
                if count > lastSeenMessageCount, messages.last?.isFromPlayer == false {
                    if action == .waitingForReply { action = pendingAction ?? .home; pendingAction = nil }
                    restoreDeal()
                }
                lastSeenMessageCount = count
            }
            .onChange(of: shipments.count) { _, count in if count == 0, action == .shipping { action = .home } }
            .onChange(of: activeStock?.quantity ?? 0) { _, available in
                purchaseQuantity = min(purchaseQuantity, max(available, 1))
            }
        }
    }

    private var contactHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.headline).foregroundStyle(.primary) }
            Image(systemName: npc.avatarSymbol).font(.title2).foregroundStyle(.white)
                .frame(width: 42, height: 42).background(Color.green.gradient).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(npc.name).font(.headline)
                Text("\(reputation) · \(reviews.count) reviews").font(.caption).foregroundStyle(rating <= 3 ? .orange : .secondary)
            }
            Spacer()
            Button(isFollowing ? "Following" : "Follow") { toggleFollow() }
                .font(.caption.bold()).buttonStyle(.bordered).tint(.green)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).background(Color(.systemBackground))
    }

    private var shippingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(shipments) { order in
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox.fill").foregroundStyle(.orange)
                    Text("\(order.isSale ? "Your sale" : "Your purchase") · arrives \(Formatters.compactDate(order.arrivesAt))")
                        .font(.caption.bold())
                    Spacer()
                    if devMode && player?.isDevModeUnlocked == true {
                        Button("Skip") { engine.skipShipping(order) }.font(.caption.bold())
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    private var sellerReviewPrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(purchasesToReview) { order in
                VStack(alignment: .leading, spacing: 5) {
                    Text("Rate your \(GameData.product(order.productID)?.name ?? "order") from \(npc.name)")
                        .font(.caption.bold())
                    HStack(spacing: 7) {
                        ForEach(1...5, id: \.self) { stars in
                            Button { engine.reviewPurchase(order, stars: stars) } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                    Text("\(stars)").font(.caption2.bold())
                                }
                                .foregroundStyle(stars < 3 ? Color.red : (stars == 3 ? Color.orange : Color.yellow))
                                .frame(width: 38, height: 30).background(Color.orange.opacity(0.09)).clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rate seller \(stars) stars")
                        }
                        Text(order.packageLost == true ? "Package lost" : "Delivered")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.yellow.opacity(0.10))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty {
                        Text("You’re chatting with \(npc.name). Choose an action below to get started.")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 16)
                    }
                    ForEach(messages.indices, id: \.self) { index in
                        messageBubble(messages[index])
                            .id(index)
                            .transition(.asymmetric(
                                insertion: .move(edge: messages[index].isFromPlayer ? .trailing : .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 16)
                .animation(.snappy(duration: 0.24), value: messages.count)
            }
            .onChange(of: messages.count) { _, _ in
                if !messages.isEmpty { proxy.scrollTo(messages.count - 1, anchor: .bottom) }
            }
            .onAppear { if !messages.isEmpty { proxy.scrollTo(messages.count - 1, anchor: .bottom) } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageBubble(_ message: MessageRecord) -> some View {
        HStack {
            if message.isFromPlayer { Spacer(minLength: 54) }
            VStack(alignment: message.isFromPlayer ? .trailing : .leading, spacing: 3) {
                Text(message.text).font(.body).foregroundStyle(message.isFromPlayer ? .white : .primary)
                Text(Formatters.compactDate(message.date)).font(.system(size: 10)).foregroundStyle(message.isFromPlayer ? .white.opacity(0.7) : .secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(message.isFromPlayer ? Color(red: 0.05, green: 0.48, blue: 0.36) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !message.isFromPlayer { Spacer(minLength: 54) }
        }
    }

    private var quickReplyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(actionTitle).font(.caption.bold()).foregroundStyle(.secondary)
            if action == .waitingForReply {
                HStack(spacing: 8) { ProgressView(); Text("Waiting for \(npc.name)…").font(.subheadline).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
            } else if (action == .negotiatingPurchase || action == .readyToPurchase), let item = activeStock {
                if !engine.canStore(purchaseQuantity) {
                    Label("Storage full. Sell items or upgrade storage in Profile → My Shop.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Stepper(value: $purchaseQuantity, in: 1...max(item.quantity, 1)) {
                    HStack {
                        Text("Order quantity").font(.subheadline.weight(.medium))
                        Spacer()
                        let unitPrice = action == .readyToPurchase ? agreedPrice : item.unitPrice
                        Text("Total \(Formatters.moneyPrecise(unitPrice * Double(purchaseQuantity)))")
                            .font(.caption.bold().monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .tint(.green)
            } else if incomingOffer == nil,
                      (action == .negotiatingSale || action == .readyToShip),
                      let productID = activeProductID,
                      let item = inventoryAll.first(where: { $0.productID == productID && $0.quantity > 0 }) {
                Stepper(value: $saleQuantity, in: 1...max(item.quantity, 1)) {
                    HStack {
                        Text("Sell quantity").font(.subheadline.weight(.medium))
                        Spacer()
                        let unitPrice = action == .readyToShip ? agreedPrice : targetPrice
                        Text("Total \(Formatters.moneyPrecise(unitPrice * Double(saleQuantity)))")
                            .font(.caption.bold().monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .tint(.green)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { actionButtons }
            }
        }
        .padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
        .animation(.snappy(duration: 0.24), value: action)
        .animation(.snappy(duration: 0.18), value: purchaseQuantity)
        .animation(.snappy(duration: 0.18), value: saleQuantity)
    }

    @ViewBuilder private var actionButtons: some View {
        if action == .waitingForReply {
            EmptyView()
        } else if action == .shipping || !shipments.isEmpty {
            Text("Your package is on the way. Check back when it arrives.").font(.caption).foregroundStyle(.secondary)
        } else if let offer = incomingOffer {
            if action == .readyToShip {
                quickButton("Ship · \(Formatters.moneyPrecise(agreedPrice)) / item", icon: "shippingbox.fill") { shipToBuyer(listingOffer: offer, negotiatedPrice: agreedPrice) }
                quickButton("Cancel", icon: "xmark") { action = .home }
            } else if action == .negotiatingSale {
                quickButton("Accept & ship · \(Formatters.moneyPrecise(offer.listingPrice ?? 0))", icon: "checkmark.circle") { acceptListingOffer(offer) }
                quickButton("Ask listing price", icon: "dollarsign.circle", enabled: negotiationCount < 4) { counterListingOffer(offer, multiplier: 1) }
                quickButton("Ask 5% more", icon: "arrow.up", enabled: negotiationCount < 4) { counterListingOffer(offer, multiplier: 1.05) }
                quickButton("Ask 10% more", icon: "arrow.up", enabled: negotiationCount < 4) { counterListingOffer(offer, multiplier: 1.1) }
                quickButton("Ask 20% more", icon: "arrow.up.right", enabled: negotiationCount < 4) { counterListingOffer(offer, multiplier: 1.2) }
                quickButton("Decline", icon: "xmark.circle") { declineListingOffer(offer) }
            } else {
                quickButton("Accept & ship · \(Formatters.moneyPrecise(offer.listingPrice ?? 0))", icon: "checkmark.circle") { acceptListingOffer(offer) }
                quickButton("Negotiate", icon: "dollarsign.circle") { action = .negotiatingSale; negotiationCount = 0 }
                quickButton("Decline", icon: "xmark.circle") { declineListingOffer(offer) }
            }
        } else {
            switch action {
            case .home:
                if npc.kind == .seller {
                    quickButton("What do you have?", icon: "shippingbox") { browseStock() }
                } else {
                    quickButton("Ask if they want an item", icon: "tag") { action = .choosingItem }
                }
            case .browsingStock:
                if stockItems.isEmpty { Text("They’re out of stock for now.").font(.caption).foregroundStyle(.secondary) }
                ForEach(stockItems) { item in
                    if let product = GameData.product(item.productID) {
                        quickButton("\(product.name) · \(Formatters.moneyPrecise(item.unitPrice)) · \(item.quantity) left", icon: product.icon) { askAbout(item) }
                    }
                }
                quickButton("Back", icon: "chevron.left") { action = .home }
            case .negotiatingPurchase:
                if let item = activeStock {
                    quickButton("Buy \(purchaseQuantity) · \(Formatters.moneyPrecise(item.unitPrice * Double(purchaseQuantity)))", icon: "bag", enabled: (player?.cashUSD ?? 0) >= item.unitPrice * Double(purchaseQuantity) && engine.canStore(purchaseQuantity)) { buyFromSeller(at: item.unitPrice) }
                    quickButton("Offer 20% less / item", icon: "arrow.down", enabled: negotiationCount < 4) { makeSellerOffer(item.unitPrice * 0.8) }
                    quickButton("Offer 10% less / item", icon: "arrow.down.right", enabled: negotiationCount < 4) { makeSellerOffer(item.unitPrice * 0.9) }
                    quickButton("Offer 5% less / item", icon: "arrow.right", enabled: negotiationCount < 4) { makeSellerOffer(item.unitPrice * 0.95) }
                    quickButton("Offer 2% less / item", icon: "arrow.up.right", enabled: negotiationCount < 4) { makeSellerOffer(item.unitPrice * 0.98) }
                }
            case .readyToPurchase:
                quickButton("Buy \(purchaseQuantity) · \(Formatters.moneyPrecise(agreedPrice * Double(purchaseQuantity)))", icon: "bag.fill", enabled: (player?.cashUSD ?? 0) >= agreedPrice * Double(purchaseQuantity) && engine.canStore(purchaseQuantity)) { buyFromSeller(at: agreedPrice) }
                quickButton("Back to stock", icon: "chevron.left") { action = .browsingStock }
            case .choosingItem:
                if sellableItems.isEmpty { Text("You need inventory before offering an item.").font(.caption).foregroundStyle(.secondary) }
                ForEach(sellableItems, id: \.productID) { item in
                    if let product = GameData.product(item.productID) {
                        quickButton("Offer \(product.name) · \(item.quantity)", icon: product.icon) { offerItemToBuyer(product) }
                    }
                }
                quickButton("Cancel", icon: "xmark") { action = .home }
            case .negotiatingSale:
                if let product = activeProductID.flatMap(GameData.product) {
                    quickButton("Sell at \(Formatters.moneyPrecise(targetPrice)) / item", icon: "equal.circle", enabled: negotiationCount < 4) { makeBuyerOffer(targetPrice) }
                    quickButton("Ask 10% more / item", icon: "arrow.up", enabled: negotiationCount < 4) { makeBuyerOffer(targetPrice * 1.1) }
                    quickButton("Ask 20% more / item", icon: "arrow.up.right", enabled: negotiationCount < 4) { makeBuyerOffer(targetPrice * 1.2) }
                    quickButton("Offer 10% less / item", icon: "arrow.down", enabled: negotiationCount < 4) { makeBuyerOffer(targetPrice * 0.9) }
                    Text(product.name).hidden()
                }
            case .readyToShip:
                quickButton("Ship for \(Formatters.moneyPrecise(agreedPrice * Double(saleQuantity)))", icon: "shippingbox.fill") { shipToBuyer() }
                quickButton("Cancel", icon: "xmark") { action = .home }
            case .shipping: EmptyView()
            case .waitingForReply: EmptyView()
            }
        }
    }

    private var actionTitle: String {
        if action == .waitingForReply { return "MESSAGE SENT" }
        if !shipments.isEmpty { return "IN TRANSIT · 5–10 MINUTES" }
        if action == .readyToShip || action == .readyToPurchase { return "PRICE ACCEPTED" }
        if incomingOffer != nil { return "CUSTOMER OFFER" }
        switch action {
        case .home: return npc.kind == .seller ? "QUICK REPLIES" : "CUSTOMER CHAT"
        case .browsingStock: return "AVAILABLE STOCK"
        case .negotiatingPurchase, .negotiatingSale: return "PRICE TALK · \(negotiationCount)/4"
        case .readyToPurchase: return "PRICE ACCEPTED"
        case .choosingItem: return "CHOOSE FROM YOUR INVENTORY"
        case .readyToShip: return "OFFER ACCEPTED"
        case .shipping: return "IN TRANSIT"
        case .waitingForReply: return "MESSAGE SENT"
        }
    }

    private func quickButton(_ title: String, icon: String, enabled: Bool = true, action handler: @escaping () -> Void) -> some View {
        Button(action: handler) {
            Label(title, systemImage: icon).font(.caption.bold()).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.green.opacity(0.12)).foregroundStyle(.green).clipShape(Capsule())
        }
        .buttonStyle(PressFeedbackStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.45)
    }

    private func browseStock() {
        _ = engine.stock(for: npc.id)
        action = .browsingStock
        send("What do you have in stock?", reply: stockItems.isEmpty ? "I’m out of stock right now." : "Here’s what I have available. Items ship after payment clears.")
    }

    private func askAbout(_ item: NPCStockItem) {
        guard item.quantity > 0 else { send("Do you still have that in stock?", reply: "Sorry, I just sold the last one."); return }
        activeStockID = item.persistentModelID
        purchaseQuantity = 1
        activeProductID = item.productID
        targetPrice = item.unitPrice
        agreedPrice = item.unitPrice
        negotiationCount = messages.filter { $0.isFromPlayer && $0.offeredProductID == item.productID }.count
        action = negotiationCount >= 4 ? .readyToPurchase : .negotiatingPurchase
        let name = GameData.product(item.productID)?.name ?? "item"
        let reply = negotiationCount >= 4
            ? "Yes, it’s still available. We’ve already used the four offer limit, so my listed price of \(Formatters.moneyPrecise(item.unitPrice)) is firm."
            : "Yes, I have \(item.quantity) in stock. My price is \(Formatters.moneyPrecise(item.unitPrice)). You can buy now or make an offer."
        send("Do you still have \(name)? I’m interested in one.", reply: reply)
    }

    private func makeSellerOffer(_ offer: Double) {
        guard let item = activeStock, negotiationCount < 4 else { return }
        negotiationCount += 1
        let floor = sellerPriceFloor(rating: rating)
        let accepted = offer >= item.unitPrice * floor
        if accepted {
            agreedPrice = offer
            action = .readyToPurchase
            send("Would you take \(Formatters.moneyPrecise(offer))?", reply: "Yes, I’ll accept \(Formatters.moneyPrecise(offer)). Want me to ship it?", offeredProductID: item.productID, offeredPrice: offer)
        } else {
            let left = 4 - negotiationCount
            let reply = left == 0 ? "That’s too low. My listed price is firm; that was the last offer." : "I can’t go that low. My best is \(Formatters.moneyPrecise(item.unitPrice)). You have \(left) offer\(left == 1 ? "" : "s") left."
            if left == 0 { action = .readyToPurchase; agreedPrice = item.unitPrice }
            send("Would you take \(Formatters.moneyPrecise(offer))?", reply: reply, offeredProductID: item.productID)
        }
    }

    private func sellerPriceFloor(rating: Double) -> Double {
        switch rating {
        case ..<1.5: return 0.55
        case ..<2.5: return 0.65
        case ..<3.5: return 0.80
        case ..<4.5: return 0.92
        default: return 0.98
        }
    }

    private func buyFromSeller(at price: Double) {
        guard let item = activeStock else { action = .home; send("Is that item still available?", reply: "Sorry, it just sold out."); return }
        if engine.purchaseFromNPC(npcID: npc.id, stockItem: item, quantity: purchaseQuantity, unitPrice: price) {
            action = .shipping
            send("I’ll take \(purchaseQuantity) at \(Formatters.moneyPrecise(price)) each. Please ship the order.", reply: "Confirmed. Your order is on its way; delivery takes 5–10 minutes.")
        } else {
            send("I can’t complete the purchase yet.", reply: "Check your balance or stock and try again.")
        }
    }

    private func offerItemToBuyer(_ product: ProductDef) {
        guard let item = sellableItems.first(where: { $0.productID == product.id }), item.quantity > 0 else { return }
        activeProductID = product.id
        saleQuantity = 1
        targetPrice = engine.price(for: product.id)
        agreedPrice = targetPrice
        negotiationCount = 0
        let wantsItem = engine.buyerWantsProduct(npcID: npc.id, productID: product.id)
        let advertisedName = product.isCounterfeit ? (product.publicAlias ?? "collector item") : product.name
        if wantsItem {
            action = .negotiatingSale
            send("I have \(saleQuantity) \(advertisedName) available. Interested?", reply: "Yes, I’m interested in \(saleQuantity). I usually pay around \(Formatters.moneyPrecise(targetPrice)) each. What’s your price?", offeredProductID: product.id)
        } else {
            action = .choosingItem
            send("I have \(saleQuantity) \(advertisedName) available. Interested?", reply: "That’s not really what I collect. Do you have something else?", offeredProductID: product.id)
        }
    }

    private func makeBuyerOffer(_ offer: Double) {
        guard negotiationCount < 4, activeProductID != nil else { return }
        negotiationCount += 1
        let ceiling = targetPrice * (1 + max(0, 5 - rating) * 0.08)
        let accepted = offer <= ceiling
        if accepted {
            agreedPrice = offer
            action = .readyToShip
            send("Would you pay \(Formatters.moneyPrecise(offer))?", reply: "That works for me. Please send it and I’ll pay when it arrives.", offeredProductID: activeProductID, offeredPrice: offer)
        } else {
            let left = 4 - negotiationCount
            let reply = left == 0 ? "That’s above my limit. I can pay up to \(Formatters.moneyPrecise(ceiling)); final offer." : "That’s high for me. I can do \(Formatters.moneyPrecise(ceiling)). You have \(left) offer\(left == 1 ? "" : "s") left."
            if left == 0 { agreedPrice = ceiling; action = .readyToShip }
            send("Would you pay \(Formatters.moneyPrecise(offer))?", reply: reply)
        }
    }

    private func shipToBuyer(listingOffer: MessageRecord? = nil, negotiatedPrice: Double? = nil) {
        let productID = listingOffer?.listingProductID ?? activeProductID
        let quantity = listingOffer?.listingQuantity ?? saleQuantity
        guard let productID else { return }
        let price = negotiatedPrice ?? listingOffer?.listingPrice ?? agreedPrice
        let listingDate = listingOffer?.listingCreatedAt
        guard engine.shipSale(npcID: npc.id, productID: productID, quantity: quantity, unitPrice: price, listingCreatedAt: listingDate) else {
            action = .home
            send("I can’t ship that item now.", reply: "No problem. Check that it’s still available.")
            return
        }
        let product = GameData.product(productID)
        let name = product?.isCounterfeit == true ? (product?.publicAlias ?? "collector item") : (product?.name ?? "item")
        action = .shipping
        send("Deal. I’m shipping \(quantity) \(name) for \(Formatters.moneyPrecise(price)) each.", reply: "Agreed. Your order is confirmed; shipping takes 5–10 minutes.")
    }

    private func acceptListingOffer(_ offer: MessageRecord) {
        shipToBuyer(listingOffer: offer)
    }

    private func counterListingOffer(_ offer: MessageRecord, multiplier: Double) {
        guard negotiationCount < 4,
              let ask = listingAll.first(where: { $0.productID == offer.listingProductID && $0.createdAt == offer.listingCreatedAt })?.price else { return }
        negotiationCount += 1
        let counter = ask * multiplier
        let ceiling = (offer.listingPrice ?? 0) * (1 + max(0, 5 - rating) * 0.08)
        if counter <= ceiling {
            agreedPrice = counter
            action = .readyToShip
            send("I can do \(Formatters.moneyPrecise(counter)) each.", reply: "That works for me. Please ship it and I’ll pay on arrival.", listingCreatedAt: offer.listingCreatedAt, offeredPrice: counter)
            return
        }
        let remaining = 4 - negotiationCount
        let response = remaining == 0
            ? "I can’t go that high. My final offer is \(Formatters.moneyPrecise(ceiling))."
            : "That’s too high for me. My best is \(Formatters.moneyPrecise(ceiling)); you have \(remaining) offer\(remaining == 1 ? "" : "s") left."
        if remaining == 0 { action = .home }
        send("I can do \(Formatters.moneyPrecise(counter)) each.", reply: response, listingCreatedAt: offer.listingCreatedAt)
    }

    private func declineListingOffer(_ offer: MessageRecord) {
        action = .home
        send("Thanks, but I’ll pass on this offer.", reply: "No worries. Message me if you change your mind.", listingCreatedAt: offer.listingCreatedAt)
        if let listing = listingAll.first(where: { $0.productID == offer.listingProductID && $0.createdAt == offer.listingCreatedAt }) {
            engine.queueNextBuyerOffer(for: listing, excluding: npc.id)
        }
    }

    private func restoreDeal() {
        guard shipments.isEmpty else { action = .shipping; return }
        if let offer = incomingOffer {
            negotiationCount = messages.filter { $0.isFromPlayer && $0.npcID == offer.npcID && $0.listingCreatedAt == offer.listingCreatedAt && $0.date > offer.date }.count
            if let counter = messages.last(where: { $0.isFromPlayer && $0.npcID == offer.npcID && $0.listingCreatedAt == offer.listingCreatedAt && $0.date > offer.date && $0.offeredPrice != nil }),
               let reply = messages.last(where: { !$0.isFromPlayer && $0.date > counter.date }), reply.text.hasPrefix("That works for me") {
                agreedPrice = counter.offeredPrice ?? 0
                action = .readyToShip
            } else if negotiationCount > 0 { action = .negotiatingSale }
            return
        }
        if let offer = messages.last(where: { $0.isFromPlayer && $0.text.hasPrefix("Would you take ") }),
           let acceptedReply = messages.last(where: { !$0.isFromPlayer && $0.text.hasPrefix("Yes, I’ll accept") }), acceptedReply.date > offer.date {
            action = .readyToPurchase
            agreedPrice = offer.offeredPrice ?? activeStock?.unitPrice ?? 0
            if let item = stockAll.first(where: { $0.npcID == npc.id && $0.productID == offer.offeredProductID }) {
                activeStockID = item.persistentModelID
                activeProductID = item.productID
            }
        }
        if npc.kind == .buyer,
           let productOffer = messages.last(where: { $0.isFromPlayer && $0.text.hasPrefix("I have ") && $0.offeredProductID != nil }) {
            activeProductID = productOffer.offeredProductID
            targetPrice = activeProductID.map { engine.price(for: $0) } ?? 0
            negotiationCount = messages.filter { $0.isFromPlayer && $0.text.hasPrefix("Would you pay ") }.count
            action = .negotiatingSale
        }
        if npc.kind == .buyer,
           let offer = messages.last(where: { $0.isFromPlayer && $0.offeredPrice != nil && $0.offeredProductID != nil }),
           let accepted = messages.last(where: { !$0.isFromPlayer && $0.text.hasPrefix("That works for me") }), accepted.date > offer.date {
            agreedPrice = offer.offeredPrice ?? 0
            activeProductID = offer.offeredProductID
            action = .readyToShip
        }
    }

    private func toggleFollow() {
        let profile = engine.fetchPlayer()
        var didFollow = false
        if let rel = followedAll.first(where: { $0.npcID == npc.id }) {
            rel.isFollowing.toggle(); profile.following += rel.isFollowing ? 1 : -1
            didFollow = rel.isFollowing
        } else {
            context.insert(FollowedNPC(npcID: npc.id)); profile.following += 1
            didFollow = true
        }
        if didFollow { engine.incrementObjectiveProgress(matching: { $0.objectiveID == "obj_network" }) }
        engine.checkAchievements()
        try? context.save()
    }

    private func send(_ text: String, reply: String, listingCreatedAt: Date? = nil, offeredProductID: String? = nil, offeredPrice: Double? = nil) {
        context.insert(MessageRecord(npcID: npc.id, text: text, isFromPlayer: true, offeredProductID: offeredProductID, offeredPrice: offeredPrice, listingCreatedAt: listingCreatedAt))
        pendingAction = action
        action = .waitingForReply
        MessageSounds.playSent()
        let delay = TimeInterval.random(in: 1.4...3.2)
        _ = engine.queueNPCMessage(npcID: npc.id, text: reply, at: .now.addingTimeInterval(delay), listingCreatedAt: listingCreatedAt, notifyWhenClosed: false)
        try? context.save()
    }
}
