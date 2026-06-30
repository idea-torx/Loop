import Foundation

final class MetricsService {
    func makeWeeklyReview(
        tasks: [DailyTask],
        weighIns: [WeighIn],
        meals: [MealLog],
        workouts: [WorkoutSession],
        health: HealthMetricSnapshot,
        isSickDay: Bool = false
    ) -> WeeklyReview {
        let completed = tasks.filter(\.isComplete).count
        let total = max(tasks.count, 1)
        let adherence = Int((Double(completed) / Double(total)) * 100)
        let todaysMeals = meals.filter { Calendar.current.isDateInToday($0.date) }
        let proteinToday = todaysMeals.reduce(0) { $0 + $1.protein }
        let caloriesToday = todaysMeals.reduce(0) { $0 + $1.calories }
        let incompleteTasks = tasks.filter { !$0.isComplete }
        let hour = Calendar.current.component(.hour, from: Date())

        let weightSummary: String
        if let latest = weighIns.last?.pounds, let first = weighIns.first?.pounds {
            let delta = latest - first
            let direction = delta < 0 ? "down" : "up"
            weightSummary = "Weight is \(direction) \(abs(delta).formatted(.number.precision(.fractionLength(1)))) lb across the current trend window."
        } else {
            weightSummary = "No real weigh-ins are logged yet, so the weight trend is waiting on the first entry."
        }

        var suggestions: [String] = []
        if isSickDay {
            return WeeklyReview(
                title: "Sick day",
                summary: "Today is marked as a recovery day. Loop is skipping normal adherence pressure; the goal is fluids, food you can tolerate, and an easy walk only if it helps.",
                suggestions: [
                    "Take a 10-20 minute easy walk if symptoms allow.",
                    "Keep protein simple and hydration boring.",
                    "Skip hard training today. Resume the split when you feel normal."
                ]
            )
        }

        if health.steps < 7_500 && hour >= 17 {
            suggestions.append("Take a 20-30 minute evening walk to close the movement gap without turning the night into a workout.")
        } else if health.steps < 4_000 {
            suggestions.append("Get one low-friction walk in soon. The day is still salvageable if you start small.")
        } else {
            suggestions.append("Movement is in a decent place. Keep the rest of the day boring and repeatable.")
        }

        if proteinToday < PTProtocol.proteinTargetG {
            suggestions.append("Protein is at \(proteinToday)g. Aim the next meal at lean protein first, then fill around it.")
        } else {
            suggestions.append("Protein target is covered. Keep dinner simple so calories do not drift late.")
        }

        if let nextTask = incompleteTasks.first {
            suggestions.append("Next adherence lever: \(nextTask.title.lowercased()). Do that before adding anything fancy.")
        } else if health.workoutsToday == 0 && hour >= 16 {
            suggestions.append("No HealthKit session logged today. If this was meant to be a training day, do the minimum viable session.")
        } else {
            suggestions.append("The checklist is clean. Protect sleep and let the win count.")
        }

        return WeeklyReview(
            title: "Today's read",
            summary: "Adherence is \(adherence)% so far. Apple Health shows \(health.steps) steps, \(health.activeEnergy) active cal, and \(health.workoutsToday) session\(health.workoutsToday == 1 ? "" : "s") today. Logged food is \(caloriesToday) cal and \(proteinToday)g protein. \(weightSummary)",
            suggestions: suggestions
        )
    }

    func rollingAverage(points: [WeighIn], window: Int = 7) -> [WeighIn] {
        points.enumerated().map { index, point in
            let lower = max(0, index - window + 1)
            let slice = points[lower...index]
            let average = slice.map(\.pounds).reduce(0, +) / Double(slice.count)
            return WeighIn(date: point.date, pounds: average)
        }
    }
}

