import SwiftUI

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}

struct StatPill: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = .green

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct LevelBadge: View {
    let level: SellerLevel
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.icon)
            Text(level.title)
        }
        .font(.caption.bold())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.green.opacity(0.15))
        .foregroundStyle(.green)
        .clipShape(Capsule())
    }
}

struct TrendArrow: View {
    let trend: Double
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
            Text(Formatters.percent(abs(trend) * 100))
        }
        .font(.caption.bold())
        .foregroundStyle(trend >= 0 ? .green : .red)
    }
}
