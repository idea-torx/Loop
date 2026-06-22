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
    @Published var cloudSyncStatus = "Cloud has not checked in yet."

    let coachService = CoachService()
    let reminderScheduler = ReminderScheduler()
    let healthKitService = HealthKitService()
    let metricsService = MetricsService()
    let gateway = SupabaseGateway()

    private var session: SupabaseSession?
    private var didBootstrap = false
    private var isLoadingCloudData = false

    /// Ensure a valid anonymous Supabase session, restoring/refreshing across launches.
    /// Returns nil when the backend isn't configured (app stays in local mode).
    @discardableResult
    func ensureSession() async -> SupabaseSession? {
        guard let base = gateway.configuration.projectURL,
              let key = gateway.configuration.anonKey, !key.isEmpty else {
            cloudSyncStatus = "Supabase is not configured in the app environment."
            return nil
        }

        if let current = session, current.expiresAt > Date() { return current }

        if let stored = UserDefaults.standard.string(forKey: "sb_refresh_token"),
           let refreshed = await SupabaseGateway.refresh(base: base, anonKey: key, refreshToken: stored) {
            store(refreshed)
            cloudSyncStatus = "Supabase session refreshed."
            return refreshed
        }
        if let fresh = await SupabaseGateway.signInAnonymously(base: base, anonKey: key) {
            store(fresh)
            cloudSyncStatus = "Supabase anonymous session created."
            return fresh
        }
        cloudSyncStatus = SupabaseGateway.lastEvent
        return nil
    }

    private func store(_ newSession: SupabaseSession) {
        session = newSession
        UserDefaults.standard.set(newSession.refreshToken, forKey: "sb_refresh_token")
        UserDefaults.standard.set(newSession.userID, forKey: "sb_user_id")
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        gateway.loadConfiguration()
        if conversations.isEmpty {
            startDailyCheckInConversation()
        }
        if selectedWorkoutDayID == nil {
            selectedWorkoutDayID = workoutSchedule.first?.id
        }
        Task { await loadCloudData() }
    }

    /// Open a blank chat for open-ended fitness, nutrition, and coaching questions.
    func startNewConversation() {
        let convo = Conversation(
            title: "New chat",
            messages: []
        )
        conversations.insert(convo, at: 0)
        activeConversationID = convo.id
    }

    /// Create the default daily thread with a contextual check-in.
    private func startDailyCheckInConversation() {
        let convo = Conversation(
            title: "Daily check-in",
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
        syncTask(tasks[index])
    }

    // MARK: Editable reminders

    func upsertTask(_ task: DailyTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            syncTask(tasks[index])
        } else {
            tasks.append(task)
            syncTask(task)
        }
        sortTasksForToday()
        rescheduleReminders()
    }

    func updateTask(_ task: DailyTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        syncTask(tasks[index])
        sortTasksForToday()
        rescheduleReminders()
    }

    func deleteTask(_ task: DailyTask) {
        tasks.removeAll { $0.id == task.id }
        deleteCloudTask(task)
        rescheduleReminders()
    }

    func rescheduleReminders() {
        let snapshot = tasks
        Task { await reminderScheduler.scheduleTaskReminders(snapshot, tone: settings.notificationTone) }
    }

    private func sortTasksForToday() {
        tasks.sort { lhs, rhs in
            let left = Self.daySortMinutes(for: lhs)
            let right = Self.daySortMinutes(for: rhs)
            if left != right { return left < right }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func daySortMinutes(for task: DailyTask) -> Int {
        if let reminderTime = task.reminderTime {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            return (parts.hour ?? 12) * 60 + (parts.minute ?? 0)
        }

        let text = "\(task.title) \(task.detail)".lowercased()
        if text.contains("morning") || text.contains("weigh") || text.contains("breakfast") { return 8 * 60 }
        if text.contains("lunch") { return 12 * 60 }
        if text.contains("step") || text.contains("walk") || text.contains("recovery") { return 15 * 60 + 30 }
        if text.contains("dinner") { return 17 * 60 }
        if text.contains("workout") || text.contains("gym") || text.contains("lift") { return 18 * 60 + 30 }
        if text.contains("evening") || text.contains("review") || text.contains("sleep") { return 21 * 60 }
        return 16 * 60
    }

    // MARK: Meals

    func logMeal(title: String, calories: Int, protein: Int, imageData: Data?) {
        let meal = MealLog(date: Date(), title: title, calories: calories, protein: protein, imageData: imageData)
        meals.append(meal)
        syncMeal(meal)
    }

    func updateMeal(_ mealID: MealLog.ID, title: String, calories: Int, protein: Int) {
        guard let index = meals.firstIndex(where: { $0.id == mealID }) else { return }
        meals[index].title = title
        meals[index].calories = calories
        meals[index].protein = protein
        syncUpdatedMeal(meals[index])
    }

    func deleteMeal(_ mealID: MealLog.ID) {
        guard let index = meals.firstIndex(where: { $0.id == mealID }) else { return }
        let meal = meals.remove(at: index)
        deleteCloudMeal(meal)
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
        syncLatestMessage()
        setTitleIfNeeded(from: trimmed)

        // Conversational reminder management.
        if let command = CommandParser.reminderCommand(from: trimmed) {
            let reply = applyReminderCommand(command)
            messages.append(CoachMessage(role: .assistant, text: reply))
            syncLatestMessage()
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
            syncLatestMessage()
            return
        }

        if let response = await haikuCoachResponse(to: trimmed) {
            apply(response)
            return
        }

        let failure = cloudSyncStatus.isEmpty ? "Haiku chat is not connected yet." : cloudSyncStatus
        messages.append(CoachMessage(role: .assistant, text: "I could not reach Haiku for that message. \(failure)"))
        syncLatestMessage()
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

    func sendMealImageToHaiku(imageData: Data, note: String?) async {
        let prompt = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = prompt?.isEmpty == false ? prompt! : "Estimate this meal from the photo and log it."
        messages.append(CoachMessage(role: .user, text: "Log this meal photo."))
        syncLatestMessage()
        let macros = await logMealWithHaiku(description: description, imageData: imageData)
        let reply = "Logged from photo: \(macros.title) — \(macros.calories) cal, \(macros.protein)g protein."
            + " Today is now \(proteinToday)g protein."
        messages.append(CoachMessage(role: .assistant, text: reply))
        syncLatestMessage()
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
            syncTask(tasks[index])
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
            sortTasksForToday()
            syncTask(task)
            rescheduleReminders()
            if let time {
                return "Added \"\(title)\" at \(time.formatted(date: .omitted, time: .shortened))."
            }
            return "Added \"\(title)\" to today's list."

        case .move(let keyword, let time):
            guard let index = taskIndex(matching: keyword) else {
                return "I couldn't find a reminder matching \"\(keyword)\". Try the exact name from Today."
            }
            let title = tasks[index].title
            tasks[index].reminderTime = time
            syncTask(tasks[index])
            sortTasksForToday()
            rescheduleReminders()
            return "Moved \(title) to \(time.formatted(date: .omitted, time: .shortened))."

        case .remove(let keyword):
            guard let index = taskIndex(matching: keyword) else {
                return "I couldn't find a reminder matching \"\(keyword)\"."
            }
            let title = tasks[index].title
            let task = tasks[index]
            tasks.remove(at: index)
            deleteCloudTask(task)
            rescheduleReminders()
            return "Removed \(title) from today's list."
        }
    }

    func sendWorkoutMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(CoachMessage(role: .user, text: "Workout: \(trimmed)"))
        syncLatestMessage()
        let response = await coachService.respondToWorkoutLog(trimmed, state: self)
        apply(response)
    }

    func sendWorkoutConfigurationMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let dayLabel = selectedWorkoutDay?.dayName ?? "selected day"
        let workoutMessage = "Configure \(dayLabel) workout: \(trimmed)"
        messages.append(CoachMessage(role: .user, text: workoutMessage))
        syncLatestMessage()

        if let response = await haikuCoachResponse(to: workoutMessage) {
            apply(response)
            return
        }

        let response = await coachService.configureWorkoutDay(trimmed, state: self)
        apply(response)
    }

    func apply(_ response: CoachResponse) {
        messages.append(CoachMessage(role: .assistant, text: response.reply))
        syncLatestMessage()

        for update in response.updates {
            switch update {
            case .taskCompleted(let keyword):
                if let index = tasks.firstIndex(where: { $0.title.localizedCaseInsensitiveContains(keyword) }) {
                    tasks[index].isComplete = true
                    tasks[index].completedAt = Date()
                    syncTask(tasks[index])
                }
            case .weighIn(let value):
                let weighIn = WeighIn(date: Date(), pounds: value)
                weighIns.append(weighIn)
                syncWeighIn(weighIn)
            case .meal(let title, let calories, let protein):
                let meal = MealLog(date: Date(), title: title, calories: calories, protein: protein)
                meals.append(meal)
                syncMeal(meal)
            case .mealUpdate(let id, let keyword, let title, let calories, let protein):
                updateMealFromCoach(id: id, keyword: keyword, title: title, calories: calories, protein: protein)
            case .mealDelete(let id, let keyword):
                deleteMealFromCoach(id: id, keyword: keyword)
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
        syncWeeklyReview()
    }

    func addSet(exercise: String, reps: Int, weight: Int) {
        guard let dayIndex = selectedWorkoutDayIndex() else { return }
        let set = ExerciseSet(exercise: exercise, reps: reps, weight: weight)
        workoutSchedule[dayIndex].sets.append(set)
        workoutSchedule[dayIndex].isTrainingDay = true

        let session = workoutSession(from: workoutSchedule[dayIndex])
        upsertLocalWorkoutSession(session)
        syncExerciseSet(set, workout: session, dayID: workoutSchedule[dayIndex].id, sortOrder: workoutSchedule[dayIndex].sets.count - 1)
    }

    func updateSet(_ setID: ExerciseSet.ID, exercise: String, reps: Int, weight: Int) {
        guard let dayIndex = selectedWorkoutDayIndex(),
              let setIndex = workoutSchedule[dayIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
        workoutSchedule[dayIndex].sets[setIndex].exercise = exercise
        workoutSchedule[dayIndex].sets[setIndex].reps = reps
        workoutSchedule[dayIndex].sets[setIndex].weight = weight
        let updatedSet = workoutSchedule[dayIndex].sets[setIndex]

        let session = workoutSession(from: workoutSchedule[dayIndex])
        upsertLocalWorkoutSession(session)
        syncWorkoutSession(session, dayID: workoutSchedule[dayIndex].id)
        syncUpdatedExerciseSet(updatedSet)
    }

    func deleteSet(_ setID: ExerciseSet.ID) {
        guard let dayIndex = selectedWorkoutDayIndex(),
              let setIndex = workoutSchedule[dayIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
        let removedSet = workoutSchedule[dayIndex].sets.remove(at: setIndex)

        let session = workoutSession(from: workoutSchedule[dayIndex])
        upsertLocalWorkoutSession(session)
        syncWorkoutSession(session, dayID: workoutSchedule[dayIndex].id)
        deleteCloudExerciseSet(removedSet)
    }

    private func updateSelectedWorkoutPlan(title: String, focus: String, notes: String) {
        guard let index = selectedWorkoutDayIndex() else { return }

        workoutSchedule[index].title = title
        workoutSchedule[index].focus = focus
        workoutSchedule[index].coachNotes = notes
        workoutSchedule[index].isTrainingDay = true
        let session = workoutSession(from: workoutSchedule[index])
        upsertLocalWorkoutSession(session)
        syncWorkoutSession(session, dayID: workoutSchedule[index].id)
    }

    private func updateMealFromCoach(id: String?, keyword: String?, title: String?, calories: Int?, protein: Int?) {
        guard let index = mealIndex(id: id, keyword: keyword) else { return }
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meals[index].title = title
        }
        if let calories {
            meals[index].calories = calories
        }
        if let protein {
            meals[index].protein = protein
        }
        syncUpdatedMeal(meals[index])
    }

    private func deleteMealFromCoach(id: String?, keyword: String?) {
        guard let index = mealIndex(id: id, keyword: keyword) else { return }
        let meal = meals.remove(at: index)
        deleteCloudMeal(meal)
    }

    private func mealIndex(id: String?, keyword: String?) -> Int? {
        if let id,
           let uuid = UUID(uuidString: id),
           let index = meals.firstIndex(where: { $0.id == uuid }) {
            return index
        }
        if let id,
           let index = meals.firstIndex(where: { $0.cloudID == id }) {
            return index
        }
        if let keyword {
            let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty,
               let index = todaysMeals.lastIndex(where: { $0.title.localizedCaseInsensitiveContains(normalized) }),
               let realIndex = meals.firstIndex(where: { $0.id == todaysMeals[index].id }) {
                return realIndex
            }
        }
        return todaysMeals.last.flatMap { meal in meals.firstIndex(where: { $0.id == meal.id }) }
    }

    private func selectedWorkoutDayIndex() -> Int? {
        guard let selectedID = selectedWorkoutDayID ?? workoutSchedule.first?.id else { return nil }
        return workoutSchedule.firstIndex(where: { $0.id == selectedID })
    }

    private func workoutSession(from day: WorkoutDayPlan) -> WorkoutSession {
        WorkoutSession(
            cloudID: day.cloudID,
            date: day.date,
            title: day.title,
            focus: day.focus,
            coachNotes: day.coachNotes,
            sets: day.sets,
            isComplete: false
        )
    }

    private func upsertLocalWorkoutSession(_ session: WorkoutSession) {
        if let index = workouts.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: session.date) }) {
            workouts[index] = session
        } else if workouts.isEmpty {
            workouts = [session]
        } else {
            workouts[0] = session
        }
    }

    private func haikuCoachResponse(to text: String) async -> CoachResponse? {
        guard let context = await cloudContext else { return nil }
        guard let result = await SupabaseGateway.coachChat(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            message: text,
            context: haikuContext()
        ) else {
            cloudSyncStatus = "Haiku chat unavailable. \(SupabaseGateway.lastEvent)"
            return nil
        }

        cloudSyncStatus = "Haiku replied through Supabase."
        return CoachResponse(reply: result.reply, updates: result.updates.compactMap(Self.update(fromHaiku:)))
    }

    private func haikuContext() -> [String: Any] {
        let selectedDayContext: Any = selectedWorkoutDay.map(Self.workoutDayContext) ?? NSNull()
        let latestSessionContext: Any = workouts.first.map(Self.workoutSessionContext) ?? NSNull()

        return [
            "profile": [
                "name": profile.displayName,
                "goal": profile.goal,
                "training_level": profile.trainingLevel,
                "preferred_tone": profile.preferredTone
            ],
            "today": [
                "date": Self.cloudDate(Date()),
                "tasks": tasks.map { [
                    "title": $0.title,
                    "complete": $0.isComplete,
                    "detail": $0.detail
                ] },
                "meals_logged_today": todaysMeals.map { [
                    "local_id": $0.id.uuidString,
                    "cloud_id": $0.cloudID ?? "",
                    "title": $0.title,
                    "calories": $0.calories,
                    "protein_grams": $0.protein,
                    "logged_at": Self.isoString($0.date)
                ] },
                "protein_grams_today": proteinToday,
                "protein_target_grams": PTProtocol.proteinTargetG,
                "calories_today": caloriesToday,
                "calorie_target": PTProtocol.calorieTarget,
                "latest_weight": weighIns.last?.pounds ?? NSNull(),
                "workout_focus": selectedWorkoutDay?.focus ?? NSNull(),
                "workout_title": selectedWorkoutDay?.title ?? NSNull()
            ],
            "training": [
                "selected_day": selectedDayContext,
                "week_schedule": workoutSchedule.map(Self.workoutDayContext),
                "latest_session": latestSessionContext
            ],
            "recent_messages": messages.dropLast().suffix(8).map { [
                "role": $0.role.cloudValue,
                "text": $0.text
            ] },
            "settings": [
                "notification_tone": settings.notificationTone,
                "gym_days": settings.gymDays,
                "meal_timing": settings.mealTiming
            ]
        ]
    }

    private static func update(fromHaiku raw: [String: Any]) -> CoachAppUpdate? {
        let type = (raw["type"] as? String) ?? (raw["kind"] as? String) ?? (raw["update"] as? String)
        switch type {
        case "task_completed":
            guard let keyword = raw["keyword"] as? String ?? raw["title"] as? String else { return nil }
            return .taskCompleted(keyword: keyword)
        case "weigh_in":
            guard let pounds = Self.doubleValue(raw["pounds"]) ?? Self.doubleValue(raw["value"]) else { return nil }
            return .weighIn(pounds)
        case "meal_log":
            guard let title = raw["title"] as? String else { return nil }
            let calories = (raw["calories"] as? NSNumber)?.intValue ?? 0
            let protein = (raw["protein"] as? NSNumber)?.intValue
                ?? (raw["protein_grams"] as? NSNumber)?.intValue
                ?? 0
            return .meal(title: title, calories: calories, protein: protein)
        case "meal_update", "meal_edit":
            let id = raw["meal_id"] as? String ?? raw["id"] as? String ?? raw["local_id"] as? String ?? raw["cloud_id"] as? String
            let keyword = raw["keyword"] as? String ?? raw["target"] as? String ?? raw["title_contains"] as? String
            let title = raw["title"] as? String
            let calories = (raw["calories"] as? NSNumber)?.intValue
            let protein = (raw["protein"] as? NSNumber)?.intValue ?? (raw["protein_grams"] as? NSNumber)?.intValue
            return .mealUpdate(id: id, keyword: keyword, title: title, calories: calories, protein: protein)
        case "meal_delete", "delete_meal":
            let id = raw["meal_id"] as? String ?? raw["id"] as? String ?? raw["local_id"] as? String ?? raw["cloud_id"] as? String
            let keyword = raw["keyword"] as? String ?? raw["target"] as? String ?? raw["title_contains"] as? String
            return .mealDelete(id: id, keyword: keyword)
        case "notification_tone":
            guard let tone = raw["value"] as? String ?? raw["tone"] as? String else { return nil }
            return .notificationTone(tone)
        case "gym_days":
            guard let days = raw["value"] as? String ?? raw["days"] as? String else { return nil }
            return .gymDays(days)
        case "meal_timing":
            guard let timing = raw["value"] as? String ?? raw["timing"] as? String else { return nil }
            return .mealTiming(timing)
        case "workout_set":
            guard let exercise = raw["exercise"] as? String else { return nil }
            let reps = (raw["reps"] as? NSNumber)?.intValue ?? 0
            let weight = (raw["weight"] as? NSNumber)?.intValue ?? 0
            guard reps > 0 else { return nil }
            return .workoutSet(exercise: exercise, reps: reps, weight: weight)
        case "workout_plan", "workout_update", "workout_substitution":
            let title = raw["title"] as? String ?? raw["name"] as? String ?? "Coach Updated Session"
            let focus = raw["focus"] as? String
                ?? raw["description"] as? String
                ?? raw["summary"] as? String
                ?? "Updated from your latest training context."
            let notes = raw["notes"] as? String
                ?? raw["coach_notes"] as? String
                ?? raw["details"] as? String
                ?? focus
            return .workoutPlan(title: title, focus: focus, notes: notes)
        default:
            return nil
        }
    }

    private static func workoutDayContext(_ day: WorkoutDayPlan) -> [String: Any] {
        [
            "date": cloudDate(day.date),
            "day_name": day.dayName,
            "title": day.title,
            "focus": day.focus,
            "coach_notes": day.coachNotes,
            "is_training_day": day.isTrainingDay,
            "sets": day.sets.map(exerciseSetContext),
            "volume": day.volume
        ]
    }

    private static func workoutSessionContext(_ workout: WorkoutSession) -> [String: Any] {
        [
            "date": cloudDate(workout.date),
            "title": workout.title,
            "focus": workout.focus,
            "coach_notes": workout.coachNotes,
            "is_complete": workout.isComplete,
            "sets": workout.sets.map(exerciseSetContext)
        ]
    }

    private static func exerciseSetContext(_ set: ExerciseSet) -> [String: Any] {
        [
            "exercise": set.exercise,
            "reps": set.reps,
            "weight": set.weight
        ]
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let string = value as? String { return Double(string) }
        return nil
    }

    func testCloudSync() async {
        gateway.loadConfiguration()
        guard let context = await cloudContext else {
            cloudSyncStatus = SupabaseGateway.lastEvent
            return
        }
        await upsertProfile(context)
        let rows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "profiles",
            query: "select=id,display_name&id=eq.\(context.userID)&limit=1"
        )
        cloudSyncStatus = rows.isEmpty
            ? "Connected, but profile read/write did not confirm. \(SupabaseGateway.lastEvent)"
            : "Cloud sync confirmed. Profile row is visible in Supabase."
    }

    // MARK: - Supabase sync

    private struct CloudContext {
        let base: URL
        let anonKey: String
        let token: String
        let userID: String
    }

    private var cloudContext: CloudContext? {
        get async {
            guard let creds = await ensureSession(),
                  let base = gateway.configuration.projectURL,
                  let key = gateway.configuration.anonKey else { return nil }
            return CloudContext(base: base, anonKey: key, token: creds.accessToken, userID: creds.userID)
        }
    }

    private func loadCloudData() async {
        guard !isLoadingCloudData, let context = await cloudContext else { return }
        isLoadingCloudData = true
        defer { isLoadingCloudData = false }

        await upsertProfile(context)
        await seedTodayTasksIfNeeded(context)

        let loadedTasks = await loadTasks(context)
        if !loadedTasks.isEmpty {
            tasks = loadedTasks
            sortTasksForToday()
        }

        let loadedMeals = await loadMeals(context)
        if !loadedMeals.isEmpty { meals = loadedMeals }

        let loadedWeighIns = await loadWeighIns(context)
        if !loadedWeighIns.isEmpty { weighIns = loadedWeighIns }

        let loadedMessages = await loadMessages(context)
        if !loadedMessages.isEmpty {
            conversations = [Conversation(title: "Coach", messages: loadedMessages)]
            activeConversationID = conversations.first?.id
        }

        let loadedWorkouts = await loadRecentWorkouts(context)
        if !loadedWorkouts.isEmpty {
            workouts = loadedWorkouts
            var mappedWorkoutDates = Set<String>()
            for loadedWorkout in loadedWorkouts {
                let workoutDate = Self.cloudDate(loadedWorkout.date)
                guard !mappedWorkoutDates.contains(workoutDate) else { continue }
                if let index = workoutSchedule.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: loadedWorkout.date) }) {
                    mappedWorkoutDates.insert(workoutDate)
                    workoutSchedule[index].cloudID = loadedWorkout.cloudID
                    workoutSchedule[index].sets = loadedWorkout.sets
                    if !loadedWorkout.coachNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        workoutSchedule[index].title = loadedWorkout.title
                        workoutSchedule[index].focus = loadedWorkout.focus
                        workoutSchedule[index].coachNotes = loadedWorkout.coachNotes
                    }
                    workoutSchedule[index].isTrainingDay = true
                }
            }
        }

        if let review = await loadWeeklyReview(context) {
            weeklyReview = review
        }
        cloudSyncStatus = "Cloud loaded. New app events will write to Supabase."
    }

    private func upsertProfile(_ context: CloudContext) async {
        await SupabaseGateway.insert(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "profiles",
            rows: [[
                "id": context.userID,
                "display_name": profile.displayName,
                "goal": profile.goal,
                "training_level": profile.trainingLevel,
                "preferred_tone": profile.preferredTone,
                "timezone": TimeZone.current.identifier
            ]],
            upsertOnConflict: "id"
        )
        cloudSyncStatus = SupabaseGateway.lastEvent
    }

    private func seedTodayTasksIfNeeded(_ context: CloudContext) async {
        let date = Self.cloudDate(Date())
        let existing = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "task_instances",
            query: "select=id&task_date=eq.\(date)&limit=1"
        )
        guard existing.isEmpty else { return }

        let rows = tasks.enumerated().map { index, task in
            taskRow(task, context: context, sortOrder: index)
        }
        let inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "task_instances", rows: rows)
        cloudSyncStatus = inserted.isEmpty ? SupabaseGateway.lastEvent : "Seeded today's tasks in Supabase."
        for (index, row) in inserted.enumerated() where tasks.indices.contains(index) {
            tasks[index].cloudID = row["id"] as? String
        }
    }

    private func loadTasks(_ context: CloudContext) async -> [DailyTask] {
        let rows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "task_instances",
            query: "select=*&task_date=eq.\(Self.cloudDate(Date()))&order=created_at.asc"
        )
        return rows.compactMap(Self.task(from:))
    }

    private func loadMeals(_ context: CloudContext) async -> [MealLog] {
        let rows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "meals",
            query: "select=*&order=eaten_at.desc&limit=250"
        )
        return rows.compactMap(Self.meal(from:)).sorted { $0.date < $1.date }
    }

    private func loadWeighIns(_ context: CloudContext) async -> [WeighIn] {
        let rows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "weigh_ins",
            query: "select=*&order=measured_at.asc&limit=120"
        )
        return rows.compactMap(Self.weighIn(from:))
    }

    private func loadMessages(_ context: CloudContext) async -> [CoachMessage] {
        let rows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "coach_messages",
            query: "select=*&order=created_at.asc&limit=200"
        )
        return rows.compactMap(Self.message(from:))
    }

    private func loadRecentWorkouts(_ context: CloudContext) async -> [WorkoutSession] {
        let sessions = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "workout_sessions",
            query: "select=*&order=started_at.desc&limit=30"
        )
        var workouts: [WorkoutSession] = []
        for row in sessions {
            guard let id = row["id"] as? String,
                  var workout = Self.workout(from: row) else { continue }
            let sets = await SupabaseGateway.select(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "exercise_sets",
                query: "select=*&workout_session_id=eq.\(id)&order=sort_order.asc"
            )
            workout.sets = sets.compactMap(Self.exerciseSet(from:))
            workouts.append(workout)
        }
        return workouts
    }

    private func loadWeeklyReview(_ context: CloudContext) async -> WeeklyReview? {
        let rows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "weekly_reviews",
            query: "select=*&week_starts_on=eq.\(Self.weekStartDate())&limit=1"
        )
        return rows.first.flatMap(Self.weeklyReview(from:))
    }

    private func syncLatestMessage() {
        guard !isLoadingCloudData, let message = messages.last else { return }
        Task { await syncMessage(message) }
    }

    private func syncMessage(_ message: CoachMessage) async {
        guard let context = await cloudContext else { return }
        await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "coach_messages", rows: [[
            "user_id": context.userID,
            "role": message.role.cloudValue,
            "content": message.text,
            "created_at": Self.isoString(message.createdAt)
        ]])
        cloudSyncStatus = SupabaseGateway.lastEvent
    }

    private func syncTask(_ task: DailyTask) {
        guard !isLoadingCloudData else { return }
        Task {
            guard let context = await cloudContext else { return }
            let row = taskRow(task, context: context, sortOrder: tasks.firstIndex(where: { $0.id == task.id }) ?? 0)
            if let cloudID = task.cloudID {
                await SupabaseGateway.update(base: context.base, anonKey: context.anonKey, token: context.token, table: "task_instances", match: "id=eq.\(cloudID)", values: row)
                cloudSyncStatus = SupabaseGateway.lastEvent
            } else {
                let inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "task_instances", rows: [row])
                cloudSyncStatus = inserted.isEmpty ? SupabaseGateway.lastEvent : "Task wrote to Supabase."
                if let id = inserted.first?["id"] as? String,
                   let index = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[index].cloudID = id
                }
            }
        }
    }

    private func deleteCloudTask(_ task: DailyTask) {
        guard let cloudID = task.cloudID else { return }
        Task {
            guard let context = await cloudContext else { return }
            await SupabaseGateway.delete(base: context.base, anonKey: context.anonKey, token: context.token, table: "task_instances", match: "id=eq.\(cloudID)")
            cloudSyncStatus = SupabaseGateway.lastEvent
        }
    }

    private func syncMeal(_ meal: MealLog) {
        guard !isLoadingCloudData else { return }
        Task {
            guard let context = await cloudContext else { return }
            let inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "meals", rows: [[
                "user_id": context.userID,
                "eaten_at": Self.isoString(meal.date),
                "title": meal.title,
                "calories": meal.calories,
                "protein_grams": meal.protein,
                "source": "conversation"
            ]])
            cloudSyncStatus = inserted.isEmpty ? SupabaseGateway.lastEvent : "Meal wrote to Supabase."
            if let id = inserted.first?["id"] as? String,
               let index = meals.firstIndex(where: { $0.id == meal.id }) {
                meals[index].cloudID = id
            }
        }
    }

    private func syncUpdatedMeal(_ meal: MealLog) {
        guard !isLoadingCloudData, let cloudID = meal.cloudID else { return }
        Task {
            guard let context = await cloudContext else { return }
            await SupabaseGateway.update(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "meals",
                match: "id=eq.\(cloudID)",
                values: [
                    "title": meal.title,
                    "calories": meal.calories,
                    "protein_grams": meal.protein
                ]
            )
            cloudSyncStatus = SupabaseGateway.lastEvent
        }
    }

    private func deleteCloudMeal(_ meal: MealLog) {
        guard !isLoadingCloudData, let cloudID = meal.cloudID else { return }
        Task {
            guard let context = await cloudContext else { return }
            await SupabaseGateway.delete(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "meals",
                match: "id=eq.\(cloudID)"
            )
            cloudSyncStatus = SupabaseGateway.lastEvent
        }
    }

    private func syncWeighIn(_ weighIn: WeighIn) {
        guard !isLoadingCloudData else { return }
        Task {
            guard let context = await cloudContext else { return }
            let inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "weigh_ins", rows: [[
                "user_id": context.userID,
                "measured_at": Self.isoString(weighIn.date),
                "pounds": weighIn.pounds,
                "source": "conversation"
            ]])
            cloudSyncStatus = inserted.isEmpty ? SupabaseGateway.lastEvent : "Weigh-in wrote to Supabase."
            if let id = inserted.first?["id"] as? String,
               let index = weighIns.firstIndex(where: { $0.id == weighIn.id }) {
                weighIns[index].cloudID = id
            }
        }
    }

    private func syncWorkoutSession(_ workout: WorkoutSession, dayID: WorkoutDayPlan.ID?) {
        guard !isLoadingCloudData else { return }
        Task {
            guard let context = await cloudContext else { return }
            if await ensureCloudWorkoutSession(workout, dayID: dayID, context: context) != nil {
                cloudSyncStatus = "Workout day wrote to Supabase."
            }
        }
    }

    private func syncExerciseSet(_ set: ExerciseSet, workout: WorkoutSession, dayID: WorkoutDayPlan.ID?, sortOrder: Int) {
        guard !isLoadingCloudData else { return }
        Task {
            guard let context = await cloudContext else { return }
            let workoutID = await ensureCloudWorkoutSession(workout, dayID: dayID, context: context)
            guard let workoutID else { return }
            let inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "exercise_sets", rows: [[
                "user_id": context.userID,
                "workout_session_id": workoutID,
                "exercise": set.exercise,
                "reps": set.reps,
                "weight": set.weight,
                "sort_order": sortOrder
            ]])
            cloudSyncStatus = inserted.isEmpty ? SupabaseGateway.lastEvent : "Workout set wrote to Supabase."
            if let id = inserted.first?["id"] as? String,
               let sessionIndex = workouts.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: workout.date) }),
               let setIndex = workouts[sessionIndex].sets.firstIndex(where: { $0.id == set.id }) {
                workouts[sessionIndex].sets[setIndex].cloudID = id
            }
            if let dayID,
               let dayIndex = workoutSchedule.firstIndex(where: { $0.id == dayID }),
               let setIndex = workoutSchedule[dayIndex].sets.firstIndex(where: { $0.id == set.id }) {
                workoutSchedule[dayIndex].sets[setIndex].cloudID = inserted.first?["id"] as? String
            }
        }
    }

    private func syncUpdatedExerciseSet(_ set: ExerciseSet) {
        guard !isLoadingCloudData, let cloudID = set.cloudID else { return }
        Task {
            guard let context = await cloudContext else { return }
            await SupabaseGateway.update(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "exercise_sets",
                match: "id=eq.\(cloudID)",
                values: [
                    "exercise": set.exercise,
                    "reps": set.reps,
                    "weight": set.weight
                ]
            )
            cloudSyncStatus = SupabaseGateway.lastEvent
        }
    }

    private func deleteCloudExerciseSet(_ set: ExerciseSet) {
        guard !isLoadingCloudData, let cloudID = set.cloudID else { return }
        Task {
            guard let context = await cloudContext else { return }
            await SupabaseGateway.delete(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "exercise_sets",
                match: "id=eq.\(cloudID)"
            )
            cloudSyncStatus = SupabaseGateway.lastEvent
        }
    }

    private func ensureCloudWorkoutSession(_ workout: WorkoutSession, dayID: WorkoutDayPlan.ID?, context: CloudContext) async -> String? {
        let row = workoutSessionRow(workout, includeNotes: true, context: context)
        let fallbackRow = workoutSessionRow(workout, includeNotes: false, context: context)

        if let cloudID = workout.cloudID {
            let saved = await SupabaseGateway.update(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "workout_sessions",
                match: "id=eq.\(cloudID)",
                values: row
            )
            if !saved {
                await SupabaseGateway.update(
                    base: context.base,
                    anonKey: context.anonKey,
                    token: context.token,
                    table: "workout_sessions",
                    match: "id=eq.\(cloudID)",
                    values: fallbackRow
                )
            }
            return cloudID
        }

        if let existingID = await findCloudWorkoutSessionID(for: workout, context: context) {
            let saved = await SupabaseGateway.update(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "workout_sessions",
                match: "id=eq.\(existingID)",
                values: row
            )
            if !saved {
                await SupabaseGateway.update(
                    base: context.base,
                    anonKey: context.anonKey,
                    token: context.token,
                    table: "workout_sessions",
                    match: "id=eq.\(existingID)",
                    values: fallbackRow
                )
            }
            applyCloudWorkoutID(existingID, dayID: dayID, workoutDate: workout.date)
            return existingID
        }

        var inserted = await SupabaseGateway.insert(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "workout_sessions",
            rows: [row]
        )
        if inserted.isEmpty {
            inserted = await SupabaseGateway.insert(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "workout_sessions",
                rows: [fallbackRow]
            )
        }
        guard let cloudID = inserted.first?["id"] as? String else {
            cloudSyncStatus = SupabaseGateway.lastEvent
            return nil
        }
        applyCloudWorkoutID(cloudID, dayID: dayID, workoutDate: workout.date)
        return cloudID
    }

    private func workoutSessionRow(_ workout: WorkoutSession, includeNotes: Bool, context: CloudContext) -> [String: Any] {
        var row: [String: Any] = [
            "user_id": context.userID,
            "started_at": Self.isoString(workout.date),
            "title": workout.title,
            "focus": workout.focus,
            "is_complete": workout.isComplete
        ]
        if includeNotes {
            row["coach_notes"] = workout.coachNotes
        }
        return row
    }

    private func findCloudWorkoutSessionID(for workout: WorkoutSession, context: CloudContext) async -> String? {
        let rows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "workout_sessions",
            query: "select=id&started_at=eq.\(Self.isoString(workout.date))&order=started_at.desc&limit=1"
        )
        return rows.first?["id"] as? String
    }

    private func applyCloudWorkoutID(_ cloudID: String, dayID: WorkoutDayPlan.ID?, workoutDate: Date) {
        if let dayID,
           let index = workoutSchedule.firstIndex(where: { $0.id == dayID }) {
            workoutSchedule[index].cloudID = cloudID
        }
        if let index = workouts.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: workoutDate) }) {
            workouts[index].cloudID = cloudID
        }
    }

    private func syncWeeklyReview() {
        guard !isLoadingCloudData else { return }
        let review = weeklyReview
        Task {
            guard let context = await cloudContext else { return }
            await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "weekly_reviews", rows: [[
                "user_id": context.userID,
                "week_starts_on": Self.weekStartDate(),
                "summary": review.summary,
                "suggestions": review.suggestions
            ]], upsertOnConflict: "user_id,week_starts_on")
            cloudSyncStatus = SupabaseGateway.lastEvent
        }
    }

    private func taskRow(_ task: DailyTask, context: CloudContext, sortOrder: Int) -> [String: Any] {
        var row: [String: Any] = [
            "user_id": context.userID,
            "task_date": Self.cloudDate(Date()),
            "title": task.title,
            "detail": task.detail,
            "system_image": task.systemImage,
            "is_complete": task.isComplete,
            "completed_at": task.completedAt.map(Self.isoString) ?? NSNull(),
            "sort_order": sortOrder
        ]
        if let reminderTime = task.reminderTime {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            row["local_hour"] = parts.hour
            row["local_minute"] = parts.minute
        } else {
            row["local_hour"] = NSNull()
            row["local_minute"] = NSNull()
        }
        return row
    }

    private static func task(from row: [String: Any]) -> DailyTask? {
        guard let title = row["title"] as? String else { return nil }
        let hour = (row["local_hour"] as? NSNumber)?.intValue
        let minute = (row["local_minute"] as? NSNumber)?.intValue
        let reminder = hour.flatMap { DailyTask.time($0, minute ?? 0) }
        return DailyTask(
            cloudID: row["id"] as? String,
            title: title,
            detail: row["detail"] as? String ?? "",
            systemImage: row["system_image"] as? String ?? "circle",
            isComplete: (row["is_complete"] as? Bool) ?? false,
            completedAt: (row["completed_at"] as? String).flatMap(Self.date(from:)),
            reminderTime: reminder
        )
    }

    private static func meal(from row: [String: Any]) -> MealLog? {
        guard let title = row["title"] as? String else { return nil }
        return MealLog(
            cloudID: row["id"] as? String,
            date: (row["eaten_at"] as? String).flatMap(Self.date(from:)) ?? Date(),
            title: title,
            calories: (row["calories"] as? NSNumber)?.intValue ?? 0,
            protein: (row["protein_grams"] as? NSNumber)?.intValue ?? 0,
            imageData: nil
        )
    }

    private static func weighIn(from row: [String: Any]) -> WeighIn? {
        guard let pounds = (row["pounds"] as? NSNumber)?.doubleValue else { return nil }
        return WeighIn(
            cloudID: row["id"] as? String,
            date: (row["measured_at"] as? String).flatMap(Self.date(from:)) ?? Date(),
            pounds: pounds
        )
    }

    private static func message(from row: [String: Any]) -> CoachMessage? {
        guard let content = row["content"] as? String else { return nil }
        let role = CoachMessage.Role(rawCloudValue: row["role"] as? String) ?? .assistant
        return CoachMessage(
            cloudID: row["id"] as? String,
            role: role,
            text: content,
            createdAt: (row["created_at"] as? String).flatMap(Self.date(from:)) ?? Date()
        )
    }

    private static func workout(from row: [String: Any]) -> WorkoutSession? {
        guard let title = row["title"] as? String else { return nil }
        return WorkoutSession(
            cloudID: row["id"] as? String,
            date: (row["started_at"] as? String).flatMap(Self.date(from:)) ?? Date(),
            title: title,
            focus: row["focus"] as? String ?? "",
            coachNotes: row["coach_notes"] as? String ?? "",
            sets: [],
            isComplete: (row["is_complete"] as? Bool) ?? false
        )
    }

    private static func exerciseSet(from row: [String: Any]) -> ExerciseSet? {
        guard let exercise = row["exercise"] as? String else { return nil }
        return ExerciseSet(
            cloudID: row["id"] as? String,
            exercise: exercise,
            reps: (row["reps"] as? NSNumber)?.intValue ?? 0,
            weight: (row["weight"] as? NSNumber)?.intValue ?? 0
        )
    }

    private static func weeklyReview(from row: [String: Any]) -> WeeklyReview? {
        guard let summary = row["summary"] as? String else { return nil }
        return WeeklyReview(
            title: "This week's lever",
            summary: summary,
            suggestions: row["suggestions"] as? [String] ?? WeeklyReview.seed.suggestions
        )
    }

    private static func cloudDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func weekStartDate() -> String {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return cloudDate(start)
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}

private extension CoachMessage.Role {
    var cloudValue: String {
        switch self {
        case .user: return "user"
        case .assistant: return "assistant"
        }
    }

    init?(rawCloudValue: String?) {
        switch rawCloudValue {
        case "user": self = .user
        case "assistant", "system": self = .assistant
        default: return nil
        }
    }
}