final class TodayEnergyService {
    func makeSnapshot(
        tasks: [DailyTask],
        meals: [MealLog],
        workouts: [WorkoutSession],
        health: HealthMetricSnapshot,
        isSickDay: Bool
    ) -> TodayEnergySnapshot {
        if isSickDay {
            return TodayEnergySnapshot(
                score: 28,
                label: "Limited",
                confidence: 0.85,
                primaryDriver: "Sick day is active.",
                secondaryDrivers: ["Normal training pressure is intentionally skipped."],
                bestMove: "Recover first. Take only an easy walk if it genuinely helps.",
                expandedExplanation: "Loop is suppressing performance coaching today because recovery is the priority."
            )
        }

        var score = 68.0
        var drivers: [String] = []
        var missingSignals: [String] = []
        var dataPoints = 2

        if let sleepDelta = health.sleepDeltaVs30d {
            dataPoints += 1
            if sleepDelta < -60 {
                score -= 12
                drivers.append("Sleep was more than an hour below baseline.")
            } else if sleepDelta < -25 {
                score -= 6
                drivers.append("Sleep was slightly below baseline.")
            } else if sleepDelta > 30 {
                score += 6
                drivers.append("Sleep is above baseline.")
            }
        } else if health.sleepMinutes == nil {
            missingSignals.append("Sleep is not available, so it is not included in the score.")
        }

        if let hrvDelta = health.hrvDeltaVs30d {
            dataPoints += 1
            if hrvDelta < -8 {
                score -= 10
                drivers.append("HRV is below your recent baseline.")
            } else if hrvDelta > 8 {
                score += 6
                drivers.append("HRV is trending above baseline.")
            }
        }

        if let restingDelta = health.restingHeartRateDeltaVs30d {
            dataPoints += 1
            if restingDelta > 6 {
                score -= 9
                drivers.append("Resting heart rate is elevated versus baseline.")
            } else if restingDelta < -4 {
                score += 4
                drivers.append("Resting heart rate is calm versus baseline.")
            }
        }

        if health.workoutsToday > 0 {
            score -= 4
            drivers.append("A workout is already logged today.")
        }
        if health.workoutsThisWeek >= 5 {
            score -= 4
            drivers.append("Training load is building this week.")
        }
        if health.activeEnergy >= 700 {
            score -= 6
            drivers.append("Active calories are already high today.")
        } else if health.activeEnergy >= 500 {
            score += 2
            drivers.append("Move target is covered without excess strain.")
        }

        let completed = tasks.filter(\.isComplete).count
        let total = max(tasks.count, 1)
        let adherence = Double(completed) / Double(total)
        if adherence >= 0.65 {
            score += 5
            drivers.append("Supportive habits are moving.")
        } else if completed == 0 && Calendar.current.component(.hour, from: Date()) >= 14 {
            score -= 4
            drivers.append("Habit support is behind pace.")
        }

        let todaysMeals = meals.filter { Calendar.current.isDateInToday($0.date) }
        let protein = todaysMeals.reduce(0) { $0 + $1.protein }
        if protein >= PTProtocol.proteinTargetG {
            score += 4
            drivers.append("Protein target is covered.")
        } else if protein < 60 && Calendar.current.component(.hour, from: Date()) >= 15 {
            score -= 3
            drivers.append("Protein is light for this point in the day.")
        }

        let clamped = Int(min(max(score, 15), 96).rounded())
        let label: String
        switch clamped {
        case 82...100: label = "High"
        case 60..<82: label = "Stable"
        case 38..<60: label = "Limited"
        default: label = "Depleted"
        }

        let confidence = min(0.95, max(0.35, Double(dataPoints) / 7.0))
        let primary = drivers.first ?? "Today’s logged habits and activity are the main signal."
        let dataGapNote = missingSignals.isEmpty ? nil : missingSignals.joined(separator: " ")
        var secondary = Array(drivers.dropFirst().prefix(3))
        if let dataGapNote, secondary.count < 3 {
            secondary.append(dataGapNote)
        }
        let bestMove = bestMove(for: label, health: health, protein: protein)

        return TodayEnergySnapshot(
            score: clamped,
            label: label,
            confidence: confidence,
            primaryDriver: primary,
            secondaryDrivers: secondary.isEmpty ? ["Loop will refine this as more data lands; missing signals lower confidence, not the score."] : secondary,
            bestMove: bestMove,
            expandedExplanation: expandedExplanation(label: label, primary: primary, drivers: secondary, confidence: confidence)
        )
    }

    func makeCoachSnapshot(
        energy: TodayEnergySnapshot,
        tasks: [DailyTask],
        meals: [MealLog],
        workouts: [WorkoutSession],
        health: HealthMetricSnapshot,
        selectedWorkout: WorkoutDayPlan?,
        isSickDay: Bool,
        at date: Date = Date()
    ) -> DailyCoachSnapshot {
        let window = updateWindow(at: date)
        if isSickDay {
            return DailyCoachSnapshot(
                updateWindow: window,
                recommendationType: "recover",
                coachRead: "Today is a recovery day, so the win is reducing pressure.",
                evidence: ["Sick day is active.", "Normal workout and adherence pressure should stay off."],
                bestNextMove: "Fluids, food you can tolerate, and a 10-20 minute walk only if it feels helpful.",
                habitFocus: "Recovery",
                avoid: ["Hard training", "Trying to make up missed volume"],
                coachCue: "Let the day be light on purpose."
            )
        }

        let incomplete = tasks.first { !$0.isComplete }
        let protein = meals.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.protein }
        let split = selectedWorkout?.title ?? "today’s plan"
        let recommendation: String
        let habit: String

