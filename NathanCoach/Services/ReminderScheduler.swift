import Foundation
import UserNotifications

@MainActor
final class ReminderScheduler {
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func scheduleDailyNudges(tone: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ReminderRule.defaultRules.map(\.id))

        for rule in ReminderRule.defaultRules {
            var date = DateComponents()
            date.hour = rule.hour
            date.minute = rule.minute

            let content = UNMutableNotificationContent()
            content.title = rule.title
            content.body = rule.body(tone)
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: rule.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}

struct ReminderRule: Sendable {
    let id: String
    let title: String
    let hour: Int
    let minute: Int
    let body: @Sendable (String) -> String

    static let defaultRules = [
        ReminderRule(id: "weigh-in", title: "Quick weigh-in", hour: 7, minute: 30) { _ in
            "Two minutes. Step on, log it, move on."
        },
        ReminderRule(id: "lunch", title: "Lunch check", hour: 12, minute: 15) { tone in
            "Protein first. Send a note or photo and I’ll keep the day calibrated. Tone: \(tone)."
        },
        ReminderRule(id: "gym", title: "Gym window", hour: 17, minute: 30) { _ in
            "The plan is waiting. Tell me what equipment is open if we need to adapt."
        },
        ReminderRule(id: "weekly-review", title: "Weekly review", hour: 19, minute: 0) { _ in
            "Let’s look at the trend, keep what worked, and choose next week’s lever."
        }
    ]
}
