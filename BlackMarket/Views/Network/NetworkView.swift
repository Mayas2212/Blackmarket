import SwiftUI
import SwiftData

struct NetworkView: View {
    var engine: GameEngine
    @Query private var followed: [FollowedNPC]
    @State private var selectedNPC: NPCDef?

    var body: some View {
        NavigationStack {
            List {
                Section("Your Network") {
                    ForEach(GameData.npcs) { npc in
                        Button { selectedNPC = npc } label: {
                            NPCRow(npc: npc, isFollowing: followed.first { $0.npcID == npc.id }?.isFollowing ?? false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Network")
            .sheet(item: $selectedNPC) { npc in
                NPCProfileView(engine: engine, npc: npc)
            }
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
            if isFollowing {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }
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

struct NPCProfileView: View {
    var engine: GameEngine
    let npc: NPCDef
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var followedAll: [FollowedNPC]
    @Query private var reviewsAll: [ReviewRecord]
    @Query private var messagesAll: [MessageRecord]
    @Query private var inventoryAll: [InventoryItem]
    @State private var messageText = ""
    @State private var sellQuantity = 1
    @State private var selectedProductID: String?

    private var isFollowing: Bool { followedAll.first { $0.npcID == npc.id }?.isFollowing ?? false }
    private var reviews: [ReviewRecord] { reviewsAll.filter { $0.npcID == npc.id } }
    private var messages: [MessageRecord] { messagesAll.filter { $0.npcID == npc.id }.sorted { $0.date < $1.date } }
    private var sellableItems: [InventoryItem] { inventoryAll.filter { $0.quantity > 0 } }
    private var currentProductID: String { selectedProductID ?? sellableItems.first?.productID ?? "" }
    private var maxQty: Int { sellableItems.first { $0.productID == currentProductID }?.quantity ?? 1 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: npc.avatarSymbol).font(.system(size: 40))
                            .frame(width: 70, height: 70).background(Color(.secondarySystemBackground)).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(npc.name).font(.title3.bold())
                            Text(npc.bio).font(.caption).foregroundStyle(.secondary)
                            Button(isFollowing ? "Following" : "Follow") { toggleFollow() }
                                .font(.caption.bold())
                                .buttonStyle(.borderedProminent)
                                .tint(isFollowing ? .gray : .green)
                        }
                    }
                }

                if npc.kind == .buyer {
                    Section("Sell Directly") { directSellForm }
                }

                Section("Reviews") {
                    if reviews.isEmpty {
                        Text("No reviews yet.").foregroundStyle(.secondary)
                    }
                    ForEach(reviews) { review in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 2) {
                                ForEach(0..<5, id: \.self) { i in
                                    Image(systemName: i < review.rating ? "star.fill" : "star")
                                        .foregroundStyle(.yellow).font(.caption)
                                }
                            }
                            Text(review.text).font(.caption)
                        }
                    }
                }

                Section("Messages") {
                    ForEach(messages) { msg in
                        HStack {
                            if msg.isFromPlayer { Spacer() }
                            Text(msg.text)
                                .padding(8)
                                .background(msg.isFromPlayer ? Color.green.opacity(0.2) : Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            if !msg.isFromPlayer { Spacer() }
                        }
                    }
                    HStack {
                        TextField("Message...", text: $messageText)
                        Button("Send") { sendMessage() }.disabled(messageText.isEmpty)
                    }
                }
            }
            .navigationTitle(npc.name)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    @ViewBuilder
    private var directSellForm: some View {
        if sellableItems.isEmpty {
            Text("No inventory to sell.").font(.caption).foregroundStyle(.secondary)
        } else {
            Picker("Product", selection: Binding(get: { currentProductID }, set: { selectedProductID = $0; sellQuantity = 1 })) {
                ForEach(sellableItems, id: \.productID) { item in
                    if let p = GameData.product(item.productID) {
                        Text("\(p.name) (\(item.quantity))").tag(item.productID)
                    }
                }
            }
            Stepper("Qty: \(sellQuantity)", value: $sellQuantity, in: 1...max(maxQty, 1))
            Button("Sell to \(npc.name)") {
                let pid = currentProductID
                let price = engine.price(for: pid) * Double.random(in: 0.95...1.1)
                if engine.sell(productID: pid, quantity: sellQuantity, unitPrice: price, toNPC: npc.id) {
                    engine.incrementObjectiveProgress(matching: { $0.objectiveID == "obj_sell3" })
                    addReviewChance()
                }
            }
            .buttonStyle(.borderedProminent).tint(.green)
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

    private func sendMessage() {
        context.insert(MessageRecord(npcID: npc.id, text: messageText, isFromPlayer: true))
        let reply = ["Deal.", "Let's talk price.", "I'll check back later.", "Sounds good.", "Not interested right now."].randomElement()!
        context.insert(MessageRecord(npcID: npc.id, text: reply, isFromPlayer: false, date: .now.addingTimeInterval(2)))
        messageText = ""
        try? context.save()
    }

    private func addReviewChance() {
        guard Double.random(in: 0...1) < 0.6 else { return }
        let texts = ["Smooth transaction.", "Would deal again.", "Fast and reliable.", "Good quality, fair price."]
        context.insert(ReviewRecord(npcID: npc.id, rating: Int.random(in: 4...5), text: texts.randomElement()!))
        try? context.save()
    }
}