        switch window {
        case "morning":
            recommendation = energy.label == "High"
                ? "Treat \(split) as live, but earn the intensity after warm-up sets."
                : "Start with weigh-in, hydration, and keep \(split) controlled."
            habit = incomplete?.title ?? "Morning weigh-in"
        case "afternoon":
            if health.steps < 4_000 {
                recommendation = "Take a 12-minute walk before the next work block."
                habit = "Movement loop"
            } else if protein < PTProtocol.proteinTargetG {
                recommendation = "Make the next meal protein-first so dinner is easier."
                habit = "Protein"
            } else {
                recommendation = "Keep the day steady and avoid adding junk volume."
                habit = incomplete?.title ?? "Consistency"
            }
        default:
            recommendation = energy.label == "Limited" || energy.label == "Depleted"
                ? "Wind down earlier and stop adding training load tonight."
                : "Close the final habit, then protect sleep."
            habit = incomplete?.title ?? "Sleep routine"
        }

        return DailyCoachSnapshot(
            updateWindow: window,
            recommendationType: recommendationType(for: energy.label, window: window),
            coachRead: "Today’s Energy is \(energy.label.lowercased()) at \(energy.score)%.",
            evidence: [energy.primaryDriver] + energy.secondaryDrivers.prefix(2),
            bestNextMove: recommendation,
            habitFocus: habit,
            avoid: energy.label == "High" ? [] : ["Max-effort work without a clear reason"],
            coachCue: cue(for: energy.label, window: window)
        )
    }

    private func bestMove(for label: String, health: HealthMetricSnapshot, protein: Int) -> String {
        if health.steps < 4_000 && Calendar.current.component(.hour, from: Date()) >= 12 {
            return "Take a short walk and close the movement gap without adding fatigue."
        }
        if protein < PTProtocol.proteinTargetG && Calendar.current.component(.hour, from: Date()) >= 12 {
            return "Make the next meal protein-first."
        }
        switch label {
        case "High": return "Train or push one meaningful habit forward."
        case "Stable": return "Train, but keep intensity controlled."
        case "Limited": return "Reduce friction: easy movement, hydration, and simple food."
        default: return "Protect recovery and keep the day light."
        }
    }

    private func expandedExplanation(label: String, primary: String, drivers: [String], confidence: Double) -> String {
        let joined = ([primary] + drivers).joined(separator: " ")
        let confidenceText = Int((confidence * 100).rounded())
        return "Today’s Energy is \(label.lowercased()) with \(confidenceText)% confidence. \(joined)"
    }

    private func updateWindow(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "morning"
        case 12..<18: return "afternoon"
        default: return "evening"
        }
    }

    private func recommendationType(for label: String, window: String) -> String {
        if window == "evening" { return "wind_down" }
        switch label {
        case "High": return "push"
        case "Stable": return "maintain"
        case "Limited": return "modify"
        default: return "recover"
        }
    }

    private func cue(for label: String, window: String) -> String {
        if window == "evening" { return "Close the loop. Let tomorrow be better." }
        switch label {
        case "High": return "Use the green light, do not waste it."
        case "Stable": return "Controlled effort still counts."
        case "Limited": return "Small move, clean reset."
        default: return "Recover first. The plan can wait."
        }
    }
}

final class GoalService {
    func makeProgress(
        goal: GoalPlan,
        weighIns: [WeighIn],
        meals: [MealLog],
        dailyMetrics: [DailyMetricSnapshot],
        health: HealthMetricSnapshot,
        today: Date = Date()
    ) -> GoalProgress {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: goal.startDate)
        let end = calendar.startOfDay(for: goal.endDate)
        let now = calendar.startOfDay(for: today)
        let totalDays = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
        let elapsed = min(max(0, calendar.dateComponents([.day], from: start, to: now).day ?? 0), totalDays)
        let remaining = max(0, totalDays - elapsed)
        let timelineProgress = min(1, max(0, Double(elapsed) / Double(totalDays)))

        let trendWeight = rollingTrendWeight(weighIns: weighIns)
        let expected = goal.startWeight + ((goal.targetWeight - goal.startWeight) * timelineProgress)
        let current = trendWeight ?? weighIns.last?.pounds
        let lost = current.map { goal.startWeight - $0 } ?? 0
        let remainingPounds = current.map { max(0, $0 - goal.targetWeight) } ?? max(0, goal.startWeight - goal.targetWeight)

