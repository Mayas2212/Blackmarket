import Foundation
import SwiftData

/// Central gameplay engine. Owns all business logic that mutates persisted state.
/// Views read data via @Query and call into this engine to perform actions.
@Observable
final class GameEngine {
    var context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Bootstrap

    func bootstrapIfNeeded() {
        let players = (try? context.fetch(FetchDescriptor<PlayerState>())) ?? []
        if players.isEmpty {
            context.insert(PlayerState())
        }
        seedPricesIfNeeded()
        seedAchievementsIfNeeded()
        refreshDailyObjectivesIfNeeded()
        try? context.save()
    }

    private func seedPricesIfNeeded() {
        let existing = (try? context.fetch(FetchDescriptor<PriceOverride>())) ?? []
        let existingIDs = Set(existing.map { $0.productID })
        for product in GameData.products where !existingIDs.contains(product.id) {
            context.insert(PriceOverride(productID: product.id, currentPrice: product.basePrice))
        }
        for coin in GameData.cryptocurrencies where !existingIDs.contains(coin.id) {
            context.insert(PriceOverride(productID: coin.id, currentPrice: coin.initialPrice))
        }
        let snapshots = (try? context.fetch(FetchDescriptor<PriceSnapshot>())) ?? []
        let snapshotIDs = Set(snapshots.map(\.assetID))
        for product in GameData.products where !snapshotIDs.contains(product.id) {
            context.insert(PriceSnapshot(assetID: product.id, price: product.basePrice))
        }
        for coin in GameData.cryptocurrencies where !snapshotIDs.contains(coin.id) {
            context.insert(PriceSnapshot(assetID: coin.id, price: coin.initialPrice))
        }
        try? context.save()
    }

    private func seedAchievementsIfNeeded() {
        let existing = (try? context.fetch(FetchDescriptor<AchievementRecord>())) ?? []
        let existingIDs = Set(existing.map { $0.achievementID })
        for a in GameData.achievements where !existingIDs.contains(a.id) {
            context.insert(AchievementRecord(achievementID: a.id))
        }
    }

    // MARK: - Fetch helpers

    func fetchPlayer() -> PlayerState {
        let players = (try? context.fetch(FetchDescriptor<PlayerState>())) ?? []
        if let existing = players.first { return existing }
        let p = PlayerState()
        context.insert(p)
        return p
    }

    func price(for productID: String) -> Double {
        let overrides = (try? context.fetch(FetchDescriptor<PriceOverride>())) ?? []
        return overrides.first { $0.productID == productID }?.currentPrice ?? GameData.product(productID)?.basePrice ?? 0
    }

    func btcRate() -> Double { price(for: "BTC_RATE") }

    func cryptoAmount(_ assetID: String) -> Double {
        if assetID == "BTC_RATE" { return fetchPlayer().btc }
        let holdings = (try? context.fetch(FetchDescriptor<CryptoHolding>())) ?? []
        return holdings.first { $0.assetID == assetID }?.amount ?? 0
    }

    @discardableResult
    func buyCrypto(assetID: String, usdAmount: Double) -> Bool {
        guard assetID != "BTC_RATE", GameData.cryptocurrencies.contains(where: { $0.id == assetID }), usdAmount > 0 else { return false }
        let player = fetchPlayer()
        guard player.cashUSD >= usdAmount else { return false }
        player.cashUSD -= usdAmount
        let holdings = (try? context.fetch(FetchDescriptor<CryptoHolding>())) ?? []
        let amount = usdAmount / max(price(for: assetID), 0.000001)
        if let holding = holdings.first(where: { $0.assetID == assetID }) { holding.amount += amount }
        else { context.insert(CryptoHolding(assetID: assetID, amount: amount)) }
        context.insert(TransactionRecord(type: .btcTrade, total: -usdAmount, note: "Bought \(GameData.cryptocurrencies.first { $0.id == assetID }?.name ?? "coin")"))
        incrementObjectiveProgress(matching: { $0.objectiveID == "obj_crypto" })
        checkAchievements()
        try? context.save()
        return true
    }

    @discardableResult
    func sellCrypto(assetID: String, amount: Double) -> Bool {
        guard assetID != "BTC_RATE", amount > 0 else { return false }
        let holdings = (try? context.fetch(FetchDescriptor<CryptoHolding>())) ?? []
        guard let holding = holdings.first(where: { $0.assetID == assetID }), holding.amount >= amount else { return false }
        holding.amount -= amount
        let proceeds = amount * price(for: assetID)
        fetchPlayer().cashUSD += proceeds
        if holding.amount < 0.00000001 { context.delete(holding) }
        context.insert(TransactionRecord(type: .btcTrade, total: proceeds, note: "Sold \(GameData.cryptocurrencies.first { $0.id == assetID }?.name ?? "coin")"))
        incrementObjectiveProgress(matching: { $0.objectiveID == "obj_crypto" })
        try? context.save()
        return true
    }

    func inventory() -> [InventoryItem] {
        (try? context.fetch(FetchDescriptor<InventoryItem>())) ?? []
    }

