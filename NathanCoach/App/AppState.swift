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

    private var session: SupabaseSession?

    /// Ensure a valid anonymous Supabase session, restoring/refreshing across launches.
    /// Returns nil when the backend isn't configured (app stays in local mode).
    @discardableResult
    func ensureSession() async -> SupabaseSession? {
        guard let base = gateway.configuration.projectURL,
              let key = gateway.configuration.anonKey, !key.isEmpty else { return nil }

        if let current = session, current.expiresAt > Date() { return current }

        if let stored = UserDefaults.standard.string(forKey: "sb_refresh_token"),
           let refreshed = await SupabaseGateway.refresh(base: base, anonKey: key, refreshToken: stored) {
            store(refreshed)
            return refreshed
        }
        if let fresh = await SupabaseGateway.signInAnonymously(base: base, anonKey: key) {
            store(fresh)
            return fresh
        }
        return nil
    }

    private func store(_ newSession: SupabaseSession) {
        session = newSession
        UserDefaults.standard.set(newSession.refreshToken, forKey: "sb_refresh_token")
        UserDefaults.standard.set(newSession.userID, forKey: "sb_user_id")
    }

    func bootstrap() {
        gateway.loadConfiguration()
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

    // MARK: Editable reminders

    func upsertTask(_ task: DailyTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        rescheduleReminders()
    }

    func updateTask(_ task: DailyTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        rescheduleReminders()
    }

    func deleteTask(_ task: DailyTask) {
        tasks.removeAll { $0.id == task.id }
        rescheduleReminders()
    }

    func rescheduleReminders() {
        let snapshot = tasks
        Task { await reminderScheduler.scheduleTaskReminders(snapshot, tone: settings.notificationTone) }
    }

    // MARK: Meals

    func logMeal(title: String, calories: Int, protein: Int, imageData: Data?) {
        meals.append(MealLog(date: Date(), title: title, calories: calories, protein: protein, imageData: imageData))
    }

    var todaysMeals: [MealLog] {
        meals.filter { Calendar.current.isDateInToday($0.date) }
    }

    var caloriesToday: Int { todaysMeals.reduce(0) { $0 + $1.calories } }
    var proteinToday: Int { todaysMeals.reduce(0) { $0 + $1.protein } }

    func sendCoachMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(CoachMessage(role: .user, text: trimmed))
        setTitleIfNeeded(from: trimmed)

        // Conversational reminder management.
        if let command = CommandParser.reminderCommand(from: trimmed) {
            let reply = applyReminderCommand(command)
            messages.append(CoachMessage(role: .assistant, text: reply))
            return
        }

        // Conversational meal logging — macros evaluated by Haiku.
        if let description = CommandParser.mealLog(from: trimmed) {
            let macros = await logMealWithHaiku(description: description, imageData: nil)
            if let keyword = CommandParser.mealKeyword(in: trimmed) {
                completeTask(matching: keyword)
            }
            let reply = "Logged: \(macros.title) — \(macros.calories) cal, \(macros.protein)g protein. "
                + "That puts you at \(proteinToday)g protein today (target \(PTProtocol.proteinTargetG)g)."
            messages.append(CoachMessage(role: .assistant, text: reply))
            return
        }

        let response = await coachService.respond(to: trimmed, state: self)
        apply(response)
    }

    // MARK: Conversational actions

    /// Evaluate macros via the Haiku Edge Function (falling back to a local estimate), then log the meal.
    @discardableResult
    func logMealWithHaiku(description: String, imageData: Data?) async -> MealMacros {
        var macros: MealMacros?
        if let creds = await ensureSession(),
           let base = gateway.configuration.projectURL,
           let key = gateway.configuration.anonKey {
            macros = await SupabaseGateway.analyzeMeal(base: base, anonKey: key, token: creds.accessToken, description: description, imageData: imageData)
        }
        let resolved = macros ?? localMealEstimate(description: description)
        logMeal(title: resolved.title, calories: resolved.calories, protein: resolved.protein, imageData: imageData)
        return resolved
    }

    private func localMealEstimate(description: String) -> MealMacros {
        // Offline fallback when the backend isn't configured.
        let title = description.split(separator: ",").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? "Meal"
        return MealMacros(title: title.isEmpty ? "Meal" : title, calories: 550, protein: 45)
    }

    private func completeTask(matching keyword: String) {
        if let index = taskIndex(matching: keyword) {
            tasks[index].isComplete = true
            tasks[index].completedAt = Date()
        }
    }

    /// Fuzzy, hyphen-insensitive task lookup: every keyword word must appear in the title.
    private func taskIndex(matching keyword: String) -> Int? {
        let needles = keyword.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 }
        guard !needles.isEmpty else { return nil }
        return tasks.firstIndex { task in
            let hay = task.title.lowercased().replacingOccurrences(of: "-", with: " ")
            return needles.allSatisfy { hay.contains($0) }
        }
    }

    private func applyReminderCommand(_ command: CommandParser.ReminderCommand) -> String {
        switch command {
        case .add(let title, let time):
            let task = DailyTask(title: title, detail: "Added via coach", systemImage: "bell.fill", isComplete: false, reminderTime: time)
            tasks.append(task)
            rescheduleReminders()
            if let time {
                return "Added \"\(title)\" at \(time.formatted(date: .omitted, time: .shortened))."
            }
            return "Added \"\(title)\" to today's list."

        case .move(let keyword, let time):
            guard let index = taskIndex(matching: keyword) else {
                return "I couldn't find a reminder matching \"\(keyword)\". Try the exact name from Today."
            }
            tasks[index].reminderTime = time
            rescheduleReminders()
            return "Moved \(tasks[index].title) to \(time.formatted(date: .omitted, time: .shortened))."

        case .remove(let keyword):
            guard let index = taskIndex(matching: keyword) else {
                return "I couldn't find a reminder matching \"\(keyword)\"."
            }
            let title = tasks[index].title
            tasks.remove(at: index)
            rescheduleReminders()
            return "Removed \(title) from today's list."
        }
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
