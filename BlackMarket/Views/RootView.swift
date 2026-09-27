import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine: GameEngine?
    @State private var showAdmin = false
    @State private var selectedTab = 0
    @AppStorage("blackmarket.accent") private var accent = "green"
    @AppStorage("blackmarket.darkMode") private var darkMode = false

    var body: some View {
        Group {
            if let engine {
                ZStack {
                    currentScreen
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 77).accessibilityHidden(true) }
                    VStack {
                        Spacer()
                        FloatingGlassTabBar(selection: $selectedTab, tint: accentColor)
                    }
                    .ignoresSafeArea(.keyboard)
                }
                    .preferredColorScheme(darkMode ? .dark : .light)
                    .sheet(isPresented: $showAdmin) {
                        AdminView(engine: engine)
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background {
                            UserDefaults.standard.set(Date.now, forKey: "blackmarket.lastBackgroundAt")
                        } else if phase == .active {
                            engine.simulateMarketTick()
                        }
                    }
            } else {
                ProgressView()
                    .onAppear { setup() }
            }
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch selectedTab {
        case 0: HomeView(engine: engine!)
        case 1: MarketView(engine: engine!)
        case 2: NetworkView(engine: engine!)
        case 3: MessagesView(engine: engine!)
        case 4: BusinessView(engine: engine!)
        default: ProfileView(engine: engine!, showAdmin: $showAdmin)
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

private struct FloatingGlassTabBar: View {
    @Binding var selection: Int
    let tint: Color
    private let tabs: [(title: String, icon: String)] = [
        ("Home", "house.fill"), ("Market", "cart.fill"), ("Network", "person.2.fill"),
        ("Messages", "bubble.left.and.bubble.right.fill"), ("Business", "chart.bar.fill"), ("Profile", "person.crop.circle.fill")
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs.indices, id: \.self) { index in
                let tab = tabs[index]
                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { selection = index } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 18, weight: .semibold))
                        Text(tab.title).font(.system(size: 9, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(selection == index ? tint : .gray)
                    .frame(maxWidth: .infinity).frame(height: 47)
                    .background {
                        if selection == index {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(tint.opacity(0.13)).padding(.horizontal, 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 9)
        .background {
            let shape = RoundedRectangle(cornerRadius: 27, style: .continuous)
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.white.opacity(0.15))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.13), .black.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 7)
    }
}
