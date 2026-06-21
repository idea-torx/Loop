import Charts
import PhotosUI
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedWeighIn: WeighIn?
    @State private var showsMealEntry = false
    @State private var appeared = false

    private var rollingWeights: [WeighIn] {
        appState.metricsService.rollingAverage(points: appState.weighIns)
    }

    private var currentWeight: Double { appState.weighIns.last?.pounds ?? 0 }
    private var startWeight: Double { appState.weighIns.first?.pounds ?? currentWeight }
    private var delta: Double { currentWeight - startWeight }

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
                weightHero
                weightChart
                nutritionSection
                insightCard
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

    // MARK: Weight

    private var weightHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT WEIGHT · GOAL \(PTProtocol.goal.uppercased())")
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

    private var weightChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Weight trend",
                subtitle: selectedWeighIn.map { "\($0.date.formatted(.dateTime.month().day())) · \($0.pounds.formatted(.number.precision(.fractionLength(1)))) lb" } ?? "Last 14 days · drag to inspect"
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
            Text(meal.date.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(CoachTheme.Text.faint)
        }
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
