import Foundation
import SwiftData

// MARK: - Player

@Model
final class PlayerState {
    var username: String
    var avatarSymbol: String
    var cashUSD: Double
    var btc: Double
    var reputation: Int
    var xp: Int
    var followers: Int
    var following: Int
    var joinDate: Date
    var badges: [String]
    var levelRaw: Int
    var isDevModeUnlocked: Bool
    var trustScoreRaw: Int?
    var lastCheckIn: Date?
    var loginStreakRaw: Int?
    var referralCountRaw: Int?
    var storageLevelRaw: Int?

    init(username: String = "you_underground",
         avatarSymbol: String = "person.crop.circle.fill",
         cashUSD: Double = 500,
         btc: Double = 0,
         reputation: Int = 0,
         xp: Int = 0,
         followers: Int = 12,
         following: Int = 5,
         joinDate: Date = .now,
         badges: [String] = [],
         levelRaw: Int = 0,
         isDevModeUnlocked: Bool = false,
         trustScore: Int = 50,
         lastCheckIn: Date? = nil,
         loginStreak: Int = 0,
         referralCount: Int = 0,
         storageLevel: Int = 0) {
        self.username = username
        self.avatarSymbol = avatarSymbol
        self.cashUSD = cashUSD
        self.btc = btc
        self.reputation = reputation
        self.xp = xp
        self.followers = followers
        self.following = following
        self.joinDate = joinDate
        self.badges = badges
        self.levelRaw = levelRaw
        self.isDevModeUnlocked = isDevModeUnlocked
        self.trustScoreRaw = trustScore
        self.lastCheckIn = lastCheckIn
        self.loginStreakRaw = loginStreak
        self.referralCountRaw = referralCount
        self.storageLevelRaw = storageLevel
    }

    var level: SellerLevel {
        get { SellerLevel(rawValue: levelRaw) ?? .newcomer }
        set { levelRaw = newValue.rawValue }
    }
    var trustScore: Int {
        get { trustScoreRaw ?? 50 }
        set { trustScoreRaw = min(100, max(0, newValue)) }
    }
    var loginStreak: Int {
        get { loginStreakRaw ?? 0 }
        set { loginStreakRaw = max(0, newValue) }
    }
    var referralCount: Int {
        get { referralCountRaw ?? 0 }
        set { referralCountRaw = max(0, newValue) }
    }
    var storageLevel: Int {
        get { storageLevelRaw ?? 0 }
        set { storageLevelRaw = min(10, max(0, newValue)) }
    }
}

// MARK: - Inventory & Listings

@Model
final class InventoryItem {
    var productID: String
    var quantity: Int
    var avgCost: Double

    init(productID: String, quantity: Int, avgCost: Double) {
        self.productID = productID
        self.quantity = quantity
        self.avgCost = avgCost
    }
}

@Model
final class ListingItem {
    var productID: String
    var quantity: Int
    var price: Double
    var createdAt: Date
    var isActive: Bool
    var saleCompletesAt: Date?
    var claimedAsAuthentic: Bool?

    init(productID: String, quantity: Int, price: Double, createdAt: Date = .now, isActive: Bool = true, saleCompletesAt: Date? = nil, claimedAsAuthentic: Bool = false) {
        self.productID = productID
        self.quantity = quantity
        self.price = price
        self.createdAt = createdAt
        self.isActive = isActive
        self.saleCompletesAt = saleCompletesAt
        self.claimedAsAuthentic = claimedAsAuthentic
    }
}

// MARK: - Transactions

enum TransactionType: String, Codable {
    case buy, sell, listingSale, btcTrade, event, admin
}

@Model
final class TransactionRecord {
    var typeRaw: String
    var productID: String?
    var quantity: Int
    var unitPrice: Double
    var total: Double
    var date: Date
    var note: String

    init(type: TransactionType, productID: String? = nil, quantity: Int = 0, unitPrice: Double = 0, total: Double, date: Date = .now, note: String = "") {
        self.typeRaw = type.rawValue
        self.productID = productID
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.total = total
        self.date = date
        self.note = note
    }

    var type: TransactionType { TransactionType(rawValue: typeRaw) ?? .buy }
}

// MARK: - Social

@Model
final class FollowedNPC {
    var npcID: String
    var isFollowing: Bool
    var relationship: Int

    init(npcID: String, isFollowing: Bool = true, relationship: Int = 0) {
        self.npcID = npcID
        self.isFollowing = isFollowing
        self.relationship = relationship
    }
}

@Model
final class ReviewRecord {
    var npcID: String
    var rating: Int
    var text: String
    var date: Date
    var isAboutPlayer: Bool?

    init(npcID: String, rating: Int, text: String, date: Date = .now, isAboutPlayer: Bool = false) {
        self.npcID = npcID
        self.rating = rating
        self.text = text
        self.date = date
        self.isAboutPlayer = isAboutPlayer
    }
}

