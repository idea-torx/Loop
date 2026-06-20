import Foundation

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
            return "Got it. I’ll fold that into the plan. For today, keep the next move small and visible: complete one check-in, then we adjust."
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
