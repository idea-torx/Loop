import Charts
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedWeighIn: WeighIn?
    @State private var appeared = false

    private var rollingWeights: [WeighIn] {
        appState.metricsService.rollingAverage(points: appState.weighIns)
    }

    private var currentWeight: Double { appState.weighIns.last?.pounds ?? 0 }
    private var startWeight: Double { appState.weighIns.first?.pounds ?? currentWeight }
    private var delta: Double { currentWeight - startWeight }

    /// Tight y-range around the data so the trend reads expressively (AreaMark would otherwise pull the axis to 0).
    private var weightDomain: ClosedRange<Double> {
        let values = appState.weighIns.map(\.pounds)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max(1, (hi - lo) * 0.3)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                weightHero
                weightChart
                adherenceCard
                metricGrid
                insightCard
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(CoachTheme.background)
        .scrollIndicators(.hidden)
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LAST 14 DAYS")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundStyle(CoachTheme.accent)
            Text("Trends")
                .font(.system(size: 32, weight: .bold, design: .rounded))
        }
        .padding(.top, 8)
    }

    // MARK: Weight hero

    private var weightHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT WEIGHT")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(CoachTheme.Text.faint)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(currentWeight.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                Text("lb")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(CoachTheme.Text.muted)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: delta <= 0 ? "arrow.down.right" : "arrow.up.right")
                    Text("\(abs(delta).formatted(.number.precision(.fractionLength(1)))) lb")
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(delta <= 0 ? .green : CoachTheme.flame)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background((delta <= 0 ? Color.green : CoachTheme.flame).opacity(0.15), in: Capsule())
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.xl)
    }

    // MARK: Weight chart

    private var weightChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Weight trend",
                subtitle: selectedWeighIn.map { "\($0.date.formatted(.dateTime.month().day())) · \($0.pounds.formatted(.number.precision(.fractionLength(1)))) lb" } ?? "Drag to inspect"
            )

            Chart {
                ForEach(rollingWeights) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Baseline", weightDomain.lowerBound),
                        yEnd: .value("Weight", point.pounds)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [CoachTheme.ember.opacity(0.35), CoachTheme.ember.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.pounds)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(CoachTheme.ember)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }

                ForEach(appState.weighIns) { point in
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.pounds)
                    )
                    .foregroundStyle(.white.opacity(0.25))
                    .symbolSize(18)
                }

                if let selected = selectedWeighIn {
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(CoachTheme.accent.opacity(0.5))
                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Weight", selected.pounds)
                    )
                    .foregroundStyle(CoachTheme.flame)
                    .symbolSize(120)
                }
            }
            .chartYScale(domain: weightDomain)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(CoachTheme.Stroke.hairline)
                    AxisValueLabel().foregroundStyle(CoachTheme.Text.faint)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                        .foregroundStyle(CoachTheme.Text.faint)
                }
            }
            .frame(height: 200)
            .chartPlotStyle { plot in
                plot.clipped()
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard let date: Date = proxy.value(atX: value.location.x) else { return }
                                    selectedWeighIn = appState.weighIns.min(by: {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    })
                                }
                                .onEnded { _ in selectedWeighIn = nil }
                        )
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    // MARK: Adherence

    private var adherenceCard: some View {
        let done = appState.tasks.filter(\.isComplete).count
        let total = appState.tasks.count

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Adherence", subtitle: "\(done) of \(total) tasks done today")

            Chart(appState.tasks) { task in
                BarMark(
                    x: .value("Task", task.title),
                    y: .value("Done", task.isComplete ? 1 : 0)
                )
                .foregroundStyle(
                    task.isComplete
                        ? LinearGradient(colors: [CoachTheme.flame, CoachTheme.ember], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [CoachTheme.Fill.medium, CoachTheme.Fill.subtle], startPoint: .top, endPoint: .bottom)
                )
                .cornerRadius(6)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(CoachTheme.Text.faint)
                }
            }
            .frame(height: 140)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    // MARK: Metric grid

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricTile("Steps today", appState.healthMetrics.steps.formatted(), "figure.walk")
            metricTile("Active energy", "\(appState.healthMetrics.activeEnergy) cal", "flame.fill")
            metricTile("Training volume", "\(appState.workouts.first?.volume ?? 0) lb", "dumbbell.fill")
            metricTile("Workouts", "\(appState.healthMetrics.workoutsThisWeek)", "checkmark.seal.fill")
        }
    }

    private func metricTile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(CoachTheme.accent)
            MetricTile(title: title, value: value)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.md)
    }

    // MARK: Insight

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(systemImage: "sparkles", size: 40)
                Text("Weekly suggestions")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            Text(appState.weeklyReview.summary)
                .font(.subheadline)
                .foregroundStyle(CoachTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(appState.weeklyReview.suggestions, id: \.self) { suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(CoachTheme.accent)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(suggestion)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.xl)
    }
}
