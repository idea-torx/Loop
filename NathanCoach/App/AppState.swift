import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var profile = UserProfile.seed
    @Published var conversations: [Conversation] = []
    @Published var activeConversationID: Conversation.ID?
    @Published var tasks: [DailyTask] = DailyTask.seed

    /// Active conversation's messages, bridged so existing call sites keep working.
    var messages: [CoachMessage] {
        get { activeConversation?.messages ?? [] }
        set {
            guard let id = activeConversationID ?? conversations.first?.id,
                  let index = conversations.firstIndex(where: { $0.id == id }) else { return }
            conversations[index].messages = newValue
            conversations[index].updatedAt = Date()
        }
    }

    var activeConversation: Conversation? {
        conversations.first { $0.id == activeConversationID } ?? conversations.first
    }
    @Published var workouts: [WorkoutSession] = WorkoutSession.seed
    @Published var workoutSchedule: [WorkoutDayPlan] = WorkoutDayPlan.seed
    @Published var selectedWorkoutDayID: WorkoutDayPlan.ID?
    @Published var weighIns: [WeighIn] = WeighIn.seed
    @Published var meals: [MealLog] = MealLog.seed
    @Published var healthMetrics = HealthMetricSnapshot.seed
    @Published var weeklyReview = WeeklyReview.seed
    @Published var settings = AppSettings()
    @Published var isOnboardingComplete = false

    let coachService = CoachService()
    let reminderScheduler = ReminderScheduler()
    let healthKitService = HealthKitService()
    let metricsService = MetricsService()
    let gateway = SupabaseGateway()

    func bootstrap() {
        if conversations.isEmpty {
            startNewConversation()
        }
        if selectedWorkoutDayID == nil {
            selectedWorkoutDayID = workoutSchedule.first?.id
        }
    }

    /// Open a fresh chat, leading with a time-of-day briefing grounded in the Break 170 protocol.
    func startNewConversation() {
        let convo = Conversation(
            title: "New chat",
            messages: [CoachMessage(role: .assistant, text: CoachBriefing.opening())]
        )
        conversations.insert(convo, at: 0)
        activeConversationID = convo.id
    }

    func selectConversation(_ conversation: Conversation) {
        activeConversationID = conversation.id
    }

    private func setTitleIfNeeded(from text: String) {
        guard let id = activeConversationID,
              let index = conversations.firstIndex(where: { $0.id == id }),
              conversations[index].title == "New chat" else { return }
        conversations[index].title = String(text.prefix(42))
    }

    var selectedWorkoutDay: WorkoutDayPlan? {
        let selectedID = selectedWorkoutDayID ?? workoutSchedule.first?.id
        return workoutSchedule.first(where: { $0.id == selectedID }) ?? workoutSchedule.first
    }

    func selectWorkoutDay(_ day: WorkoutDayPlan) {
        selectedWorkoutDayID = day.id
    }

    func toggleTask(_ task: DailyTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isComplete.toggle()
        tasks[index].completedAt = tasks[index].isComplete ? Date() : nil
    }

    func sendCoachMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(CoachMessage(role: .user, text: trimmed))
        setTitleIfNeeded(from: trimmed)
        let response = await coachService.respond(to: trimmed, state: self)
        apply(response)
    }

    func sendWorkoutMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(CoachMessage(role: .user, text: "Workout: \(trimmed)"))
        let response = await coachService.respondToWorkoutLog(trimmed, state: self)
        apply(response)
    }

    func sendWorkoutConfigurationMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let dayLabel = selectedWorkoutDay?.dayName ?? "selected day"
        messages.append(CoachMessage(role: .user, text: "Configure \(dayLabel): \(trimmed)"))
        let response = await coachService.configureWorkoutDay(trimmed, state: self)
        apply(response)
    }

    func apply(_ response: CoachResponse) {
        messages.append(CoachMessage(role: .assistant, text: response.reply))

        for update in response.updates {
            switch update {
            case .taskCompleted(let keyword):
                if let index = tasks.firstIndex(where: { $0.title.localizedCaseInsensitiveContains(keyword) }) {
                    tasks[index].isComplete = true
                    tasks[index].completedAt = Date()
                }
            case .weighIn(let value):
                weighIns.append(WeighIn(date: Date(), pounds: value))
            case .meal(let title, let calories, let protein):
                meals.append(MealLog(date: Date(), title: title, calories: calories, protein: protein))
            case .notificationTone(let tone):
                settings.notificationTone = tone
            case .gymDays(let days):
                settings.gymDays = days
            case .mealTiming(let timing):
                settings.mealTiming = timing
            case .workoutSet(let exercise, let reps, let weight):
                addSet(exercise: exercise, reps: reps, weight: weight)
            case .workoutPlan(let title, let focus, let notes):
                updateSelectedWorkoutPlan(title: title, focus: focus, notes: notes)
            }
        }

        weeklyReview = metricsService.makeWeeklyReview(
            tasks: tasks,
            weighIns: weighIns,
            meals: meals,
            workouts: workouts,
            health: healthMetrics
        )
    }

    func addSet(exercise: String, reps: Int, weight: Int) {
        guard var session = workouts.first else { return }
        session.sets.append(ExerciseSet(exercise: exercise, reps: reps, weight: weight))
        workouts[0] = session

        guard
            let selectedID = selectedWorkoutDayID ?? workoutSchedule.first?.id,
            let index = workoutSchedule.firstIndex(where: { $0.id == selectedID })
        else { return }
        workoutSchedule[index].sets.append(ExerciseSet(exercise: exercise, reps: reps, weight: weight))
    }

    private func updateSelectedWorkoutPlan(title: String, focus: String, notes: String) {
        guard
            let selectedID = selectedWorkoutDayID ?? workoutSchedule.first?.id,
            let index = workoutSchedule.firstIndex(where: { $0.id == selectedID })
        else { return }

        workoutSchedule[index].title = title
        workoutSchedule[index].focus = focus
        workoutSchedule[index].coachNotes = notes
        workoutSchedule[index].isTrainingDay = true
    }
}
