import Charts
import PhotosUI
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedPage: TrendsPage = .trends
    @State private var selectedWeighIn: WeighIn?
    @State private var showsMealEntry = false
    @State private var editingMeal: EditableMeal?
    @State private var selectedMeal: MealLog?
    @State private var editingGoal: EditableGoal?
    @State private var appeared = false

    enum TrendsPage: String, CaseIterable {
        case trends = "Trends"
        case goal = "Goal"
    }

    struct EditableMeal: Identifiable {
        let id: MealLog.ID
        var title: String
        var calories: Int
        var protein: Int
    }

    struct EditableGoal: Identifiable {
        let id = UUID()
        var plan: GoalPlan
    }

    private var rollingWeights: [WeighIn] {
        appState.metricsService.rollingAverage(points: appState.weighIns)
    }

    private var currentWeight: Double? { appState.weighIns.last?.pounds }
    private var startWeight: Double? { appState.weighIns.first?.pounds }
    private var delta: Double? {
        guard let currentWeight, let startWeight else { return nil }
        return currentWeight - startWeight
    }

    /// Tight y-range around the data so the trend reads expressively.
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
                pagePicker
                if selectedPage == .trends {
                    weightHero
                    weightChart
                    nutritionSection
                    insightCard
                } else {
                    goalPage
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(CoachTheme.background)
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showsMealEntry) {
            MealEntrySheet { description, imageData in
                await appState.logMealWithHaiku(description: description, imageData: imageData)
            }
            .preferredColorScheme(.dark)
        }
        .sheet(item: $editingMeal) { draft in
            MealEditSheet(draft: draft) { updated in
                Haptics.success()
                appState.updateMeal(updated.id, title: updated.title, calories: updated.calories, protein: updated.protein)
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedMeal) { meal in
            MealDetailSheet(
                meal: meal,
                onEdit: {
                    selectedMeal = nil
                    editingMeal = EditableMeal(id: meal.id, title: meal.title, calories: meal.calories, protein: meal.protein)
                },
                onDelete: {
                    Haptics.soft()
                    selectedMeal = nil
                    appState.deleteMeal(meal.id)
                }
            )
            .preferredColorScheme(.dark)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingGoal) { draft in
            GoalEditSheet(draft: draft.plan) { updated in
                Haptics.success()
                appState.updateGoalPlan(updated)
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FOOD & WEIGHT")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundStyle(CoachTheme.accent)
            Text("Trends")
                .font(.system(size: 32, weight: .bold, design: .rounded))
        }
        .padding(.top, 8)
    }

    private var pagePicker: some View {
        HStack(spacing: 8) {
            ForEach(TrendsPage.allCases, id: \.self) { page in
                Button {
                    Haptics.light()
                    withAnimation(.snappy(duration: 0.25)) {
                        selectedPage = page
                    }
                } label: {
                    Text(page.rawValue)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedPage == page ? .white : CoachTheme.Text.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedPage == page ? CoachTheme.accent.opacity(0.24) : Color.white.opacity(0.04), in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay { Capsule().stroke(CoachTheme.Stroke.hairline, lineWidth: 1) }
    }

    // MARK: Weight

    private var weightHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT WEIGHT · GOAL \(PTProtocol.goal.uppercased())")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(CoachTheme.Text.faint)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(currentWeight.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "--")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                Text("lb")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(CoachTheme.Text.muted)

                Spacer()

                if let delta {
                    HStack(spacing: 4) {
                        Image(systemName: delta <= 0 ? "arrow.down.right" : "arrow.up.right")
                        Text("\(abs(delta).formatted(.number.precision(.fractionLength(1)))) lb")
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(delta <= 0 ? .green : CoachTheme.flame)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background((delta <= 0 ? Color.green : CoachTheme.flame).opacity(0.15), in: Capsule())
                } else {
                    Text("No logs yet")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.faint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.xl)
    }

    private var weightChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Weight trend",
                subtitle: selectedWeighIn.map { "\($0.date.formatted(.dateTime.month().day())) · \($0.pounds.formatted(.number.precision(.fractionLength(1)))) lb" } ?? "Last 14 days · drag to inspect"
            )

            if appState.weighIns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No weigh-ins logged yet.")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.primary)
                    Text("Tell Coach something like “log my weight at 169.8” and this will become your real trend line.")
                        .font(.subheadline)
                        .foregroundStyle(CoachTheme.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
            } else {
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
                    AxisMarks { _ in
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
                .chartPlotStyle { $0.clipped() }
                .chartOverlay { proxy in
                    GeometryReader { _ in
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
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    // MARK: Nutrition

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Today's fuel", subtitle: healthNote) {
                Button {
                    Haptics.light()
                    showsMealEntry = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CoachTheme.accent)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .overlay { Circle().stroke(CoachTheme.Stroke.hairline, lineWidth: 1) }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Log a meal")
            }

            VStack(spacing: 14) {
                nutrientBar(label: "Protein", value: appState.proteinToday, target: PTProtocol.proteinTargetG, unit: "g")
                nutrientBar(label: "Calories", value: appState.caloriesToday, target: PTProtocol.calorieTarget, unit: "")
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .glassPanel(radius: CoachTheme.Radius.lg)

            if appState.todaysMeals.isEmpty {
                Button {
                    Haptics.light()
                    showsMealEntry = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                        Text("Log a meal — describe it or snap a photo")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundStyle(CoachTheme.Text.muted)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .foregroundStyle(CoachTheme.Stroke.panel)
                    }
                }
                .buttonStyle(.pressable)
            } else {
                VStack(spacing: 10) {
                    ForEach(appState.todaysMeals) { meal in
                        mealRow(meal)
                    }
                }
            }
        }
    }

    private func nutrientBar(label: String, value: Int, target: Int, unit: String) -> some View {
        let progress = target == 0 ? 0 : min(1, Double(value) / Double(target))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(value.formatted())\(unit) ")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(CoachTheme.Text.primary)
                + Text("/ \(target.formatted())\(unit)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CoachTheme.Text.faint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CoachTheme.Fill.medium)
                    Capsule()
                        .fill(LinearGradient(colors: [CoachTheme.flame, CoachTheme.ember], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * progress))
                }
            }
            .frame(height: 10)
        }
    }

    private func mealRow(_ meal: MealLog) -> some View {
        Button {
            Haptics.light()
            selectedMeal = meal
        } label: {
            HStack(spacing: 14) {
                if let data = meal.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    IconTile(systemImage: "fork.knife", size: 48)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("\(meal.protein)g protein · \(meal.calories) cal")
                        .font(.caption)
                        .foregroundStyle(CoachTheme.Text.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(meal.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(CoachTheme.Text.faint)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CoachTheme.Text.faint)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
        }
    }

    private var healthNote: String {
        let protein = appState.proteinToday
        let target = PTProtocol.proteinTargetG
        if appState.todaysMeals.isEmpty { return "Nothing logged yet today" }
        if protein >= target { return "Protein locked in — nicely done" }
        return "\(target - protein)g protein to go"
    }

    // MARK: Goal

    private var goalPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            goalHero
            goalTimelineChart
            goalAverages
            goalProfile
            goalInsightCard
        }
    }

    private var goalHero: some View {
        let goal = appState.goalPlan
        let progress = appState.goalProgress
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Cut · \(goal.startDate.formatted(.dateTime.month(.abbreviated).day())) to \(goal.endDate.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CoachTheme.Text.muted)
                }
                Spacer()
                Button {
                    Haptics.light()
                    editingGoal = EditableGoal(plan: goal)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(CoachTheme.accent)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.pressable)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(progress.paceStatus)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(goalStatusColor(progress.paceStatus))
                Spacer()
                Text("\(progress.daysRemaining)d left")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CoachTheme.Text.muted)
            }

            Text(progress.paceSummary)
                .font(.subheadline)
                .foregroundStyle(CoachTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(CoachTheme.Fill.medium)
                    Capsule()
                        .fill(LinearGradient(colors: [CoachTheme.flame, CoachTheme.ember], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * min(max(progress.timelineProgress, 0), 1))
                }
            }
            .frame(height: 9)

            HStack {
                detailMetric(title: "Trend", value: progress.currentTrendWeight.map { "\($0.formatted(.number.precision(.fractionLength(1)))) lb" } ?? "--", systemImage: "chart.line.uptrend.xyaxis")
                detailMetric(title: "Target", value: "\(goal.targetWeight.formatted(.number.precision(.fractionLength(1)))) lb", systemImage: "target")
                detailMetric(title: "Left", value: "\(progress.poundsRemaining.formatted(.number.precision(.fractionLength(1)))) lb", systemImage: "arrow.down")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.xl)
    }

    private var goalTimelineChart: some View {
        let goal = appState.goalPlan
        let progress = appState.goalProgress
        let current = progress.currentTrendWeight ?? goal.startWeight
        let domainPadding = max(1.0, abs(goal.startWeight - goal.targetWeight) * 0.25)
        let lower = min(goal.targetWeight, current, progress.expectedWeightToday) - domainPadding
        let upper = max(goal.startWeight, current, progress.expectedWeightToday) + domainPadding

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Goal line", subtitle: "Current trend vs expected pace")
            Chart {
                LineMark(x: .value("Date", goal.startDate), y: .value("Weight", goal.startWeight))
                    .foregroundStyle(CoachTheme.Text.faint)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                LineMark(x: .value("Date", goal.endDate), y: .value("Weight", goal.targetWeight))
                    .foregroundStyle(CoachTheme.Text.faint)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))

                PointMark(x: .value("Date", Date()), y: .value("Weight", current))
                    .foregroundStyle(CoachTheme.flame)
                    .symbolSize(120)
                PointMark(x: .value("Date", Date()), y: .value("Expected", progress.expectedWeightToday))
                    .foregroundStyle(CoachTheme.accent)
                    .symbolSize(90)
            }
            .chartYScale(domain: lower...upper)
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(CoachTheme.Stroke.hairline)
                    AxisValueLabel().foregroundStyle(CoachTheme.Text.faint)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(format: .dateTime.month().day(), centered: true)
                        .foregroundStyle(CoachTheme.Text.faint)
                }
            }
            .frame(height: 190)
        }
        .padding(20)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private var goalAverages: some View {
        let goal = appState.goalPlan
        let progress = appState.goalProgress
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Last 7 days", subtitle: "Deficit confidence: \(progress.deficitConfidence)")
            goalBar(title: "Active calories", value: progress.sevenDayActiveCaloriesAverage, target: goal.activeCalorieMin, suffix: "", cap: goal.activeCalorieMax)
            goalBar(title: "Calories eaten", value: progress.sevenDayCaloriesAverage, target: goal.calorieTarget, suffix: "", cap: max(goal.calorieTarget, 1))
            goalBar(title: "Protein", value: progress.sevenDayProteinAverage, target: goal.proteinTarget, suffix: "g", cap: goal.proteinTarget)
            HStack {
                detailMetric(title: "Burn today", value: "\(progress.estimatedDailyBurn)", systemImage: "flame")
                detailMetric(title: "Deficit", value: progress.estimatedDailyDeficit.map { "\($0)" } ?? "--", systemImage: "minus.circle")
            }
        }
        .padding(20)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private func goalBar(title: String, value: Int?, target: Int, suffix: String, cap: Int) -> some View {
        let actual = value ?? 0
        let progress = cap == 0 ? 0 : min(1, Double(actual) / Double(cap))
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CoachTheme.Text.muted)
                Spacer()
                Text(value.map { "\($0.formatted())\(suffix) / \(target.formatted())\(suffix)" } ?? "No data")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CoachTheme.Text.primary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(CoachTheme.Fill.medium)
                    Capsule()
                        .fill(CoachTheme.accent)
                        .frame(width: max(6, proxy.size.width * progress))
                }
            }
            .frame(height: 8)
        }
    }

    private var goalProfile: some View {
        let profile = appState.goalPlan.bodyProfile
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Body profile", subtitle: profile.rmrSource)
            HStack {
                detailMetric(title: "RMR", value: "\(profile.rmrEstimate)", systemImage: "bolt.heart")
                detailMetric(title: "Height", value: profile.heightInches.map { "\($0.formatted(.number.precision(.fractionLength(1)))) in" } ?? "--", systemImage: "ruler")
                detailMetric(title: "Lean mass", value: profile.leanMassPounds.map { "\($0.formatted(.number.precision(.fractionLength(1)))) lb" } ?? "--", systemImage: "figure.strengthtraining.traditional")
            }
        }
        .padding(20)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private var goalInsightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Goal coach", subtitle: "Cut read")
            Text(appState.goalInsight.summary)
                .font(.subheadline)
                .foregroundStyle(CoachTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(appState.goalInsight.suggestions, id: \.self) { suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(CoachTheme.accent)
                        .padding(.top, 2)
                    Text(suggestion)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private func goalStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "on track": return .green
        case "watch": return CoachTheme.accent
        case "behind": return CoachTheme.flame
        default: return CoachTheme.Text.faint
        }
    }

    private func detailMetric(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(CoachTheme.accent)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(CoachTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(CoachTheme.Text.faint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
        }
    }

    // MARK: Insight

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image("LoopMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 22)
                    .padding(10)
                    .background(CoachTheme.flame, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

private struct MealDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let meal: MealLog
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let data = meal.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: CoachTheme.Radius.lg, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(meal.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(CoachTheme.Text.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(meal.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(CoachTheme.Text.muted)
                    }

                    HStack(spacing: 12) {
                        detailMetric(title: "Calories", value: meal.calories.formatted(), systemImage: "flame.fill")
                        detailMetric(title: "Protein", value: "\(meal.protein)g", systemImage: "bolt.fill")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Coach context")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(CoachTheme.Text.faint)
                        Text("This meal contributes \(meal.calories.formatted()) calories and \(meal.protein)g protein to today’s logged totals.")
                            .font(.subheadline)
                            .foregroundStyle(CoachTheme.Text.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
                }
                .padding(20)
            }
            .background(CoachTheme.background.ignoresSafeArea())
            .navigationTitle("Meal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit meal", systemImage: "pencil", action: onEdit)
                        Button("Delete meal", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private func detailMetric(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(CoachTheme.accent)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(CoachTheme.Text.primary)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(CoachTheme.Text.faint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
        }
    }
}

private struct MealEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TrendsView.EditableMeal
    let onSave: (TrendsView.EditableMeal) -> Void

    init(draft: TrendsView.EditableMeal, onSave: @escaping (TrendsView.EditableMeal) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    private var isValid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Meal", text: $draft.title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .padding(14)
                    .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))

                Stepper("Calories: \(draft.calories)", value: $draft.calories, in: 0...5000, step: 25)
                Stepper("Protein: \(draft.protein)g", value: $draft.protein, in: 0...300, step: 1)

                Spacer()
            }
            .padding(20)
            .background(CoachTheme.background.ignoresSafeArea())
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

private struct GoalEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var plan: GoalPlan
    let onSave: (GoalPlan) -> Void

    init(draft: GoalPlan, onSave: @escaping (GoalPlan) -> Void) {
        _plan = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Goal title") {
                        TextField("Cut to September 1", text: $plan.title)
                            .textFieldStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Timeline")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        DatePicker("End date", selection: $plan.endDate, displayedComponents: .date)
                            .tint(CoachTheme.accent)
                        Stepper("Target loss: \(Int((plan.targetLossPercent * 100).rounded()))%", value: $plan.targetLossPercent, in: 0.03...0.20, step: 0.01)
                            .onChange(of: plan.targetLossPercent) { _, newValue in
                                plan.targetWeight = plan.startWeight * (1 - newValue)
                            }
                        Stepper("Start weight: \(plan.startWeight.formatted(.number.precision(.fractionLength(1)))) lb", value: $plan.startWeight, in: 80...400, step: 0.1)
                            .onChange(of: plan.startWeight) { _, newValue in
                                plan.targetWeight = newValue * (1 - plan.targetLossPercent)
                            }
                    }
                    .goalSettingsBlock()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Daily targets")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Stepper("Active min: \(plan.activeCalorieMin)", value: $plan.activeCalorieMin, in: 0...2000, step: 25)
                        Stepper("Active max: \(plan.activeCalorieMax)", value: $plan.activeCalorieMax, in: max(plan.activeCalorieMin, 0)...2500, step: 25)
                        Stepper("Calories: \(plan.calorieTarget)", value: $plan.calorieTarget, in: 1200...4000, step: 25)
                        Stepper("Protein: \(plan.proteinTarget)g", value: $plan.proteinTarget, in: 80...260, step: 5)
                    }
                    .goalSettingsBlock()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Body profile")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Stepper("RMR: \(plan.bodyProfile.rmrEstimate)", value: $plan.bodyProfile.rmrEstimate, in: 1200...2600, step: 25)
                        Stepper("Height: \(plan.bodyProfile.heightInches.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "--") in", value: heightBinding, in: 48...84, step: 0.5)
                        Stepper("Lean mass: \(plan.bodyProfile.leanMassPounds.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "--") lb", value: leanMassBinding, in: 80...240, step: 1)
                    }
                    .goalSettingsBlock()
                }
                .padding()
            }
            .background(CoachTheme.background.ignoresSafeArea())
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        plan.targetWeight = plan.startWeight * (1 - plan.targetLossPercent)
                        onSave(plan)
                        dismiss()
                    }
                }
            }
        }
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { plan.bodyProfile.heightInches ?? 70 },
            set: { plan.bodyProfile.heightInches = $0 }
        )
    }

    private var leanMassBinding: Binding<Double> {
        Binding(
            get: { plan.bodyProfile.leanMassPounds ?? 135 },
            set: {
                plan.bodyProfile.leanMassPounds = $0
                plan.bodyProfile.rmrEstimate = Int((370 + (21.6 * ($0 / 2.20462))).rounded())
                plan.bodyProfile.rmrSource = "Lean-mass estimate"
            }
        )
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(CoachTheme.Text.faint)
            content()
                .padding(14)
                .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                        .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
                }
        }
    }
}

