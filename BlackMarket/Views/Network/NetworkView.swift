import SwiftUI
import SwiftData

struct NetworkView: View {
    var engine: GameEngine
    @Query private var followed: [FollowedNPC]
    @State private var selectedNPC: NPCDef?

    private var contacts: [NPCDef] {
        var byID = Dictionary(uniqueKeysWithValues: GameData.npcs.map { ($0.id, $0) })
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

private enum ChatAction {
    case home
    case choosingTrade
    case acceptedTrade
    case discussingPrice
}

struct NPCChatView: View {
    var engine: GameEngine
    let npc: NPCDef
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var followedAll: [FollowedNPC]
    @Query private var reviewsAll: [ReviewRecord]
    @Query private var messagesAll: [MessageRecord]
    @Query private var inventoryAll: [InventoryItem]
    @State private var action: ChatAction = .home
    @State private var didRestoreAction = false
    @State private var offeredProductID: String?
    @State private var agreedPriceMultiplier = 1.0

    private var isFollowing: Bool { followedAll.first { $0.npcID == npc.id }?.isFollowing ?? false }
    private var reviews: [ReviewRecord] { reviewsAll.filter { $0.npcID == npc.id } }
    private var messages: [MessageRecord] { messagesAll.filter { $0.npcID == npc.id }.sorted { $0.date < $1.date } }
    private var sellableItems: [InventoryItem] { inventoryAll.filter { $0.quantity > 0 } }
    private var reputation: String {
        let score = reviews.isEmpty ? Double(npc.baseRatingSeed) : Double(reviews.map(\.rating).reduce(0, +)) / Double(reviews.count)
        return String(format: "★ %.1f reputation", score)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contactHeader
                Divider()
                conversation
                quickReplyPanel
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: restoreAction)
        }
    }

