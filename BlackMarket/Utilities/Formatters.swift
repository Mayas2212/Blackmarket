import Foundation

enum Formatters {
    static let usd: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    static let usdPrecise: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    static func money(_ value: Double) -> String {
        usd.string(from: NSNumber(value: value)) ?? "$0"
    }

    static func moneyPrecise(_ value: Double) -> String {
        usdPrecise.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    static func btc(_ value: Double) -> String {
        String(format: "%.5f BTC", value)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    static func compactDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }
}
