import Foundation
import UserNotifications

@MainActor
final class ReminderScheduler {
    func authorizationStatus() async -> (isOn: Bool, label: String) {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return (true, "Daily nudges enabled")
        case .denied:
            return (false, "Denied in iOS Settings")
        case .notDetermined:
            return (false, "Not requested")
        @unknown default:
            return (false, "Unknown")
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    /// Schedule a repeating daily reminder for each task that has a time set.
    /// Best-effort: silently no-ops if notifications aren't authorized.
    func scheduleTaskReminders(_ tasks: [DailyTask], tone: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let taskIDs = pending.map(\.identifier).filter { $0.hasPrefix("task-") }
        center.removePendingNotificationRequests(withIdentifiers: taskIDs)

        let calendar = Calendar.current
        for task in tasks {
            guard let time = task.reminderTime else { continue }
            var date = DateComponents()
            date.hour = calendar.component(.hour, from: time)
            date.minute = calendar.component(.minute, from: time)

            let content = UNMutableNotificationContent()
            content.title = Self.publicNotificationText(task.title, fallback: "Reminder")
            content.body = Self.publicNotificationText(
                task.detail,
                fallback: Self.defaultBody(for: task.title)
            )
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: "task-\(task.id.uuidString)", content: content, trigger: trigger)
            try? await center.add(request)
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
            content.title = Self.publicNotificationText(rule.title, fallback: "Loop")
            content.body = Self.publicNotificationText(rule.body(), fallback: "Quick check-in when you have a second.")
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: rule.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    private static func defaultBody(for title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("lunch") || lower.contains("dinner") || lower.contains("meal") {
            return "Protein first. Send a note or photo when you’re ready."
        }
        if lower.contains("weigh") || lower.contains("weight") {
            return "Step on, log it, move on."
        }
        if lower.contains("workout") || lower.contains("gym") || lower.contains("lift") {
            return "Log the session as you go."
        }
        return "Time to check this off, Leo."
    }

    private static func publicNotificationText(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        let patterns = [
            #"(?i)\s*tone\s*:\s*[^.\n]*(?:[.\n]|$)"#,
            #"(?i)\s*voice\s*tone\s*:\s*[^.\n]*(?:[.\n]|$)"#,
            #"(?i)\s*style\s*:\s*[^.\n]*(?:[.\n]|$)"#,
            #"(?i)\s*system\s*prompt\s*:\s*[^.\n]*(?:[.\n]|$)"#,
            #"(?i)\s*internal\s*(?:note|instruction|thinking)\s*:\s*[^.\n]*(?:[.\n]|$)"#
        ]

        let cleaned = patterns.reduce(trimmed) { partial, pattern in
            partial.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? fallback : cleaned
    }
}

struct ReminderRule: Sendable {
    let id: String
    let title: String
    let hour: Int
    let minute: Int
    let body: @Sendable () -> String

    static let defaultRules = [
        ReminderRule(id: "weigh-in", title: "Quick weigh-in", hour: 8, minute: 15) {
            "Two minutes. Step on, log it, move on."
        },
        ReminderRule(id: "lunch", title: "Lunch check", hour: 12, minute: 15) {
            "Protein first. Send a note or photo and I’ll keep the day calibrated."
        },
        ReminderRule(id: "gym", title: "Gym window", hour: 17, minute: 30) {
            "The plan is waiting. Tell me what equipment is open if we need to adapt."
        },
        ReminderRule(id: "weekly-review", title: "Weekly review", hour: 19, minute: 0) {
            "Let’s look at the trend, keep what worked, and choose next week’s lever."
        }
    ]
}
