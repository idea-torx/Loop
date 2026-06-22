import Foundation

/// Single source of truth for Leo's "Break 170" protocol (mirrors claude-pt.md).
/// Update these as the plan evolves; the coach briefing reads from here.
enum PTProtocol {
    static let name = "Leo"
    static let goal = "Break 170"
    static let latestWeight = 169.8
    static let sevenDayAvg = 170.1
    static let calorieRange = "2,100–2,300"
    static let proteinRange = "160–175g"
    static let stepGoal = "8–10k"
    static let calorieTarget = 2_200
    static let proteinTargetG = 170

    /// Training focus by weekday (1 = Sunday … 7 = Saturday).
    static func focus(forWeekday weekday: Int) -> String {
        switch weekday {
        case 1: return "full-body rotation"
        case 2: return "rest + batch cook"
        case 3: return "back + biceps"
        case 4: return "chest + triceps"
        case 5: return "legs"
        case 6: return "pull & arms"
        default: return "chest + triceps"   // Saturday
        }
    }

    static var todaysFocus: String {
        focus(forWeekday: Calendar.current.component(.weekday, from: Date()))
    }

    static var isTrainingDay: Bool {
        Calendar.current.component(.weekday, from: Date()) != 2   // Monday = rest
    }
}

/// Builds the coach's time-of-day opening check-in.
enum CoachBriefing {
    enum Window { case morning, midday, dinner, gym, night }

    static func window(at date: Date) -> Window {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: return .morning
        case 11..<15: return .midday
        case 15..<17: return .dinner
        case 17..<21: return .gym
        default: return .night
        }
    }

    static func opening(at date: Date = Date()) -> String {
        let focus = PTProtocol.todaysFocus
        let rest = !PTProtocol.isTrainingDay

        switch window(at: date) {
        case .morning:
            return """
            Morning, Leo. Weigh-in first — post-bathroom, pre-coffee.
            You closed at \(PTProtocol.latestWeight.formatted()), 7-day avg \(PTProtocol.sevenDayAvg.formatted()). Under 170 and pointed the right way.
            Today's \(focus). Fuel it: \(PTProtocol.calorieRange) cal, protein \(PTProtocol.proteinRange).
            What's the scale say?
            """
        case .midday:
            return """
            Lunch window, Leo. Protein-first — chicken wrap, salad sandwich, or chicken + rice + greens.
            Easy on the heavy dressings, and walk 10–15 after to bank steps toward \(PTProtocol.stepGoal).
            \(rest ? "Rest day, so food discipline is the whole game today." : "You've got \(focus) later — keep the tank topped up.")
            What are you eating?
            """
        case .dinner:
            return """
            Dinner's the big protein hit, Leo. Chicken + potatoes + broccoli, or salmon + potato + greens.
            Goal is landing protein at \(PTProtocol.proteinRange) by bed.
            A 20–30 min walk after does more than you'd think.
            What's on the plate?
            """
        case .gym:
            if rest {
                return """
                Rest day, Leo — no lift tonight. Steps, mobility, and an early-ish night.
                Keep food on plan: \(PTProtocol.calorieRange) cal, protein \(PTProtocol.proteinRange).
                Tomorrow we're back under the bar.
                Anything feeling beat up I should plan around?
                """
            }
            return """
            Gym time, Leo. Tonight's \(focus).
            Train 1–2 reps shy of failure — compound-first, then arms.
            Call your sets as you go ("bench 185 x 5, 5, 4") and I'll log them and hand you targets to beat next time.
            What are we opening with?
            """
        case .night:
            return """
            Protein check, Leo. If you're shy of ~165g, the 9 PM shake closes the gap — it's already in the budget.
            Blend with frozen banana/PB if you want it to feel like a treat.
            How'd today land — food, steps\(rest ? "" : ", training")?
            """
        }
    }
}

/// Parses natural-language commands the coach can act on directly (reminders, meals).
enum CommandParser {
    enum ReminderCommand {
        case add(title: String, time: Date?)
        case move(keyword: String, time: Date)
        case remove(keyword: String)
    }

    private static let stopWords: Set<String> = [
        "delete", "remove", "cancel", "move", "change", "set", "reschedule", "make",
        "my", "the", "a", "an", "reminder", "reminders", "task", "nudge", "alarm",
        "to", "at", "for", "please", "remind", "me", "of", "on"
    ]