    private var contactHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.headline).foregroundStyle(.primary)
            }
            Image(systemName: npc.avatarSymbol)
                .font(.title2).foregroundStyle(.white)
                .frame(width: 42, height: 42).background(Color.green.gradient).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(npc.name).font(.headline)
                Text(reputation).font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Button(isFollowing ? "Following" : "Follow") { toggleFollow() }
                .font(.caption.bold()).buttonStyle(.bordered).tint(.green)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty {
                        Text("This is the start of your chat with \(npc.name).")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 16)
                    }
                    ForEach(messages.indices, id: \.self) { index in
                        messageBubble(messages[index]).id(index)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                if !messages.isEmpty { proxy.scrollTo(messages.count - 1, anchor: .bottom) }
            }
            .onAppear {
                if !messages.isEmpty { proxy.scrollTo(messages.count - 1, anchor: .bottom) }
            }
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
        VStack(alignment: .leading, spacing: 9) {
            Text(actionTitle).font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    switch action {
                    case .home:
                        quickButton("I can offer a trade", icon: "arrow.left.arrow.right") { action = .choosingTrade }
                        quickButton("Let’s make a deal", icon: "dollarsign.circle") { beginPriceDiscussion() }
                    case .choosingTrade:
                        if sellableItems.isEmpty {
                            Text("Buy something first to make a trade offer.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(sellableItems, id: \.productID) { item in
                            if let product = GameData.product(item.productID) {
                                quickButton("\(product.name) · \(item.quantity)", icon: product.icon) { offerTrade(product: product) }
                            }
                        }
                        quickButton("Cancel", icon: "xmark") { offeredProductID = nil; action = .home }
                    case .acceptedTrade:
                        quickButton("Discuss price", icon: "dollarsign.circle") { beginPriceDiscussion() }
                        quickButton("Confirm trade", icon: "checkmark.circle") { completeTrade() }
                    case .discussingPrice:
                        quickButton("Offer market price", icon: "equal.circle") { sendPriceOffer(multiplier: 1.0, label: "market price") }
                        quickButton("Offer 10% less", icon: "arrow.down.circle") { sendPriceOffer(multiplier: 0.9, label: "10% below market") }
                        quickButton("Offer 10% more", icon: "arrow.up.circle") { sendPriceOffer(multiplier: 1.1, label: "10% above market") }
                        quickButton("Done", icon: "checkmark") { action = .home }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
    }

    private var actionTitle: String {
        switch action {
        case .home: return "QUICK REPLIES"
        case .choosingTrade: return "CHOOSE AN ITEM TO OFFER"
        case .acceptedTrade: return "TRADE ACCEPTED · NEXT STEP"
        case .discussingPrice: return "PRICE OPTIONS"
        }
    }

    private func quickButton(_ title: String, icon: String, action handler: @escaping () -> Void) -> some View {
        Button(action: handler) {
            Label(title, systemImage: icon).font(.caption.bold()).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.green.opacity(0.12)).foregroundStyle(.green)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func restoreAction() {
        guard !didRestoreAction else { return }
        didRestoreAction = true
        guard let offer = messages.last(where: { $0.isFromPlayer && $0.offeredProductID != nil }),
              let productID = offer.offeredProductID else { return }
        offeredProductID = productID
        let laterMessages = messages.filter { $0.date > offer.date }
        if laterMessages.contains(where: { $0.isFromPlayer && $0.text.hasPrefix("Trade completed:") }) {
            offeredProductID = nil
            return
        }
        if let reply = laterMessages.last(where: { !$0.isFromPlayer }) {
            if reply.text.hasPrefix("Trade accepted") || reply.text.contains("offer is fair") {
                action = .acceptedTrade
            } else if reply.text.hasPrefix("I’ll pass") {
                offeredProductID = nil
                action = .choosingTrade
            }
        }
    }

    private func toggleFollow() {
        let player = engine.fetchPlayer()
        if let rel = followedAll.first(where: { $0.npcID == npc.id }) {
            rel.isFollowing.toggle()
            player.following += rel.isFollowing ? 1 : -1
        } else {
            context.insert(FollowedNPC(npcID: npc.id))
            player.following += 1
        }
        try? context.save()
    }

    private func offerTrade(product: ProductDef) {
        offeredProductID = product.id
        agreedPriceMultiplier = 1
        let message = "Trade offer: I can offer \(product.name). Would you take it?"
        context.insert(MessageRecord(npcID: npc.id, text: message, isFromPlayer: true, offeredProductID: product.id))
        let suitable = npc.kind == .seller || product.category == .collectibles || product.category == .electronics || product.category == .luxury
        let relationship = followedAll.first { $0.npcID == npc.id }?.relationship ?? 0
        let accepted = suitable && (npc.kind == .seller || relationship >= 2 || product.basePrice <= 500)
        let reply = accepted
            ? "Trade accepted — \(product.name) works for me. Want to discuss the price?"
            : "I’ll pass on \(product.name) for now. Do you have something else?"
        context.insert(MessageRecord(npcID: npc.id, text: reply, isFromPlayer: false))
        if !accepted { offeredProductID = nil }
        action = accepted ? .acceptedTrade : .choosingTrade
        try? context.save()
    }

    private func beginPriceDiscussion() {
        send("Let’s make a deal. Can we discuss the price?", reply: "Sure. Choose an offer around today’s market price.")
        action = .discussingPrice
    }

    private func sendPriceOffer(multiplier: Double, label: String) {
        let accepted = multiplier >= 0.95
        let reply = accepted ? "That \(label) offer is fair. We have a deal." : "That’s a little low. I can meet you at market price."
        send("I’d like to offer \(label).", reply: reply)
        if accepted {
            agreedPriceMultiplier = multiplier
            action = offeredProductID == nil ? .home : .acceptedTrade
        } else {
            action = .discussingPrice
        }
    }

    private func completeTrade() {
        guard let offeredProductID,
              let item = sellableItems.first(where: { $0.productID == offeredProductID }),
              item.quantity > 0 else {
            send("I can’t complete that trade now.", reply: "No problem. Let me know when you have it ready.")
            action = .home
            return
        }
        let price = engine.price(for: offeredProductID) * agreedPriceMultiplier
        if engine.sell(productID: offeredProductID, quantity: 1, unitPrice: price, toNPC: npc.id) {
            engine.incrementObjectiveProgress(matching: { $0.objectiveID == "obj_sell3" })
            send("Trade completed: one \(GameData.product(offeredProductID)?.name ?? "item") at \(Formatters.moneyPrecise(price)).", reply: "Trade complete. Thanks — let’s work together again.")
        }
        action = .home
        self.offeredProductID = nil
    }

    private func send(_ text: String, reply: String) {
        context.insert(MessageRecord(npcID: npc.id, text: text, isFromPlayer: true))
        context.insert(MessageRecord(npcID: npc.id, text: reply, isFromPlayer: false, date: .now.addingTimeInterval(1)))
        try? context.save()
    }
}
