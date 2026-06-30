import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsSettings = false
    @State private var appeared = false
    @State private var showsEditor = false
    @State private var editorSeed: DailyTask?
    @State private var isEnergyExpanded = false

    private var completedCount: Int { appState.tasks.filter(\.isComplete).count }
    private var totalCount: Int { appState.tasks.count }
    private var timelineTasks: [DailyTask] {
        appState.tasks.sorted { lhs, rhs in
            let left = daySortMinutes(for: lhs)
            let right = daySortMinutes(for: rhs)
            if left != right { return left < right }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
    private var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }
    private var workoutCompleteToday: Bool {
        appState.healthMetrics.workoutsToday > 0
            || appState.tasks.contains {
                $0.isComplete
                    && ($0.title.localizedCaseInsensitiveContains("workout")
                        || $0.title.localizedCaseInsensitiveContains("gym")
                        || $0.title.localizedCaseInsensitiveContains("lift"))
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                stagger(0) { topBar }
                stagger(1) { energyCard }
                stagger(2) { coachCard }
                stagger(3) { goalCard }
                stagger(4) { heroCard }
                stagger(5) { taskSection }
                stagger(6) { sickDayCard }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(CoachTheme.background)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showsSettings) {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showsEditor) {
            TaskEditorSheet(existing: editorSeed) { task in
                appState.upsertTask(task)
            }
            .preferredColorScheme(.dark)
        }
        .onAppear {
            withAnimation { appeared = true }
            Task { await appState.refreshDailyState() }
        }
    }

    private func stagger<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 22)
            .animation(.easeOut(duration: 0.55).delay(Double(index) * 0.09), value: appeared)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(CoachTheme.accent)
                Text(greeting)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(CoachTheme.Text.primary)
            }
            Spacer()
            Button {
                Haptics.light()
                showsSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(CoachTheme.accent)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .overlay { Circle().stroke(CoachTheme.Stroke.panel, lineWidth: 1) }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    // MARK: Today's Energy

    private var energyCard: some View {
        let energy = appState.todayEnergy
        return Button {
            Haptics.light()
            withAnimation(.snappy(duration: 0.3)) {
                isEnergyExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's Energy")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(CoachTheme.Text.primary)
                        Text("\(energy.score)% · \(energy.label)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(Double(energy.score) / 100))
                            .stroke(CoachTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int((energy.confidence * 100).rounded()))")
                            .font(.caption.bold())
                            .foregroundStyle(CoachTheme.Text.muted)
                    }
                    .frame(width: 58, height: 58)
                    .accessibilityLabel("Confidence \(Int((energy.confidence * 100).rounded())) percent")
                }

                Text(energy.bestMove)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CoachTheme.Text.primary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    driverRow("Main driver", energy.primaryDriver)
                    if isEnergyExpanded {
                        ForEach(energy.secondaryDrivers, id: \.self) { driver in
                            driverRow("Signal", driver)
                        }
                        Text(energy.expandedExplanation)
                            .font(.footnote)
                            .foregroundStyle(CoachTheme.Text.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(radius: CoachTheme.Radius.xl)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Tap to expand today's energy drivers")
    }

    private func driverRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(CoachTheme.accent)
            Text(value)
                .font(.footnote)
                .foregroundStyle(CoachTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var coachCard: some View {
        let coach = appState.dailyCoachSnapshot
        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 12) {
                Image("LoopMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 20)
                    .padding(9)
                    .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.primary)
                    Text(coach.updateWindow.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CoachTheme.accent)
                }
                Spacer()
                Text(coach.recommendationType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(CoachTheme.accent.opacity(0.25), in: Capsule())
            }

            Text(coach.coachRead)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CoachTheme.Text.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(coach.evidence.prefix(3), id: \.self) { point in
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(CoachTheme.accent)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(point)
                            .font(.footnote)
                            .foregroundStyle(CoachTheme.Text.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Best next move")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CoachTheme.accent)
                Text(coach.bestNextMove)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Label(coach.habitFocus, systemImage: "target")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CoachTheme.Text.muted)
                Spacer()
                Text(coach.coachCue)
                    .font(.caption)
                    .foregroundStyle(CoachTheme.Text.faint)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.xl)
    }

    private var goalCard: some View {
        let goal = appState.goalPlan
        let progress = appState.goalProgress
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cut Goal")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.primary)
                    Text("Target \(goal.endDate.formatted(.dateTime.month(.abbreviated).day())) · \(progress.daysRemaining)d left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CoachTheme.Text.muted)
                }
                Spacer()
                Text(progress.paceStatus)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(goalStatusColor(progress.paceStatus))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(goalStatusColor(progress.paceStatus).opacity(0.15), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(progress.currentTrendWeight.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "--")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("lb trend")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CoachTheme.Text.muted)
                Spacer()
                Text("Target \(goal.targetWeight.formatted(.number.precision(.fractionLength(1))))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CoachTheme.Text.faint)
            }

            targetBar(
                title: "Active calories",
                value: "\(progress.sevenDayActiveCaloriesAverage ?? appState.healthMetrics.activeEnergy)/\(goal.activeCalorieMin)-\(goal.activeCalorieMax)",
                progress: Double(progress.sevenDayActiveCaloriesAverage ?? appState.healthMetrics.activeEnergy) / Double(max(goal.activeCalorieMax, 1)),
                systemImage: "flame.fill"
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Daily targets")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CoachTheme.Text.primary)
                Spacer()
                Text(appState.healthMetrics.healthKitStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CoachTheme.Text.faint)
            }

            targetBar(
                title: "Workout",
                value: workoutCompleteToday ? "Complete" : "Open",
                progress: workoutCompleteToday ? 1 : 0,
                systemImage: "dumbbell.fill"
            )
            targetBar(
                title: "Active calories",
                value: "\(appState.healthMetrics.activeEnergy)/500",
                progress: Double(appState.healthMetrics.activeEnergy) / 500,
                systemImage: "flame.fill"
            )
            targetBar(
                title: "Steps",
                value: "\(appState.healthMetrics.steps.formatted())/8,000",
                progress: Double(appState.healthMetrics.steps) / 8_000,
                systemImage: "figure.walk"
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private func targetBar(title: String, value: String, progress: Double, systemImage: String) -> some View {
        let clamped = min(max(progress, 0), 1)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CoachTheme.accent)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CoachTheme.Text.muted)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(clamped >= 1 ? CoachTheme.accent : CoachTheme.Text.primary)
                    .contentTransition(.numericText())
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [CoachTheme.accent, CoachTheme.ember],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * clamped)
                }
            }
            .frame(height: 7)
        }
    }

    // MARK: Tasks

    private var sickDayCard: some View {
        Button {
            guard !appState.isSickDay else { return }
            Haptics.soft()
            withAnimation(.snappy(duration: 0.35)) {
                appState.activateSickDay()
            }
        } label: {
            HStack(spacing: 14) {
                IconTile(systemImage: appState.isSickDay ? "checkmark.circle.fill" : "cross.case.fill", size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.isSickDay ? "Sick day active" : "Sick day")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.primary)
                    Text(appState.isSickDay ? "Normal targets are skipped. Light walk only if it helps." : "Skip today’s pressure and switch to a light walk.")
                        .font(.caption)
                        .foregroundStyle(CoachTheme.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: appState.isSickDay ? "heart.fill" : "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(appState.isSickDay ? CoachTheme.accent : CoachTheme.Text.faint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                    .stroke(appState.isSickDay ? CoachTheme.accent.opacity(0.55) : CoachTheme.Stroke.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.pressable)
        .disabled(appState.isSickDay)
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Today's focus", subtitle: "Swipe right to complete · long-press to edit") {
                Button {
                    Haptics.light()
                    editorSeed = nil
                    showsEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CoachTheme.accent)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .overlay { Circle().stroke(CoachTheme.Stroke.hairline, lineWidth: 1) }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Add reminder")
            }

            VStack(spacing: 10) {
                ForEach(timelineTasks) { task in
                    TaskRowView(
                        task: task,
                        onComplete: { complete(task) },
                        onEdit: {
                            Haptics.light()
                            editorSeed = task
                            showsEditor = true
                        },
                        onDelete: {
                            Haptics.soft()
                            withAnimation(.snappy(duration: 0.3)) { appState.deleteTask(task) }
                        }
                    )
                }
            }
        }
    }

    private func complete(_ task: DailyTask) {
        Haptics.success()
        withAnimation(.snappy(duration: 0.35)) {
            appState.toggleTask(task)
        }
    }

    private func daySortMinutes(for task: DailyTask) -> Int {
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

}

