import Charts
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var appState: AppState

    var rollingWeights: [WeighIn] {
        appState.metricsService.rollingAverage(points: appState.weighIns)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    metricGrid
                    weightChart
                    adherenceChart
                    weeklyReview
                }
                .padding()
                .padding(.bottom, 104)
            }
            .background(CoachTheme.background)
            .navigationTitle("Trends")
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric("Current weight", value: "\(appState.weighIns.last?.pounds.formatted(.number.precision(.fractionLength(1))) ?? "--") lb")
            metric("Steps today", value: appState.healthMetrics.steps.formatted())
            metric("Active energy", value: "\(appState.healthMetrics.activeEnergy) cal")
            metric("Training volume", value: "\(appState.workouts.first?.volume ?? 0) lb")
        }
    }

    private var weightChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight trend")
                .font(.headline)
            Chart {
                ForEach(appState.weighIns) { point in
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.pounds)
                    )
                    .foregroundStyle(.white.opacity(0.45))
                }

                ForEach(rollingWeights) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Rolling", point.pounds)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(CoachTheme.mint)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
            }
            .chartYAxisLabel("lb")
            .frame(height: 220)
        }
        .padding()
        .glassPanel()
    }

    private var adherenceChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visible adherence")
                .font(.headline)
            Chart(appState.tasks) { task in
                BarMark(
                    x: .value("Task", task.title),
                    y: .value("Done", task.isComplete ? 1 : 0)
                )
                .foregroundStyle(task.isComplete ? CoachTheme.mint : Color.white.opacity(0.2))
            }
            .chartYScale(domain: 0...1)
            .frame(height: 180)
        }
        .padding()
        .glassPanel()
    }

    private var weeklyReview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Weekly suggestions", systemImage: "sparkles")
                .font(.headline)
            Text(appState.weeklyReview.summary)
                .font(.subheadline)
                .foregroundStyle(CoachTheme.mutedText)
            ForEach(appState.weeklyReview.suggestions, id: \.self) { suggestion in
                Label(suggestion, systemImage: "arrow.right.circle.fill")
                    .font(.caption)
            }
        }
        .padding()
        .glassPanel()
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.title2.weight(.bold))
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption)
                .foregroundStyle(CoachTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassPanel(radius: 18)
    }
}
