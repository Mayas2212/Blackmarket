import Foundation
import UserNotifications

enum MessageNotifications {
    private static let center = UNUserNotificationCenter.current()

    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(npcName: String, text: String, at date: Date, identifier: String) {
        guard UserDefaults.standard.bool(forKey: "blackmarket.buyerNotifications"), date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = npcName
        content.body = text
        content.sound = (UserDefaults.standard.object(forKey: "blackmarket.messageSounds") as? Bool ?? true) ? .default : nil
        let seconds = max(1, date.timeIntervalSinceNow)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        Task { try? await center.add(request) }
    }

    static func cancelPending() {
        center.removeAllPendingNotificationRequests()
    }

    static func cancel(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