// MARK: - Task row with swipe-to-complete

private struct TaskRowView: View {
    let task: DailyTask
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        rowContent
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if !task.isComplete {
                    Button {
                        onComplete()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .tint(CoachTheme.ember)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.gray)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private var rowContent: some View {
        Button(action: onComplete) {
            HStack(spacing: 14) {
                IconTile(systemImage: task.systemImage)
                    .saturation(task.isComplete ? 0.3 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .strikethrough(task.isComplete, color: .white.opacity(0.6))
                    HStack(spacing: 8) {
                        Text(task.detail)
                            .font(.caption)
                            .foregroundStyle(CoachTheme.Text.muted)
                        if let time = task.reminderTime {
                            Label(time.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(CoachTheme.accent)
                        }
                    }
                }

                Spacer()

                CircularCheck(isOn: task.isComplete)
            }
            .foregroundStyle(.white)
            .opacity(task.isComplete ? 0.6 : 1)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                    .fill(task.isComplete ? CoachTheme.Fill.subtle : CoachTheme.Fill.soft)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                    .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.pressable)
        .contextMenu {
            Button { onEdit() } label: { Label("Edit reminder", systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Task editor

private struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existing: DailyTask?
    let onSave: (DailyTask) -> Void

    @State private var title = ""
    @State private var detail = ""
    @State private var symbol = "checklist"
    @State private var hasReminder = true
    @State private var time = DailyTask.time(9, 0)

    private let symbols = [
        "checklist", "scalemass.fill", "fork.knife", "takeoutbag.and.cup.and.straw.fill",
        "figure.strengthtraining.traditional", "figure.walk", "moon.stars.fill",
        "drop.fill", "pills.fill", "bed.double.fill", "cup.and.saucer.fill", "heart.fill"
    ]

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(existing == nil ? "New reminder" : "Edit reminder")
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

                field("TITLE") {
                    TextField("e.g. Afternoon walk", text: $title)
                        .textFieldStyle(.plain)
                }

                field("DETAIL") {
                    TextField("Short note", text: $detail)
                        .textFieldStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("ICON")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(CoachTheme.Text.faint)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(symbols, id: \.self) { sym in
                                Button { Haptics.soft(); symbol = sym } label: {
                                    IconTile(systemImage: sym, size: 44)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(CoachTheme.accent, lineWidth: symbol == sym ? 2 : 0)
                                        }
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $hasReminder.animation(.snappy)) {
                        Label("Remind me", systemImage: "bell.fill")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .tint(CoachTheme.accent)

                    if hasReminder {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
                .glassPanel(radius: CoachTheme.Radius.lg)

                PrimaryButton(title: existing == nil ? "Add reminder" : "Save changes", systemImage: "checkmark", isEnabled: isValid) {
                    save()
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .background(CoachTheme.background.ignoresSafeArea())
        .onAppear {
            if let existing {
                title = existing.title
                detail = existing.detail
                symbol = existing.systemImage
                hasReminder = existing.reminderTime != nil
                time = existing.reminderTime ?? DailyTask.time(9, 0)
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(CoachTheme.Text.faint)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                        .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
                }
        }
    }

    private func save() {
        Haptics.success()
        var task = existing ?? DailyTask(title: "", detail: "", systemImage: symbol, isComplete: false)
        task.title = title.trimmingCharacters(in: .whitespaces)
        task.detail = detail.trimmingCharacters(in: .whitespaces)
        task.systemImage = symbol
        task.reminderTime = hasReminder ? time : nil
        onSave(task)
        dismiss()
    }
}