        let sevenDayMeals = valuesByDay(meals: meals, days: 7, endingAt: today)
        let calorieAverage = average(sevenDayMeals.map(\.calories))
        let proteinAverage = average(sevenDayMeals.map(\.protein))
        let activeAverage = activeCaloriesAverage(metrics: dailyMetrics, health: health, days: 7, today: today)
        let burn = goal.bodyProfile.rmrEstimate + health.activeEnergy
        let loggedToday = meals.filter { calendar.isDate($0.date, inSameDayAs: today) }
        let caloriesToday = loggedToday.reduce(0) { $0 + $1.calories }
        let deficit = caloriesToday > 0 ? burn - caloriesToday : nil
        let confidence = confidence(mealDays: sevenDayMeals.count, weighIns: weighIns.count)
        let activeProgress = Double(activeAverage ?? health.activeEnergy) / Double(max(goal.activeCalorieMax, 1))

        let status: String
        let summary: String
        if let current {
            let variance = current - expected
            if variance <= 0.5 {
                status = "On track"
                summary = "Trend weight is at or ahead of the September 1 pace."
            } else if variance <= 1.5 {
                status = "Watch"
                summary = "Trend weight is slightly behind pace; the next week matters."
            } else {
                status = "Behind"
                summary = "Trend weight is behind the target line. Tighten food logging and active calories."
            }
        } else {
            status = "Needs weigh-ins"
            summary = "Log a few weigh-ins before Loop judges the weight trend."
        }

        return GoalProgress(
            daysElapsed: elapsed,
            daysRemaining: remaining,
            totalDays: totalDays,
            currentTrendWeight: current,
            expectedWeightToday: expected,
            targetWeight: goal.targetWeight,
            poundsLost: lost,
            poundsRemaining: remainingPounds,
            paceStatus: status,
            paceSummary: summary,
            sevenDayCaloriesAverage: calorieAverage,
            sevenDayProteinAverage: proteinAverage,
            sevenDayActiveCaloriesAverage: activeAverage,
            estimatedDailyBurn: burn,
            estimatedDailyDeficit: deficit,
            deficitConfidence: confidence,
            activeCalorieProgress: min(max(activeProgress, 0), 1.25),
            timelineProgress: timelineProgress
        )
    }

    func makeInsight(goal: GoalPlan, progress: GoalProgress) -> GoalInsight {
        var suggestions: [String] = []
        if progress.sevenDayActiveCaloriesAverage ?? 0 < goal.activeCalorieMin {
            suggestions.append("Active calories are under the cut target. Add a walk or bike block before dinner.")
        } else {
            suggestions.append("Active calories are supporting the cut. Keep that repeatable.")
        }

        if let protein = progress.sevenDayProteinAverage, protein < goal.proteinTarget {
            suggestions.append("Protein is averaging \(protein)g. Push meals toward \(goal.proteinTarget)g/day.")
        } else {
            suggestions.append("Protein looks close enough to preserve training quality.")
        }

        if progress.deficitConfidence == "low" {
            suggestions.append("Food logging is too sparse for precise deficit math. Log lunch and dinner for the next three days.")
        } else if let deficit = progress.estimatedDailyDeficit, deficit < 500 {
            suggestions.append("Today’s estimated deficit is light. Keep dinner lean or add easy movement.")
        } else {
            suggestions.append("The deficit estimate is usable; judge it against the weekly weight trend.")
        }

        return GoalInsight(
            summary: "\(progress.paceStatus): \(progress.paceSummary)",
            suggestions: suggestions
        )
    }

    private func rollingTrendWeight(weighIns: [WeighIn]) -> Double? {
        let recent = weighIns.sorted { $0.date > $1.date }.prefix(7)
        guard !recent.isEmpty else { return nil }
        return recent.map(\.pounds).reduce(0, +) / Double(recent.count)
    }

    private func valuesByDay(meals: [MealLog], days: Int, endingAt date: Date) -> [(calories: Int, protein: Int)] {
        let calendar = Calendar.current
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            let dayMeals = meals.filter { calendar.isDate($0.date, inSameDayAs: day) }
            guard !dayMeals.isEmpty else { return nil }
            return (
                calories: dayMeals.reduce(0) { $0 + $1.calories },
                protein: dayMeals.reduce(0) { $0 + $1.protein }
            )
        }
    }

    private func activeCaloriesAverage(metrics: [DailyMetricSnapshot], health: HealthMetricSnapshot, days: Int, today: Date) -> Int? {
        let calendar = Calendar.current
        let recent = metrics.filter {
            guard let dayDiff = calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.date), to: calendar.startOfDay(for: today)).day else { return false }
            return (0..<days).contains(dayDiff)
        }
        let values = recent.map(\.activeEnergy) + (recent.contains { calendar.isDate($0.date, inSameDayAs: today) } ? [] : [health.activeEnergy])
        return average(values.filter { $0 > 0 })
    }

    private func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private func confidence(mealDays: Int, weighIns: Int) -> String {
        if mealDays >= 5 && weighIns >= 5 { return "high" }
        if mealDays >= 3 || weighIns >= 3 { return "medium" }
        return "low"
    }
}
