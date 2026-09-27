import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine: GameEngine?
    @State private var showAdmin = false
    @AppStorage("blackmarket.accent") private var accent = "green"
    @AppStorage("blackmarket.darkMode") private var darkMode = false

    var body: some View {
        Group {
            if let engine {
                tabBar
                    .tint(accentColor)
                    .preferredColorScheme(darkMode ? .dark : .light)
                    .sheet(isPresented: $showAdmin) {
                        AdminView(engine: engine)
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { engine.simulateMarketTick() }
                    }
            } else {
                ProgressView()
                    .onAppear { setup() }
            }
        }
    }

    private var tabBar: some View {
        Group {
            if #available(iOS 26.0, *) {
                tabs.tabBarMinimizeBehavior(.onScrollDown)
            } else {
                tabs
            }
        }
    }

    private var tabs: some View {
        TabView {
            HomeView(engine: engine)
                .tabItem { Label("Home", systemImage: "house.fill") }
            MarketView(engine: engine)
                .tabItem { Label("Market", systemImage: "cart.fill") }
            NetworkView(engine: engine)
                .tabItem { Label("Network", systemImage: "person.2.fill") }
            MessagesView(engine: engine)
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right.fill") }
            BusinessView(engine: engine)
                .tabItem { Label("Business", systemImage: "chart.bar.fill") }
            ProfileView(engine: engine, showAdmin: $showAdmin)
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
    }

    private var accentColor: Color {
        switch accent {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        default: return .green
        }
    }

    private func setup() {
        let e = GameEngine(context: modelContext)
        e.bootstrapIfNeeded()
        engine = e
    }
}
