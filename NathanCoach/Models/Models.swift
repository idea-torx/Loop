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
    var cloudID: String? = nil
    let role: Role
    let text: String
    var createdAt = Date()

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
    var cloudID: String? = nil
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
        DailyTask(title: "Morning weigh-in", detail: "Log weight before breakfast", systemImage: "scalemass.fill", isComplete: false, reminderTime: time(8, 15)),
        DailyTask(title: "Lunch check-in", detail: "Text or photo log", systemImage: "fork.knife", isComplete: false, reminderTime: time(12, 15)),
        DailyTask(title: "Dinner check-in", detail: "Keep it honest, not perfect", systemImage: "takeoutbag.and.cup.and.straw.fill", isComplete: false, reminderTime: time(17, 0)),
        DailyTask(title: "Workout", detail: "Today's lift — log your sets", systemImage: "figure.strengthtraining.traditional", isComplete: false, reminderTime: time(18, 30)),
        DailyTask(title: "Steps and recovery", detail: "Close the activity gap", systemImage: "figure.walk", isComplete: false, reminderTime: nil),
        DailyTask(title: "Evening review", detail: "One sentence about what worked", systemImage: "moon.stars.fill", isComplete: false, reminderTime: time(21, 0))
    ]
}

struct WeighIn: Identifiable {
    let id = UUID()
    var cloudID: String? = nil
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
    var cloudID: String? = nil
    let date: Date
    var title: String
    var calories: Int
    var protein: Int
    var imageData: Data?

    static let seed: [MealLog] = []
}

struct MealClarification: Identifiable {
    let id = UUID()
    let question: String
    let options: [String]
}

struct WorkoutSession: Identifiable {
    let id = UUID()
    var cloudID: String? = nil
    var date: Date
    var title: String
    var focus: String
    var coachNotes: String = ""
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
    var cloudID: String? = nil
    var exercise: String
    var normalizedExercise: String? = nil
    var category: String? = nil
    var reps: Int
    var weight: Int
    var targetMinReps: Int? = nil
    var targetMaxReps: Int? = nil
    var rir: Int? = nil
}

struct WorkoutDayPlan: Identifiable {
    let id = UUID()
    var cloudID: String? = nil
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
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let templates = [
            (
                "Push",
                "Zones: chest, shoulders, triceps",
                "Push day: press patterns first, then shoulder and triceps accessories. First push exposure of the week.",
                true
            ),
            (
                "Pull",
                "Zones: back, lats, rear delts, biceps",
                "Pull day: rows, vertical pulls, rear delts, and curls. First pull exposure of the week.",
                true
            ),
            (
                "Legs + Abs",
                "Zones: quads, hamstrings, glutes, calves, core",
                "Leg day also carries abs: reverse crunches and rope cable crunches. Keep bracing crisp and prioritize hypertrophy work.",
                true
            ),
            (
                "Push",
                "Zones: chest, shoulders, triceps",
                "Second push exposure. Keep pressing quality high, then finish with shoulders and triceps.",
                true
            ),
            (
                "Pull",
                "Zones: back, lats, rear delts, biceps",
                "Second pull exposure. Rows, lats, rear delts, and curls.",
                true
            ),
            (
                "Legs + Abs",
                "Zones: quads, hamstrings, glutes, calves, core",
                "Second leg exposure. Abs reminders: reverse crunches and rope cable crunches.",
                true
            ),
            (
                "Big Cardio",
                "Zones: aerobic base, legs, lungs, recovery capacity",
                "Sunday is the big cardio day: bike, hike, or run. Keep it sustainable and make it count.",
                true
            )
        ]

        return templates.enumerated().map { index, template in
            WorkoutDayPlan(
                date: calendar.date(byAdding: .day, value: index, to: start) ?? start,
                title: template.0,
                focus: template.1,
                coachNotes: template.2,
                isTrainingDay: template.3,
                sets: []
            )
        }
    }()
}

struct HealthMetricSnapshot {
    var steps: Int
    var activeEnergy: Int
    var workoutsToday: Int
    var workoutsThisWeek: Int
    var healthKitStatus: String
    var sleepMinutes: Int? = nil
    var sleepDeltaVs30d: Int? = nil
    var hrvMilliseconds: Double? = nil
    var hrvDeltaVs30d: Double? = nil
    var restingHeartRate: Double? = nil
    var restingHeartRateDeltaVs30d: Double? = nil
    var respiratoryRate: Double? = nil
    var respiratoryRateDeltaVs30d: Double? = nil
    var exerciseMinutes: Int? = nil
    var standHours: Int? = nil
    var movePercent: Double? = nil

    static let seed = HealthMetricSnapshot(
        steps: 0,
        activeEnergy: 0,
        workoutsToday: 0,
        workoutsThisWeek: 0,
        healthKitStatus: "Not connected"
    )
}

struct DailyMetricSnapshot: Identifiable {
    let id = UUID()
    var cloudID: String? = nil
    var date: Date
    var steps: Int
    var activeEnergy: Int
    var workoutsCount: Int
    var taskCompletionRate: Double?
}

