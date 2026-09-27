import Foundation

// MARK: - Seller Levels

enum SellerLevel: Int, CaseIterable, Codable, Comparable {
    case newcomer, runner, reseller, dealer, broker, established, trusted, elite

    var title: String {
        switch self {
        case .newcomer: return "NEWCOMER"
        case .runner: return "RUNNER"
        case .reseller: return "RESELLER"
        case .dealer: return "DEALER"
        case .broker: return "BROKER"
        case .established: return "ESTABLISHED"
        case .trusted: return "TRUSTED"
        case .elite: return "ELITE"
        }
    }

    var repRequired: Int {
        switch self {
        case .newcomer: return 0
        case .runner: return 50
        case .reseller: return 150
        case .dealer: return 350
        case .broker: return 700
        case .established: return 1200
        case .trusted: return 2000
        case .elite: return 3200
        }
    }

    var icon: String {
        switch self {
        case .newcomer: return "leaf"
        case .runner: return "figure.run"
        case .reseller: return "arrow.left.arrow.right"
        case .dealer: return "briefcase.fill"
        case .broker: return "building.columns.fill"
        case .established: return "star.fill"
        case .trusted: return "shield.fill"
        case .elite: return "crown.fill"
        }
    }

    static func < (lhs: SellerLevel, rhs: SellerLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    static func forReputation(_ rep: Int) -> SellerLevel {
        var current = SellerLevel.newcomer
        for level in SellerLevel.allCases where rep >= level.repRequired {
            current = level
        }
        return current
    }
}

// MARK: - Products

enum ProductCategory: String, CaseIterable, Codable {
    case electronics = "Electronics"
    case collectibles = "Collectibles"
    case herbal = "Herbal Goods"
    case pharma = "Grey Pharma"
    case luxury = "Luxury Items"
    case documents = "Documents"
    case tech = "Tech & Data"
}

struct ProductDef: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: ProductCategory
    let basePrice: Double
    let unlockLevel: SellerLevel
    let icon: String
    let volatility: Double
    let riskTier: Int
}

struct SupplierDef: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let unlockLevel: SellerLevel
    let repRequired: Int
    let productIDs: [String]
    let discount: Double
    let icon: String
}

enum NPCKind: String, Codable { case buyer, seller, rival }

struct NPCDef: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let avatarSymbol: String
    let kind: NPCKind
    let bio: String
    let baseRatingSeed: Int
}

struct AchievementDef: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let description: String
    let icon: String
}

enum GameData {
    static let products: [ProductDef] = [
        ProductDef(id: "p_burner", name: "Burner Phones", category: .electronics, basePrice: 45, unlockLevel: .newcomer, icon: "phone.fill", volatility: 0.05, riskTier: 1),
        ProductDef(id: "p_watch", name: "Replica Watches", category: .luxury, basePrice: 120, unlockLevel: .newcomer, icon: "clock.fill", volatility: 0.08, riskTier: 1),
        ProductDef(id: "p_herb", name: "Herbal Blend", category: .herbal, basePrice: 25, unlockLevel: .runner, icon: "leaf.fill", volatility: 0.15, riskTier: 2),
        ProductDef(id: "p_cards", name: "Rare Trading Cards", category: .collectibles, basePrice: 60, unlockLevel: .runner, icon: "rectangle.stack.fill", volatility: 0.1, riskTier: 1),
        ProductDef(id: "p_pills", name: "Grey Market Supplements", category: .pharma, basePrice: 80, unlockLevel: .reseller, icon: "pills.fill", volatility: 0.2, riskTier: 3),
        ProductDef(id: "p_data", name: "Data Drives", category: .tech, basePrice: 200, unlockLevel: .reseller, icon: "externaldrive.fill", volatility: 0.18, riskTier: 3),
        ProductDef(id: "p_docs", name: "Blank Documents", category: .documents, basePrice: 300, unlockLevel: .dealer, icon: "doc.fill", volatility: 0.22, riskTier: 4),
        ProductDef(id: "p_jewel", name: "Loose Gemstones", category: .luxury, basePrice: 450, unlockLevel: .dealer, icon: "sparkles", volatility: 0.2, riskTier: 3),
        ProductDef(id: "p_art", name: "Questionable Art", category: .collectibles, basePrice: 800, unlockLevel: .broker, icon: "paintpalette.fill", volatility: 0.25, riskTier: 3),
        ProductDef(id: "p_tech2", name: "Prototype Tech", category: .tech, basePrice: 1200, unlockLevel: .broker, icon: "cpu.fill", volatility: 0.28, riskTier: 4),
        ProductDef(id: "p_gold", name: "Gold Bars", category: .luxury, basePrice: 2200, unlockLevel: .established, icon: "square.stack.3d.up.fill", volatility: 0.12, riskTier: 2),
        ProductDef(id: "p_ledger", name: "Offshore Ledgers", category: .documents, basePrice: 3500, unlockLevel: .trusted, icon: "book.closed.fill", volatility: 0.3, riskTier: 5),
        ProductDef(id: "p_chip", name: "Encrypted Chips", category: .tech, basePrice: 5000, unlockLevel: .elite, icon: "memorychip.fill", volatility: 0.32, riskTier: 5)
    ]

