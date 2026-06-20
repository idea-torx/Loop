import Foundation

final class MetricsService {
    func makeWeeklyReview(
        tasks: [DailyTask],
        weighIns: [WeighIn],
        meals: [MealLog],
        workouts: [WorkoutSession],
        health: HealthMetricSnapshot
    ) -> WeeklyReview {
        let completed = tasks.filter(\.isComplete).count
        let total = max(tasks.count, 1)
        let adherence = Int((Double(completed) / Double(total)) * 100)
        let latest = weighIns.last?.pounds ?? 0
        let first = weighIns.first?.pounds ?? latest
        let delta = latest - first
        let direction = delta < 0 ? "down" : "up"

        return WeeklyReview(
            title: "Weekly review",
            summary: "You hit \(adherence)% of today’s visible adherence list. Weight is \(direction) \(abs(delta).formatted(.number.precision(.fractionLength(1)))) lb across the current trend window. Apple Health shows \(health.steps) steps today and \(health.workoutsThisWeek) workouts this week.",
            suggestions: [
                "Protect the weigh-in habit because it gives the coach a clean trend line.",
                "Keep lunch boring and high-protein on training days.",
                "Use the gym nudge as a decision deadline, not just a reminder."
            ]
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
