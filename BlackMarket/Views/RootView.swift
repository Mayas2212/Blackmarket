import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var engine: GameEngine?
    @State private var showAdmin = false
    @AppStorage("blackmarket.accent") private var accent = "green"
    @AppStorage("blackmarket.darkMode") private var darkMode = false

    var body: some View {
        Group {
            if let engine {
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
                .tint(accentColor)
                .preferredColorScheme(darkMode ? .dark : .light)
                .sheet(isPresented: $showAdmin) {
                    AdminView(engine: engine)
                }
            } else {
                ProgressView()
                    .onAppear { setup() }
            }
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
