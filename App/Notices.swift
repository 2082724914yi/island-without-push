import Foundation
import UIKit
import UserNotifications

/// Local notifications standing in for push. Without APNs these can only come while the App is still
/// running in the background (standby): the poll brings the server's new messages, and this turns
/// the ones the user has not been told about into a notification. Nothing is shown while the App is
/// open; ids are remembered so a message is never posted twice.
final class Notices: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notices()

    private static let askedKey = "notifications.asked.v1"
    private static let toldKey = "notifications.told.v1"

    /// Ids already turned into a notification (or seen in the App); nil until the first poll answered.
    private var told: [String]? = UserDefaults.standard.stringArray(forKey: Notices.toldKey)

    /// Called from the App's init, so a tap that launches the App still reaches the delegate.
    func setUp() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Once, on first launch: alert, sound and badge.
    func requestOnce() {
        guard !UserDefaults.standard.bool(forKey: Self.askedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.askedKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func clearBadge() {
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    // MARK: from the poll (main thread)

    /// Returns the messages that are new to this phone (posted when in the background).
    @discardableResult
    func handle(messages: [Message]?, foreground: Bool) -> [Message] {
        let items = messages ?? []
        let ids = items.map(\.id)
        guard var known = told else {
            // First answer after installing: what is already there is old news, not a burst of banners.
            told = ids
            UserDefaults.standard.set(ids, forKey: Self.toldKey)
            return []
        }
        var fresh: [Message] = []
        for item in items where !known.contains(item.id) {
            known.append(item.id)
            fresh.append(item)
            if !foreground { post(item, badge: items.count) }
        }
        if known.count > 200 { known.removeFirst(known.count - 200) }
        told = known
        UserDefaults.standard.set(known, forKey: Self.toldKey)
        return fresh
    }

    private func post(_ item: Message, badge: Int) {
        let content = UNMutableNotificationContent()
        if let title = item.title, !title.isEmpty { content.title = String(title.prefix(24)) }
        content.body = String(item.text.prefix(80))
        content.sound = .default
        content.badge = NSNumber(value: badge)
        let request = UNNotificationRequest(identifier: "poll." + item.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])          // the App is open: no banner
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // A tap just opens the App. Route to a screen here if you have more than one.
        completionHandler()
    }
}
