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
    case fashion = "Fashion"
    case audio = "Audio & Home"
    case books = "Books & Media"
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
    var fixedPrice: Bool = false
    var isCounterfeit: Bool = false
    var publicAlias: String? = nil
}

struct CryptoDef: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let initialPrice: Double
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
        ProductDef(id: "p_watch", name: "Replica Watches", category: .luxury, basePrice: 120, unlockLevel: .newcomer, icon: "clock.fill", volatility: 0, riskTier: 3, fixedPrice: true, isCounterfeit: true, publicAlias: "Vintage Chronograph"),
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
        ProductDef(id: "p_chip", name: "Encrypted Chips", category: .tech, basePrice: 5000, unlockLevel: .elite, icon: "memorychip.fill", volatility: 0.32, riskTier: 5),
        ProductDef(id: "p_vinyl", name: "Limited Vinyl Records", category: .collectibles, basePrice: 85, unlockLevel: .newcomer, icon: "opticaldisc.fill", volatility: 0.09, riskTier: 1),
        ProductDef(id: "p_console", name: "Retro Game Consoles", category: .electronics, basePrice: 175, unlockLevel: .newcomer, icon: "gamecontroller.fill", volatility: 0.11, riskTier: 1),
        ProductDef(id: "p_sneakers", name: "Collector Sneakers", category: .collectibles, basePrice: 240, unlockLevel: .runner, icon: "shoe.fill", volatility: 0.16, riskTier: 2),
        ProductDef(id: "p_camera", name: "Vintage Cameras", category: .electronics, basePrice: 320, unlockLevel: .runner, icon: "camera.fill", volatility: 0.12, riskTier: 1),
        ProductDef(id: "p_watch_real", name: "Luxury Watches", category: .luxury, basePrice: 1800, unlockLevel: .reseller, icon: "watch.analog", volatility: 0.1, riskTier: 2),
        ProductDef(id: "p_counterfeit", name: "Counterfeit Luxury Watches", category: .luxury, basePrice: 140, unlockLevel: .newcomer, icon: "clock.badge.xmark", volatility: 0, riskTier: 4, fixedPrice: true, isCounterfeit: true, publicAlias: "Collector Chronograph"),
        ProductDef(id: "p_antiques", name: "Vintage Antiques", category: .collectibles, basePrice: 650, unlockLevel: .dealer, icon: "lamp.desk.fill", volatility: 0.13, riskTier: 2),
        ProductDef(id: "p_artprint", name: "Rare Art Prints", category: .collectibles, basePrice: 1100, unlockLevel: .broker, icon: "photo.artframe", volatility: 0.18, riskTier: 2),
        ProductDef(id: "p_comics", name: "Rare Comic Issues", category: .books, basePrice: 95, unlockLevel: .runner, icon: "book.closed.fill", volatility: 0.12, riskTier: 1),
        ProductDef(id: "p_firstpress", name: "First-Press Vinyl", category: .books, basePrice: 180, unlockLevel: .runner, icon: "opticaldisc.fill", volatility: 0.11, riskTier: 1),
        ProductDef(id: "p_headphones", name: "Studio Headphones", category: .audio, basePrice: 260, unlockLevel: .reseller, icon: "headphones", volatility: 0.12, riskTier: 1),
        ProductDef(id: "p_speakers", name: "Vintage Speakers", category: .audio, basePrice: 540, unlockLevel: .dealer, icon: "hifispeaker.fill", volatility: 0.16, riskTier: 2),
        ProductDef(id: "p_bag", name: "Designer Bags", category: .fashion, basePrice: 900, unlockLevel: .dealer, icon: "bag.fill", volatility: 0.17, riskTier: 2),
        ProductDef(id: "p_archivecoat", name: "Archive Jackets", category: .fashion, basePrice: 420, unlockLevel: .dealer, icon: "tshirt.fill", volatility: 0.14, riskTier: 1),
        ProductDef(id: "p_keyboard", name: "Custom Keyboards", category: .electronics, basePrice: 210, unlockLevel: .reseller, icon: "keyboard.fill", volatility: 0.13, riskTier: 1),
        ProductDef(id: "p_projector", name: "Vintage Projectors", category: .electronics, basePrice: 380, unlockLevel: .reseller, icon: "video.fill", volatility: 0.15, riskTier: 2),
        ProductDef(id: "p_sculpture", name: "Studio Sculptures", category: .collectibles, basePrice: 1450, unlockLevel: .broker, icon: "sparkles", volatility: 0.2, riskTier: 2),
        ProductDef(id: "p_collectorwatch", name: "Collector Watches", category: .luxury, basePrice: 2800, unlockLevel: .established, icon: "watch.analog", volatility: 0.13, riskTier: 2),
        ProductDef(id: "p_fragrance", name: "Rare Fragrances", category: .fashion, basePrice: 160, unlockLevel: .reseller, icon: "drop.fill", volatility: 0.1, riskTier: 1),
        ProductDef(id: "p_rarebook", name: "First-Edition Books", category: .books, basePrice: 720, unlockLevel: .broker, icon: "books.vertical.fill", volatility: 0.17, riskTier: 2),
        ProductDef(id: "p_earbuds", name: "Wireless Earbuds", category: .audio, basePrice: 75, unlockLevel: .newcomer, icon: "earbuds", volatility: 0.08, riskTier: 1),
        ProductDef(id: "p_zines", name: "Indie Art Zines", category: .books, basePrice: 35, unlockLevel: .newcomer, icon: "book.closed.fill", volatility: 0.09, riskTier: 1),
        ProductDef(id: "p_denim", name: "Vintage Denim Jackets", category: .fashion, basePrice: 110, unlockLevel: .newcomer, icon: "tshirt.fill", volatility: 0.1, riskTier: 1),
        ProductDef(id: "p_replica_bag", name: "Replica Designer Bags", category: .fashion, basePrice: 135, unlockLevel: .newcomer, icon: "bag.fill", volatility: 0, riskTier: 3, fixedPrice: true, isCounterfeit: true, publicAlias: "Archive Leather Handbag"),
        ProductDef(id: "p_replica_sneakers", name: "Replica Collector Sneakers", category: .collectibles, basePrice: 95, unlockLevel: .newcomer, icon: "shoe.fill", volatility: 0, riskTier: 3, fixedPrice: true, isCounterfeit: true, publicAlias: "Limited Edition High Tops"),
        ProductDef(id: "p_replica_camera", name: "Replica Vintage Camera", category: .electronics, basePrice: 160, unlockLevel: .runner, icon: "camera.fill", volatility: 0, riskTier: 4, fixedPrice: true, isCounterfeit: true, publicAlias: "Classic Rangefinder Camera"),
        ProductDef(id: "p_replica_fragrance", name: "Replica Luxury Fragrance", category: .fashion, basePrice: 42, unlockLevel: .newcomer, icon: "drop.fill", volatility: 0, riskTier: 2, fixedPrice: true, isCounterfeit: true, publicAlias: "Reserve No. 8 Eau de Parfum"),
        ProductDef(id: "p_replica_cards", name: "Reproduction Trading Cards", category: .collectibles, basePrice: 28, unlockLevel: .runner, icon: "rectangle.stack.fill", volatility: 0, riskTier: 3, fixedPrice: true, isCounterfeit: true, publicAlias: "First Edition Collector Cards"),
        ProductDef(id: "p_replica_earbuds", name: "Replica Wireless Earbuds", category: .audio, basePrice: 24, unlockLevel: .newcomer, icon: "earbuds", volatility: 0, riskTier: 2, fixedPrice: true, isCounterfeit: true, publicAlias: "Studio Wireless Earbuds")
    ]

    static let cryptocurrencies: [CryptoDef] = [
        CryptoDef(id: "BTC_RATE", name: "Bitcoin", symbol: "₿", initialPrice: 42000),
        CryptoDef(id: "SMP_RATE", name: "SMP300", symbol: "SMP", initialPrice: 320),
        CryptoDef(id: "ETH_RATE", name: "Ether", symbol: "Ξ", initialPrice: 2400),
        CryptoDef(id: "SOL_RATE", name: "Solana", symbol: "◎", initialPrice: 145),
        CryptoDef(id: "DOGE_RATE", name: "Dogecoin", symbol: "Ð", initialPrice: 0.16),
        CryptoDef(id: "LTC_RATE", name: "Litecoin", symbol: "Ł", initialPrice: 92),
        CryptoDef(id: "ADA_RATE", name: "Cardano", symbol: "₳", initialPrice: 0.44),
        CryptoDef(id: "AVAX_RATE", name: "Avalanche", symbol: "AVAX", initialPrice: 36),
        CryptoDef(id: "LINK_RATE", name: "Chainlink", symbol: "LINK", initialPrice: 14)
    ]

    static let suppliers: [SupplierDef] = [
        SupplierDef(id: "s_alley", name: "Alley Contacts", unlockLevel: .newcomer, repRequired: 0, productIDs: ["p_burner", "p_watch", "p_vinyl", "p_console"], discount: 0.0, icon: "figure.walk"),
        SupplierDef(id: "s_lowkey", name: "Lowkey Imports", unlockLevel: .runner, repRequired: 40, productIDs: ["p_herb", "p_cards", "p_comics", "p_firstpress"], discount: 0.05, icon: "shippingbox.fill"),
        SupplierDef(id: "s_midtier", name: "Midtier Logistics", unlockLevel: .reseller, repRequired: 150, productIDs: ["p_pills", "p_data", "p_headphones", "p_keyboard", "p_projector"], discount: 0.08, icon: "truck.box.fill"),
        SupplierDef(id: "s_backroom", name: "Backroom Network", unlockLevel: .dealer, repRequired: 350, productIDs: ["p_docs", "p_jewel", "p_bag", "p_archivecoat", "p_speakers"], discount: 0.1, icon: "lock.rectangle.stack.fill"),
        SupplierDef(id: "s_broker", name: "The Broker's Circle", unlockLevel: .broker, repRequired: 700, productIDs: ["p_art", "p_tech2"], discount: 0.12, icon: "person.3.fill"),
        SupplierDef(id: "s_vault", name: "Vault Connections", unlockLevel: .established, repRequired: 1200, productIDs: ["p_gold"], discount: 0.1, icon: "building.columns.fill"),
        SupplierDef(id: "s_offshore", name: "Offshore Channel", unlockLevel: .trusted, repRequired: 2000, productIDs: ["p_ledger"], discount: 0.15, icon: "globe"),
        SupplierDef(id: "s_shadow", name: "Shadow Syndicate", unlockLevel: .elite, repRequired: 3200, productIDs: ["p_chip", "p_collectorwatch"], discount: 0.18, icon: "crown.fill"),
        SupplierDef(id: "s_archive", name: "Archive House", unlockLevel: .broker, repRequired: 700, productIDs: ["p_rarebook", "p_sculpture", "p_artprint"], discount: 0.1, icon: "books.vertical.fill")
    ]

    static let npcs: [NPCDef] = [
        NPCDef(id: "n_marco", name: "Marco V.", avatarSymbol: "person.circle.fill", kind: .buyer, bio: "Buys anything shiny, pays fast.", baseRatingSeed: 4),
        NPCDef(id: "n_lena", name: "Lena K.", avatarSymbol: "person.crop.circle.fill", kind: .seller, bio: "Reliable herbal supplier from the east side.", baseRatingSeed: 5),
        NPCDef(id: "n_dre", name: "Dre", avatarSymbol: "person.crop.circle.badge.checkmark", kind: .buyer, bio: "Collector. Only wants rare stuff.", baseRatingSeed: 4),
        NPCDef(id: "n_ivy", name: "Ivy Chen", avatarSymbol: "person.crop.circle.fill.badge.plus", kind: .rival, bio: "Rival reseller. Watch your prices.", baseRatingSeed: 3),
        NPCDef(id: "n_omar", name: "Omar R.", avatarSymbol: "person.circle", kind: .seller, bio: "Tech sourcing, prototype gear.", baseRatingSeed: 4),
        NPCDef(id: "n_sasha", name: "Sasha B.", avatarSymbol: "person.crop.circle.badge.moon", kind: .buyer, bio: "High roller. Buys in bulk.", baseRatingSeed: 5),
        NPCDef(id: "n_the_broker", name: "The Broker", avatarSymbol: "person.crop.square.fill", kind: .seller, bio: "Only deals with trusted names.", baseRatingSeed: 5),
        NPCDef(id: "n_mina", name: "Mina R.", avatarSymbol: "person.crop.circle", kind: .buyer, bio: "Vintage finds and collectible records.", baseRatingSeed: 5),
        NPCDef(id: "n_jules", name: "Jules", avatarSymbol: "person.circle.fill", kind: .seller, bio: "Sneakers, cameras, and retro games.", baseRatingSeed: 4),
        NPCDef(id: "n_aria", name: "Aria S.", avatarSymbol: "person.crop.circle.fill", kind: .buyer, bio: "Curates a growing luxury collection.", baseRatingSeed: 5),
        NPCDef(id: "n_niko", name: "Niko", avatarSymbol: "person.circle", kind: .seller, bio: "Antiques and one-of-a-kind pieces.", baseRatingSeed: 4),
        NPCDef(id: "n_theo", name: "Theo Park", avatarSymbol: "person.crop.circle.fill", kind: .seller, bio: "Comic books, records, and pop-culture finds.", baseRatingSeed: 4),
        NPCDef(id: "n_priya", name: "Priya Shah", avatarSymbol: "person.crop.circle.fill", kind: .seller, bio: "Carefully tested audio and camera gear.", baseRatingSeed: 5),
        NPCDef(id: "n_mateo", name: "Mateo Cruz", avatarSymbol: "person.crop.circle.fill", kind: .seller, bio: "Archive fashion and rare accessories.", baseRatingSeed: 3),
        NPCDef(id: "n_yuna", name: "Yuna Ito", avatarSymbol: "person.crop.circle.fill", kind: .seller, bio: "Custom electronics sourced from local makers.", baseRatingSeed: 4),
        NPCDef(id: "n_ellis", name: "Ellis Moore", avatarSymbol: "person.crop.circle.fill", kind: .buyer, bio: "Looking for designer pieces and collector watches.", baseRatingSeed: 4),
        NPCDef(id: "n_noor", name: "Noor Ahmed", avatarSymbol: "person.crop.circle.fill", kind: .buyer, bio: "Avid reader and collector of first editions.", baseRatingSeed: 5),
        NPCDef(id: "n_finn", name: "Finn Taylor", avatarSymbol: "person.crop.circle.fill", kind: .buyer, bio: "Building a studio and audio collection.", baseRatingSeed: 3),
        NPCDef(id: "n_gabriel", name: "Gabriel Chen", avatarSymbol: "person.crop.circle.fill", kind: .buyer, bio: "Always interested in clever new technology.", baseRatingSeed: 4),
        NPCDef(id: "n_cassia", name: "Cassia Reed", avatarSymbol: "person.crop.circle.fill", kind: .rival, bio: "A sharp reseller who knows the latest market prices.", baseRatingSeed: 2),
        NPCDef(id: "n_reece", name: "Reece Vale", avatarSymbol: "person.crop.circle.badge.exclamationmark", kind: .seller, bio: "Replica goods at tempting prices. Quality varies.", baseRatingSeed: 2),
        NPCDef(id: "n_marlow", name: "Marlow Finch", avatarSymbol: "person.crop.circle.fill", kind: .buyer, bio: "Bargain hunter with an eye for fashion and watches.", baseRatingSeed: 3),
        NPCDef(id: "n_kez", name: "Kez Alvarez", avatarSymbol: "person.crop.circle.fill", kind: .buyer, bio: "Sneaker collector who buys in pairs and knows the market.", baseRatingSeed: 4),
        NPCDef(id: "n_soraya", name: "Soraya Bell", avatarSymbol: "person.crop.circle.fill", kind: .seller, bio: "Fashion accessories, fragrance, and seasonal stock.", baseRatingSeed: 4),
        NPCDef(id: "n_hugo", name: "Hugo Lin", avatarSymbol: "person.crop.circle.fill", kind: .buyer, bio: "Buys tested cameras, audio, and small tech.", baseRatingSeed: 5),
        NPCDef(id: "n_beck", name: "Beck Turner", avatarSymbol: "person.crop.circle.fill", kind: .seller, bio: "Cards, comics, and collector curiosities.", baseRatingSeed: 4),
        NPCDef(id: "n_amelia", name: "Amelia Cross", avatarSymbol: "person.crop.circle.fill", kind: .buyer, bio: "A careful buyer who checks provenance before paying.", baseRatingSeed: 5),
        NPCDef(id: "n_roman", name: "Roman Pike", avatarSymbol: "person.crop.circle.fill", kind: .seller, bio: "Small electronics and refurbished audio gear.", baseRatingSeed: 3),
        NPCDef(id: "n_tess", name: "Tess Morgan", avatarSymbol: "person.crop.circle.fill", kind: .buyer, bio: "Vintage book and vinyl collector.", baseRatingSeed: 4),
        NPCDef(id: "n_dorian", name: "Dorian Wells", avatarSymbol: "person.crop.circle.fill", kind: .rival, bio: "A patient trader who watches everyone's listings.", baseRatingSeed: 3)
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
        AchievementDef(id: "a_btc", title: "Off the Books", description: "Trade BTC for the first time.", icon: "bitcoinsign.circle.fill"),
        AchievementDef(id: "a_5_listings", title: "Shopfront", description: "Create five profile listings.", icon: "storefront.fill"),
        AchievementDef(id: "a_10_followers", title: "Rising Profile", description: "Build your network to 25 followers.", icon: "person.2.badge.plus.fill"),
        AchievementDef(id: "a_5_coins", title: "Altcoin Collector", description: "Buy a simulated coin besides Bitcoin.", icon: "bitcoinsign"),
        AchievementDef(id: "a_20k_profit", title: "Market Maker", description: "Reach $20,000 net worth.", icon: "chart.xyaxis.line"),
        AchievementDef(id: "a_5_contacts", title: "People Person", description: "Follow five contacts.", icon: "person.3.sequence.fill"),
        AchievementDef(id: "a_10_contacts", title: "Inner Circle", description: "Follow ten contacts.", icon: "person.3.fill"),
        AchievementDef(id: "a_5_products", title: "Collector’s Shelf", description: "Hold five different products at once.", icon: "square.grid.2x2.fill"),
        AchievementDef(id: "a_3_coins", title: "Market Basket", description: "Hold three different simulated cryptocurrencies.", icon: "chart.pie.fill"),
        AchievementDef(id: "a_referrals", title: "Word Gets Around", description: "Earn five customer referrals.", icon: "person.2.wave.2.fill"),
        AchievementDef(id: "a_trusted", title: "Trusted Seller", description: "Reach a 90 trust score.", icon: "checkmark.seal.fill"),
        AchievementDef(id: "a_streak_7", title: "Seven-Day Run", description: "Check in seven days in a row.", icon: "calendar.badge.checkmark"),
        AchievementDef(id: "a_counterfeit_clear", title: "Smooth Talker", description: "Pass a buyer's authenticity check.", icon: "eye.slash.fill"),
        AchievementDef(id: "a_storage_5", title: "Warehouse Upgrade", description: "Expand storage to level 5.", icon: "shippingbox.fill")
    ]

    static func product(_ id: String) -> ProductDef? { products.first { $0.id == id } }
    static func supplier(_ id: String) -> SupplierDef? { suppliers.first { $0.id == id } }
    static func npc(_ id: String) -> NPCDef? {
        if let known = npcs.first(where: { $0.id == id }) { return known }
        guard id.hasPrefix("n_generated_"), let index = Int(id.replacingOccurrences(of: "n_generated_", with: "")), index > 0 else { return nil }
        let firstNames = ["Riley", "Casey", "Morgan", "Taylor", "Jordan", "Avery", "Quinn", "Rowan", "Emery", "Skyler"]
        let surnames = ["Vale", "Park", "Reed", "Lane", "Hayes", "Blake", "Sage", "Wren", "Ellis", "Gray"]
        let name = "\(firstNames[(index - 1) % firstNames.count]) \(surnames[((index - 1) / firstNames.count) % surnames.count])\(index > 100 ? " \(index)" : "")"
        let kind: NPCKind = index.isMultiple(of: 2) ? .buyer : .seller
        let bio = kind == .buyer ? "New collector looking for good finds." : "Independent seller with fresh stock."
        return NPCDef(id: id, name: name, avatarSymbol: "person.crop.circle.fill", kind: kind, bio: bio, baseRatingSeed: 4)
    }
}
