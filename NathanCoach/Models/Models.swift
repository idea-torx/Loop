import Foundation
import SwiftUI

struct UserProfile {
    var displayName: String
    var goal: String
    var trainingLevel: String
    var preferredTone: String

    static let seed = UserProfile(
        displayName: "Leo",
        goal: "Break 170 — a sustainable fat-loss cut that preserves muscle.",
        trainingLevel: "Intermediate",
        preferredTone: "Warm, slightly wry, human"
    )
}

struct AppSettings {
    var notificationTone = "Human and encouraging"
    var gymDays = "Mon, Wed, Fri"
    var mealTiming = "Lunch around noon, dinner around 7"
    var storesMealPhotos = false
    var recoveryLinked = false
}

struct CoachMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let createdAt = Date()

    static let seed = [
        CoachMessage(
            role: .assistant,
            text: "Morning. I’ll keep this simple: weigh in, eat like you care about tomorrow, and we’ll get your lift handled. Tell me how you want today to feel."
        )
    ]
}

struct Conversation: Identifiable {
    let id = UUID()
    var title: String
    var messages: [CoachMessage]
    var createdAt = Date()
    var updatedAt = Date()

    var preview: String {
        messages.last?.text ?? "New conversation"
    }
}

struct DailyTask: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var systemImage: String
    var isComplete: Bool
    var completedAt: Date?
    var reminderTime: Date?

    /// Today at the given hour/minute — used for reminder scheduling defaults.
    static func time(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    static let seed = [
        DailyTask(title: "Morning weigh-in", detail: "Log weight before breakfast", systemImage: "scalemass.fill", isComplete: false, reminderTime: time(8, 45)),
        DailyTask(title: "Lunch check-in", detail: "Text or photo log", systemImage: "fork.knife", isComplete: false, reminderTime: time(12, 15)),
        DailyTask(title: "Dinner check-in", detail: "Keep it honest, not perfect", systemImage: "takeoutbag.and.cup.and.straw.fill", isComplete: false, reminderTime: time(17, 0)),
        DailyTask(title: "Workout", detail: "Today's lift — log your sets", systemImage: "figure.strengthtraining.traditional", isComplete: false, reminderTime: time(18, 30)),
        DailyTask(title: "Steps and recovery", detail: "Close the activity gap", systemImage: "figure.walk", isComplete: false, reminderTime: nil),
        DailyTask(title: "Evening review", detail: "One sentence about what worked", systemImage: "moon.stars.fill", isComplete: false, reminderTime: time(21, 0))
    ]
}

struct WeighIn: Identifiable {
    let id = UUID()
    let date: Date
    let pounds: Double

    // Break 170 cut: ~172.1 → 169.8 over the trailing two weeks, with daily water noise.
    static let seed: [WeighIn] = stride(from: 13, through: 0, by: -1).map { offset in
        WeighIn(
            date: Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date(),
            pounds: 172.14 - Double(13 - offset) * 0.18 + Double.random(in: -0.35...0.35)
        )
    }
}

struct MealLog: Identifiable {
    let id = UUID()
    let date: Date
    let title: String
    let calories: Int
    let protein: Int
    var imageData: Data?

    static let seed = [
        MealLog(date: Date(), title: "Greek yogurt, berries, protein coffee", calories: 430, protein: 42),
        MealLog(date: Date(), title: "Chicken bowl with rice", calories: 720, protein: 55)
    ]
}

struct WorkoutSession: Identifiable {
    let id = UUID()
    var date: Date
    var title: String
    var focus: String
    var sets: [ExerciseSet]
    var isComplete: Bool

    var volume: Int {
        sets.reduce(0) { $0 + ($1.reps * $1.weight) }
    }

    static let seed = [
        WorkoutSession(
            date: Date(),
            title: "Upper Strength",
            focus: "Press, pull, arms",
            sets: [
                ExerciseSet(exercise: "Bench Press", reps: 5, weight: 185),
                ExerciseSet(exercise: "Bench Press", reps: 5, weight: 185),
                ExerciseSet(exercise: "Row", reps: 8, weight: 145)
            ],
            isComplete: false
        )
    ]
}

struct ExerciseSet: Identifiable {
    let id = UUID()
    var exercise: String
    var reps: Int
    var weight: Int
}

struct WorkoutDayPlan: Identifiable {
    let id = UUID()
    var date: Date
    var title: String
    var focus: String
    var coachNotes: String
    var isTrainingDay: Bool
    var sets: [ExerciseSet]

    var dayName: String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    var dayNumber: String {
        date.formatted(.dateTime.day())
    }

    var volume: Int {
        sets.reduce(0) { $0 + ($1.reps * $1.weight) }
    }

    static let seed: [WorkoutDayPlan] = {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let templates = [
            ("Upper Strength", "Press, pull, arms", true),
            ("Steps + Mobility", "Easy movement and recovery", false),
            ("Lower Strength", "Squat pattern, hinge, core", true),
            ("Recovery Check", "Walk, stretch, sleep target", false),
            ("Full Body", "Compounds plus accessories", true),
            ("Conditioning", "Zone 2 or incline walk", true),
            ("Weekly Reset", "Review, prep, light movement", false)
        ]

        return templates.enumerated().map { index, template in
            WorkoutDayPlan(
                date: calendar.date(byAdding: .day, value: index, to: start) ?? start,
                title: template.0,
                focus: template.1,
                coachNotes: template.2 ? "Configured by the coach. Tell me what equipment, soreness, or schedule constraints changed." : "Keep this light unless the week needs a reshuffle.",
                isTrainingDay: template.2,
                sets: index == 0 ? WorkoutSession.seed[0].sets : []
            )
        }
    }()
}

struct HealthMetricSnapshot {
    var steps: Int
    var activeEnergy: Int
    var workoutsThisWeek: Int
    var healthKitStatus: String

    static let seed = HealthMetricSnapshot(
        steps: 6420,
        activeEnergy: 486,
        workoutsThisWeek: 2,
        healthKitStatus: "Not connected"
    )
}

struct WeeklyReview {
    var title: String
    var summary: String
    var suggestions: [String]

    static let seed = WeeklyReview(
        title: "This week’s lever",
        summary: "Consistency is forming. The biggest gap is dinner logging and getting the third lift done.",
        suggestions: [
            "Keep weigh-ins boring and automatic.",
            "Move gym nudges 45 minutes earlier on workdays.",
            "Anchor dinner around a protein first choice."
        ]
    )
}

enum CoachAppUpdate {
    case taskCompleted(keyword: String)
    case weighIn(Double)
    case meal(title: String, calories: Int, protein: Int)
    case notificationTone(String)
    case gymDays(String)
    case mealTiming(String)
    case workoutSet(exercise: String, reps: Int, weight: Int)
    case workoutPlan(title: String, focus: String, notes: String)
}

struct CoachResponse {
    var reply: String
    var updates: [CoachAppUpdate]
}