struct TodayEnergySnapshot {
    var score: Int
    var label: String
    var confidence: Double
    var primaryDriver: String
    var secondaryDrivers: [String]
    var bestMove: String
    var expandedExplanation: String

    static let seed = TodayEnergySnapshot(
        score: 64,
        label: "Stable",
        confidence: 0.35,
        primaryDriver: "Waiting on live Apple Health data.",
        secondaryDrivers: ["Loop can still use meals, tasks, workouts, steps, and active calories."],
        bestMove: "Start with the next obvious habit and keep intensity controlled.",
        expandedExplanation: "Today’s Energy will sharpen as HealthKit and logged data come in."
    )
}

struct BodyProfile {
    var heightInches: Double?
    var weightSource: String
    var leanMassPounds: Double?
    var rmrEstimate: Int
    var rmrSource: String

    static let seed = BodyProfile(
        heightInches: nil,
        weightSource: "Latest weigh-in",
        leanMassPounds: nil,
        rmrEstimate: 1_800,
        rmrSource: "Manual estimate"
    )
}

struct GoalPlan: Identifiable {
    let id = UUID()
    var cloudID: String? = nil
    var title: String
    var type: String
    var startDate: Date
    var endDate: Date
    var startWeight: Double
    var targetLossPercent: Double
    var targetWeight: Double
    var activeCalorieMin: Int
    var activeCalorieMax: Int
    var calorieTarget: Int
    var proteinTarget: Int
    var status: String
    var bodyProfile: BodyProfile

    static func defaultCut(startWeight: Double, startDate: Date = Date()) -> GoalPlan {
        let calendar = Calendar.current
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)) ?? calendar.date(byAdding: .day, value: 63, to: startDate) ?? startDate
        let targetLoss = 0.10
        return GoalPlan(
            title: "Cut to September 1",
            type: "cut",
            startDate: calendar.startOfDay(for: startDate),
            endDate: end,
            startWeight: startWeight,
            targetLossPercent: targetLoss,
            targetWeight: startWeight * (1 - targetLoss),
            activeCalorieMin: 800,
            activeCalorieMax: 1_000,
            calorieTarget: PTProtocol.calorieTarget,
            proteinTarget: PTProtocol.proteinTargetG,
            status: "active",
            bodyProfile: .seed
        )
    }
}

struct GoalProgress {
    var daysElapsed: Int
    var daysRemaining: Int
    var totalDays: Int
    var currentTrendWeight: Double?
    var expectedWeightToday: Double
    var targetWeight: Double
    var poundsLost: Double
    var poundsRemaining: Double
    var paceStatus: String
    var paceSummary: String
    var sevenDayCaloriesAverage: Int?
    var sevenDayProteinAverage: Int?
    var sevenDayActiveCaloriesAverage: Int?
    var estimatedDailyBurn: Int
    var estimatedDailyDeficit: Int?
    var deficitConfidence: String
    var activeCalorieProgress: Double
    var timelineProgress: Double

    static let seed = GoalProgress(
        daysElapsed: 0,
        daysRemaining: 0,
        totalDays: 1,
        currentTrendWeight: nil,
        expectedWeightToday: 0,
        targetWeight: 0,
        poundsLost: 0,
        poundsRemaining: 0,
        paceStatus: "Setup",
        paceSummary: "Set up the cut goal to start tracking pace.",
        sevenDayCaloriesAverage: nil,
        sevenDayProteinAverage: nil,
        sevenDayActiveCaloriesAverage: nil,
        estimatedDailyBurn: 1_800,
        estimatedDailyDeficit: nil,
        deficitConfidence: "low",
        activeCalorieProgress: 0,
        timelineProgress: 0
    )
}

struct GoalInsight {
    var summary: String
    var suggestions: [String]

    static let seed = GoalInsight(
        summary: "Loop will compare your weight trend, active calories, and logged food against the cut goal as data comes in.",
        suggestions: ["Keep weigh-ins consistent.", "Hit the active calorie range most days.", "Log meals enough to make deficit math useful."]
    )
}

struct DailyCoachSnapshot {
    var updateWindow: String
    var recommendationType: String
    var coachRead: String
    var evidence: [String]
    var bestNextMove: String
    var habitFocus: String
    var avoid: [String]
    var coachCue: String

    static let seed = DailyCoachSnapshot(
        updateWindow: "morning",
        recommendationType: "maintain",
        coachRead: "Loop is waiting for today’s signal.",
        evidence: ["HealthKit and your logs will tighten this read as the day unfolds."],
        bestNextMove: "Hit the first scheduled habit and keep the loop moving.",
        habitFocus: "Morning weigh-in",
        avoid: [],
        coachCue: "Small start, clean day."
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
    case mealUpdate(id: String?, keyword: String?, title: String?, calories: Int?, protein: Int?)
    case mealDelete(id: String?, keyword: String?)
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
