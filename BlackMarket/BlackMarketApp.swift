import SwiftUI
import SwiftData

@main
struct BlackMarketApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PlayerState.self,
            InventoryItem.self,
            ListingItem.self,
            TransactionRecord.self,
            FollowedNPC.self,
            ReviewRecord.self,
            MessageRecord.self,
            ActiveMarketEvent.self,
            PriceOverride.self,
            PriceSnapshot.self,
            CryptoHolding.self,
            NPCStockItem.self,
            ShippingOrder.self,
            AchievementRecord.self,
            DailyObjective.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
