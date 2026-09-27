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
                        .buttonStyle(.plain)
                    }
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

    private var contactIDs: [String] {
        Array(Set(followed.filter(\.isFollowing).map(\.npcID) + allMessages.map(\.npcID))).sorted()
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
                                        Text(allMessages.first(where: { $0.npcID == id })?.text ?? npc.bio)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
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

private enum ChatAction: Equatable { case home, browsingStock, negotiatingPurchase, readyToPurchase, choosingItem, negotiatingSale, readyToShip, shipping }

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

    private var player: PlayerState? { players.first }
    private var isFollowing: Bool { followedAll.first { $0.npcID == npc.id }?.isFollowing ?? false }
    private var reviews: [ReviewRecord] { reviewsAll.filter { $0.npcID == npc.id } }
    private var messages: [MessageRecord] { messagesAll.filter { $0.npcID == npc.id }.sorted { $0.date < $1.date } }
    private var sellableItems: [InventoryItem] { inventoryAll.filter { $0.quantity > 0 } }
    private var stockItems: [NPCStockItem] { stockAll.filter { $0.npcID == npc.id && $0.quantity > 0 } }
    private var activeStock: NPCStockItem? { stockAll.first { $0.persistentModelID == activeStockID && $0.quantity > 0 } }
    private var shipments: [ShippingOrder] { shippingAll.filter { $0.npcID == npc.id && !$0.isComplete } }
    private var rating: Double { reviews.isEmpty ? Double(npc.baseRatingSeed) : Double(reviews.map(\.rating).reduce(0, +)) / Double(reviews.count) }
    private var reputation: String { String(format: "★ %.1f reputation", rating) }
    private var incomingOffer: MessageRecord? {
        guard npc.kind == .buyer,
              let message = messages.last(where: { !$0.isFromPlayer && $0.listingProductID != nil }),
              let productID = message.listingProductID,
              let createdAt = message.listingCreatedAt,
              listingAll.contains(where: { $0.productID == productID && $0.createdAt == createdAt && $0.quantity > 0 }) else { return nil }
        let replies = messages.filter { $0.isFromPlayer && $0.listingCreatedAt == createdAt }
        if replies.count >= 4 || replies.contains(where: { $0.text.hasPrefix("Thanks, but I’ll pass") }) { return nil }
        return message
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contactHeader
                Divider()
                if !shipments.isEmpty { shippingBanner }
                conversation
                quickReplyPanel
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if npc.kind == .seller { _ = engine.stock(for: npc.id) }
                restoreDeal()
            }
            .onChange(of: shipments.count) { _, count in if count == 0, action == .shipping { action = .home } }
        }
    }

    private var contactHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.headline).foregroundStyle(.primary) }
            Image(systemName: npc.avatarSymbol).font(.title2).foregroundStyle(.white)
                .frame(width: 42, height: 42).background(Color.green.gradient).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(npc.name).font(.headline)
                Text(reputation).font(.caption).foregroundStyle(rating <= 3 ? .orange : .secondary)
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

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty {
                        Text("You’re chatting with \(npc.name). Choose an action below to get started.")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 16)
                    }
                    ForEach(messages.indices, id: \.self) { index in
                        messageBubble(messages[index]).id(index)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 16)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { actionButtons }
            }
        }
        .padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
    }

    @ViewBuilder private var actionButtons: some View {
        if action == .shipping || !shipments.isEmpty {
            Text("Your package is on the way. Check back when it arrives.").font(.caption).foregroundStyle(.secondary)
        } else if let offer = incomingOffer {
            if action == .negotiatingSale {
                quickButton("Accept · \(Formatters.moneyPrecise(offer.listingPrice ?? 0))", icon: "checkmark.circle") { acceptListingOffer(offer) }
                quickButton("Ask listing price", icon: "dollarsign.circle", enabled: negotiationCount < 4) { counterListingOffer(offer, multiplier: 1) }
                quickButton("Ask 5% more", icon: "arrow.up", enabled: negotiationCount < 4) { counterListingOffer(offer, multiplier: 1.05) }
                quickButton("Ask 10% more", icon: "arrow.up", enabled: negotiationCount < 4) { counterListingOffer(offer, multiplier: 1.1) }
                quickButton("Ask 20% more", icon: "arrow.up.right", enabled: negotiationCount < 4) { counterListingOffer(offer, multiplier: 1.2) }
                quickButton("Decline", icon: "xmark.circle") { declineListingOffer(offer) }
            } else {
                quickButton("Accept · \(Formatters.moneyPrecise(offer.listingPrice ?? 0))", icon: "checkmark.circle") { acceptListingOffer(offer) }
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
                    quickButton("Buy at \(Formatters.moneyPrecise(item.unitPrice))", icon: "bag") { buyFromSeller(at: item.unitPrice) }
                    quickButton("Offer 20% less", icon: "arrow.down", enabled: negotiationCount < 4) { makeSellerOffer(item.unitPrice * 0.8) }
                    quickButton("Offer 10% less", icon: "arrow.down.right", enabled: negotiationCount < 4) { makeSellerOffer(item.unitPrice * 0.9) }
                    quickButton("Offer 5% less", icon: "arrow.right", enabled: negotiationCount < 4) { makeSellerOffer(item.unitPrice * 0.95) }
                    quickButton("Offer 2% less", icon: "arrow.up.right", enabled: negotiationCount < 4) { makeSellerOffer(item.unitPrice * 0.98) }
                }
            case .readyToPurchase:
                quickButton("Buy for \(Formatters.moneyPrecise(agreedPrice))", icon: "bag.fill") { buyFromSeller(at: agreedPrice) }
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
                    quickButton("Sell at \(Formatters.moneyPrecise(targetPrice))", icon: "equal.circle", enabled: negotiationCount < 4) { makeBuyerOffer(targetPrice) }
                    quickButton("Ask 10% more", icon: "arrow.up", enabled: negotiationCount < 4) { makeBuyerOffer(targetPrice * 1.1) }
                    quickButton("Ask 20% more", icon: "arrow.up.right", enabled: negotiationCount < 4) { makeBuyerOffer(targetPrice * 1.2) }
                    quickButton("Offer 10% less", icon: "arrow.down", enabled: negotiationCount < 4) { makeBuyerOffer(targetPrice * 0.9) }
                    Text(product.name).hidden()
                }
            case .readyToShip:
                quickButton("Ship for \(Formatters.moneyPrecise(agreedPrice))", icon: "shippingbox.fill") { shipToBuyer() }
                quickButton("Cancel", icon: "xmark") { action = .home }
            case .shipping: EmptyView()
            }
        }
    }

    private var actionTitle: String {
        if !shipments.isEmpty { return "IN TRANSIT · 5–10 MINUTES" }
        if incomingOffer != nil { return "CUSTOMER OFFER" }
        switch action {
        case .home: return npc.kind == .seller ? "QUICK REPLIES" : "CUSTOMER CHAT"
        case .browsingStock: return "AVAILABLE STOCK"
        case .negotiatingPurchase, .negotiatingSale: return "PRICE TALK · \(negotiationCount)/4"
        case .readyToPurchase: return "PRICE ACCEPTED"
        case .choosingItem: return "CHOOSE FROM YOUR INVENTORY"
        case .readyToShip: return "OFFER ACCEPTED"
        case .shipping: return "IN TRANSIT"
        }
    }

    private func quickButton(_ title: String, icon: String, enabled: Bool = true, action handler: @escaping () -> Void) -> some View {
        Button(action: handler) {
            Label(title, systemImage: icon).font(.caption.bold()).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.green.opacity(0.12)).foregroundStyle(.green).clipShape(Capsule())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.45)
    }

    private func browseStock() {
        _ = engine.stock(for: npc.id)
        action = .browsingStock
        send("What do you have in stock?", reply: stockItems.isEmpty ? "I’m out of stock right now." : "Here’s what I have available. Items ship after payment clears.")
    }

    private func askAbout(_ item: NPCStockItem) {
        guard item.quantity > 0 else { send("Do you still have that in stock?", reply: "Sorry, I just sold the last one."); return }
        activeStockID = item.persistentModelID
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
            send("Would you take \(Formatters.moneyPrecise(offer))?", reply: "Yes, I’ll accept \(Formatters.moneyPrecise(offer)). Want me to ship it?", offeredProductID: item.productID)
        } else {
            let left = 4 - negotiationCount
            let reply = left == 0 ? "That’s too low. My listed price is firm; that was the last offer." : "I can’t go that low. My best is \(Formatters.moneyPrecise(item.unitPrice)). You have \(left) offer\(left == 1 ? "" : "s") left."
            send("Would you take \(Formatters.moneyPrecise(offer))?", reply: reply, offeredProductID: item.productID)
            if left == 0 { action = .readyToPurchase; agreedPrice = item.unitPrice }
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
        guard let item = activeStock else { send("Is that item still available?", reply: "Sorry, it just sold out."); action = .home; return }
        if engine.purchaseFromNPC(npcID: npc.id, stockItem: item, unitPrice: price) {
            send("I’ll take one at \(Formatters.moneyPrecise(price)). Please ship it.", reply: "Confirmed. Your order is on its way; delivery takes 5–10 minutes.")
            action = .shipping
        } else {
            send("I can’t complete the purchase yet.", reply: "Check your balance or stock and try again.")
        }
    }

    private func offerItemToBuyer(_ product: ProductDef) {
        guard let item = sellableItems.first(where: { $0.productID == product.id }), item.quantity > 0 else { return }
        activeProductID = product.id
        targetPrice = engine.price(for: product.id)
        agreedPrice = targetPrice
        negotiationCount = 0
        let wantsItem: Bool
        switch npc.id {
        case "n_dre", "n_mina": wantsItem = product.category == .collectibles || product.category == .electronics
        case "n_aria": wantsItem = product.category == .luxury || product.category == .collectibles
        case "n_sasha": wantsItem = product.basePrice >= 300
        default: wantsItem = true
        }
        if wantsItem {
            action = .negotiatingSale
            send("I have a \(product.name) available. Interested?", reply: "Yes, I’m interested in one. I usually pay around \(Formatters.moneyPrecise(targetPrice)). What’s your price?")
        } else {
            action = .choosingItem
            send("I have a \(product.name) available. Interested?", reply: "That’s not really what I collect. Do you have something else?")
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
            send("Would you pay \(Formatters.moneyPrecise(offer))?", reply: "That works for me. Please send it and I’ll pay when it arrives.")
        } else {
            let left = 4 - negotiationCount
            let reply = left == 0 ? "That’s above my limit. I can pay up to \(Formatters.moneyPrecise(ceiling)); final offer." : "That’s high for me. I can do \(Formatters.moneyPrecise(ceiling)). You have \(left) offer\(left == 1 ? "" : "s") left."
            send("Would you pay \(Formatters.moneyPrecise(offer))?", reply: reply)
            if left == 0 { agreedPrice = ceiling; action = .readyToShip }
        }
    }

    private func shipToBuyer(listingOffer: MessageRecord? = nil, negotiatedPrice: Double? = nil) {
        let productID = listingOffer?.listingProductID ?? activeProductID
        let quantity = listingOffer?.listingQuantity ?? 1
        guard let productID else { return }
        let price = negotiatedPrice ?? listingOffer?.listingPrice ?? agreedPrice
        let listingDate = listingOffer?.listingCreatedAt
        guard engine.shipSale(npcID: npc.id, productID: productID, quantity: quantity, unitPrice: price, listingCreatedAt: listingDate) else {
            send("I can’t ship that item now.", reply: "No problem. Check that it’s still available.")
            action = .home
            return
        }
        let name = GameData.product(productID)?.name ?? "item"
        send("Deal. I’m shipping \(quantity) \(name) for \(Formatters.moneyPrecise(price)) each.", reply: "Agreed. I’ll pay as soon as it arrives. Shipping takes 5–10 minutes.")
        action = .shipping
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
            send("I can do \(Formatters.moneyPrecise(counter)) each.", reply: "That works for me. Please ship it and I’ll pay on arrival.", listingCreatedAt: offer.listingCreatedAt)
            shipToBuyer(listingOffer: offer, negotiatedPrice: counter)
            return
        }
        let remaining = 4 - negotiationCount
        let response = remaining == 0
            ? "I can’t go that high. My final offer is \(Formatters.moneyPrecise(ceiling))."
            : "That’s too high for me. My best is \(Formatters.moneyPrecise(ceiling)); you have \(remaining) offer\(remaining == 1 ? "" : "s") left."
        send("I can do \(Formatters.moneyPrecise(counter)) each.", reply: response, listingCreatedAt: offer.listingCreatedAt)
        if remaining == 0 {
            action = .home
            try? context.save()
        }
    }

    private func declineListingOffer(_ offer: MessageRecord) {
        context.insert(MessageRecord(npcID: npc.id, text: "Thanks, but I’ll pass on this offer.", isFromPlayer: true, listingCreatedAt: offer.listingCreatedAt))
        context.insert(MessageRecord(npcID: npc.id, text: "No worries. Message me if you change your mind.", isFromPlayer: false))
        try? context.save()
    }

    private func restoreDeal() {
        guard shipments.isEmpty else { action = .shipping; return }
        if let offer = incomingOffer {
            negotiationCount = messages.filter { $0.isFromPlayer && $0.listingCreatedAt == offer.listingCreatedAt }.count
            if negotiationCount > 0 { action = .negotiatingSale }
            return
        }
        if let offer = messages.last(where: { $0.isFromPlayer && $0.text.hasPrefix("Would you take ") }),
           let acceptedReply = messages.last(where: { !$0.isFromPlayer && $0.text.hasPrefix("Yes, I’ll accept") }), acceptedReply.date > offer.date {
            action = .readyToPurchase
        }
    }

    private func toggleFollow() {
        let profile = engine.fetchPlayer()
        if let rel = followedAll.first(where: { $0.npcID == npc.id }) {
            rel.isFollowing.toggle(); profile.following += rel.isFollowing ? 1 : -1
        } else {
            context.insert(FollowedNPC(npcID: npc.id)); profile.following += 1
        }
        try? context.save()
    }

    private func send(_ text: String, reply: String, listingCreatedAt: Date? = nil, offeredProductID: String? = nil) {
        context.insert(MessageRecord(npcID: npc.id, text: text, isFromPlayer: true, offeredProductID: offeredProductID, listingCreatedAt: listingCreatedAt))
        context.insert(MessageRecord(npcID: npc.id, text: reply, isFromPlayer: false, date: .now.addingTimeInterval(1)))
        try? context.save()
    }
}