private extension View {
    func goalSettingsBlock() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CoachTheme.Radius.lg, style: .continuous)
                    .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
            }
    }
}

// MARK: - Meal entry (describe or photo)

private struct MealEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (_ description: String, _ imageData: Data?) async -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var description = ""
    @State private var isLogging = false

    private var isValid: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty || imageData != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Log a meal")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(CoachTheme.Text.muted)
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.pressable)
                }

                photoPicker

                VStack(alignment: .leading, spacing: 8) {
                    Text("WHAT DID YOU EAT?")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(CoachTheme.Text.faint)
                    TextField("e.g. Chicken bowl with rice and greens", text: $description, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                                .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
                        }
                }

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Haiku estimates the calories & protein automatically — no need to enter numbers.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(CoachTheme.Text.faint)

                if isLogging {
                    HStack(spacing: 10) {
                        ProgressView().tint(CoachTheme.accent)
                        Text("Evaluating with Haiku…")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(CoachTheme.Text.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                } else {
                    PrimaryButton(title: "Log meal", systemImage: "checkmark", isEnabled: isValid) {
                        let text = description.trimmingCharacters(in: .whitespaces)
                        let prompt = text.isEmpty ? "Estimate this meal from the photo." : text
                        isLogging = true
                        Task {
                            await onSave(prompt, imageData)
                            dismiss()
                        }
                    }
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .background(CoachTheme.background.ignoresSafeArea())
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack {
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 170)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: CoachTheme.Radius.lg, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(CoachTheme.accent)
                        Text("Add a photo")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(CoachTheme.Text.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CoachTheme.Radius.lg, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .foregroundStyle(CoachTheme.Stroke.panel)
                    }
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    imageData = data
                }
            }
        }
    }
}
