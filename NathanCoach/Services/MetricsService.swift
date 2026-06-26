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