    static func reminderCommand(from text: String) -> ReminderCommand? {
        let lower = text.lowercased()
        let mentionsReminder = lower.contains("remind") || lower.contains("reminder")
            || lower.contains("nudge") || lower.contains("alarm")

        // Remove: "delete the evening review reminder"
        if (lower.contains("delete") || lower.contains("remove") || lower.contains("cancel")),
           mentionsReminder || lower.contains("task") {
            let keyword = extractKeyword(from: lower)
            return keyword.isEmpty ? nil : .remove(keyword: keyword)
        }

        // Add: "remind me to take creatine at 9pm"
        if let range = lower.range(of: "remind me to ") {
            let rest = String(lower[range.upperBound...])
            let time = parseTime(from: rest)
            let title = cleanTitle(from: rest)
            return title.isEmpty ? nil : .add(title: title, time: time)
        }

        // Move: "move my weigh-in to 8am" / "change dinner reminder to 6:30"
        if (lower.contains("move") || lower.contains("change") || lower.contains("reschedule")
            || lower.contains("set") || lower.contains("make")),
           let time = parseTime(from: lower) {
            let keyword = extractKeyword(from: lower)
            return keyword.isEmpty ? nil : .move(keyword: keyword, time: time)
        }

        return nil
    }

    /// Returns a meal description if the message reads like a meal log, else nil.
    static func mealLog(from text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("?") { return nil }
        if reminderCommand(from: text) != nil { return nil }

        let adviceWords = ["should i", "what should", "what can", "can i", "could i", "recommend",
                           "advice", "ideas", "idea", "healthy", "better", "instead", "option"]
        if adviceWords.contains(where: { lower.contains($0) }) { return nil }

        let explicitLogWords = ["log", "track", "record", "add this meal", "add meal"]
        let declarativeMealWords = ["i ate", "i had", "just ate", "just had", "had ", "lunch was",
                                    "dinner was", "breakfast was", "snack was", "for lunch i",
                                    "for dinner i", "for breakfast i"]
        let isMealLog = explicitLogWords.contains { lower.contains($0) }
            || declarativeMealWords.contains { lower.contains($0) }
        guard isMealLog else { return nil }

        // Need some actual content, not just "lunch done".
        let words = lower.split(separator: " ")
        guard words.count >= 3 else { return nil }
        return text
    }

    static func mealKeyword(in text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("breakfast") { return "Morning weigh-in" }
        if lower.contains("lunch") { return "Lunch" }
        if lower.contains("dinner") { return "Dinner" }
        return nil
    }

    // MARK: Helpers

    private static func cleanTitle(from text: String) -> String {
        // Drop a trailing "at <time>" clause, then tidy.
        var working = text
        if let atRange = working.range(of: " at ", options: .backwards) {
            working = String(working[..<atRange.lowerBound])
        }
        return working
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalizedFirst
    }

    private static func extractKeyword(from text: String) -> String {
        // Strip a time clause first.
        var working = text
        if let atRange = working.range(of: " to ", options: .backwards) {
            working = String(working[..<atRange.lowerBound])
        }
        let tokens = working
            .replacingOccurrences(of: "-", with: " ")
            .split { !$0.isLetter }
            .map(String.init)
            .filter { !stopWords.contains($0) && $0.count > 1 }
        return tokens.joined(separator: " ")
    }