@Model
final class MessageRecord {
    var npcID: String
    var text: String
    var isFromPlayer: Bool
    var date: Date
    var offeredProductID: String?
    var offeredPrice: Double?
    var listingProductID: String?
    var listingQuantity: Int?
    var listingPrice: Double?
    var listingCreatedAt: Date?
    var deliveryState: Bool?

    init(npcID: String, text: String, isFromPlayer: Bool, date: Date = .now, offeredProductID: String? = nil, offeredPrice: Double? = nil, listingProductID: String? = nil, listingQuantity: Int? = nil, listingPrice: Double? = nil, listingCreatedAt: Date? = nil, isDelivered: Bool = true) {
        self.npcID = npcID
        self.text = text
        self.isFromPlayer = isFromPlayer
        self.date = date
        self.offeredProductID = offeredProductID
        self.offeredPrice = offeredPrice
        self.listingProductID = listingProductID
        self.listingQuantity = listingQuantity
        self.listingPrice = listingPrice
        self.listingCreatedAt = listingCreatedAt
        self.deliveryState = isDelivered
    }

    var isDelivered: Bool { deliveryState ?? true }
}

// MARK: - Market

@Model
final class ActiveMarketEvent {
    var title: String
    var eventDescription: String
    var productID: String?
    var multiplier: Double
    var expiresAt: Date
    var icon: String

    init(title: String, eventDescription: String, productID: String? = nil, multiplier: Double, expiresAt: Date, icon: String = "bolt.fill") {
        self.title = title
        self.eventDescription = eventDescription
        self.productID = productID
        self.multiplier = multiplier
        self.expiresAt = expiresAt
        self.icon = icon
    }
}

@Model
final class PriceOverride {
    var productID: String
    var currentPrice: Double
    var lastUpdated: Date
    var trend: Double

    init(productID: String, currentPrice: Double, lastUpdated: Date = .now, trend: Double = 0) {
        self.productID = productID
        self.currentPrice = currentPrice
        self.lastUpdated = lastUpdated
        self.trend = trend
    }
}

@Model
final class PriceSnapshot {
    var assetID: String
    var price: Double
    var date: Date

    init(assetID: String, price: Double, date: Date = .now) {
        self.assetID = assetID
        self.price = price
        self.date = date
    }
}

@Model
final class CryptoHolding {
    var assetID: String
    var amount: Double
    init(assetID: String, amount: Double = 0) { self.assetID = assetID; self.amount = amount }
}

@Model
final class NPCStockItem {
    var npcID: String
    var productID: String
    var quantity: Int
    var unitPrice: Double
    init(npcID: String, productID: String, quantity: Int, unitPrice: Double) {
        self.npcID = npcID; self.productID = productID; self.quantity = quantity; self.unitPrice = unitPrice
    }
}

@Model
final class ShippingOrder {
    var npcID: String
    var productID: String
    var quantity: Int
    var unitPrice: Double
    var isSale: Bool
    var createdAt: Date
    var arrivesAt: Date
    var isComplete: Bool
    var packageLost: Bool?
    var listingCreatedAt: Date?
    var isMisrepresented: Bool?
    var counterfeitDetected: Bool?
    var reviewed: Bool?
    init(npcID: String, productID: String, quantity: Int, unitPrice: Double, isSale: Bool, createdAt: Date = .now, arrivesAt: Date, isComplete: Bool = false, packageLost: Bool? = nil, listingCreatedAt: Date? = nil, isMisrepresented: Bool = false, counterfeitDetected: Bool = false, reviewed: Bool = false) {
        self.npcID = npcID; self.productID = productID; self.quantity = quantity; self.unitPrice = unitPrice
        self.isSale = isSale; self.createdAt = createdAt; self.arrivesAt = arrivesAt; self.isComplete = isComplete; self.packageLost = packageLost
        self.listingCreatedAt = listingCreatedAt
        self.isMisrepresented = isMisrepresented
        self.counterfeitDetected = counterfeitDetected
        self.reviewed = reviewed
    }
}

// MARK: - Progression

@Model
final class AchievementRecord {
    var achievementID: String
    var isUnlocked: Bool
    var unlockedDate: Date?

    init(achievementID: String, isUnlocked: Bool = false, unlockedDate: Date? = nil) {
        self.achievementID = achievementID
        self.isUnlocked = isUnlocked
        self.unlockedDate = unlockedDate
    }
}

@Model
final class DailyObjective {
    var objectiveID: String
    var title: String
    var objectiveDescription: String
    var target: Int
    var progress: Int
    var rewardCash: Double
    var rewardRep: Int
    var dateAssigned: Date
    var isCompleted: Bool

    init(objectiveID: String, title: String, objectiveDescription: String, target: Int, progress: Int = 0, rewardCash: Double, rewardRep: Int, dateAssigned: Date = .now, isCompleted: Bool = false) {
        self.objectiveID = objectiveID
        self.title = title
        self.objectiveDescription = objectiveDescription
        self.target = target
        self.progress = progress
        self.rewardCash = rewardCash
        self.rewardRep = rewardRep
        self.dateAssigned = dateAssigned
        self.isCompleted = isCompleted
    }
}
