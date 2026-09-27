import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var engine: GameEngine?
    @State private var showAdmin = false

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
                    BusinessView(engine: engine)
                        .tabItem { Label("Business", systemImage: "chart.bar.fill") }
                    ProfileView(engine: engine, showAdmin: $showAdmin)
                        .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                }
                .tint(.green)
                .sheet(isPresented: $showAdmin) {
                    AdminView(engine: engine)
                }
            } else {
                ProgressView()
                    .onAppear { setup() }
            }
        }
    }

    private func setup() {
        let e = GameEngine(context: modelContext)
        e.bootstrapIfNeeded()
        engine = e
    }
}
