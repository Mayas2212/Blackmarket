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
         isDevModeUnlocked: Bool = false) {
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
    }

    var level: SellerLevel {
        get { SellerLevel(rawValue: levelRaw) ?? .newcomer }
        set { levelRaw = newValue.rawValue }
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

    init(productID: String, quantity: Int, price: Double, createdAt: Date = .now, isActive: Bool = true, saleCompletesAt: Date? = nil) {
        self.productID = productID
        self.quantity = quantity
        self.price = price
        self.createdAt = createdAt
        self.isActive = isActive
        self.saleCompletesAt = saleCompletesAt
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

    init(npcID: String, rating: Int, text: String, date: Date = .now) {
        self.npcID = npcID
        self.rating = rating
        self.text = text
        self.date = date
    }
}

@Model
final class MessageRecord {
    var npcID: String
    var text: String
    var isFromPlayer: Bool
    var date: Date
    var offeredProductID: String?

    init(npcID: String, text: String, isFromPlayer: Bool, date: Date = .now, offeredProductID: String? = nil) {
        self.npcID = npcID
        self.text = text
        self.isFromPlayer = isFromPlayer
        self.date = date
        self.offeredProductID = offeredProductID
    }
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