    static let suppliers: [SupplierDef] = [
        SupplierDef(id: "s_alley", name: "Alley Contacts", unlockLevel: .newcomer, repRequired: 0, productIDs: ["p_burner", "p_watch"], discount: 0.0, icon: "figure.walk"),
        SupplierDef(id: "s_lowkey", name: "Lowkey Imports", unlockLevel: .runner, repRequired: 40, productIDs: ["p_herb", "p_cards"], discount: 0.05, icon: "shippingbox.fill"),
        SupplierDef(id: "s_midtier", name: "Midtier Logistics", unlockLevel: .reseller, repRequired: 150, productIDs: ["p_pills", "p_data"], discount: 0.08, icon: "truck.box.fill"),
        SupplierDef(id: "s_backroom", name: "Backroom Network", unlockLevel: .dealer, repRequired: 350, productIDs: ["p_docs", "p_jewel"], discount: 0.1, icon: "lock.rectangle.stack.fill"),
        SupplierDef(id: "s_broker", name: "The Broker's Circle", unlockLevel: .broker, repRequired: 700, productIDs: ["p_art", "p_tech2"], discount: 0.12, icon: "person.3.fill"),
        SupplierDef(id: "s_vault", name: "Vault Connections", unlockLevel: .established, repRequired: 1200, productIDs: ["p_gold"], discount: 0.1, icon: "building.columns.fill"),
        SupplierDef(id: "s_offshore", name: "Offshore Channel", unlockLevel: .trusted, repRequired: 2000, productIDs: ["p_ledger"], discount: 0.15, icon: "globe"),
        SupplierDef(id: "s_shadow", name: "Shadow Syndicate", unlockLevel: .elite, repRequired: 3200, productIDs: ["p_chip"], discount: 0.18, icon: "crown.fill")
    ]

    static let npcs: [NPCDef] = [
        NPCDef(id: "n_marco", name: "Marco V.", avatarSymbol: "person.circle.fill", kind: .buyer, bio: "Buys anything shiny, pays fast.", baseRatingSeed: 4),
        NPCDef(id: "n_lena", name: "Lena K.", avatarSymbol: "person.crop.circle.fill", kind: .seller, bio: "Reliable herbal supplier from the east side.", baseRatingSeed: 5),
        NPCDef(id: "n_dre", name: "Dre", avatarSymbol: "person.crop.circle.badge.checkmark", kind: .buyer, bio: "Collector. Only wants rare stuff.", baseRatingSeed: 4),
        NPCDef(id: "n_ivy", name: "Ivy Chen", avatarSymbol: "person.crop.circle.fill.badge.plus", kind: .rival, bio: "Rival reseller. Watch your prices.", baseRatingSeed: 3),
        NPCDef(id: "n_omar", name: "Omar R.", avatarSymbol: "person.circle", kind: .seller, bio: "Tech sourcing, prototype gear.", baseRatingSeed: 4),
        NPCDef(id: "n_sasha", name: "Sasha B.", avatarSymbol: "person.crop.circle.badge.moon", kind: .buyer, bio: "High roller. Buys in bulk.", baseRatingSeed: 5),
        NPCDef(id: "n_the_broker", name: "The Broker", avatarSymbol: "person.crop.square.fill", kind: .seller, bio: "Only deals with trusted names.", baseRatingSeed: 5)
    ]

    static let achievements: [AchievementDef] = [
        AchievementDef(id: "a_first_sale", title: "First Move", description: "Complete your first sale.", icon: "dollarsign.circle.fill"),
        AchievementDef(id: "a_1k", title: "First Grand", description: "Reach $1,000 net worth.", icon: "banknote.fill"),
        AchievementDef(id: "a_10k", title: "Five Figures", description: "Reach $10,000 net worth.", icon: "chart.line.uptrend.xyaxis"),
        AchievementDef(id: "a_100k", title: "Six Figures", description: "Reach $100,000 net worth.", icon: "building.2.fill"),
        AchievementDef(id: "a_rep_100", title: "Known Name", description: "Reach 100 reputation.", icon: "star.fill"),
        AchievementDef(id: "a_rep_1000", title: "Street Legend", description: "Reach 1000 reputation.", icon: "crown.fill"),
        AchievementDef(id: "a_10_deals", title: "Getting Busy", description: "Complete 10 total deals.", icon: "arrow.left.arrow.right.circle.fill"),
        AchievementDef(id: "a_100_deals", title: "Well Connected", description: "Complete 100 total deals.", icon: "person.3.fill"),
        AchievementDef(id: "a_elite", title: "Top of the Chain", description: "Reach ELITE seller level.", icon: "flame.fill"),
        AchievementDef(id: "a_btc", title: "Off the Books", description: "Trade BTC for the first time.", icon: "bitcoinsign.circle.fill")
    ]

    static func product(_ id: String) -> ProductDef? { products.first { $0.id == id } }
    static func supplier(_ id: String) -> SupplierDef? { suppliers.first { $0.id == id } }
    static func npc(_ id: String) -> NPCDef? { npcs.first { $0.id == id } }
}