    func listings() -> [ListingItem] {
        (try? context.fetch(FetchDescriptor<ListingItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    func transactions() -> [TransactionRecord] {
        (try? context.fetch(FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    func availableContacts(for player: PlayerState) -> [NPCDef] {
        let unlocked = GameData.npcs.filter { player.reputation >= contactUnlockRep($0.id) }
        let followedIDs = ((try? context.fetch(FetchDescriptor<FollowedNPC>())) ?? []).map(\.npcID)
        let generated = followedIDs.compactMap { GameData.npc($0) }.filter { $0.id.hasPrefix("n_generated_") }
        return Array(Dictionary((unlocked + generated).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values).sorted { $0.name < $1.name }
    }

    func buyerWantsProduct(npcID: String, productID: String) -> Bool {
        guard let product = GameData.product(productID) else { return false }
        switch npcID {
        case "n_dre", "n_mina": return product.category == .collectibles || product.category == .electronics
        case "n_aria", "n_ellis": return product.category == .luxury || product.category == .collectibles || product.category == .fashion
        case "n_noor", "n_tess": return product.category == .books || product.category == .collectibles
        case "n_finn": return product.category == .audio || product.category == .electronics
        case "n_gabriel", "n_hugo": return product.category == .tech || product.category == .electronics || product.category == .audio
        case "n_sasha": return product.basePrice >= 300
        case "n_marlow": return product.category == .luxury || product.category == .fashion
        case "n_kez": return product.category == .collectibles || product.category == .fashion
        case "n_amelia": return !product.isCounterfeit && (product.category == .luxury || product.category == .electronics || product.category == .collectibles)
        default: return true
        }
    }

    private func contactUnlockRep(_ id: String) -> Int {
        switch id {
        case "n_mina": 100
        case "n_aria", "n_jules": 250
        case "n_sasha", "n_niko": 450
        case "n_omar", "n_ivy": 100
        case "n_the_broker": 700
        case "n_theo": 50
        case "n_priya", "n_noor": 100
        case "n_finn": 150
        case "n_ellis": 250
        case "n_mateo", "n_cassia": 350
        case "n_gabriel", "n_yuna": 450
        case "n_reece", "n_soraya", "n_beck", "n_roman", "n_marlow", "n_tess": 100
        case "n_amelia": 250
        case "n_kez", "n_hugo": 450
        case "n_dorian": 700
        default: 0
        }
    }

    func stock(for npcID: String) -> [NPCStockItem] {
        if let npc = GameData.npc(npcID), npc.kind == .seller {
            seedStock(for: npc)
        }
        let updated = (try? context.fetch(FetchDescriptor<NPCStockItem>())) ?? []
        return updated.filter { $0.npcID == npcID && $0.quantity > 0 }
    }

    private func seedStock(for npc: NPCDef) {
        let existing = (try? context.fetch(FetchDescriptor<NPCStockItem>())) ?? []
        let player = fetchPlayer()
        let existingForNPC = existing.filter { $0.npcID == npc.id }
        let existingProductIDs = Set(existingForNPC.map(\.productID))
        var choices = GameData.products.filter { $0.unlockLevel.rawValue <= player.levelRaw }
        if npc.id == "n_lena" { choices = choices.filter { $0.category == .herbal || $0.category == .collectibles || $0.category == .books } }
        if ["n_omar", "n_jules", "n_priya"].contains(npc.id) { choices = choices.filter { $0.category == .electronics || $0.category == .tech || $0.category == .collectibles || $0.category == .audio } }
        if ["n_niko", "n_theo"].contains(npc.id) { choices = choices.filter { $0.category == .collectibles || $0.category == .luxury || $0.category == .books } }
        if npc.id == "n_mateo" { choices = choices.filter { $0.category == .fashion || $0.category == .luxury } }
        if npc.id == "n_yuna" { choices = choices.filter { $0.category == .electronics || $0.category == .tech || $0.category == .audio } }
        if npc.id == "n_reece" { choices = choices.filter(\.isCounterfeit) }
        if npc.id == "n_soraya" { choices = choices.filter { $0.category == .fashion || $0.category == .luxury } }
        if npc.id == "n_beck" { choices = choices.filter { $0.category == .collectibles || $0.category == .books } }
        if npc.id == "n_roman" { choices = choices.filter { $0.category == .electronics || $0.category == .audio } }
        let slots = max(0, 5 - existingForNPC.count)
        let selected = Array(choices.filter { !existingProductIDs.contains($0.id) }.shuffled().prefix(slots))
        guard !selected.isEmpty else { return }
        for product in selected {
            let markup = product.isCounterfeit ? Double.random(in: 0.75...1.05) : (product.fixedPrice ? 1 : Double.random(in: 1.0...1.2))
            context.insert(NPCStockItem(npcID: npc.id, productID: product.id, quantity: Int.random(in: 3...12), unitPrice: price(for: product.id) * markup))
        }
        try? context.save()
    }

    @discardableResult
    func purchaseFromNPC(npcID: String, stockItem: NPCStockItem, quantity: Int = 1, unitPrice: Double? = nil) -> Bool {
        let player = fetchPlayer()
        let finalPrice = unitPrice ?? stockItem.unitPrice
        let total = finalPrice * Double(quantity)
        guard quantity > 0, stockItem.quantity >= quantity, player.cashUSD >= total else { return false }
        stockItem.quantity -= quantity
        player.cashUSD -= total
        let arrival = Date.now.addingTimeInterval(TimeInterval.random(in: 300...600))
        context.insert(ShippingOrder(npcID: npcID, productID: stockItem.productID, quantity: quantity, unitPrice: finalPrice, isSale: false, arrivesAt: arrival))
        context.insert(TransactionRecord(type: .buy, productID: stockItem.productID, quantity: quantity, unitPrice: finalPrice, total: -total, note: "Bought from contact; shipping"))
        incrementObjectiveProgress(matching: { $0.objectiveID == "obj_contactbuy" })
        try? context.save()
        return true
    }

    @discardableResult
    func shipSale(npcID: String, productID: String, quantity: Int, unitPrice: Double, listingCreatedAt: Date? = nil) -> Bool {
        guard quantity > 0 else { return false }
        let due = Date.now.addingTimeInterval(TimeInterval.random(in: 300...600))
        let sourceListing = listingCreatedAt.flatMap { date in listings().first(where: { $0.productID == productID && $0.createdAt == date }) }
        let isMisrepresented = GameData.product(productID)?.isCounterfeit == true && (listingCreatedAt == nil || sourceListing?.claimedAsAuthentic == true)
        if let listingCreatedAt {
            guard let listing = listings().first(where: { $0.productID == productID && $0.quantity >= quantity && $0.createdAt == listingCreatedAt }) else { return false }
            cancelQueuedListingOffers(listing)
            let remaining = listing.quantity - quantity
            if remaining == 0 {
                context.delete(listing)
            } else {
                listing.quantity = remaining
                queueNextBuyerOffer(for: listing, excluding: npcID)
            }
        } else {
            guard let item = inventory().first(where: { $0.productID == productID && $0.quantity >= quantity }) else { return false }
            item.quantity -= quantity
            if item.quantity == 0 { context.delete(item) }
        }
        context.insert(ShippingOrder(npcID: npcID, productID: productID, quantity: quantity, unitPrice: unitPrice, isSale: true, arrivesAt: due, listingCreatedAt: listingCreatedAt, isMisrepresented: isMisrepresented))
        context.insert(TransactionRecord(type: .event, productID: productID, quantity: quantity, total: 0, note: "Packed order for \(GameData.npc(npcID)?.name ?? "customer")"))
        incrementObjectiveProgress(matching: { $0.objectiveID == "obj_ship" })
        try? context.save()
        return true
    }

    func shippingOrders() -> [ShippingOrder] {
        (try? context.fetch(FetchDescriptor<ShippingOrder>()))?.filter { !$0.isComplete } ?? []
    }

    @discardableResult
    func queueNPCMessage(npcID: String, text: String, at date: Date, listingProductID: String? = nil, listingQuantity: Int? = nil, listingPrice: Double? = nil, listingCreatedAt: Date? = nil, notifyWhenClosed: Bool = true) -> MessageRecord {
        let message = MessageRecord(
            npcID: npcID,
            text: text,
            isFromPlayer: false,
            date: date,
            listingProductID: listingProductID,
            listingQuantity: listingQuantity,
            listingPrice: listingPrice,
            listingCreatedAt: listingCreatedAt,
            isDelivered: date <= .now
        )
        context.insert(message)
        if notifyWhenClosed {
            MessageNotifications.schedule(
                npcName: GameData.npc(npcID)?.name ?? "New message",
                text: text,
                at: date,
                identifier: String(describing: message.persistentModelID)
            )
        }
        try? context.save()
        if date > .now {
            let delay = date.timeIntervalSinceNow
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay + 0.05))
                _ = self?.deliverQueuedMessages()
            }
        }
        return message
    }

    @discardableResult
    func deliverQueuedMessages() -> Int {
        let messages = (try? context.fetch(FetchDescriptor<MessageRecord>())) ?? []
        let due = messages.filter { !$0.isDelivered && $0.date <= .now }
        for message in due { message.deliveryState = true }
        if !due.isEmpty { try? context.save() }
        return due.count
    }

    func schedulePendingMessageNotifications() {
        let messages = (try? context.fetch(FetchDescriptor<MessageRecord>())) ?? []
        for message in messages where !message.isFromPlayer && !message.isDelivered && message.date > .now {
            MessageNotifications.schedule(
                npcName: GameData.npc(message.npcID)?.name ?? "New message",
                text: message.text,
                at: message.date,
                identifier: String(describing: message.persistentModelID)
            )
        }
    }

    func skipShipping(_ order: ShippingOrder) {
        guard fetchPlayer().isDevModeUnlocked, UserDefaults.standard.bool(forKey: "blackmarket.devSettingsOn") else { return }
        order.arrivesAt = .now
        processShipping()
    }

    private func processShipping() {
        let orders = shippingOrders().filter { $0.arrivesAt <= .now }
        for order in orders {
            let lost = Double.random(in: 0..<1) < 0.05
            let product = GameData.product(order.productID)
            let buyerRating = GameData.npc(order.npcID)?.baseRatingSeed ?? 3
            let detectionChance = min(0.75, max(0.12, 0.22 + Double(product?.riskTier ?? 1) * 0.075 + Double(buyerRating - 3) * 0.05 - Double(fetchPlayer().trustScore - 50) * 0.0018))
            let counterfeitDetected = order.isSale && !lost && order.isMisrepresented == true && Double.random(in: 0..<1) < detectionChance
            order.packageLost = lost
            order.counterfeitDetected = counterfeitDetected
            order.isComplete = true
            let total = order.unitPrice * Double(order.quantity)
            let player = fetchPlayer()
            if order.isSale {
                if counterfeitDetected {
                    recordPlayerReview(npcID: order.npcID, rating: 1, text: "Item didn't match its listing. Payment was reversed.")
                    player.reputation = max(0, player.reputation - max(8, (product?.riskTier ?? 2) * 8))
                    returnInventory(productID: order.productID, quantity: order.quantity, unitCost: order.unitPrice * 0.55)
                    context.insert(TransactionRecord(type: .listingSale, productID: order.productID, quantity: order.quantity, unitPrice: order.unitPrice, total: 0, note: "Counterfeit claim upheld; payment reversed"))
                } else {
                    // The customer pays the agreed amount even if the carrier loses the parcel.
                    player.cashUSD += total
                    let stars = lost ? 4 : customerReviewStars(for: player.trustScore)
                    player.reputation += lost ? 0 : max(1, order.quantity + stars - 3)
                    recordPlayerReview(npcID: order.npcID, rating: stars, text: lost ? "Seller shipped promptly; carrier lost the package." : "Item arrived as described. Good communication.")
                    context.insert(TransactionRecord(type: .listingSale, productID: order.productID, quantity: order.quantity, unitPrice: order.unitPrice, total: total, note: lost ? "Carrier lost package; customer paid in full" : "Delivered to customer"))
                    if order.isMisrepresented == true && !lost {
                        context.insert(TransactionRecord(type: .event, productID: order.productID, quantity: order.quantity, unitPrice: order.unitPrice, total: 0, note: "Claim cleared after delivery"))
                    }
                    if !lost && stars >= 4 { referCustomer(from: order.npcID) }
                }
            } else if lost {
                // Seller reimburses a lost inbound package.
                player.cashUSD += total
                context.insert(TransactionRecord(type: .event, productID: order.productID, total: total, note: "Seller reimbursed lost package"))
            } else {
                let inventory = self.inventory()
                if let item = inventory.first(where: { $0.productID == order.productID }) {
                    let newQuantity = item.quantity + order.quantity
                    item.avgCost = (item.avgCost * Double(item.quantity) + total) / Double(newQuantity)
                    item.quantity = newQuantity
                } else {
                    context.insert(InventoryItem(productID: order.productID, quantity: order.quantity, avgCost: order.unitPrice))
                }
                order.reviewed = false
            }
            let productName = order.isMisrepresented == true && !counterfeitDetected
                ? (product?.publicAlias ?? "collector item")
                : (product?.name ?? "your item")
            let status: String
            if counterfeitDetected {
                status = "The buyer flagged \(productName) as misrepresented. Payment was reversed, it was returned, and your trust score dropped."
            } else if lost {
                status = order.isSale ? "The carrier lost \(productName), but your customer paid in full." : "The carrier lost \(productName). The seller reimbursed you."
            } else {
                status = order.isSale ? "\(productName) was delivered. Payment is in your balance." : "\(productName) arrived. It’s in your inventory."
            }
            context.insert(MessageRecord(npcID: order.npcID, text: status, isFromPlayer: false))
        }
        checkAchievements()
        try? context.save()
    }

    private func customerReviewStars(for trust: Int) -> Int {
        if trust >= 80 { return Int.random(in: 4...5) }
        if trust < 30 { return Int.random(in: 2...4) }
        return Int.random(in: 3...5)
    }

    private func recordPlayerReview(npcID: String, rating: Int, text: String) {
        context.insert(ReviewRecord(npcID: npcID, rating: rating, text: text, isAboutPlayer: true))
        let player = fetchPlayer()
        let target = rating * 20
        player.trustScore = Int((Double(player.trustScore) * 0.72 + Double(target) * 0.28).rounded())
        if player.trustScore >= 80 && !player.badges.contains("Trusted Seller") { player.badges.append("Trusted Seller") }
        if player.trustScore < 30 && !player.badges.contains("Needs to Rebuild Trust") { player.badges.append("Needs to Rebuild Trust") }
        applyLevelUpIfNeeded(player: player)
    }

    private func returnInventory(productID: String, quantity: Int, unitCost: Double) {
        if let item = inventory().first(where: { $0.productID == productID }) {
            let newQuantity = item.quantity + quantity
            item.avgCost = (item.avgCost * Double(item.quantity) + unitCost * Double(quantity)) / Double(newQuantity)
            item.quantity = newQuantity
        } else {
            context.insert(InventoryItem(productID: productID, quantity: quantity, avgCost: unitCost))
        }
    }

    private func referCustomer(from npcID: String) {
        guard Double.random(in: 0..<1) < 0.18 + Double(fetchPlayer().trustScore) * 0.003 else { return }
        let contacts = ((try? context.fetch(FetchDescriptor<FollowedNPC>())) ?? [])
        let maxIndex = contacts.compactMap { Int($0.npcID.replacingOccurrences(of: "n_generated_", with: "")) }.max() ?? 0
        var nextIndex = maxIndex + 1
        if nextIndex.isMultiple(of: 2) == false { nextIndex += 1 }
        let newID = "n_generated_\(nextIndex)"
        guard !contacts.contains(where: { $0.npcID == newID }) else { return }
        context.insert(FollowedNPC(npcID: newID, isFollowing: true, relationship: 1))
        let player = fetchPlayer()
        player.followers += 1
        player.following += 1
        player.referralCount += 1
        incrementObjectiveProgress(matching: { $0.objectiveID == "obj_referral" })
        _ = queueNPCMessage(npcID: newID, text: "Hi, I was referred by \(GameData.npc(npcID)?.name ?? "a customer"). Your reviews look good. Do you have anything interesting listed?", at: .now.addingTimeInterval(TimeInterval.random(in: 2...5)))
    }

    func reviewPurchase(_ order: ShippingOrder, stars: Int) {
        guard !order.isSale, order.isComplete, order.reviewed != true, (1...5).contains(stars) else { return }
        let lost = order.packageLost ?? false
        let text = lost ? "Seller reimbursed me after the carrier lost the package." : (stars >= 4 ? "Item matched the description and arrived safely." : "The item or delivery did not meet expectations.")
        context.insert(ReviewRecord(npcID: order.npcID, rating: stars, text: text))
        order.reviewed = true
        incrementObjectiveProgress(matching: { $0.objectiveID == "obj_review" })
        try? context.save()
    }

    func recordDailyVisit() {
        let player = fetchPlayer()
        let today = Calendar.current.startOfDay(for: .now)
        guard let last = player.lastCheckIn else {
            player.lastCheckIn = today
            player.loginStreak = 1
            incrementObjectiveProgress(matching: { $0.objectiveID == "obj_checkin" })
            checkAchievements()
            try? context.save()
            return
        }
        guard !Calendar.current.isDate(last, inSameDayAs: today) else { return }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? .distantPast
        player.loginStreak = Calendar.current.isDate(last, inSameDayAs: yesterday) ? player.loginStreak + 1 : 1
        player.lastCheckIn = today
        refreshDailyObjectivesIfNeeded()
        incrementObjectiveProgress(matching: { $0.objectiveID == "obj_checkin" })
        checkAchievements()
        try? context.save()
    }

    func fetchFollowed(npcID: String) -> FollowedNPC? {
        let all = (try? context.fetch(FetchDescriptor<FollowedNPC>())) ?? []
        return all.first { $0.npcID == npcID }
    }

    // MARK: - Buying / Selling (core loop)

    @discardableResult
    func buy(productID: String, quantity: Int, supplier: SupplierDef?) -> Bool {
        guard quantity > 0 else { return false }
        let player = fetchPlayer()
        let basePrice = price(for: productID)
        let discount = supplier?.discount ?? 0
        let unitPrice = basePrice * (1 - discount)
        let total = unitPrice * Double(quantity)
        guard player.cashUSD >= total else { return false }

        player.cashUSD -= total

        let allInv = inventory()
        if let existing = allInv.first(where: { $0.productID == productID }) {
            let newQty = existing.quantity + quantity
            existing.avgCost = ((existing.avgCost * Double(existing.quantity)) + total) / Double(newQty)
            existing.quantity = newQty
        } else {
            context.insert(InventoryItem(productID: productID, quantity: quantity, avgCost: unitPrice))
        }

        context.insert(TransactionRecord(type: .buy, productID: productID, quantity: quantity, unitPrice: unitPrice, total: -total, note: "Bought from \(supplier?.name ?? "market")"))
        checkAchievements()
        try? context.save()
        return true
    }

    @discardableResult
    func sell(productID: String, quantity: Int, unitPrice: Double, toNPC npcID: String? = nil) -> Bool {
        guard quantity > 0 else { return false }
        let player = fetchPlayer()
        let allInv = inventory()
        guard let existing = allInv.first(where: { $0.productID == productID }), existing.quantity >= quantity else { return false }

        let total = unitPrice * Double(quantity)
        let cost = existing.avgCost * Double(quantity)
        let profit = total - cost

        existing.quantity -= quantity
        if existing.quantity == 0 { context.delete(existing) }

        player.cashUSD += total

        let product = GameData.product(productID)
        let riskTier = product?.riskTier ?? 1
        let marginRatio = cost > 0 ? max(0, profit / cost) : 0
        let repGain = max(1, Int((marginRatio * 8) + Double(riskTier)))
        player.reputation += repGain
        player.xp += repGain
        applyLevelUpIfNeeded(player: player)

        if let npcID {
            if let rel = fetchFollowed(npcID: npcID) {
                rel.relationship += 1
            } else {
                context.insert(FollowedNPC(npcID: npcID, isFollowing: true, relationship: 1))
                player.following += 1
                player.followers += 1
            }
        }

        let noteName = npcID.flatMap { GameData.npc($0)?.name }
        let saleCount = transactions().filter { $0.type == .sell || $0.type == .listingSale }.count + 1
        context.insert(TransactionRecord(type: .sell, productID: productID, quantity: quantity, unitPrice: unitPrice, total: total, note: noteName.map { "Sold to \($0)" } ?? "Sold on market"))
        incrementObjectiveProgress(matching: { $0.objectiveID == "obj_sell3" })
        if saleCount.isMultiple(of: 3) {
            let contactID = "n_generated_\(saleCount / 3)"
            if fetchFollowed(npcID: contactID) == nil {
                context.insert(FollowedNPC(npcID: contactID, isFollowing: true))
                player.followers += 1
                player.following += 1
            }
        }
        checkAchievements()
        try? context.save()
        return true
    }

    // MARK: - Listings

    @discardableResult
    func createListing(productID: String, quantity: Int, price: Double, claimedAsAuthentic: Bool = false) -> Bool {
        guard quantity > 0, price > 0 else { return false }
        let allInv = inventory()
        guard let item = allInv.first(where: { $0.productID == productID }), item.quantity >= quantity else { return false }
        item.quantity -= quantity
        if item.quantity == 0 { context.delete(item) }
        let marketPrice = max(self.price(for: productID), 1)
        let minutesToBuyer = max(3.0, min(30.0, 10.0 * (price / marketPrice))) * Double.random(in: 0.8...1.2)
        let saleDate = Date.now.addingTimeInterval(minutesToBuyer * 60)
        let claim = claimedAsAuthentic && GameData.product(productID)?.isCounterfeit == true
        let listing = ListingItem(productID: productID, quantity: quantity, price: price, saleCompletesAt: saleDate, claimedAsAuthentic: claim)
        context.insert(listing)
        context.insert(TransactionRecord(type: .event, total: 0, note: claim ? "Profile listing created · authenticity claim" : "Profile listing created"))
        if claim { incrementObjectiveProgress(matching: { $0.objectiveID == "obj_fake" }) }
        let suitableBuyers = availableContacts(for: fetchPlayer()).filter { $0.kind == .buyer && buyerWantsProduct(npcID: $0.id, productID: productID) }
        if let buyer = suitableBuyers.randomElement() {
            let offerQuantity = Int.random(in: 1...quantity)
            let offerPrice = price * Double.random(in: 0.85...1.05)
            let productName = GameData.product(productID)?.name ?? "your item"
            let publicName = claim ? (GameData.product(productID)?.publicAlias ?? "collector item") : productName
            let message = "Hi! I saw your profile listing for \(publicName). I’d like \(offerQuantity). Would you consider \(Formatters.moneyPrecise(offerPrice)) per item?"
            _ = queueNPCMessage(npcID: buyer.id, text: message, at: saleDate, listingProductID: productID, listingQuantity: offerQuantity, listingPrice: offerPrice, listingCreatedAt: listing.createdAt)
            if fetchFollowed(npcID: buyer.id) == nil {
                context.insert(FollowedNPC(npcID: buyer.id, isFollowing: true))
                fetchPlayer().following += 1
            }
            try? context.save()
        }
        checkAchievements()
        try? context.save()
        return true
    }

    func cancelListing(_ listing: ListingItem) {
        cancelQueuedListingOffers(listing)
        let allInv = inventory()
        if let existing = allInv.first(where: { $0.productID == listing.productID }) {
            existing.quantity += listing.quantity
        } else {
            context.insert(InventoryItem(productID: listing.productID, quantity: listing.quantity, avgCost: listing.price))
        }
        context.delete(listing)
        try? context.save()
    }

    private func cancelQueuedListingOffers(_ listing: ListingItem) {
        let messages = (try? context.fetch(FetchDescriptor<MessageRecord>())) ?? []
        for message in messages where message.listingCreatedAt == listing.createdAt && message.listingProductID == listing.productID && !message.isDelivered {
            MessageNotifications.cancel(identifier: String(describing: message.persistentModelID))
            context.delete(message)
        }
    }

    func queueNextBuyerOffer(for listing: ListingItem, excluding npcID: String) {
        let suitable = availableContacts(for: fetchPlayer()).filter {
            $0.kind == .buyer && buyerWantsProduct(npcID: $0.id, productID: listing.productID)
        }
        let alternatives = suitable.filter { $0.id != npcID }
        guard let buyer = alternatives.randomElement() ?? suitable.randomElement() else { return }
        let quantity = Int.random(in: 1...max(1, listing.quantity))
        let price = listing.price * Double.random(in: 0.82...1.04)
        let product = GameData.product(listing.productID)
        let title = listing.claimedAsAuthentic == true && product?.isCounterfeit == true ? (product?.publicAlias ?? "collector item") : (product?.name ?? "your item")
        let text = buyer.id == npcID
            ? "I thought it over. I can revise my offer to \(Formatters.moneyPrecise(price)) for \(quantity) \(title). Interested?"
            : "Hi, I saw your live listing for \(title). I’m interested in \(quantity). Would you take \(Formatters.moneyPrecise(price)) per item?"
        _ = queueNPCMessage(npcID: buyer.id, text: text, at: .now.addingTimeInterval(TimeInterval.random(in: 18...38)), listingProductID: listing.productID, listingQuantity: quantity, listingPrice: price, listingCreatedAt: listing.createdAt)
        if fetchFollowed(npcID: buyer.id) == nil {
            context.insert(FollowedNPC(npcID: buyer.id, isFollowing: true))
            fetchPlayer().following += 1
            try? context.save()
        }
    }

    /// Prices are fixed for the whole local calendar day and roll once after midnight.
    func simulateMarketTick() {
        _ = deliverQueuedMessages()
        let overrides = (try? context.fetch(FetchDescriptor<PriceOverride>())) ?? []
        let btc = overrides.first { $0.productID == "BTC_RATE" }
        let shouldRoll = btc.map { !Calendar.current.isDate($0.lastUpdated, inSameDayAs: .now) } ?? false
        if shouldRoll {
            refreshMarketPrices()
            restockContactInventory()
        }
        let player = fetchPlayer()
        let activeListings = listings().filter { $0.isActive }
        for listing in activeListings {
            if listing.saleCompletesAt == nil {
                let ratio = max(3.0, min(30.0, 10.0 * listing.price / max(price(for: listing.productID), 1)))
                listing.saleCompletesAt = listing.createdAt.addingTimeInterval(ratio * 60)
            }
            guard let due = listing.saleCompletesAt, due <= .now else { continue }
            let existingMessages = (try? context.fetch(FetchDescriptor<MessageRecord>())) ?? []
            let alreadyContacted = existingMessages.contains { !$0.isFromPlayer && $0.listingProductID == listing.productID && $0.listingCreatedAt == listing.createdAt }
            guard !alreadyContacted else { continue }
            let buyers = availableContacts(for: player).filter { $0.kind == .buyer && buyerWantsProduct(npcID: $0.id, productID: listing.productID) }
            guard let buyer = buyers.randomElement() else { continue }
            let quantity = max(1, min(listing.quantity, Int.random(in: 1...max(listing.quantity, 1))))
            let offer = listing.price * Double.random(in: 0.85...1.05)
            let product = GameData.product(listing.productID)
            let productName = listing.claimedAsAuthentic == true && product?.isCounterfeit == true
                ? (product?.publicAlias ?? "collector item")
                : (product?.name ?? "your listing")
            _ = queueNPCMessage(npcID: buyer.id, text: "Hi! I saw your profile listing for \(productName). I’d like \(quantity). Would you consider \(Formatters.moneyPrecise(offer)) per item?", at: Date.now.addingTimeInterval(TimeInterval.random(in: 1.5...4.0)), listingProductID: listing.productID, listingQuantity: quantity, listingPrice: offer, listingCreatedAt: listing.createdAt)
            if fetchFollowed(npcID: buyer.id) == nil {
                context.insert(FollowedNPC(npcID: buyer.id, isFollowing: true))
                player.following += 1
            }
        }
        applyLevelUpIfNeeded(player: player)
        if shouldRoll {
            if Double.random(in: 0...1) < 0.3 { player.followers += Int.random(in: 0...2) }
            maybeTriggerEvent()
        }
        checkAchievements()
        processShipping()
        try? context.save()
    }

    // MARK: - Progression

    func applyLevelUpIfNeeded(player: PlayerState) {
        let newLevel = SellerLevel.forReputation(player.reputation)
        if newLevel.rawValue > player.levelRaw {
            player.levelRaw = newLevel.rawValue
            player.badges.append("Reached \(newLevel.title)")
            context.insert(TransactionRecord(type: .event, total: 0, note: "Leveled up to \(newLevel.title)!"))
        }
    }

    func availableProducts(for player: PlayerState) -> [ProductDef] {
        GameData.products.filter { $0.unlockLevel.rawValue <= player.levelRaw }
    }

    func availableSuppliers(for player: PlayerState) -> [SupplierDef] {
        GameData.suppliers.filter { $0.unlockLevel.rawValue <= player.levelRaw && player.reputation >= $0.repRequired }
    }

    // MARK: - Market prices

    func refreshMarketPrices() {
        let overrides = (try? context.fetch(FetchDescriptor<PriceOverride>())) ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for override in overrides {
            let lastDay = calendar.startOfDay(for: override.lastUpdated)
            let missedDays = max(1, calendar.dateComponents([.day], from: lastDay, to: today).day ?? 1)
            let firstDayToSimulate = max(1, missedDays - 89)
            if let coin = GameData.cryptocurrencies.first(where: { $0.id == override.productID }) {
                let volatility: Double
                switch coin.id {
                case "BTC_RATE": volatility = 0.045
                case "ETH_RATE": volatility = 0.055
                case "SOL_RATE", "AVAX_RATE": volatility = 0.085
                case "DOGE_RATE": volatility = 0.11
                case "SMP_RATE": volatility = 0.065
                default: volatility = 0.07
                }
                for day in firstDayToSimulate...missedDays {
                    let change = Double.random(in: -volatility...volatility) - volatility * volatility / 2
                    override.currentPrice = max(coin.initialPrice * 0.2, min(coin.initialPrice * 5, override.currentPrice * (1 + change)))
                    override.trend = change
                    let date = calendar.date(byAdding: .day, value: day, to: lastDay) ?? today
                    override.lastUpdated = date
                    context.insert(PriceSnapshot(assetID: override.productID, price: override.currentPrice, date: date))
                }
                continue
            }
            guard let product = GameData.product(override.productID) else { continue }
            for day in firstDayToSimulate...missedDays {
                if product.fixedPrice {
                    override.trend = 0
                } else {
                    let change = Double.random(in: -product.volatility...product.volatility)
                    override.trend = change
                    override.currentPrice = max(product.basePrice * 0.4, min(product.basePrice * 2.2, override.currentPrice * (1 + change)))
                }
                let date = calendar.date(byAdding: .day, value: day, to: lastDay) ?? today
                override.lastUpdated = date
                context.insert(PriceSnapshot(assetID: override.productID, price: override.currentPrice, date: date))
            }
        }
        try? context.save()
    }

    private func restockContactInventory() {
        let stock = (try? context.fetch(FetchDescriptor<NPCStockItem>())) ?? []
        for item in stock {
            guard let product = GameData.product(item.productID) else { continue }
            item.quantity = Int.random(in: 3...12)
            item.unitPrice = price(for: product.id) * (product.fixedPrice ? 1 : Double.random(in: 1.0...1.2))
        }
    }

    func priceHistory(for assetID: String, days: Int = 30) -> [PriceSnapshot] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let all = (try? context.fetch(FetchDescriptor<PriceSnapshot>(sortBy: [SortDescriptor(\.date)]))) ?? []
        return all.filter { $0.assetID == assetID && $0.date >= cutoff }
    }

    // MARK: - Random events

    func maybeTriggerEvent() {
        let active = (try? context.fetch(FetchDescriptor<ActiveMarketEvent>())) ?? []
        for e in active where e.expiresAt < .now { context.delete(e) }
        guard active.filter({ $0.expiresAt >= .now }).isEmpty else { return }
        guard Double.random(in: 0...1) < 0.2 else { return }
        triggerRandomEvent()
    }

    @discardableResult
    func triggerRandomEvent() -> ActiveMarketEvent {
        let product = GameData.products.filter { !$0.fixedPrice }.randomElement()!
        let isPositive = Bool.random()
        let multiplier = isPositive ? Double.random(in: 1.15...1.5) : Double.random(in: 0.6...0.85)
        let title = isPositive ? "Demand Spike: \(product.name)" : "Market Crackdown: \(product.name)"
        let desc = isPositive ? "Buyers are paying premium for \(product.name) right now." : "Increased risk is depressing prices on \(product.name)."
        let event = ActiveMarketEvent(title: title, eventDescription: desc, productID: product.id, multiplier: multiplier, expiresAt: Calendar.current.date(byAdding: .hour, value: 6, to: .now) ?? .now, icon: isPositive ? "arrow.up.right.circle.fill" : "exclamationmark.triangle.fill")
        context.insert(event)
        let overrides = (try? context.fetch(FetchDescriptor<PriceOverride>())) ?? []
        if let override = overrides.first(where: { $0.productID == product.id }) {
            override.currentPrice *= multiplier
            override.trend = multiplier - 1
            context.insert(PriceSnapshot(assetID: product.id, price: override.currentPrice))
        }
        try? context.save()
        return event
    }

    // MARK: - Achievements

    func checkAchievements() {
        let player = fetchPlayer()
        let records = (try? context.fetch(FetchDescriptor<AchievementRecord>())) ?? []
        let netWorth = businessStats().netWorth
        let dealCount = transactions().filter { $0.type == .buy || $0.type == .sell || $0.type == .listingSale }.count

        func unlock(_ id: String) {
            if let rec = records.first(where: { $0.achievementID == id }), !rec.isUnlocked {
                rec.isUnlocked = true
                rec.unlockedDate = .now
            }
        }
        if dealCount >= 1 { unlock("a_first_sale") }
        if dealCount >= 10 { unlock("a_10_deals") }
        if dealCount >= 100 { unlock("a_100_deals") }
        if netWorth >= 1000 { unlock("a_1k") }
        if netWorth >= 10000 { unlock("a_10k") }
        if netWorth >= 100000 { unlock("a_100k") }
        if player.reputation >= 100 { unlock("a_rep_100") }
        if player.reputation >= 1000 { unlock("a_rep_1000") }
        if player.level == .elite { unlock("a_elite") }
        if player.btc > 0 { unlock("a_btc") }
        if player.followers >= 25 { unlock("a_10_followers") }
        if netWorth >= 20000 { unlock("a_20k_profit") }
        if ((try? context.fetch(FetchDescriptor<CryptoHolding>())) ?? []).contains(where: { $0.amount > 0 }) { unlock("a_5_coins") }
        let contactCount = ((try? context.fetch(FetchDescriptor<FollowedNPC>())) ?? []).filter { $0.isFollowing }.count
        if contactCount >= 5 { unlock("a_5_contacts") }
        if transactions().filter({ $0.type == .event && $0.note.hasPrefix("Profile listing created") }).count >= 5 { unlock("a_5_listings") }
        if contactCount >= 10 { unlock("a_10_contacts") }
        if inventory().filter({ $0.quantity > 0 }).count >= 5 { unlock("a_5_products") }
        let heldCoins = ((try? context.fetch(FetchDescriptor<CryptoHolding>())) ?? []).filter { $0.amount > 0 }.count + (player.btc > 0 ? 1 : 0)
        if heldCoins >= 3 { unlock("a_3_coins") }
        if player.referralCount >= 5 { unlock("a_referrals") }
        if player.trustScore >= 90 { unlock("a_trusted") }
        if player.loginStreak >= 7 { unlock("a_streak_7") }
        if transactions().contains(where: { $0.type == .event && $0.note == "Claim cleared after delivery" }) { unlock("a_counterfeit_clear") }
    }

    // MARK: - BTC exchange (simulated only, never real payments)

    @discardableResult
    func buyBTC(usdAmount: Double) -> Bool {
        let player = fetchPlayer()
        guard usdAmount > 0, player.cashUSD >= usdAmount else { return false }
        let rate = btcRate()
        let amountBTC = usdAmount / rate
        player.cashUSD -= usdAmount
        player.btc += amountBTC
        context.insert(TransactionRecord(type: .btcTrade, total: -usdAmount, note: "Bought \(String(format: "%.5f", amountBTC)) BTC"))
        incrementObjectiveProgress(matching: { $0.objectiveID == "obj_crypto" })
        checkAchievements()
        try? context.save()
        return true
    }

    @discardableResult
    func sellBTC(btcAmount: Double) -> Bool {
        let player = fetchPlayer()
        guard btcAmount > 0, player.btc >= btcAmount else { return false }
        let rate = btcRate()
        let usdAmount = btcAmount * rate
        player.btc -= btcAmount
        player.cashUSD += usdAmount
        context.insert(TransactionRecord(type: .btcTrade, total: usdAmount, note: "Sold \(String(format: "%.5f", btcAmount)) BTC"))
        incrementObjectiveProgress(matching: { $0.objectiveID == "obj_crypto" })
        try? context.save()
        return true
    }

    // MARK: - Daily objectives

    func refreshDailyObjectivesIfNeeded() {
        let existing = (try? context.fetch(FetchDescriptor<DailyObjective>())) ?? []
        let today = Calendar.current.startOfDay(for: .now)
        let todays = existing.filter { Calendar.current.isDate($0.dateAssigned, inSameDayAs: today) }
        if todays.isEmpty {
            for old in existing { context.delete(old) }
        }
        let player = fetchPlayer()
        var templates: [(String, String, String, Int, Double, Int)] = [
            ("obj_sell3", "Move Product", "Complete 3 sales today", 3, 150, 10),
            ("obj_buy2", "Restock", "Buy from 2 different products", 2, 100, 5),
            ("obj_listing", "List It", "Create 1 new listing", 1, 75, 5),
            ("obj_ship", "Ship It", "Pack an order for delivery", 1, 100, 8),
            ("obj_checkin", "Clock In", "Check in today", 1, 40, 2)
        ]
        if player.levelRaw >= SellerLevel.runner.rawValue {
            templates.append(("obj_contactbuy", "Know a Supplier", "Buy from a contact", 1, 140, 10))
            templates.append(("obj_referral", "Word of Mouth", "Receive a customer referral", 1, 175, 12))
        }
        if player.levelRaw >= SellerLevel.reseller.rawValue {
            templates.append(("obj_crypto", "Market Watch", "Make a cryptocurrency trade", 1, 125, 8))
        }
        if player.levelRaw >= SellerLevel.dealer.rawValue {
            templates.append(("obj_network", "Build Your Network", "Follow a new contact", 1, 90, 8))
            templates.append(("obj_review", "Read the Fine Print", "Rate a seller after delivery", 1, 100, 6))
        }
        if player.levelRaw >= SellerLevel.reseller.rawValue {
            templates.append(("obj_fake", "Risky Catalog", "List a replica as authentic", 1, 150, 0))
        }
        let assignedIDs = Set(todays.map(\.objectiveID))
        for item in templates where !assignedIDs.contains(item.0) {
            context.insert(DailyObjective(objectiveID: item.0, title: item.1, objectiveDescription: item.2, target: item.3, rewardCash: item.4, rewardRep: item.5, dateAssigned: today))
        }
        try? context.save()
    }

    func incrementObjectiveProgress(matching predicate: (DailyObjective) -> Bool, by amount: Int = 1) {
        let all = (try? context.fetch(FetchDescriptor<DailyObjective>())) ?? []
        var completedAny = false
        for obj in all where predicate(obj) && !obj.isCompleted {
            obj.progress = min(obj.target, obj.progress + amount)
            if obj.progress >= obj.target {
                obj.isCompleted = true
                let player = fetchPlayer()
                player.cashUSD += obj.rewardCash
                player.reputation += obj.rewardRep
                applyLevelUpIfNeeded(player: player)
                completedAny = true
            }
        }
        if completedAny { checkAchievements() }
        try? context.save()
    }

    // MARK: - Stats

    struct BusinessStats {
        var revenue: Double
        var expenses: Double
        var profit: Double
        var margin: Double
        var inventoryValue: Double
        var netWorth: Double
        var activeListingsValue: Double
    }

    func businessStats(daysBack: Int = 30) -> BusinessStats {
        let player = fetchPlayer()
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysBack, to: .now) ?? .distantPast
        let txs = transactions().filter { $0.date >= cutoff }
        let revenue = txs.filter { $0.total > 0 }.reduce(0) { $0 + $1.total }
        let expenses = abs(txs.filter { $0.total < 0 }.reduce(0) { $0 + $1.total })
        let profit = revenue - expenses
        let margin = revenue > 0 ? (profit / revenue) * 100 : 0
        let invValue = inventory().reduce(0.0) { $0 + (price(for: $1.productID) * Double($1.quantity)) }
        let listingsValue = listings().reduce(0.0) { $0 + ($1.price * Double($1.quantity)) }
        let netWorth = player.cashUSD + (player.btc * btcRate()) + invValue + listingsValue
        return BusinessStats(revenue: revenue, expenses: expenses, profit: profit, margin: margin, inventoryValue: invValue, netWorth: netWorth, activeListingsValue: listingsValue)
    }

    func dailyProfitSeries(days: Int = 14) -> [(date: Date, profit: Double)] {
        var result: [(Date, Double)] = []
        let cal = Calendar.current
        let allTxs = transactions()
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now)) else { continue }
            guard let nextDay = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            let dayTxs = allTxs.filter { $0.date >= day && $0.date < nextDay }
            let profit = dayTxs.reduce(0.0) { $0 + $1.total }
            result.append((day, profit))
        }
        return result
    }

    // MARK: - Admin / Dev tools (hidden menu for testing)

    func adminAddCash(_ amount: Double) {
        let player = fetchPlayer()
        player.cashUSD += amount
        context.insert(TransactionRecord(type: .admin, total: amount, note: "Admin cash adjustment"))
        try? context.save()
    }

    func adminAddBTC(_ amount: Double) {
        let player = fetchPlayer()
        player.btc = max(0, player.btc + amount)
        try? context.save()
    }

    func adminSetReputation(_ rep: Int) {
        let player = fetchPlayer()
        player.reputation = rep
        applyLevelUpIfNeeded(player: player)
        try? context.save()
    }

    func adminSpawnItem(productID: String, quantity: Int) {
        let allInv = inventory()
        if let existing = allInv.first(where: { $0.productID == productID }) {
            existing.quantity += quantity
        } else {
            context.insert(InventoryItem(productID: productID, quantity: quantity, avgCost: price(for: productID)))
        }
        try? context.save()
    }

    func adminSetPrice(productID: String, price newPrice: Double) {
        let overrides = (try? context.fetch(FetchDescriptor<PriceOverride>())) ?? []
        if let override = overrides.first(where: { $0.productID == productID }) {
            override.currentPrice = newPrice
        }
        try? context.save()
    }

    func adminUnlockLevel(_ level: SellerLevel) {
        let player = fetchPlayer()
        player.levelRaw = max(player.levelRaw, level.rawValue)
        player.reputation = max(player.reputation, level.repRequired)
        try? context.save()
    }

    func adminResetAllData() {
        MessageNotifications.cancelPending()
        func deleteAll<T: PersistentModel>(_ type: T.Type) {
            if let items = try? context.fetch(FetchDescriptor<T>()) {
                for item in items { context.delete(item) }
            }
        }
        deleteAll(PlayerState.self)
        deleteAll(InventoryItem.self)
        deleteAll(ListingItem.self)
        deleteAll(TransactionRecord.self)
        deleteAll(FollowedNPC.self)
        deleteAll(ReviewRecord.self)
        deleteAll(MessageRecord.self)
        deleteAll(ActiveMarketEvent.self)
        deleteAll(PriceOverride.self)
        deleteAll(PriceSnapshot.self)
        deleteAll(CryptoHolding.self)
        deleteAll(NPCStockItem.self)
        deleteAll(ShippingOrder.self)
        deleteAll(AchievementRecord.self)
        deleteAll(DailyObjective.self)
        try? context.save()
        bootstrapIfNeeded()
    }
}