    /// Parse a clock time like "8", "8:45", "9am", "6:30 pm", "noon".
    static func parseTime(from text: String) -> Date? {
        let lower = text.lowercased()
        if lower.contains("noon") { return at(12, 0) }
        if lower.contains("midnight") { return at(0, 0) }

        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#) else { return nil }
        let ns = lower as NSString
        guard let match = regex.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length)) else { return nil }

        func group(_ i: Int) -> String? {
            let r = match.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }

        guard var hour = group(1).flatMap(Int.init) else { return nil }
        let minute = group(2).flatMap(Int.init) ?? 0
        let meridiem = group(3)

        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return at(hour, minute)
    }

    private static func at(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

actor CoachService {
    func respond(to message: String, state: AppState) async -> CoachResponse {
        let lower = message.lowercased()
        var updates: [CoachAppUpdate] = []

        if lower.contains("weigh") || lower.contains("weight") {
            if let number = firstNumber(in: lower) {
                updates.append(.weighIn(number))
            }
        }

        if lower.contains("lunch") || lower.contains("dinner") || lower.contains("ate") {
            updates.append(.taskCompleted(keyword: lower.contains("dinner") ? "Dinner" : "Lunch"))
            updates.append(.meal(title: message, calories: 650, protein: 40))
        }

        if lower.contains("gym") || lower.contains("workout") || lower.contains("lift") {
            updates.append(.taskCompleted(keyword: "Workout"))
        }

        if lower.contains("earlier") && lower.contains("notification") {
            updates.append(.mealTiming("Move nudges earlier when the day looks crowded."))
        }

        if lower.contains("gentle") || lower.contains("direct") || lower.contains("strict") {
            updates.append(.notificationTone(message))
        }

        let reply = makeReply(for: lower, updates: updates)
        return CoachResponse(reply: reply, updates: updates)
    }

    func respondToWorkoutLog(_ message: String, state: AppState) async -> CoachResponse {
        let sets = parseWorkoutSets(from: message)
        var updates: [CoachAppUpdate] = [.taskCompleted(keyword: "Workout")]
        updates.append(contentsOf: sets.map { .workoutSet(exercise: $0.exercise, reps: $0.reps, weight: $0.weight) })

        let reply: String
        if sets.isEmpty {
            reply = "I heard the workout note. I did not see a clean set pattern yet, so I saved the context mentally. Try something like: bench 185 x 5, 5, 4 or rows 145 for 8."
        } else {
            let volume = sets.reduce(0) { $0 + ($1.reps * $1.weight) }
            reply = "Logged \(sets.count) set\(sets.count == 1 ? "" : "s") for \(volume.formatted()) lb of volume. Keep talking to me like that and I’ll keep the session tidy."
        }

        return CoachResponse(reply: reply, updates: updates)
    }

    func configureWorkoutDay(_ message: String, state: AppState) async -> CoachResponse {
        let lower = message.lowercased()
        let title: String
        let focus: String

        if lower.contains("lower") || lower.contains("legs") || lower.contains("squat") {
            title = "Lower Strength"
            focus = "Squat pattern, hinge, unilateral work, core"
        } else if lower.contains("upper") || lower.contains("bench") || lower.contains("press") {
            title = "Upper Strength"
            focus = "Press, row, vertical pull, arms"
        } else if lower.contains("cardio") || lower.contains("conditioning") || lower.contains("zone") {
            title = "Conditioning"
            focus = "Zone 2 base, incline walk, or intervals"
        } else if lower.contains("rest") || lower.contains("recovery") || lower.contains("sore") {
            title = "Recovery"
            focus = "Steps, mobility, sleep, and soreness management"
        } else {
            title = "Coach Built Session"
            focus = "Adapted to your schedule, equipment, and energy"
        }

        let notes = "Coach config: \(message)"
        let reply = "Configured this day as \(title.lowercased()). I’ll use that when nudging you, and you can keep refining it conversationally."
        return CoachResponse(reply: reply, updates: [.workoutPlan(title: title, focus: focus, notes: notes)])
    }

    private func makeReply(for message: String, updates: [CoachAppUpdate]) -> String {
        if message.contains("photo") {
            return "Send the meal photo when you are ready. I’ll estimate it, ask one correction if needed, and keep the original image out of storage by default."
        }

        if message.contains("weigh") || message.contains("weight") {
            return "Logged. I care more about the trend than one noisy data point, so we’ll watch the rolling line instead of reacting to today alone."
        }

        if message.contains("workout") || message.contains("gym") || message.contains("lift") {
            return "Good. Today’s job is to get quality sets in, not turn the session into a saga. If equipment is busy, tell me what is open and I’ll swap it."
        }

        if updates.isEmpty {
            return "I need the cloud coach for open-ended chat. Check Cloud & AI status, then send that again."
        }

        return "Updated. I changed the relevant checklist or preference, and I’ll use that context for the next nudge."
    }

    private func firstNumber(in text: String) -> Double? {
        let pattern = #"\d+(\.\d+)?"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(text[range])
    }

    private func parseWorkoutSets(from text: String) -> [(exercise: String, reps: Int, weight: Int)] {
        let normalized = text
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: " for ", with: " x ")
            .replacingOccurrences(of: " at ", with: " x ")

        let pattern = #"([A-Za-z][A-Za-z ]{1,32}?)\s+(\d{1,3})\s*x\s*((?:\d{1,2}\s*,\s*)*\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }

        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return regex.matches(in: normalized, range: nsRange).flatMap { match in
            guard
                let exerciseRange = Range(match.range(at: 1), in: normalized),
                let weightRange = Range(match.range(at: 2), in: normalized),
                let repsRange = Range(match.range(at: 3), in: normalized),
                let weight = Int(normalized[weightRange])
            else {
                return [(exercise: String, reps: Int, weight: Int)]()
            }

            let exercise = normalized[exerciseRange]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .capitalized

            return normalized[repsRange]
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .map { (exercise: exercise, reps: $0, weight: weight) }
        }
    }
}
