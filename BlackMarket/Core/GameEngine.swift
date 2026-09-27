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
        if snapshots.isEmpty {
            for product in GameData.products { context.insert(PriceSnapshot(assetID: product.id, price: product.basePrice)) }
            for coin in GameData.cryptocurrencies { context.insert(PriceSnapshot(assetID: coin.id, price: coin.initialPrice)) }
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

    private func contactUnlockRep(_ id: String) -> Int {
        switch id {
        case "n_mina": 100
        case "n_aria", "n_jules": 250
        case "n_sasha", "n_niko": 450
        case "n_omar", "n_ivy": 100
        case "n_the_broker": 700
        default: 0
        }
    }

    func stock(for npcID: String) -> [NPCStockItem] {
        let all = (try? context.fetch(FetchDescriptor<NPCStockItem>())) ?? []
        if !all.contains(where: { $0.npcID == npcID }), let npc = GameData.npc(npcID), npc.kind == .seller {
            seedStock(for: npc)
        }
        let updated = (try? context.fetch(FetchDescriptor<NPCStockItem>())) ?? []
        return updated.filter { $0.npcID == npcID && $0.quantity > 0 }
    }

    private func seedStock(for npc: NPCDef) {
        let existing = (try? context.fetch(FetchDescriptor<NPCStockItem>())) ?? []
        guard !existing.contains(where: { $0.npcID == npc.id }) else { return }
        let player = fetchPlayer()
        var choices = GameData.products.filter { !$0.fixedPrice }
        if npc.id == "n_lena" { choices = choices.filter { $0.category == .herbal || $0.category == .collectibles } }
        if npc.id == "n_omar" || npc.id == "n_jules" { choices = choices.filter { $0.category == .electronics || $0.category == .tech || $0.category == .collectibles } }
        if npc.id == "n_niko" { choices = choices.filter { $0.category == .collectibles || $0.category == .luxury } }
        let selected = Array(choices.shuffled().prefix(5))
        for product in selected {
            let markup = product.fixedPrice ? 1 : Double.random(in: 1.0...1.2)
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
        try? context.save()
        return true
    }

    @discardableResult
    func shipSale(npcID: String, productID: String, quantity: Int, unitPrice: Double, listingCreatedAt: Date? = nil) -> Bool {
        guard quantity > 0 else { return false }
        let due = Date.now.addingTimeInterval(TimeInterval.random(in: 300...600))
        if let listingCreatedAt {
            guard let listing = listings().first(where: { $0.productID == productID && $0.quantity >= quantity && $0.createdAt == listingCreatedAt }) else { return false }
            let remaining = listing.quantity - quantity
            if remaining == 0 { context.delete(listing) } else { listing.quantity = remaining }
        } else {
            guard let item = inventory().first(where: { $0.productID == productID && $0.quantity >= quantity }) else { return false }
            item.quantity -= quantity
            if item.quantity == 0 { context.delete(item) }
        }
        context.insert(ShippingOrder(npcID: npcID, productID: productID, quantity: quantity, unitPrice: unitPrice, isSale: true, arrivesAt: due, listingCreatedAt: listingCreatedAt))
        context.insert(TransactionRecord(type: .event, productID: productID, quantity: quantity, total: 0, note: "Packed order for \(GameData.npc(npcID)?.name ?? "customer")"))
        try? context.save()
        return true
    }

    func shippingOrders() -> [ShippingOrder] {
        (try? context.fetch(FetchDescriptor<ShippingOrder>()))?.filter { !$0.isComplete } ?? []
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
            order.packageLost = lost
            order.isComplete = true
            let total = order.unitPrice * Double(order.quantity)
            let player = fetchPlayer()
            if order.isSale {
                // The customer pays the agreed amount even if the carrier loses the parcel.
                player.cashUSD += total
                player.reputation += lost ? 0 : max(1, order.quantity)
                context.insert(TransactionRecord(type: .listingSale, productID: order.productID, quantity: order.quantity, unitPrice: order.unitPrice, total: total, note: lost ? "Carrier lost package; customer paid in full" : "Delivered to customer"))
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
            }
            let productName = GameData.product(order.productID)?.name ?? "your item"
            let status = lost ? (order.isSale ? "The carrier lost \(productName), but your customer paid in full." : "The carrier lost \(productName). The seller reimbursed you.") : (order.isSale ? "\(productName) was delivered. Payment is in your balance." : "\(productName) arrived. It’s in your inventory.")
            context.insert(MessageRecord(npcID: order.npcID, text: status, isFromPlayer: false))
        }
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
    func createListing(productID: String, quantity: Int, price: Double) -> Bool {
        guard quantity > 0, price > 0 else { return false }
        let allInv = inventory()
        guard let item = allInv.first(where: { $0.productID == productID }), item.quantity >= quantity else { return false }
        item.quantity -= quantity
        if item.quantity == 0 { context.delete(item) }
        let marketPrice = max(self.price(for: productID), 1)
        let minutesToBuyer = max(3.0, min(30.0, 10.0 * (price / marketPrice))) * Double.random(in: 0.8...1.2)
        let saleDate = Date.now.addingTimeInterval(minutesToBuyer * 60)
        context.insert(ListingItem(productID: productID, quantity: quantity, price: price, saleCompletesAt: saleDate))
        context.insert(TransactionRecord(type: .event, total: 0, note: "Profile listing created"))
        checkAchievements()
        try? context.save()
        return true
    }

    func cancelListing(_ listing: ListingItem) {
        let allInv = inventory()
        if let existing = allInv.first(where: { $0.productID == listing.productID }) {
            existing.quantity += listing.quantity
        } else {
            context.insert(InventoryItem(productID: listing.productID, quantity: listing.quantity, avgCost: listing.price))
        }
        context.delete(listing)
        try? context.save()
    }

    /// Prices are fixed for the whole local calendar day and roll once after midnight.
    func simulateMarketTick() {
        let backgroundAt = UserDefaults.standard.object(forKey: "blackmarket.lastBackgroundAt") as? Date
        let wasAway = backgroundAt.map { Date.now.timeIntervalSince($0) >= 60 } ?? false
        UserDefaults.standard.removeObject(forKey: "blackmarket.lastBackgroundAt")
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
            let existingOffer = existingMessages.last {
                !$0.isFromPlayer && $0.listingProductID == listing.productID && $0.listingCreatedAt == listing.createdAt
            }
            let alreadyAnswered = existingMessages.contains {
                $0.isFromPlayer && $0.listingCreatedAt == listing.createdAt
            }
            if wasAway, !alreadyAnswered,
               let buyer = existingOffer.flatMap({ GameData.npc($0.npcID) }) ?? availableContacts(for: player).filter({ $0.kind == .buyer }).randomElement() {
                let quantity = min(listing.quantity, existingOffer?.listingQuantity ?? listing.quantity)
                let salePrice = existingOffer?.listingPrice ?? listing.price
                let productName = GameData.product(listing.productID)?.name ?? "your item"
                if existingOffer == nil {
                    context.insert(MessageRecord(npcID: buyer.id, text: "I found your profile listing for \(productName) and bought all \(quantity) at your listed price of \(Formatters.moneyPrecise(salePrice)) each. It’s on the way.", isFromPlayer: false, listingProductID: listing.productID, listingQuantity: quantity, listingPrice: salePrice, listingCreatedAt: listing.createdAt))
                } else {
                    context.insert(MessageRecord(npcID: buyer.id, text: "I accepted your offer for \(quantity) \(productName) at \(Formatters.moneyPrecise(salePrice)) each. It’s on the way.", isFromPlayer: false))
                }
                context.insert(MessageRecord(npcID: buyer.id, text: "Order confirmed. Ship it when ready.", isFromPlayer: true, listingCreatedAt: existingOffer?.listingCreatedAt ?? listing.createdAt))
                if fetchFollowed(npcID: buyer.id) == nil {
                    context.insert(FollowedNPC(npcID: buyer.id, isFollowing: true))
                    player.following += 1
                }
                _ = shipSale(npcID: buyer.id, productID: listing.productID, quantity: quantity, unitPrice: salePrice, listingCreatedAt: listing.createdAt)
                continue
            }
            let alreadyContacted = existingMessages.contains { !$0.isFromPlayer && $0.listingProductID == listing.productID && $0.listingCreatedAt == listing.createdAt }
            guard !alreadyContacted else { continue }
            let buyers = availableContacts(for: player).filter { $0.kind == .buyer }
            guard let buyer = buyers.randomElement() else { continue }
            let quantity = max(1, min(listing.quantity, Int.random(in: 1...max(listing.quantity, 1))))
            let offer = listing.price * Double.random(in: 0.85...1.05)
            let productName = GameData.product(listing.productID)?.name ?? "your listing"
            context.insert(MessageRecord(npcID: buyer.id, text: "Hi! I saw your profile listing for \(productName). I can take \(quantity) for \(Formatters.moneyPrecise(offer)) each. Want to make a deal?", isFromPlayer: false, listingProductID: listing.productID, listingQuantity: quantity, listingPrice: offer, listingCreatedAt: listing.createdAt))
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
        for override in overrides {
            if let coin = GameData.cryptocurrencies.first(where: { $0.id == override.productID }) {
                let change = Double.random(in: -0.03...0.03)
                override.currentPrice = max(coin.initialPrice * 0.2, override.currentPrice * (1 + change))
                override.trend = change
                override.lastUpdated = .now
                context.insert(PriceSnapshot(assetID: override.productID, price: override.currentPrice))
                continue
            }
            guard let product = GameData.product(override.productID) else { continue }
            override.lastUpdated = .now
            if product.fixedPrice { override.trend = 0; continue }
            let change = Double.random(in: -product.volatility...product.volatility)
            let newPrice = max(product.basePrice * 0.4, min(product.basePrice * 2.2, override.currentPrice * (1 + change)))
            override.trend = change
            override.currentPrice = newPrice
            context.insert(PriceSnapshot(assetID: override.productID, price: newPrice))
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
        if transactions().filter({ $0.type == .event && $0.note == "Profile listing created" }).count >= 5 { unlock("a_5_listings") }
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
            let templates: [(String, String, String, Int, Double, Int)] = [
                ("obj_sell3", "Move Product", "Complete 3 sales today", 3, 150, 10),
                ("obj_buy2", "Restock", "Buy from 2 different products", 2, 100, 5),
                ("obj_listing", "List It", "Create 1 new listing", 1, 75, 5)
            ]
            for t in templates {
                context.insert(DailyObjective(objectiveID: t.0, title: t.1, objectiveDescription: t.2, target: t.3, rewardCash: t.4, rewardRep: t.5, dateAssigned: today))
            }
            try? context.save()
        }
    }

    func incrementObjectiveProgress(matching predicate: (DailyObjective) -> Bool, by amount: Int = 1) {
        let all = (try? context.fetch(FetchDescriptor<DailyObjective>())) ?? []
        for obj in all where predicate(obj) && !obj.isCompleted {
            obj.progress = min(obj.target, obj.progress + amount)
            if obj.progress >= obj.target {
                obj.isCompleted = true
                let player = fetchPlayer()
                player.cashUSD += obj.rewardCash
                player.reputation += obj.rewardRep
            }
        }
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
