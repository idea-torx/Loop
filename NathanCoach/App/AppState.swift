import Foundation
import Security
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
    @Published var weighIns: [WeighIn] = []
    @Published var meals: [MealLog] = []
    @Published var dailyMetrics: [DailyMetricSnapshot] = []
    @Published var healthMetrics = HealthMetricSnapshot.seed
    @Published var todayEnergy = TodayEnergySnapshot.seed
    @Published var dailyCoachSnapshot = DailyCoachSnapshot.seed
    @Published var goalPlan = GoalPlan.defaultCut(startWeight: PTProtocol.latestWeight)
    @Published var goalProgress = GoalProgress.seed
    @Published var goalInsight = GoalInsight.seed
    @Published var weeklyReview = WeeklyReview.seed
    @Published var settings = AppSettings()
    @Published var isOnboardingComplete = false
    @Published var cloudSyncStatus = "Cloud has not checked in yet."
    @Published var cloudUserID = SupabaseAuthStore.userID ?? ""
    @Published var cloudAuthEmail = SupabaseAuthStore.email ?? ""
    @Published var isCloudSigningIn = false
    @Published var isSickDay = false
    @Published var mealClarification: MealClarification?
    @Published private(set) var currentDay = Calendar.current.startOfDay(for: Date())

    let coachService = CoachService()
    let reminderScheduler = ReminderScheduler()
    let healthKitService = HealthKitService()
    let metricsService = MetricsService()
    let energyService = TodayEnergyService()
    let goalService = GoalService()
    let gateway = SupabaseGateway()

    private var session: SupabaseSession?
    private var didBootstrap = false
    private var isLoadingCloudData = false
    private var cloudDayIDs: [String: String] = [:]
    private var dailyLogSupportUnavailable = false
    private var pendingMealLog: PendingMealLog?
    private var sickDayKey: String { "loop_sick_day_\(Self.cloudDate(currentDay))" }

    private struct PendingMealLog {
        let description: String
        let imageData: Data?
        var answers: [String]
    }

    /// Ensure a valid Supabase account session, restoring/refreshing across launches.
    /// Returns nil when cloud is unavailable or the user has not signed in.
    @discardableResult
    func ensureSession() async -> SupabaseSession? {
        if !gateway.isConfigured {
            gateway.loadConfiguration()
        }

        guard let base = gateway.configuration.projectURL,
              let key = gateway.configuration.anonKey, !key.isEmpty else {
            cloudSyncStatus = "Supabase config unavailable after environment, Info.plist, cache, and baked fallback checks."
            return nil
        }

        if let current = session, current.expiresAt > Date() { return current }

        SupabaseAuthStore.migrateFromUserDefaultsIfNeeded()

        if SupabaseAuthStore.refreshToken != nil, SupabaseAuthStore.email == nil {
            cloudSyncStatus = "Legacy anonymous cloud session detected for user \(Self.shortID(SupabaseAuthStore.userID ?? "")). Sign in or create an account in Settings so future data uses one stable identity."
            return nil
        }

        if let stored = SupabaseAuthStore.refreshToken,
           let refreshed = await SupabaseGateway.refresh(base: base, anonKey: key, refreshToken: stored) {
            store(refreshed)
            cloudSyncStatus = "Supabase session refreshed."
            return refreshed
        }
        if SupabaseAuthStore.refreshToken != nil {
            let storedUser = SupabaseAuthStore.userID.map(Self.shortID) ?? "unknown"
            cloudSyncStatus = "Could not refresh the stored Supabase session for user \(storedUser). Sign in again to reconnect cloud data without creating a different user."
            return nil
        }

        cloudSyncStatus = "Sign in to Cloud & AI in Settings to sync Loop with one stable Supabase account."
        return nil
    }

    func signInToCloud(email: String, password: String) async {
        await authenticateCloud(email: email, password: password, isCreatingAccount: false)
    }

    func createCloudAccount(email: String, password: String) async {
        await authenticateCloud(email: email, password: password, isCreatingAccount: true)
    }

    func signOutOfCloud() {
        session = nil
        cloudUserID = ""
        cloudAuthEmail = ""
        SupabaseAuthStore.clear()
        cloudSyncStatus = "Signed out of Cloud & AI. Local data remains on this phone."
    }

    private func authenticateCloud(email: String, password: String, isCreatingAccount: Bool) async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, password.count >= 6 else {
            cloudSyncStatus = "Enter an email and a password with at least 6 characters."
            return
        }

        if !gateway.isConfigured {
            gateway.loadConfiguration()
        }
        guard let base = gateway.configuration.projectURL,
              let key = gateway.configuration.anonKey, !key.isEmpty else {
            cloudSyncStatus = "Supabase config unavailable after environment, Info.plist, cache, and baked fallback checks."
            return
        }

        isCloudSigningIn = true
        defer { isCloudSigningIn = false }

        let newSession: SupabaseSession?
        if isCreatingAccount {
            newSession = await SupabaseGateway.signUpWithPassword(base: base, anonKey: key, email: normalizedEmail, password: password)
        } else {
            newSession = await SupabaseGateway.signInWithPassword(base: base, anonKey: key, email: normalizedEmail, password: password)
        }

        guard let newSession else {
            cloudSyncStatus = SupabaseGateway.lastEvent
            return
        }

        store(newSession, email: normalizedEmail)
        cloudSyncStatus = isCreatingAccount
            ? "Cloud account created and connected as \(Self.shortID(newSession.userID))."
            : "Signed in to Cloud & AI as \(Self.shortID(newSession.userID))."
        await loadCloudData()
    }

    private func store(_ newSession: SupabaseSession, email: String? = SupabaseAuthStore.email) {
        session = newSession
        cloudUserID = newSession.userID
        if let email { cloudAuthEmail = email }
        SupabaseAuthStore.store(refreshToken: newSession.refreshToken, userID: newSession.userID, email: email)
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        refreshCurrentDay()
        gateway.loadConfiguration()
        if conversations.isEmpty {
            startDailyCheckInConversation()
        }
        selectCurrentWorkoutDay()
        rescheduleReminders()
        Task { await reminderScheduler.scheduleDailyNudges(tone: settings.notificationTone) }
        Task { await refreshHealthMetrics() }
        Task { await loadCloudData() }
    }

    func reloadCloudData() async {
        refreshCurrentDay()
        await loadCloudData()
    }

    func refreshDailyState() async {
        refreshCurrentDay()
        await refreshDailyInsights()
        await loadCloudData()
    }

    private func refreshCurrentDay() {
        let today = Calendar.current.startOfDay(for: Date())
        if currentDay != today {
            currentDay = today
        }
        isSickDay = UserDefaults.standard.bool(forKey: sickDayKey)
    }

    func selectCurrentWorkoutDay() {
        let today = Calendar.current.startOfDay(for: Date())
        refreshCurrentDay()
        selectedWorkoutDayID = workoutSchedule.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) })?.id
            ?? workoutSchedule.first?.id
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
        let selectedID = selectedWorkoutDayID
            ?? workoutSchedule.first(where: { Calendar.current.isDate($0.date, inSameDayAs: currentDay) })?.id
            ?? workoutSchedule.first?.id
        return workoutSchedule.first(where: { $0.id == selectedID }) ?? workoutSchedule.first
    }

    func selectWorkoutDay(_ day: WorkoutDayPlan) {
        selectedWorkoutDayID = day.id
    }

    func updateGoalPlan(_ plan: GoalPlan) {
        goalPlan = plan
        refreshGoalState()
        syncGoalPlan(plan)
        refreshHomeAfterLocalChange()
    }

    func refreshGoalState() {
        goalProgress = goalService.makeProgress(
            goal: goalPlan,
            weighIns: weighIns,
            meals: meals,
            dailyMetrics: dailyMetrics,
            health: healthMetrics,
            today: Date()
        )
        goalInsight = goalService.makeInsight(goal: goalPlan, progress: goalProgress)
    }

    private func defaultGoalPlan() -> GoalPlan {
        GoalPlan.defaultCut(startWeight: weighIns.last?.pounds ?? PTProtocol.latestWeight, startDate: Date())
    }

    private func upsertLocalDailyMetricSnapshot() {
        let snapshot = DailyMetricSnapshot(
            date: Date(),
            steps: healthMetrics.steps,
            activeEnergy: healthMetrics.activeEnergy,
            workoutsCount: healthMetrics.workoutsToday,
            taskCompletionRate: taskCompletionRate
        )
        if let index = dailyMetrics.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: snapshot.date) }) {
            dailyMetrics[index] = snapshot
        } else {
            dailyMetrics.append(snapshot)
        }
        dailyMetrics.sort { $0.date < $1.date }
    }

    private var taskCompletionRate: Double {
        let total = max(tasks.count, 1)
        return Double(tasks.filter(\.isComplete).count) / Double(total)
    }

    func toggleTask(_ task: DailyTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isComplete.toggle()
        tasks[index].completedAt = tasks[index].isComplete ? Date() : nil
        syncTask(tasks[index])
        refreshHomeAfterLocalChange()
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
        refreshHomeAfterLocalChange()
    }

    func updateTask(_ task: DailyTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        syncTask(tasks[index])
        sortTasksForToday()
        rescheduleReminders()
        refreshHomeAfterLocalChange()
    }

    func deleteTask(_ task: DailyTask) {
        tasks.removeAll { $0.id == task.id }
        deleteCloudTask(task)
        rescheduleReminders()
        refreshHomeAfterLocalChange()
    }

    func activateSickDay() {
        isSickDay = true
        UserDefaults.standard.set(true, forKey: sickDayKey)

        for index in tasks.indices {
            let title = tasks[index].title.lowercased()
            guard !title.contains("light walk") else { continue }
            tasks[index].isComplete = true
            tasks[index].completedAt = Date()
            if !tasks[index].detail.localizedCaseInsensitiveContains("sick day") {
                tasks[index].detail = "Skipped for sick day"
            }
            syncTask(tasks[index])
        }

        if !tasks.contains(where: { $0.title.localizedCaseInsensitiveContains("light walk") }) {
            let walk = DailyTask(
                title: "Light walk",
                detail: "10-20 minutes easy if symptoms allow",
                systemImage: "figure.walk",
                isComplete: false,
                reminderTime: nil
            )
            tasks.append(walk)
            syncTask(walk)
        }

        sortTasksForToday()
        weeklyReview = metricsService.makeWeeklyReview(
            tasks: tasks,
            weighIns: weighIns,
            meals: meals,
            workouts: workouts,
            health: healthMetrics,
            isSickDay: isSickDay
        )
        syncWeeklyReview()
        rescheduleReminders()
        refreshHomeAfterLocalChange()
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
        if text.contains("morning") || text.contains("weigh") || text.contains("breakfast") { return 8 * 60 + 15 }
        if text.contains("lunch") { return 12 * 60 }
        if text.contains("step") || text.contains("walk") || text.contains("recovery") { return 15 * 60 + 30 }
        if text.contains("dinner") { return 17 * 60 }
        if text.contains("workout") || text.contains("gym") || text.contains("lift") { return 18 * 60 + 30 }
        if text.contains("evening") || text.contains("review") || text.contains("sleep") { return 21 * 60 }
        return 16 * 60
    }

    private func normalizeMorningWeighInReminder() {
        guard let index = tasks.firstIndex(where: {
            $0.title.localizedCaseInsensitiveContains("weigh-in")
                || $0.title.localizedCaseInsensitiveContains("weigh in")
        }) else {
            return
        }

        let target = DailyTask.time(8, 15)
        let parts = tasks[index].reminderTime.map {
            Calendar.current.dateComponents([.hour, .minute], from: $0)
        }
        guard parts?.hour != 8 || parts?.minute != 15 else { return }

        tasks[index].reminderTime = target
        syncTask(tasks[index])
    }

    // MARK: Meals

    func logMeal(title: String, calories: Int, protein: Int, imageData: Data?) {
        let meal = MealLog(date: Date(), title: title, calories: calories, protein: protein, imageData: imageData)
        meals.append(meal)
        syncMeal(meal)
        refreshHomeAfterLocalChange()
    }

    func updateMeal(_ mealID: MealLog.ID, title: String, calories: Int, protein: Int) {
        guard let index = meals.firstIndex(where: { $0.id == mealID }) else { return }
        meals[index].title = title
        meals[index].calories = calories
        meals[index].protein = protein
        syncUpdatedMeal(meals[index])
        refreshHomeAfterLocalChange()
    }

    func deleteMeal(_ mealID: MealLog.ID) {
        guard let index = meals.firstIndex(where: { $0.id == mealID }) else { return }
        let meal = meals.remove(at: index)
        deleteCloudMeal(meal)
        refreshHomeAfterLocalChange()
    }

    var todaysMeals: [MealLog] {
        meals.filter { Calendar.current.isDate($0.date, inSameDayAs: currentDay) }
    }

    var caloriesToday: Int { todaysMeals.reduce(0) { $0 + $1.calories } }
    var proteinToday: Int { todaysMeals.reduce(0) { $0 + $1.protein } }

    private enum MealSlot: String {
        case breakfast
        case lunch
        case dinner
        case snack
        case any

        var displayName: String {
            switch self {
            case .breakfast: return "breakfast"
            case .lunch: return "lunch"
            case .dinner: return "dinner"
            case .snack: return "snack"
            case .any: return "meal"
            }
        }
    }

    private struct MealRepeatRequest {
        let slot: MealSlot
        let sourceDayOffset: Int
    }

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

        if pendingMealLog != nil {
            if ["cancel", "never mind", "nevermind", "skip"].contains(trimmed.lowercased()) {
                pendingMealLog = nil
                mealClarification = nil
                messages.append(CoachMessage(role: .assistant, text: "No problem. I did not log that meal."))
                syncLatestMessage()
                return
            }

            await continuePendingMealLog(with: trimmed)
            return
        }

        // Body-weight logging is deterministic so a clear weigh-in never depends on model formatting.
        if let pounds = Self.weightLogValue(from: trimmed) {
            logWeighIn(pounds)
            completeTask(matching: "weigh-in")
            let reply = "Logged \(pounds.formatted(.number.precision(.fractionLength(1)))) lb. The trend chart will use this as a real weigh-in, not placeholder data."
            messages.append(CoachMessage(role: .assistant, text: reply))
            syncLatestMessage()
            return
        }

        if let repeatRequest = mealRepeatRequest(from: trimmed) {
            let reply = repeatRecentMeal(repeatRequest)
            messages.append(CoachMessage(role: .assistant, text: reply))
            syncLatestMessage()
            return
        }

        // Conversational meal logging — macros evaluated by the nutrition specialist.
        if let description = CommandParser.mealLog(from: trimmed) {
            let macros = await logMealWithHaiku(description: description, imageData: nil)
            let reply = mealLogReply(for: macros, source: "Logged")
            if macros.shouldLog, let keyword = CommandParser.mealKeyword(in: trimmed) {
                completeTask(matching: keyword)
            }
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

    /// Evaluate macros via the meal-specialist Edge Function, then log only when confidence is sufficient.
    @discardableResult
    func logMealWithHaiku(description: String, imageData: Data?) async -> MealMacros {
        var macros: MealMacros?
        if let creds = await ensureSession(),
           let base = gateway.configuration.projectURL,
           let key = gateway.configuration.anonKey {
            macros = await SupabaseGateway.analyzeMeal(base: base, anonKey: key, token: creds.accessToken, description: description, imageData: imageData)
        }
        let resolved = macros ?? localMealEstimate(description: description)
        if resolved.shouldLog {
            pendingMealLog = nil
            mealClarification = nil
            logMeal(title: resolved.title, calories: resolved.calories, protein: resolved.protein, imageData: imageData)
        } else {
            pendingMealLog = PendingMealLog(description: description, imageData: imageData, answers: [])
            updateMealClarification(from: resolved)
        }
        return resolved
    }

    func sendMealImageToHaiku(imageData: Data, note: String?) async {
        let prompt = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = prompt?.isEmpty == false ? prompt! : "Estimate this meal from the photo and log it."
        messages.append(CoachMessage(role: .user, text: "Log this meal photo."))
        syncLatestMessage()
        let macros = await logMealWithHaiku(description: description, imageData: imageData)
        let reply = mealLogReply(for: macros, source: "Logged from photo")
        messages.append(CoachMessage(role: .assistant, text: reply))
        syncLatestMessage()
    }

    private func continuePendingMealLog(with answer: String) async {
        guard var pending = pendingMealLog else { return }
        pending.answers.append(answer)
        pendingMealLog = pending

        var macros: MealMacros?
        if let creds = await ensureSession(),
           let base = gateway.configuration.projectURL,
           let key = gateway.configuration.anonKey {
            macros = await SupabaseGateway.analyzeMeal(
                base: base,
                anonKey: key,
                token: creds.accessToken,
                description: pending.description,
                imageData: pending.imageData,
                followUpAnswers: pending.answers
            )
        }

        let resolved = macros ?? localMealEstimate(description: pending.description)
        if resolved.shouldLog {
            pendingMealLog = nil
            mealClarification = nil
            logMeal(title: resolved.title, calories: resolved.calories, protein: resolved.protein, imageData: pending.imageData)
        } else {
            pendingMealLog = PendingMealLog(description: pending.description, imageData: pending.imageData, answers: pending.answers)
            updateMealClarification(from: resolved)
        }

        messages.append(CoachMessage(role: .assistant, text: mealLogReply(for: resolved, source: "Logged")))
        syncLatestMessage()
    }

    private func mealLogReply(for macros: MealMacros, source: String) -> String {
        if macros.shouldLog {
            var reply = "\(source): \(macros.title) — \(macros.calories) cal, \(macros.protein)g protein."
                + " Today is now \(proteinToday)g protein (target \(PTProtocol.proteinTargetG)g)."
            if macros.confidence == "low", !macros.confidenceReason.isEmpty {
                reply += " Low confidence: \(macros.confidenceReason)"
            }
            return reply
        }

        let questions = macros.clarifyingQuestions.isEmpty
            ? ["What portion did you have, and was there any oil, sauce, dressing, or drink I should include?"]
            : macros.clarifyingQuestions
        return "I’m not logging that yet because the estimate depends on a detail I can’t safely infer. "
            + questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ")
    }

    func dismissMealClarification() {
        mealClarification = nil
    }

    private func updateMealClarification(from macros: MealMacros) {
        guard let question = macros.clarifyingQuestions.first else {
            mealClarification = nil
            return
        }
        mealClarification = MealClarification(
            question: question,
            options: Array(macros.responseOptions.prefix(3))
        )
    }

    private func mealRepeatRequest(from text: String) -> MealRepeatRequest? {
        let lower = text.lowercased()
        let hasRepeatIntent = [
            "same as",
            "same thing",
            "same meal",
            "same lunch",
            "same dinner",
            "repeat",
            "copy",
            "usual",
            "again"
        ].contains { lower.contains($0) }
        guard hasRepeatIntent else { return nil }

        let mentionsMeal = ["breakfast", "lunch", "dinner", "snack", "meal", "ate", "had", "log"].contains { lower.contains($0) }
        let mentionsPriorDay = ["yesterday", "last night", "last time", "same as"].contains { lower.contains($0) }
        guard mentionsMeal || mentionsPriorDay else { return nil }

        let sourceDayOffset = lower.contains("yesterday") || lower.contains("last night") ? 1 : 0
        return MealRepeatRequest(slot: mealSlot(from: lower), sourceDayOffset: sourceDayOffset)
    }

    private func repeatRecentMeal(_ request: MealRepeatRequest) -> String {
        guard let source = previousMeal(matching: request) else {
            let slot = request.slot.displayName
            return "I couldn’t find a previous \(slot) to copy yet. Log it once with the details and I’ll be able to repeat it next time."
        }

        logMeal(title: source.title, calories: source.calories, protein: source.protein, imageData: nil)
        if request.slot != .any {
            completeTask(matching: request.slot.displayName)
        }

        return "Logged the same \(request.slot.displayName): \(source.title) — \(source.calories) cal, \(source.protein)g protein. Today is now \(proteinToday)g protein."
    }

    private func previousMeal(matching request: MealRepeatRequest) -> MealLog? {
        let todayStart = Calendar.current.startOfDay(for: currentDay)
        let priorMeals = meals
            .filter { $0.date < todayStart }
            .sorted { $0.date > $1.date }

        if request.sourceDayOffset > 0,
           let sourceDay = Calendar.current.date(byAdding: .day, value: -request.sourceDayOffset, to: todayStart) {
            let dayMatches = priorMeals.filter { Calendar.current.isDate($0.date, inSameDayAs: sourceDay) }
            if let exact = dayMatches.last(where: { mealMatches($0, slot: request.slot) }) {
                return exact
            }
            if request.slot == .any, let fallback = dayMatches.last {
                return fallback
            }
        }

        return priorMeals.first { mealMatches($0, slot: request.slot) }
    }

    private func mealMatches(_ meal: MealLog, slot: MealSlot) -> Bool {
        slot == .any || mealSlot(for: meal) == slot
    }

    private func mealSlot(from lowercasedText: String) -> MealSlot {
        if lowercasedText.contains("breakfast") { return .breakfast }
        if lowercasedText.contains("lunch") { return .lunch }
        if lowercasedText.contains("dinner") { return .dinner }
        if lowercasedText.contains("snack") { return .snack }

        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<10: return .breakfast
        case 10..<15: return .lunch
        case 15..<22: return .dinner
        default: return .any
        }
    }

    private func mealSlot(for meal: MealLog) -> MealSlot {
        let title = meal.title.lowercased()
        if title.contains("breakfast") { return .breakfast }
        if title.contains("lunch") { return .lunch }
        if title.contains("dinner") { return .dinner }
        if title.contains("snack") { return .snack }

        let hour = Calendar.current.component(.hour, from: meal.date)
        switch hour {
        case 5..<10: return .breakfast
        case 10..<15: return .lunch
        case 15..<22: return .dinner
        default: return .any
        }
    }

    private func localMealEstimate(description: String) -> MealMacros {
        // Offline fallback when the backend isn't configured.
        let title = description.split(separator: ",").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? "Meal"
        return MealMacros(
            title: title.isEmpty ? "Meal" : title,
            calories: 550,
            protein: 45,
            shouldLog: true,
            confidence: "low",
            confidenceReason: "Offline fallback estimate.",
            clarifyingQuestions: [],
            responseOptions: [],
            notes: ""
        )
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

        if let response = await haikuCoachResponse(to: "Log workout sets for \(selectedWorkoutDay?.dayName ?? "today"): \(trimmed)") {
            apply(response)
            return
        }

        let response = await coachService.respondToWorkoutLog(trimmed, state: self)
        apply(response)
    }

    func sendExerciseWorkoutMessage(exercise: String, text: String) async {
        let cleanExercise = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanExercise.isEmpty, !trimmed.isEmpty else { return }
        await sendWorkoutMessage("\(cleanExercise) \(trimmed)")
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
                logWeighIn(value)
            case .meal(let title, let calories, let protein):
                logMeal(title: title, calories: calories, protein: protein, imageData: nil)
            case .mealUpdate(let id, let keyword, let title, let calories, let protein):
                updateMealFromCoach(id: id, keyword: keyword, title: title, calories: calories, protein: protein)
            case .mealDelete(let id, let keyword):
                deleteMealFromCoach(id: id, keyword: keyword)
            case .notificationTone(let tone):
                settings.notificationTone = tone
                rescheduleReminders()
                Task { await reminderScheduler.scheduleDailyNudges(tone: settings.notificationTone) }
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
            health: healthMetrics,
            isSickDay: isSickDay
        )
        syncWeeklyReview()
    }

    func addSet(exercise: String, reps: Int, weight: Int, rir: Int? = nil) {
        guard let dayIndex = selectedWorkoutDayIndex() else { return }
        let set = makeExerciseSet(exercise: exercise, reps: reps, weight: weight, rir: rir)
        workoutSchedule[dayIndex].sets.append(set)
        workoutSchedule[dayIndex].isTrainingDay = true

        let session = workoutSession(from: workoutSchedule[dayIndex])
        upsertLocalWorkoutSession(session)
        syncExerciseSet(set, workout: session, dayID: workoutSchedule[dayIndex].id, sortOrder: workoutSchedule[dayIndex].sets.count - 1)
        refreshHomeAfterLocalChange()
    }

    struct ExerciseHistoryEntry: Identifiable {
        let id = UUID()
        let date: Date
        let split: String
        let title: String
        let sets: [ExerciseSet]

        var volume: Int {
            sets.reduce(0) { $0 + ($1.reps * $1.weight) }
        }

        var summary: String {
            sets.map { "\($0.weight)×\($0.reps)" }.joined(separator: ", ")
        }
    }

    func exerciseHistory(for exercise: String, limit: Int = 8) -> [ExerciseHistoryEntry] {
        let normalized = Self.exerciseMetadata(for: exercise).normalized
        return workouts
            .sorted { $0.date > $1.date }
            .compactMap { session -> ExerciseHistoryEntry? in
                let matchingSets = session.sets.filter { Self.comparisonKeys(for: $0).contains(normalized) }
                guard !matchingSets.isEmpty else { return nil }
                return ExerciseHistoryEntry(
                    date: session.date,
                    split: Self.splitKey(for: session.title),
                    title: session.title,
                    sets: matchingSets
                )
            }
            .prefix(limit)
            .map { $0 }
    }

    func updateSet(_ setID: ExerciseSet.ID, exercise: String, reps: Int, weight: Int, rir: Int? = nil) {
        guard let dayIndex = selectedWorkoutDayIndex(),
              let setIndex = workoutSchedule[dayIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
        let metadata = Self.exerciseMetadata(for: exercise)
        workoutSchedule[dayIndex].sets[setIndex].exercise = metadata.displayName
        workoutSchedule[dayIndex].sets[setIndex].normalizedExercise = metadata.normalized
        workoutSchedule[dayIndex].sets[setIndex].category = metadata.category
        workoutSchedule[dayIndex].sets[setIndex].reps = reps
        workoutSchedule[dayIndex].sets[setIndex].weight = weight
        workoutSchedule[dayIndex].sets[setIndex].targetMinReps = metadata.range.min
        workoutSchedule[dayIndex].sets[setIndex].targetMaxReps = metadata.range.max
        workoutSchedule[dayIndex].sets[setIndex].rir = rir
        let updatedSet = workoutSchedule[dayIndex].sets[setIndex]

        let session = workoutSession(from: workoutSchedule[dayIndex])
        upsertLocalWorkoutSession(session)
        syncWorkoutSession(session, dayID: workoutSchedule[dayIndex].id)
        syncUpdatedExerciseSet(updatedSet)
        refreshHomeAfterLocalChange()
    }

    private func makeExerciseSet(exercise: String, reps: Int, weight: Int, rir: Int?) -> ExerciseSet {
        let metadata = Self.exerciseMetadata(for: exercise)
        return ExerciseSet(
            exercise: metadata.displayName,
            normalizedExercise: metadata.normalized,
            category: metadata.category,
            reps: reps,
            weight: weight,
            targetMinReps: metadata.range.min,
            targetMaxReps: metadata.range.max,
            rir: rir
        )
    }

    func deleteSet(_ setID: ExerciseSet.ID) {
        guard let dayIndex = selectedWorkoutDayIndex(),
              let setIndex = workoutSchedule[dayIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
        let removedSet = workoutSchedule[dayIndex].sets.remove(at: setIndex)

        let session = workoutSession(from: workoutSchedule[dayIndex])
        upsertLocalWorkoutSession(session)
        syncWorkoutSession(session, dayID: workoutSchedule[dayIndex].id)
        deleteCloudExerciseSet(removedSet)
        refreshHomeAfterLocalChange()
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
        refreshHomeAfterLocalChange()
    }

    private func updateMealFromCoach(id: String?, keyword: String?, title: String?, calories: Int?, protein: Int?) {
        guard let index = mealIndex(id: id, keyword: keyword) else {
            createMealFromCoachUpdate(keyword: keyword, title: title, calories: calories, protein: protein)
            return
        }
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

    private func createMealFromCoachUpdate(keyword: String?, title: String?, calories: Int?, protein: Int?) {
        guard calories != nil || protein != nil else { return }

        let resolvedTitle = Self.nonEmpty(title)
            ?? Self.nonEmpty(keyword)
            ?? "Meal"
        logMeal(
            title: Self.capitalizedFirst(resolvedTitle),
            calories: max(0, calories ?? 0),
            protein: max(0, protein ?? 0),
            imageData: nil
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func capitalizedFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
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
        } else {
            workouts.insert(session, at: 0)
        }
        workouts.sort { $0.date > $1.date }
    }

    func overloadRecommendation(for exercise: String, fallbackReps: Int, fallbackWeight: Int) -> OverloadRecommendation {
        let metadata = Self.exerciseMetadata(for: exercise)
        let selectedDate = selectedWorkoutDay?.date ?? Date()
        let selectedSplit = Self.splitKey(for: selectedWorkoutDay?.title ?? "")
        let previous = previousComparableSession(
            normalizedExercise: metadata.normalized,
            selectedSplit: selectedSplit,
            before: selectedDate
        )
        let previousSets = previous?.sets.filter { Self.comparisonKeys(for: $0).contains(metadata.normalized) } ?? []
        let topReps = metadata.range.max

        guard let previous, !previousSets.isEmpty else {
            return OverloadRecommendation(
                exercise: metadata.displayName,
                normalizedExercise: metadata.normalized,
                split: selectedSplit,
                category: metadata.category,
                targetMinReps: metadata.range.min,
                targetMaxReps: metadata.range.max,
                previousDate: nil,
                previousSets: [],
                suggestedWeight: fallbackWeight,
                suggestedReps: max(fallbackReps, metadata.range.min),
                reason: "No previous \(metadata.displayName) set found yet. Start inside \(metadata.range.min)-\(metadata.range.max) reps."
            )
        }

        let heaviest = previousSets.map(\.weight).max() ?? fallbackWeight
        let sameWeightSets = previousSets.filter { $0.weight == heaviest }
        let comparisonSets = sameWeightSets.isEmpty ? previousSets : sameWeightSets
        let allHitTop = comparisonSets.allSatisfy { $0.reps >= topReps }
        let hadZeroRIR = comparisonSets.contains { $0.rir == 0 }
        let suggestedWeight = allHitTop && !hadZeroRIR ? heaviest + 5 : heaviest
        let suggestedReps = allHitTop && !hadZeroRIR
            ? metadata.range.min
            : min(topReps, max((comparisonSets.map(\.reps).min() ?? fallbackReps) + 1, metadata.range.min))

        let reason: String
        if allHitTop && hadZeroRIR {
            reason = "You hit the top of the range last time, but a 0 RIR set says hold load and own it again."
        } else if allHitTop {
            reason = "You hit \(comparisonSets.map(\.reps).map(String.init).joined(separator: "/")) last time. Add 5 lb and restart the range."
        } else {
            reason = "Last time was \(comparisonSets.map { "\($0.reps)" }.joined(separator: "/")). Keep load and add reps toward \(topReps)."
        }

        return OverloadRecommendation(
            exercise: metadata.displayName,
            normalizedExercise: metadata.normalized,
            split: selectedSplit,
            category: metadata.category,
            targetMinReps: metadata.range.min,
            targetMaxReps: metadata.range.max,
            previousDate: previous.date,
            previousSets: comparisonSets,
            suggestedWeight: suggestedWeight,
            suggestedReps: suggestedReps,
            reason: reason
        )
    }

    private func previousComparableSession(normalizedExercise: String, selectedSplit: String, before selectedDate: Date) -> WorkoutSession? {
        let selectedDayStart = Calendar.current.startOfDay(for: selectedDate)
        let priorSessions = workouts
            .filter { session in
                Calendar.current.startOfDay(for: session.date) < selectedDayStart
                    && session.sets.contains { Self.comparisonKeys(for: $0).contains(normalizedExercise) }
            }
            .sorted { $0.date > $1.date }

        return priorSessions.first { Self.splitKey(for: $0.title) == selectedSplit } ?? priorSessions.first
    }

    private func logWeighIn(_ pounds: Double) {
        let weighIn = WeighIn(date: Date(), pounds: pounds)
        weighIns.append(weighIn)
        weighIns.sort { $0.date < $1.date }
        syncWeighIn(weighIn)
        refreshHomeAfterLocalChange()
        weeklyReview = metricsService.makeWeeklyReview(
            tasks: tasks,
            weighIns: weighIns,
            meals: meals,
            workouts: workouts,
            health: healthMetrics,
            isSickDay: isSickDay
        )
        syncWeeklyReview()
    }

    func refreshHealthMetrics() async {
        healthMetrics = await healthKitService.fetchTodaySnapshot()
        upsertLocalDailyMetricSnapshot()
        refreshGoalState()
        refreshLocalDailyCoachSnapshot()
        weeklyReview = metricsService.makeWeeklyReview(
            tasks: tasks,
            weighIns: weighIns,
            meals: meals,
            workouts: workouts,
            health: healthMetrics,
            isSickDay: isSickDay
        )
        syncDailyMetricSnapshot()
        await refreshDailyCoachSnapshot()
    }

    func refreshDailyInsights() async {
        await refreshHealthMetrics()
        await refreshGoalInsight()
        syncWeeklyReview()
    }

    private func refreshLocalDailyCoachSnapshot() {
        let energy = energyService.makeSnapshot(
            tasks: tasks,
            meals: meals,
            workouts: workouts,
            health: healthMetrics,
            isSickDay: isSickDay
        )
        todayEnergy = energy
        dailyCoachSnapshot = energyService.makeCoachSnapshot(
            energy: energy,
            tasks: tasks,
            meals: meals,
            workouts: workouts,
            health: healthMetrics,
            selectedWorkout: selectedWorkoutDay,
            isSickDay: isSickDay
        )
    }

    private func refreshHomeAfterLocalChange() {
        refreshGoalState()
        refreshLocalDailyCoachSnapshot()
        Task {
            await refreshGoalInsight()
            await refreshDailyCoachSnapshot()
        }
    }

    private func refreshGoalInsight() async {
        guard let context = await cloudContext,
              let cloudInsight = await SupabaseGateway.goalCoach(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                context: goalContext()
              ) else { return }
        goalInsight = cloudInsight
    }

    private func refreshDailyCoachSnapshot() async {
        let fallbackEnergy = todayEnergy
        let fallbackCoach = dailyCoachSnapshot
        guard let context = await cloudContext else { return }
        let payload = dailyCoachContext(energy: fallbackEnergy)
        if let cloudCoach = await SupabaseGateway.dailyCoach(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            context: payload
        ) {
            dailyCoachSnapshot = cloudCoach
            await syncDailyCoachSnapshot(cloudCoach, energy: fallbackEnergy, context: context)
            return
        }
        await syncDailyCoachSnapshot(fallbackCoach, energy: fallbackEnergy, context: context)
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
                "recent_meal_history": recentMealHistoryContext(),
                "yesterday_meals": meals(onDayOffset: 1).map(mealContext),
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
                "latest_session": latestSessionContext,
                "progressive_overload": overloadContext()
            ],
            "today_energy": todayEnergyContext(todayEnergy),
            "home_coach": dailyCoachContext(dailyCoachSnapshot),
            "goal": goalContext(),
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

    private func dailyCoachContext(energy: TodayEnergySnapshot) -> [String: Any] {
        let completedTasks = tasks.filter(\.isComplete)
        let missedTasks = tasks.filter { !$0.isComplete }
        let latestWorkout = workouts.sorted { $0.date > $1.date }.first
        let selectedWorkout = selectedWorkoutDay
        let habitFramework: [[String: Any]] = tasks.map {
            [
                "title": $0.title,
                "detail": $0.detail,
                "is_complete": $0.isComplete
            ]
        }
        let user: [String: Any] = [
            "goal": profile.goal,
            "training_level": profile.trainingLevel,
            "habitFramework": habitFramework
        ]
        let recovery: [String: Any] = [
            "sleepDurationMinutes": healthMetrics.sleepMinutes ?? NSNull(),
            "sleepDurationDeltaVs30d": healthMetrics.sleepDeltaVs30d ?? NSNull(),
            "hrv": healthMetrics.hrvMilliseconds ?? NSNull(),
            "hrvDeltaVs30d": healthMetrics.hrvDeltaVs30d ?? NSNull(),
            "restingHR": healthMetrics.restingHeartRate ?? NSNull(),
            "restingHRDeltaVs30d": healthMetrics.restingHeartRateDeltaVs30d ?? NSNull(),
            "respiratoryRate": healthMetrics.respiratoryRate ?? NSNull(),
            "respiratoryRateDeltaVs30d": healthMetrics.respiratoryRateDeltaVs30d ?? NSNull()
        ]
        let activityToday: [String: Any] = [
            "movePercent": healthMetrics.movePercent ?? NSNull(),
            "exerciseMinutes": healthMetrics.exerciseMinutes ?? NSNull(),
            "standHours": healthMetrics.standHours ?? NSNull(),
            "steps": healthMetrics.steps,
            "activeEnergyKcal": healthMetrics.activeEnergy,
            "workoutsCompleted": healthMetrics.workoutsToday
        ]
        let trainingLoad: [String: Any] = [
            "strainToday": healthMetrics.activeEnergy + (healthMetrics.workoutsToday * 120),
            "hardDaysLast7": healthMetrics.workoutsThisWeek,
            "plannedWorkoutToday": selectedWorkout.map(Self.workoutDayContext) ?? NSNull(),
            "latestWorkout": latestWorkout.map(Self.workoutSessionContext) ?? NSNull()
        ]
        let nutrition: [String: Any] = [
            "caloriesToday": caloriesToday,
            "calorieTarget": PTProtocol.calorieTarget,
            "proteinToday": proteinToday,
            "proteinTarget": PTProtocol.proteinTargetG,
            "mealsLoggedToday": todaysMeals.map { mealContext($0) }
        ]
        let habits: [String: Any] = [
            "completedToday": completedTasks.map { $0.title },
            "missedToday": missedTasks.map { $0.title },
            "highestLeverageHabitNow": missedTasks.first?.title ?? NSNull()
        ]
        let constraints: [String: Any] = [
            "isSickDay": isSickDay,
            "timezone": TimeZone.current.identifier
        ]

        let payload: [String: Any] = [
            "updateWindow": Self.coachUpdateWindow(),
            "user": user,
            "todaysEnergy": todayEnergyContext(energy),
            "recovery": recovery,
            "activityToday": activityToday,
            "trainingLoad": trainingLoad,
            "nutrition": nutrition,
            "habits": habits,
            "goal": goalContext(),
            "recommendationConstraints": constraints
        ]
        return payload
    }

    private func goalContext() -> [String: Any] {
        [
            "plan": [
                "title": goalPlan.title,
                "type": goalPlan.type,
                "start_date": Self.cloudDate(goalPlan.startDate),
                "end_date": Self.cloudDate(goalPlan.endDate),
                "start_weight": goalPlan.startWeight,
                "target_weight": goalPlan.targetWeight,
                "target_loss_percent": goalPlan.targetLossPercent,
                "active_calorie_min": goalPlan.activeCalorieMin,
                "active_calorie_max": goalPlan.activeCalorieMax,
                "calorie_target": goalPlan.calorieTarget,
                "protein_target": goalPlan.proteinTarget,
                "status": goalPlan.status,
                "body_profile": bodyProfileContext(goalPlan.bodyProfile)
            ],
            "progress": goalProgressContext(goalProgress),
            "insight": [
                "summary": goalInsight.summary,
                "suggestions": goalInsight.suggestions
            ]
        ]
    }

    private func goalProgressContext(_ progress: GoalProgress) -> [String: Any] {
        [
            "days_elapsed": progress.daysElapsed,
            "days_remaining": progress.daysRemaining,
            "total_days": progress.totalDays,
            "current_trend_weight": progress.currentTrendWeight ?? NSNull(),
            "expected_weight_today": progress.expectedWeightToday,
            "target_weight": progress.targetWeight,
            "pounds_lost": progress.poundsLost,
            "pounds_remaining": progress.poundsRemaining,
            "pace_status": progress.paceStatus,
            "pace_summary": progress.paceSummary,
            "seven_day_calories_average": progress.sevenDayCaloriesAverage ?? NSNull(),
            "seven_day_protein_average": progress.sevenDayProteinAverage ?? NSNull(),
            "seven_day_active_calories_average": progress.sevenDayActiveCaloriesAverage ?? NSNull(),
            "estimated_daily_burn": progress.estimatedDailyBurn,
            "estimated_daily_deficit": progress.estimatedDailyDeficit ?? NSNull(),
            "deficit_confidence": progress.deficitConfidence,
            "active_calorie_progress": progress.activeCalorieProgress,
            "timeline_progress": progress.timelineProgress
        ]
    }

    private func bodyProfileContext(_ profile: BodyProfile) -> [String: Any] {
        [
            "height_inches": profile.heightInches ?? NSNull(),
            "weight_source": profile.weightSource,
            "lean_mass_pounds": profile.leanMassPounds ?? NSNull(),
            "rmr_estimate": profile.rmrEstimate,
            "rmr_source": profile.rmrSource
        ]
    }

    private func todayEnergyContext(_ energy: TodayEnergySnapshot) -> [String: Any] {
        [
            "score": energy.score,
            "label": energy.label.lowercased(),
            "confidence": energy.confidence,
            "primaryDriver": energy.primaryDriver,
            "secondaryDrivers": energy.secondaryDrivers,
            "bestMove": energy.bestMove,
            "expandedExplanation": energy.expandedExplanation
        ]
    }

    private func dailyCoachContext(_ snapshot: DailyCoachSnapshot) -> [String: Any] {
        [
            "updateWindow": snapshot.updateWindow,
            "recommendationType": snapshot.recommendationType,
            "coachRead": snapshot.coachRead,
            "evidence": snapshot.evidence,
            "bestNextMove": snapshot.bestNextMove,
            "habitFocus": snapshot.habitFocus,
            "avoid": snapshot.avoid,
            "coachCue": snapshot.coachCue
        ]
    }

    private static func coachUpdateWindow(at date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "morning"
        case 12..<18: return "afternoon"
        default: return "evening"
        }
    }

    private static func update(fromHaiku raw: [String: Any]) -> CoachAppUpdate? {
        let type = (raw["type"] as? String) ?? (raw["kind"] as? String) ?? (raw["update"] as? String)
        switch type {
        case "task_completed":
            guard let keyword = raw["keyword"] as? String ?? raw["title"] as? String else { return nil }
            return .taskCompleted(keyword: keyword)
        case "weigh_in", "weigh-in", "weight_log", "body_weight", "weight":
            guard let pounds = Self.doubleValue(raw["pounds"])
                ?? Self.doubleValue(raw["value"])
                ?? Self.doubleValue(raw["weight"])
                ?? Self.doubleValue(raw["body_weight"]) else { return nil }
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
            return .workoutSet(exercise: normalizedExerciseName(exercise), reps: reps, weight: weight)
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

    private func recentMealHistoryContext() -> [[String: Any]] {
        meals
            .filter { $0.date < currentDay || Calendar.current.isDate($0.date, inSameDayAs: currentDay) }
            .sorted { $0.date > $1.date }
            .prefix(12)
            .map(mealContext)
    }

    private func meals(onDayOffset offset: Int) -> [MealLog] {
        guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: currentDay) else { return [] }
        return meals
            .filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    private func mealContext(_ meal: MealLog) -> [String: Any] {
        [
            "local_id": meal.id.uuidString,
            "cloud_id": meal.cloudID ?? "",
            "title": meal.title,
            "slot": mealSlot(for: meal).displayName,
            "calories": meal.calories,
            "protein_grams": meal.protein,
            "logged_at": Self.isoString(meal.date)
        ]
    }

    private static func exerciseSetContext(_ set: ExerciseSet) -> [String: Any] {
        [
            "exercise": set.exercise,
            "normalized_exercise": comparisonKey(for: set),
            "exercise_category": set.category ?? exerciseCategory(forNormalizedName: comparisonKey(for: set)),
            "reps": set.reps,
            "weight": set.weight,
            "target_min_reps": set.targetMinReps ?? NSNull(),
            "target_max_reps": set.targetMaxReps ?? NSNull(),
            "rir": set.rir ?? NSNull()
        ]
    }

    private func overloadContext() -> [String: Any] {
        let selectedSets = selectedWorkoutDay?.sets ?? []
        let uniqueExercises = Array(Set(selectedSets.map { Self.comparisonKey(for: $0) })).prefix(6)
        let recommendations = uniqueExercises.compactMap { key -> [String: Any]? in
            guard let set = selectedSets.last(where: { Self.comparisonKeys(for: $0).contains(key) }) else { return nil }
            let recommendation = overloadRecommendation(for: set.exercise, fallbackReps: set.reps, fallbackWeight: set.weight)
            return Self.overloadContext(from: recommendation)
        }

        return [
            "selected_split": Self.splitKey(for: selectedWorkoutDay?.title ?? ""),
            "rules": [
                "method": "double_progression",
                "load_jump_lb": 5,
                "same_exercise_only": true,
                "rir_suppresses_load_jump_at": 0
            ],
            "recommendations": Array(recommendations)
        ]
    }

    private static func overloadContext(from recommendation: OverloadRecommendation) -> [String: Any] {
        [
            "exercise": recommendation.exercise,
            "normalized_exercise": recommendation.normalizedExercise,
            "split": recommendation.split,
            "category": recommendation.category,
            "target_min_reps": recommendation.targetMinReps,
            "target_max_reps": recommendation.targetMaxReps,
            "has_history": recommendation.hasHistory,
            "previous_date": recommendation.previousDate.map(Self.cloudDate) ?? NSNull(),
            "previous_sets": recommendation.previousSets.map(exerciseSetContext),
            "suggested_weight": recommendation.suggestedWeight,
            "suggested_reps": recommendation.suggestedReps,
            "reason": recommendation.reason
        ]
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func shortID(_ id: String) -> String {
        id.isEmpty ? "unknown" : String(id.suffix(8))
    }

    private static func weightLogValue(from text: String) -> Double? {
        let lower = text.lowercased()
        let hasWeightIntent = lower.contains("weigh") || lower.contains("weight") || lower.contains("scale")
        let hasLogIntent = lower.contains("log")
            || lower.contains("record")
            || lower.contains("track")
            || lower.contains("add")
            || lower.contains("checked in")
            || lower.contains("came in")
            || lower.contains("i was")
            || lower.contains("i'm")
            || lower.contains("im ")
            || lower.contains("today")
        guard hasWeightIntent, hasLogIntent else { return nil }

        let pattern = #"(?<!\d)(\d{2,3}(?:\.\d{1,2})?)(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        let matches = regex.matches(in: lower, range: range)

        for match in matches {
            guard let valueRange = Range(match.range(at: 1), in: lower),
                  let value = Double(lower[valueRange]),
                  (80...500).contains(value) else { continue }
            return value
        }
        return nil
    }

    func testCloudSync() async {
        gateway.loadConfiguration()
        guard let context = await cloudContext else {
            cloudSyncStatus = SupabaseGateway.lastEvent
            return
        }
        await upsertProfile(context)
        let profileRows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "profiles",
            query: "select=id,display_name&id=eq.\(context.userID)&limit=1"
        )
        let weighRows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "weigh_ins",
            query: "select=id,pounds,measured_at&order=measured_at.desc&limit=5"
        )
        let parsedWeights = weighRows.compactMap(Self.weighIn(from:))
        cloudSyncStatus = profileRows.isEmpty
            ? "Connected as user \(Self.shortID(context.userID)), but profile read/write did not confirm. \(SupabaseGateway.lastEvent)"
            : "Cloud sync confirmed as user \(Self.shortID(context.userID)). Visible weigh-in rows: \(weighRows.count), parsed: \(parsedWeights.count). If dashboard rows have another user_id, RLS hides them from this app install."
    }

    // MARK: - Supabase sync

    private struct CloudContext {
        let base: URL
        let anonKey: String
        let token: String
        let userID: String
    }

    struct OverloadRecommendation {
        let exercise: String
        let normalizedExercise: String
        let split: String
        let category: String
        let targetMinReps: Int
        let targetMaxReps: Int
        let previousDate: Date?
        let previousSets: [ExerciseSet]
        let suggestedWeight: Int
        let suggestedReps: Int
        let reason: String

        var hasHistory: Bool { previousDate != nil && !previousSets.isEmpty }

        var previousSummary: String {
            guard hasHistory else { return "No prior set yet" }
            return previousSets.map { "\($0.weight)×\($0.reps)" }.joined(separator: ", ")
        }

        var targetSummary: String {
            "\(suggestedWeight) lb × \(suggestedReps)"
        }
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
        guard !isLoadingCloudData else { return }
        isLoadingCloudData = true
        defer { isLoadingCloudData = false }
        guard let context = await cloudContext else { return }

        await upsertProfile(context)
        _ = await ensureDailyLogID(for: currentDay, context: context)
        var loadedTasks = await loadTasks(context)
        if loadedTasks.isEmpty {
            await seedTodayTasksIfNeeded(context)
            loadedTasks = await loadTasks(context)
        }
        tasks = loadedTasks.isEmpty ? DailyTask.seed : loadedTasks
        normalizeMorningWeighInReminder()
        sortTasksForToday()

        let loadedMeals = await loadMeals(context)
        meals = loadedMeals

        let loadedWeighIns = await loadWeighIns(context)
        weighIns = loadedWeighIns.items

        let loadedMetrics = await loadDailyMetrics(context)
        dailyMetrics = loadedMetrics

        if let loadedGoal = await loadGoalPlan(context) {
            goalPlan = loadedGoal
        } else {
            goalPlan = defaultGoalPlan()
            await upsertGoalPlan(goalPlan, context: context)
        }
        refreshGoalState()

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
        if let loadedCoach = await loadDailyCoachSnapshot(context) {
            todayEnergy = loadedCoach.energy
            dailyCoachSnapshot = loadedCoach.coach
        }
        cloudSyncStatus = "Cloud loaded as user \(Self.shortID(context.userID)). Visible weigh-ins: \(loadedWeighIns.visibleRows), parsed: \(loadedWeighIns.items.count). New app events will write to Supabase."
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

    private func ensureDailyLogID(for date: Date, context: CloudContext) async -> String? {
        guard !dailyLogSupportUnavailable else { return nil }
        let day = Self.cloudDate(date)
        if let cached = cloudDayIDs[day] { return cached }

        let rows = await SupabaseGateway.insert(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "daily_logs",
            rows: [[
                "user_id": context.userID,
                "day_date": day,
                "timezone": TimeZone.current.identifier
            ]],
            upsertOnConflict: "user_id,day_date"
        )

        guard let id = rows.first?["id"] as? String else {
            dailyLogSupportUnavailable = true
            return nil
        }
        cloudDayIDs[day] = id
        return id
    }

    private static func withoutDayID(_ row: [String: Any]) -> [String: Any] {
        var copy = row
        copy.removeValue(forKey: "day_id")
        return copy
    }

    private static func withoutDayID(_ rows: [[String: Any]]) -> [[String: Any]] {
        rows.map(withoutDayID)
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

        let dayID = await ensureDailyLogID(for: Date(), context: context)
        let rows = tasks.enumerated().map { index, task in
            taskRow(task, context: context, sortOrder: index, date: Date(), dayID: dayID)
        }
        var inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "task_instances", rows: rows)
        if inserted.isEmpty, dayID != nil {
            inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "task_instances", rows: Self.withoutDayID(rows))
        }
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
        return await deduplicateTasks(rows, context: context)
    }

    private func deduplicateTasks(_ rows: [[String: Any]], context: CloudContext) async -> [DailyTask] {
        var keptRows: [[String: Any]] = []
        var seenKeys = Set<String>()
        var duplicateIDs: [String] = []

        for row in rows {
            let key = Self.taskKey(from: row)
            if seenKeys.insert(key).inserted {
                keptRows.append(row)
            } else if let id = row["id"] as? String {
                duplicateIDs.append(id)
            }
        }

        for id in duplicateIDs {
            await SupabaseGateway.delete(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "task_instances",
                match: "id=eq.\(id)"
            )
        }

        if !duplicateIDs.isEmpty {
            cloudSyncStatus = "Cleaned up \(duplicateIDs.count) duplicate task\(duplicateIDs.count == 1 ? "" : "s") from today's list."
        }
        return keptRows.compactMap(Self.task(from:))
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

    private func loadWeighIns(_ context: CloudContext) async -> (items: [WeighIn], visibleRows: Int) {
        let rows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "weigh_ins",
            query: "select=*&order=measured_at.asc&limit=120"
        )
        return (rows.compactMap(Self.weighIn(from:)), rows.count)
    }

    private func loadDailyMetrics(_ context: CloudContext) async -> [DailyMetricSnapshot] {
        let rows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "daily_metric_snapshots",
            query: "select=*&order=metric_date.asc&limit=90"
        )
        return rows.compactMap(Self.dailyMetric(from:))
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
            query: "select=*&order=started_at.desc&limit=90"
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

    private func loadGoalPlan(_ context: CloudContext) async -> GoalPlan? {
        let rows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "goal_plans",
            query: "select=*&status=eq.active&order=created_at.desc&limit=1"
        )
        return rows.first.flatMap(Self.goalPlan(from:))
    }

    private func loadDailyCoachSnapshot(_ context: CloudContext) async -> (energy: TodayEnergySnapshot, coach: DailyCoachSnapshot)? {
        let rows = await SupabaseGateway.select(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "daily_coach_snapshots",
            query: "select=*&day_date=eq.\(Self.cloudDate(Date()))&update_window=eq.\(Self.coachUpdateWindow())&limit=1"
        )
        return rows.first.flatMap(Self.dailyCoachSnapshot(from:))
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
            let dayID = await ensureDailyLogID(for: Date(), context: context)
            let row = taskRow(task, context: context, sortOrder: tasks.firstIndex(where: { $0.id == task.id }) ?? 0, date: Date(), dayID: dayID)
            if let cloudID = task.cloudID {
                let saved = await SupabaseGateway.update(base: context.base, anonKey: context.anonKey, token: context.token, table: "task_instances", match: "id=eq.\(cloudID)", values: row)
                if !saved, dayID != nil {
                    await SupabaseGateway.update(base: context.base, anonKey: context.anonKey, token: context.token, table: "task_instances", match: "id=eq.\(cloudID)", values: Self.withoutDayID(row))
                }
                cloudSyncStatus = SupabaseGateway.lastEvent
            } else {
                var inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "task_instances", rows: [row])
                if inserted.isEmpty, dayID != nil {
                    inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "task_instances", rows: [Self.withoutDayID(row)])
                }
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
            let dayID = await ensureDailyLogID(for: meal.date, context: context)
            var row: [String: Any] = [
                "user_id": context.userID,
                "eaten_at": Self.isoString(meal.date),
                "title": meal.title,
                "calories": meal.calories,
                "protein_grams": meal.protein,
                "source": "conversation"
            ]
            if let dayID { row["day_id"] = dayID }
            var inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "meals", rows: [row])
            if inserted.isEmpty, dayID != nil {
                inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "meals", rows: [Self.withoutDayID(row)])
            }
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
            let dayID = await ensureDailyLogID(for: weighIn.date, context: context)
            var row: [String: Any] = [
                "user_id": context.userID,
                "measured_at": Self.isoString(weighIn.date),
                "pounds": weighIn.pounds,
                "source": "conversation"
            ]
            if let dayID { row["day_id"] = dayID }
            var inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "weigh_ins", rows: [row])
            if inserted.isEmpty, dayID != nil {
                inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "weigh_ins", rows: [Self.withoutDayID(row)])
            }
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

    private func syncDailyMetricSnapshot() {
        guard !isLoadingCloudData else { return }
        let snapshot = healthMetrics
        let completed = tasks.filter(\.isComplete).count
        let total = max(tasks.count, 1)
        let completionRate = Double(completed) / Double(total)
        Task {
            guard let context = await cloudContext else { return }
            let dayID = await ensureDailyLogID(for: Date(), context: context)
            var row: [String: Any] = [
                "user_id": context.userID,
                "metric_date": Self.cloudDate(Date()),
                "steps": snapshot.steps,
                "active_energy_calories": snapshot.activeEnergy,
                "workouts_count": snapshot.workoutsToday,
                "task_completion_rate": completionRate
            ]
            row["sleep_minutes"] = snapshot.sleepMinutes ?? NSNull()
            row["sleep_delta_vs_30d"] = snapshot.sleepDeltaVs30d ?? NSNull()
            row["hrv_ms"] = snapshot.hrvMilliseconds ?? NSNull()
            row["hrv_delta_vs_30d"] = snapshot.hrvDeltaVs30d ?? NSNull()
            row["resting_heart_rate"] = snapshot.restingHeartRate ?? NSNull()
            row["resting_heart_rate_delta_vs_30d"] = snapshot.restingHeartRateDeltaVs30d ?? NSNull()
            row["respiratory_rate"] = snapshot.respiratoryRate ?? NSNull()
            row["respiratory_rate_delta_vs_30d"] = snapshot.respiratoryRateDeltaVs30d ?? NSNull()
            row["exercise_minutes"] = snapshot.exerciseMinutes ?? NSNull()
            row["stand_hours"] = snapshot.standHours ?? NSNull()
            row["move_percent"] = snapshot.movePercent ?? NSNull()
            if let dayID { row["day_id"] = dayID }
            var inserted = await SupabaseGateway.insert(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "daily_metric_snapshots",
                rows: [row],
                upsertOnConflict: "user_id,metric_date"
            )
            if inserted.isEmpty, dayID != nil {
                inserted = await SupabaseGateway.insert(
                    base: context.base,
                    anonKey: context.anonKey,
                    token: context.token,
                    table: "daily_metric_snapshots",
                    rows: [Self.withoutDayID(row)],
                    upsertOnConflict: "user_id,metric_date"
                )
            }
            cloudSyncStatus = inserted.isEmpty ? SupabaseGateway.lastEvent : "Daily metrics wrote to Supabase."
        }
    }

    private func syncExerciseSet(_ set: ExerciseSet, workout: WorkoutSession, dayID: WorkoutDayPlan.ID?, sortOrder: Int) {
        guard !isLoadingCloudData else { return }
        Task {
            guard let context = await cloudContext else { return }
            let workoutID = await ensureCloudWorkoutSession(workout, dayID: dayID, context: context)
            guard let workoutID else { return }
            let metadata = Self.exerciseMetadata(for: set.exercise)
            let category = set.category ?? metadata.category
            let range = Self.targetRepRange(forCategory: category)
            let fullRow: [String: Any] = [
                "user_id": context.userID,
                "workout_session_id": workoutID,
                "exercise": set.exercise,
                "normalized_exercise": set.normalizedExercise ?? metadata.normalized,
                "exercise_category": category,
                "reps": set.reps,
                "weight": set.weight,
                "sort_order": sortOrder,
                "target_min_reps": set.targetMinReps ?? range.min,
                "target_max_reps": set.targetMaxReps ?? range.max,
                "rir": set.rir.map { $0 } ?? NSNull()
            ]
            let legacyRow: [String: Any] = [
                "user_id": context.userID,
                "workout_session_id": workoutID,
                "exercise": set.exercise,
                "reps": set.reps,
                "weight": set.weight,
                "sort_order": sortOrder
            ]
            var inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "exercise_sets", rows: [fullRow])
            if inserted.isEmpty {
                inserted = await SupabaseGateway.insert(base: context.base, anonKey: context.anonKey, token: context.token, table: "exercise_sets", rows: [legacyRow])
            }
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
            let metadata = Self.exerciseMetadata(for: set.exercise)
            let category = set.category ?? metadata.category
            let range = Self.targetRepRange(forCategory: category)
            let saved = await SupabaseGateway.update(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "exercise_sets",
                match: "id=eq.\(cloudID)",
                values: [
                    "exercise": set.exercise,
                    "normalized_exercise": set.normalizedExercise ?? metadata.normalized,
                    "exercise_category": category,
                    "reps": set.reps,
                    "weight": set.weight,
                    "target_min_reps": set.targetMinReps ?? range.min,
                    "target_max_reps": set.targetMaxReps ?? range.max,
                    "rir": set.rir.map { $0 } ?? NSNull()
                ]
            )
            if !saved {
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
            }
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
        let cloudDayID = await ensureDailyLogID(for: workout.date, context: context)
        let row = workoutSessionRow(workout, includeNotes: true, context: context, dayID: cloudDayID)
        let noDayRow = Self.withoutDayID(row)
        let minimalRow = workoutSessionRow(workout, includeNotes: false, context: context, dayID: nil)

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
                let savedWithoutDay = await SupabaseGateway.update(
                    base: context.base,
                    anonKey: context.anonKey,
                    token: context.token,
                    table: "workout_sessions",
                    match: "id=eq.\(cloudID)",
                    values: noDayRow
                )
                if !savedWithoutDay {
                    await SupabaseGateway.update(
                        base: context.base,
                        anonKey: context.anonKey,
                        token: context.token,
                        table: "workout_sessions",
                        match: "id=eq.\(cloudID)",
                        values: minimalRow
                    )
                }
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
                let savedWithoutDay = await SupabaseGateway.update(
                    base: context.base,
                    anonKey: context.anonKey,
                    token: context.token,
                    table: "workout_sessions",
                    match: "id=eq.\(existingID)",
                    values: noDayRow
                )
                if !savedWithoutDay {
                    await SupabaseGateway.update(
                        base: context.base,
                        anonKey: context.anonKey,
                        token: context.token,
                        table: "workout_sessions",
                        match: "id=eq.\(existingID)",
                        values: minimalRow
                    )
                }
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
                rows: [noDayRow]
            )
        }
        if inserted.isEmpty {
            inserted = await SupabaseGateway.insert(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "workout_sessions",
                rows: [minimalRow]
            )
        }
        guard let cloudID = inserted.first?["id"] as? String else {
            cloudSyncStatus = SupabaseGateway.lastEvent
            return nil
        }
        applyCloudWorkoutID(cloudID, dayID: dayID, workoutDate: workout.date)
        return cloudID
    }

    private func workoutSessionRow(_ workout: WorkoutSession, includeNotes: Bool, context: CloudContext, dayID: String?) -> [String: Any] {
        var row: [String: Any] = [
            "user_id": context.userID,
            "started_at": Self.isoString(workout.date),
            "title": workout.title,
            "focus": workout.focus,
            "is_complete": workout.isComplete
        ]
        if let dayID { row["day_id"] = dayID }
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

    private func syncGoalPlan(_ plan: GoalPlan) {
        guard !isLoadingCloudData else { return }
        Task {
            guard let context = await cloudContext else { return }
            await upsertGoalPlan(plan, context: context)
        }
    }

    private func upsertGoalPlan(_ plan: GoalPlan, context: CloudContext) async {
        let row = goalPlanRow(plan, context: context)
        if let cloudID = plan.cloudID {
            await SupabaseGateway.update(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "goal_plans",
                match: "id=eq.\(cloudID)",
                values: row
            )
            cloudSyncStatus = SupabaseGateway.lastEvent
        } else {
            let inserted = await SupabaseGateway.insert(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "goal_plans",
                rows: [row]
            )
            cloudSyncStatus = inserted.isEmpty ? SupabaseGateway.lastEvent : "Goal plan wrote to Supabase."
            if let id = inserted.first?["id"] as? String {
                goalPlan.cloudID = id
            }
        }
    }

    private func goalPlanRow(_ plan: GoalPlan, context: CloudContext) -> [String: Any] {
        [
            "user_id": context.userID,
            "title": plan.title,
            "goal_type": plan.type,
            "start_date": Self.cloudDate(plan.startDate),
            "end_date": Self.cloudDate(plan.endDate),
            "start_weight": plan.startWeight,
            "target_loss_percent": plan.targetLossPercent,
            "target_weight": plan.targetWeight,
            "active_calorie_min": plan.activeCalorieMin,
            "active_calorie_max": plan.activeCalorieMax,
            "calorie_target": plan.calorieTarget,
            "protein_target": plan.proteinTarget,
            "status": plan.status,
            "body_profile": bodyProfileContext(plan.bodyProfile)
        ]
    }

    private func syncDailyCoachSnapshot(_ coach: DailyCoachSnapshot, energy: TodayEnergySnapshot, context: CloudContext) async {
        guard !isLoadingCloudData else { return }
        let dayID = await ensureDailyLogID(for: Date(), context: context)
        var row: [String: Any] = [
            "user_id": context.userID,
            "day_date": Self.cloudDate(Date()),
            "update_window": coach.updateWindow,
            "energy_snapshot": todayEnergyContext(energy),
            "coach_snapshot": dailyCoachContext(coach)
        ]
        if let dayID { row["day_id"] = dayID }
        var inserted = await SupabaseGateway.insert(
            base: context.base,
            anonKey: context.anonKey,
            token: context.token,
            table: "daily_coach_snapshots",
            rows: [row],
            upsertOnConflict: "user_id,day_date,update_window"
        )
        if inserted.isEmpty, dayID != nil {
            inserted = await SupabaseGateway.insert(
                base: context.base,
                anonKey: context.anonKey,
                token: context.token,
                table: "daily_coach_snapshots",
                rows: [Self.withoutDayID(row)],
                upsertOnConflict: "user_id,day_date,update_window"
            )
        }
        cloudSyncStatus = inserted.isEmpty ? SupabaseGateway.lastEvent : "Daily coach wrote to Supabase."
    }

    private func taskRow(_ task: DailyTask, context: CloudContext, sortOrder: Int, date: Date, dayID: String?) -> [String: Any] {
        var row: [String: Any] = [
            "user_id": context.userID,
            "task_date": Self.cloudDate(date),
            "title": task.title,
            "detail": task.detail,
            "system_image": task.systemImage,
            "is_complete": task.isComplete,
            "completed_at": task.completedAt.map(Self.isoString) ?? NSNull(),
            "sort_order": sortOrder
        ]
        if let dayID { row["day_id"] = dayID }
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

    private static func taskKey(from row: [String: Any]) -> String {
        if let key = row["task_key"] as? String, !key.isEmpty {
            return key
        }
        return taskKey(title: row["title"] as? String ?? "")
    }

    private static func taskKey(title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func normalizedExerciseName(_ rawName: String) -> String {
        let compact = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
            .replacingOccurrences(of: #"[/_\-]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compact.isEmpty else { return "Exercise" }

        let aliases: [String: String] = [
            "bench": "Bench Press",
            "bench press": "Bench Press",
            "barbell bench": "Barbell Bench Press",
            "bb bench": "Barbell Bench Press",
            "incline bench": "Incline Bench Press",
            "incline db press": "Incline Dumbbell Press",
            "db incline press": "Incline Dumbbell Press",
            "db press": "Dumbbell Press",
            "dumbbell press": "Dumbbell Press",
            "ohp": "Overhead Press",
            "overhead press": "Overhead Press",
            "shoulder press": "Shoulder Press",
            "squat": "Back Squat",
            "back squat": "Back Squat",
            "front squat": "Front Squat",
            "deadlift": "Deadlift",
            "rdl": "Romanian Deadlift",
            "romanian deadlift": "Romanian Deadlift",
            "lat pulldown": "Lat Pulldown",
            "pulldown": "Lat Pulldown",
            "pull down": "Lat Pulldown",
            "row": "Row",
            "barbell row": "Barbell Row",
            "cable row": "Cable Row",
            "seated row": "Seated Cable Row",
            "leg press": "Leg Press",
            "leg curl": "Leg Curl",
            "hamstring curl": "Hamstring Curl",
            "leg extension": "Leg Extension",
            "calf raise": "Calf Raise",
            "rope crunch": "Rope Cable Crunch",
            "rope crunches": "Rope Cable Crunch",
            "cable crunch": "Cable Crunch",
            "reverse crunch": "Reverse Crunch",
            "reverse crunches": "Reverse Crunch",
            "curl": "Biceps Curl",
            "bicep curl": "Biceps Curl",
            "bicep curls": "Biceps Curl",
            "biceps curl": "Biceps Curl",
            "biceps curls": "Biceps Curl",
            "cable curl": "Cable Biceps Curl",
            "cable curls": "Cable Biceps Curl",
            "cable bicep curl": "Cable Biceps Curl",
            "cable bicep curls": "Cable Biceps Curl",
            "cable biceps curl": "Cable Biceps Curl",
            "cable biceps curls": "Cable Biceps Curl",
            "db curl": "Dumbbell Biceps Curl",
            "db curls": "Dumbbell Biceps Curl",
            "dumbbell curl": "Dumbbell Biceps Curl",
            "dumbbell curls": "Dumbbell Biceps Curl",
            "barbell curl": "Barbell Biceps Curl",
            "barbell curls": "Barbell Biceps Curl",
            "tricep pushdown": "Triceps Pushdown",
            "triceps pushdown": "Triceps Pushdown"
        ]

        if let alias = aliases[compact] {
            return alias
        }

        let expanded = compact
            .split(separator: " ")
            .map { word -> String in
                switch word {
                case "db": return "Dumbbell"
                case "bb": return "Barbell"
                case "ez": return "EZ"
                case "rdl": return "Romanian Deadlift"
                default:
                    return word.prefix(1).uppercased() + word.dropFirst()
                }
            }
            .joined(separator: " ")

        return expanded
    }

    private static func normalizedExerciseKey(_ rawName: String) -> String {
        normalizedExerciseName(rawName)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func comparisonKey(for set: ExerciseSet) -> String {
        let keys = comparisonKeys(for: set)
        let displayKey = normalizedExerciseKey(set.exercise)
        return keys.contains(displayKey) ? displayKey : (keys.first ?? displayKey)
    }

    private static func comparisonKeys(for set: ExerciseSet) -> Set<String> {
        var keys: Set<String> = [normalizedExerciseKey(set.exercise)]
        if let normalizedExercise = set.normalizedExercise {
            keys.insert(normalizedExerciseKey(normalizedExercise))
        }
        return keys
    }

    private static func exerciseMetadata(for exercise: String) -> (displayName: String, normalized: String, category: String, range: (min: Int, max: Int)) {
        let displayName = normalizedExerciseName(exercise)
        let normalized = normalizedExerciseKey(displayName)
        let category = exerciseCategory(forNormalizedName: normalized)
        return (displayName, normalized, category, targetRepRange(forCategory: category))
    }

    private static func exerciseCategory(forNormalizedName name: String) -> String {
        if name.contains("bench press") || name == "back squat" || name == "front squat" || name == "deadlift" || name == "overhead press" {
            return "main_compound"
        }
        if name.contains("romanian deadlift") || name.contains("leg press") || name.contains("row") || name.contains("pulldown") || name.contains("dumbbell press") || name.contains("incline") {
            return "secondary_compound"
        }
        if name.contains("crunch") || name.contains("plank") || name.contains("abs") {
            return "abs"
        }
        return "accessory"
    }

    private static func targetRepRange(forCategory category: String) -> (min: Int, max: Int) {
        switch category {
        case "main_compound": return (6, 10)
        case "secondary_compound": return (8, 12)
        case "abs": return (12, 20)
        default: return (10, 15)
        }
    }

    private static func splitKey(for title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("push") { return "Push" }
        if lower.contains("pull") { return "Pull" }
        if lower.contains("leg") { return "Legs + Abs" }
        if lower.contains("cardio") { return "Big Cardio" }
            return title.isEmpty ? "Training" : title
    }

    func previousWorkoutForSelectedSplit() -> WorkoutSession? {
        guard let selected = selectedWorkoutDay else { return nil }
        let split = Self.splitKey(for: selected.title)
        let selectedDayStart = Calendar.current.startOfDay(for: selected.date)
        return workouts
            .filter { Calendar.current.startOfDay(for: $0.date) < selectedDayStart && Self.splitKey(for: $0.title) == split }
            .sorted { $0.date > $1.date }
            .first
    }

    func splitTitle(for day: WorkoutDayPlan) -> String {
        Self.splitKey(for: day.title)
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
        guard let pounds = doubleValue(row["pounds"]) else { return nil }
        return WeighIn(
            cloudID: row["id"] as? String,
            date: (row["measured_at"] as? String).flatMap(Self.date(from:)) ?? Date(),
            pounds: pounds
        )
    }

    private static func dailyMetric(from row: [String: Any]) -> DailyMetricSnapshot? {
        guard let rawDate = row["metric_date"] as? String else { return nil }
        return DailyMetricSnapshot(
            cloudID: row["id"] as? String,
            date: dateOnly(from: rawDate) ?? Date(),
            steps: (row["steps"] as? NSNumber)?.intValue ?? 0,
            activeEnergy: (row["active_energy_calories"] as? NSNumber)?.intValue ?? 0,
            workoutsCount: (row["workouts_count"] as? NSNumber)?.intValue ?? 0,
            taskCompletionRate: doubleValue(row["task_completion_rate"])
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
        let displayName = normalizedExerciseName(exercise)
        let normalized = normalizedExerciseKey(row["normalized_exercise"] as? String ?? displayName)
        let metadata = exerciseMetadata(for: normalized)
        let category = row["exercise_category"] as? String ?? metadata.category
        let range = targetRepRange(forCategory: category)
        return ExerciseSet(
            cloudID: row["id"] as? String,
            exercise: displayName,
            normalizedExercise: normalized,
            category: category,
            reps: (row["reps"] as? NSNumber)?.intValue ?? 0,
            weight: (row["weight"] as? NSNumber)?.intValue ?? 0,
            targetMinReps: (row["target_min_reps"] as? NSNumber)?.intValue ?? range.min,
            targetMaxReps: (row["target_max_reps"] as? NSNumber)?.intValue ?? range.max,
            rir: (row["rir"] as? NSNumber)?.intValue
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

    private static func goalPlan(from row: [String: Any]) -> GoalPlan? {
        guard let start = (row["start_date"] as? String).flatMap(Self.dateOnly(from:)),
              let end = (row["end_date"] as? String).flatMap(Self.dateOnly(from:)),
              let startWeight = doubleValue(row["start_weight"]) else { return nil }
        let targetLoss = doubleValue(row["target_loss_percent"]) ?? 0.10
        let targetWeight = doubleValue(row["target_weight"]) ?? (startWeight * (1 - targetLoss))
        return GoalPlan(
            cloudID: row["id"] as? String,
            title: row["title"] as? String ?? "Cut to September 1",
            type: row["goal_type"] as? String ?? "cut",
            startDate: start,
            endDate: end,
            startWeight: startWeight,
            targetLossPercent: targetLoss,
            targetWeight: targetWeight,
            activeCalorieMin: (row["active_calorie_min"] as? NSNumber)?.intValue ?? 800,
            activeCalorieMax: (row["active_calorie_max"] as? NSNumber)?.intValue ?? 1_000,
            calorieTarget: (row["calorie_target"] as? NSNumber)?.intValue ?? PTProtocol.calorieTarget,
            proteinTarget: (row["protein_target"] as? NSNumber)?.intValue ?? PTProtocol.proteinTargetG,
            status: row["status"] as? String ?? "active",
            bodyProfile: bodyProfile(from: row["body_profile"] as? [String: Any])
        )
    }

    private static func bodyProfile(from json: [String: Any]?) -> BodyProfile {
        guard let json else { return .seed }
        return BodyProfile(
            heightInches: doubleValue(json["height_inches"]),
            weightSource: json["weight_source"] as? String ?? BodyProfile.seed.weightSource,
            leanMassPounds: doubleValue(json["lean_mass_pounds"]),
            rmrEstimate: (json["rmr_estimate"] as? NSNumber)?.intValue ?? BodyProfile.seed.rmrEstimate,
            rmrSource: json["rmr_source"] as? String ?? BodyProfile.seed.rmrSource
        )
    }

    private static func dailyCoachSnapshot(from row: [String: Any]) -> (energy: TodayEnergySnapshot, coach: DailyCoachSnapshot)? {
        guard let energyJSON = row["energy_snapshot"] as? [String: Any],
              let coachJSON = row["coach_snapshot"] as? [String: Any] else { return nil }
        return (todayEnergy(from: energyJSON), dailyCoach(from: coachJSON))
    }

    private static func todayEnergy(from json: [String: Any]) -> TodayEnergySnapshot {
        TodayEnergySnapshot(
            score: (json["score"] as? NSNumber)?.intValue ?? TodayEnergySnapshot.seed.score,
            label: capitalizedLabel(json["label"] as? String ?? TodayEnergySnapshot.seed.label),
            confidence: doubleValue(json["confidence"]) ?? TodayEnergySnapshot.seed.confidence,
            primaryDriver: json["primaryDriver"] as? String ?? json["primary_driver"] as? String ?? TodayEnergySnapshot.seed.primaryDriver,
            secondaryDrivers: stringArray(json["secondaryDrivers"] ?? json["secondary_drivers"]),
            bestMove: json["bestMove"] as? String ?? json["best_move"] as? String ?? TodayEnergySnapshot.seed.bestMove,
            expandedExplanation: json["expandedExplanation"] as? String ?? json["expanded_explanation"] as? String ?? TodayEnergySnapshot.seed.expandedExplanation
        )
    }

    private static func dailyCoach(from json: [String: Any]) -> DailyCoachSnapshot {
        DailyCoachSnapshot(
            updateWindow: json["updateWindow"] as? String ?? json["update_window"] as? String ?? Self.coachUpdateWindow(),
            recommendationType: json["recommendationType"] as? String ?? json["recommendation_type"] as? String ?? "maintain",
            coachRead: json["coachRead"] as? String ?? json["coach_read"] as? String ?? DailyCoachSnapshot.seed.coachRead,
            evidence: stringArray(json["evidence"]),
            bestNextMove: json["bestNextMove"] as? String ?? json["best_next_move"] as? String ?? DailyCoachSnapshot.seed.bestNextMove,
            habitFocus: json["habitFocus"] as? String ?? json["habit_focus"] as? String ?? DailyCoachSnapshot.seed.habitFocus,
            avoid: stringArray(json["avoid"]),
            coachCue: json["coachCue"] as? String ?? json["coach_cue"] as? String ?? DailyCoachSnapshot.seed.coachCue
        )
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let strings = value as? [String] { return strings }
        if let values = value as? [Any] { return values.compactMap { $0 as? String } }
        return []
    }

    private static func capitalizedLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "high": return "High"
        case "limited": return "Limited"
        case "depleted": return "Depleted"
        default: return "Stable"
        }
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

    private static func dateOnly(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
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

private enum SupabaseAuthStore {
    private static let service = "com.leofelix.loop.supabase.auth"

    private enum Account {
        static let refreshToken = "refresh_token"
        static let userID = "user_id"
        static let email = "email"
    }

    private enum LegacyKey {
        static let refreshToken = "sb_refresh_token"
        static let userID = "sb_user_id"
        static let email = "sb_email"
    }

    static var refreshToken: String? {
        read(Account.refreshToken) ?? UserDefaults.standard.string(forKey: LegacyKey.refreshToken)
    }

    static var userID: String? {
        read(Account.userID) ?? UserDefaults.standard.string(forKey: LegacyKey.userID)
    }

    static var email: String? {
        read(Account.email) ?? UserDefaults.standard.string(forKey: LegacyKey.email)
    }

    static func store(refreshToken: String, userID: String, email: String?) {
        write(refreshToken, account: Account.refreshToken)
        write(userID, account: Account.userID)
        if let email, !email.isEmpty {
            write(email, account: Account.email)
            UserDefaults.standard.set(email, forKey: LegacyKey.email)
        }

        UserDefaults.standard.set(refreshToken, forKey: LegacyKey.refreshToken)
        UserDefaults.standard.set(userID, forKey: LegacyKey.userID)
    }

    static func clear() {
        [Account.refreshToken, Account.userID, Account.email].forEach(delete)
        [LegacyKey.refreshToken, LegacyKey.userID, LegacyKey.email].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }

    static func migrateFromUserDefaultsIfNeeded() {
        if read(Account.refreshToken) == nil,
           let token = UserDefaults.standard.string(forKey: LegacyKey.refreshToken) {
            write(token, account: Account.refreshToken)
        }
        if read(Account.userID) == nil,
           let id = UserDefaults.standard.string(forKey: LegacyKey.userID) {
            write(id, account: Account.userID)
        }
        if read(Account.email) == nil,
           let email = UserDefaults.standard.string(forKey: LegacyKey.email) {
            write(email, account: Account.email)
        }
    }

    private static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
