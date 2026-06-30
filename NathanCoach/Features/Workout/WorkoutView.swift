import Charts
import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var workoutNote = ""
    @State private var configurationNote = ""
    @State private var lastCoachReply = "Tell me your sets naturally. I'll turn them into the log."
    @State private var lastConfigReply = "Tap a day, then tell me what that workout should become."
    @State private var loggerMode: LoggerMode = .currentSet
    @State private var exercise = ""
    @State private var reps = 8
    @State private var weight = 0
    @State private var rir: Int?
    @State private var expandedExerciseKeys: Set<String> = []
    @State private var editingSet: EditableSet?
    @State private var selectedExercise: ExerciseSelection?
    @State private var isSendingWorkoutNote = false
    @State private var workoutSendError: String?
    @FocusState private var focusedField: WorkoutFocusField?

    enum LoggerMode: String, CaseIterable { case currentSet = "Current Set", configure = "Configure" }
    enum WorkoutFocusField { case talk, configure, exercise }

    struct EditableSet: Identifiable {
        let id: ExerciseSet.ID
        var exercise: String
        var reps: Int
        var weight: Int
        var rir: Int?
    }

    struct ExerciseGroup: Identifiable {
        let id: String
        let exercise: String
        let sets: [ExerciseSet]

        var volume: Int {
            sets.reduce(0) { $0 + ($1.reps * $1.weight) }
        }
    }

    struct ExerciseSelection: Identifiable {
        let exercise: String
        var id: String { exercise }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                weekStrip

                if let workout = appState.selectedWorkoutDay {
                    loggerSection
                    heroSession(workout)
                    previousSplitSessionCard(for: workout)
                    setsList(workout)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(CoachTheme.background)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
        .sheet(item: $editingSet) { draft in
            SetEditorSheet(draft: draft) { updated in
                Haptics.success()
                appState.updateSet(updated.id, exercise: updated.exercise, reps: updated.reps, weight: updated.weight, rir: updated.rir)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedExercise) { selection in
            ExerciseFocusSheet(exercise: selection.exercise)
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            appState.selectCurrentWorkoutDay()
            syncCurrentSetControls()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            appState.selectCurrentWorkoutDay()
            syncCurrentSetControls()
        }
        .onChange(of: appState.selectedWorkoutDay?.id) { _, _ in
            syncCurrentSetControls()
        }
        .onChange(of: appState.selectedWorkoutDay?.sets.count ?? 0) { _, _ in
            syncCurrentSetControls()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("THIS WEEK")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundStyle(CoachTheme.accent)
            Text("Training")
                .font(.system(size: 32, weight: .bold, design: .rounded))
        }
        .padding(.top, 8)
    }

    // MARK: Week strip

    private var weekStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(appState.workoutSchedule) { day in
                    dayCard(day)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    private func dayCard(_ day: WorkoutDayPlan) -> some View {
        let isSelected = day.id == appState.selectedWorkoutDay?.id

        return Button {
            Haptics.soft()
            withAnimation(.snappy(duration: 0.3)) { appState.selectWorkoutDay(day) }
        } label: {
            VStack(spacing: 7) {
                Text(day.dayName.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white.opacity(0.78) : CoachTheme.Text.muted)
                Text(day.dayNumber)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : CoachTheme.Text.primary)
                Circle()
                    .fill(day.isTrainingDay ? (isSelected ? .white.opacity(0.82) : CoachTheme.accent) : Color.white.opacity(isSelected ? 0.5 : 0.25))
                    .frame(width: 6, height: 6)
            }
            .frame(width: 60, height: 84)
            .background {
                if isSelected {
                    Capsule().fill(
                        LinearGradient(colors: [CoachTheme.flame, CoachTheme.ember],
                                       startPoint: .top, endPoint: .bottom)
                    )
                } else {
                    Capsule().fill(CoachTheme.Fill.soft)
                        .overlay { Capsule().stroke(CoachTheme.Stroke.hairline, lineWidth: 1) }
                }
            }
        }
        .buttonStyle(.pressable)
    }

    // MARK: Hero session

    private func heroSession(_ workout: WorkoutDayPlan) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                IconTile(systemImage: workout.isTrainingDay ? "figure.strengthtraining.traditional" : "figure.cooldown", size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(workout.focus)
                        .font(.subheadline)
                        .foregroundStyle(CoachTheme.Text.muted)
                }
                Spacer()
            }

            HStack(spacing: 0) {
                HeroStat(value: workout.volume.formatted(), label: "Volume lb")
                Divider().frame(height: 36).overlay(CoachTheme.Stroke.hairline)
                HeroStat(value: "\(workout.sets.count)", label: "Sets", alignment: .center)
                Divider().frame(height: 36).overlay(CoachTheme.Stroke.hairline)
                HeroStat(value: workout.isTrainingDay ? "On" : "Rest", label: "Status", alignment: .center)
            }

            Text(workout.coachNotes)
                .font(.footnote)
                .foregroundStyle(CoachTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.xl)
    }

    private func previousSplitSessionCard(for workout: WorkoutDayPlan) -> some View {
        let split = appState.splitTitle(for: workout)
        let previous = appState.previousWorkoutForSelectedSplit()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Previous \(split)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.primary)
                    Text(previous.map { $0.date.formatted(.dateTime.weekday(.wide).month().day()) } ?? "No prior \(split) logged yet")
                        .font(.caption)
                        .foregroundStyle(CoachTheme.Text.faint)
                }
                Spacer()
                if let previous {
                    Text("\(previous.volume.formatted()) lb")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CoachTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(CoachTheme.glow, in: Capsule())
                }
            }

            if let previous, !previous.sets.isEmpty {
                VStack(spacing: 8) {
                    ForEach(exerciseGroups(for: previous.sets).prefix(4)) { group in
                        previousExerciseRow(group)
                    }
                }
            } else {
                Text("Log this \(split) once and Loop will show the last session here so you can repeat it, then beat it.")
                    .font(.footnote)
                    .foregroundStyle(CoachTheme.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private func previousExerciseRow(_ group: ExerciseGroup) -> some View {
        Button {
            Haptics.soft()
            selectedExercise = ExerciseSelection(exercise: group.exercise)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.exercise)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.primary)
                    Text("\(group.sets.count) set\(group.sets.count == 1 ? "" : "s") · \(group.volume.formatted()) lb")
                        .font(.caption2)
                        .foregroundStyle(CoachTheme.Text.faint)
                }
                Spacer()
                Text(group.sets.map { "\($0.weight)×\($0.reps)" }.joined(separator: ", "))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CoachTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CoachTheme.Text.faint)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
        .buttonStyle(.plain)
    }

    // MARK: Logger

    private var loggerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Log your work")

            loggerModeSelector

            switch loggerMode {
            case .currentSet: currentSetLogger
            case .configure: configureLogger
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private var loggerModeSelector: some View {
        HStack(spacing: 8) {
            ForEach(LoggerMode.allCases, id: \.self) { mode in
                let isSelected = loggerMode == mode
                Button {
                    Haptics.soft()
                    withAnimation(.snappy(duration: 0.22)) { loggerMode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : CoachTheme.Text.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            isSelected ? CoachTheme.accent : Color.white.opacity(0.055),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().stroke(Color.white.opacity(isSelected ? 0 : 0.08), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.rawValue)
            }
        }
    }

    private var currentSetLogger: some View {
        return VStack(alignment: .leading, spacing: 14) {
            TextField("What did you just do?", text: $workoutNote, axis: .vertical)
                .lineLimit(3...7)
                .focused($focusedField, equals: .talk)
                .padding(12)
                .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))

            replyBubble(icon: "sparkle", text: lastCoachReply)

            if let workoutSendError {
                Text(workoutSendError)
                    .font(.caption)
                    .foregroundStyle(CoachTheme.flame)
            }

            Button {
                sendWorkoutNote()
            } label: {
                HStack(spacing: 8) {
                    if isSendingWorkoutNote {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                    }
                    Text(isSendingWorkoutNote ? "Sending..." : "Send to coach")
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(CoachTheme.accent, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
                .opacity(canSendWorkoutNote ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canSendWorkoutNote)

            Divider().overlay(CoachTheme.Stroke.hairline)

            currentSetControls
        }
    }

    private var canSendWorkoutNote: Bool {
        !workoutNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSendingWorkoutNote
    }

    private func sendWorkoutNote() {
        let note = workoutNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else {
            workoutSendError = "Type what you did first."
            return
        }

        workoutSendError = nil
        focusedField = nil
        lastCoachReply = "Reading that now..."
        isSendingWorkoutNote = true
        Task {
            await appState.sendWorkoutMessage(note)
            lastCoachReply = appState.messages.last?.text ?? "I logged what I could from that."
            syncCurrentSetControls()
            workoutNote = ""
            isSendingWorkoutNote = false
        }
    }

    private var currentSetControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current set")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.primary)
                    Text(currentSetSubtitle)
                        .font(.caption)
                        .foregroundStyle(CoachTheme.Text.faint)
                }
                Spacer()
                if let latestSet {
                    Text("\(latestSet.weight) × \(latestSet.reps)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CoachTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(CoachTheme.glow, in: Capsule())
                }
            }

            TextField("Exercise", text: $exercise)
                .focused($focusedField, equals: .exercise)
                .padding(12)
                .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))

            if hasCurrentExercise {
                HStack(spacing: 10) {
                    quickAdjustTile(title: "Weight (LB)", value: weight, suffix: "", decrement: {
                        weight = max(0, weight - 5)
                    }, increment: {
                        weight = min(800, weight + 5)
                    })
                    quickAdjustTile(title: "Reps", value: reps, suffix: "", decrement: {
                        reps = max(1, reps - 1)
                    }, increment: {
                        reps = min(50, reps + 1)
                    })
                }

                progressionCard

                rirControl

                Button {
                    guard hasCurrentExercise else { return }
                    Haptics.success()
                    let cleanExercise = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.addSet(exercise: cleanExercise, reps: reps, weight: weight, rir: rir)
                    lastCoachReply = "Added \(cleanExercise): \(weight) lb × \(reps)."
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text(addSetButtonTitle)
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(CoachTheme.accent, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Text("No current set yet. Tell the coach what you did, or type an exercise here to start manually.")
                    .font(.footnote)
                    .foregroundStyle(CoachTheme.Text.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
        }
    }

    private var latestSet: ExerciseSet? {
        appState.selectedWorkoutDay?.sets.last
    }

    private var currentSetSubtitle: String {
        latestSet == nil ? "Tell Haiku the first set, then repeat it fast here." : "Use +/- to log another set without messaging Haiku."
    }

    private var hasCurrentExercise: Bool {
        !exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var addSetButtonTitle: String {
        latestSet == nil ? "Add set" : "Add another \(exercise)"
    }

    private var overloadRecommendation: AppState.OverloadRecommendation {
        appState.overloadRecommendation(for: exercise, fallbackReps: reps, fallbackWeight: weight)
    }

    private var progressionCard: some View {
        let recommendation = overloadRecommendation

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Progression", systemImage: "arrow.up.forward")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CoachTheme.accent)
                Spacer()
                Text("\(recommendation.targetMinReps)-\(recommendation.targetMaxReps) reps")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CoachTheme.Text.faint)
            }

            HStack(spacing: 10) {
                progressionMetric(title: "Last time", value: recommendation.previousSummary)
                progressionMetric(title: "Today target", value: recommendation.targetSummary)
            }

            Text(recommendation.reason)
                .font(.caption)
                .foregroundStyle(CoachTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.soft()
                withAnimation(.snappy(duration: 0.22)) {
                    exercise = recommendation.exercise
                    weight = recommendation.suggestedWeight
                    reps = recommendation.suggestedReps
                }
            } label: {
                Text("Apply target")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CoachTheme.Text.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay { Capsule().stroke(CoachTheme.Stroke.hairline, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .disabled(!recommendation.hasHistory)
            .opacity(recommendation.hasHistory ? 1 : 0.55)
        }
        .padding(12)
        .background(CoachTheme.glow, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
    }

    private func progressionMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(CoachTheme.Text.faint)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CoachTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
    }

    private var rirControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RIR")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(CoachTheme.Text.faint)
                Spacer()
                Text(rir.map { "\($0) reps in reserve" } ?? "Optional")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CoachTheme.Text.muted)
            }

            HStack(spacing: 8) {
                rirButton(title: "Skip", value: nil)
                ForEach(0...4, id: \.self) { value in
                    rirButton(title: "\(value)", value: value)
                }
            }
        }
    }

    private func rirButton(title: String, value: Int?) -> some View {
        let selected = rir == value
        return Button {
            Haptics.soft()
            withAnimation(.snappy(duration: 0.18)) { rir = value }
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? .white : CoachTheme.Text.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? CoachTheme.accent : Color.white.opacity(0.055), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func quickAdjustTile(title: String, value: Int, suffix: String, decrement: @escaping () -> Void, increment: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(CoachTheme.Text.faint)

            HStack(spacing: 10) {
                adjustButton(systemImage: "minus", action: decrement)

                Text("\(value)\(suffix)")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)

                adjustButton(systemImage: "plus", action: increment)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
    }

    private func adjustButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.soft()
            withAnimation(.snappy(duration: 0.18), action)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CoachTheme.Text.primary)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay { Circle().stroke(CoachTheme.Stroke.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func syncCurrentSetControls() {
        guard let latestSet else {
            exercise = ""
            reps = 8
            weight = 0
            rir = nil
            return
        }
        exercise = latestSet.exercise
        reps = latestSet.reps
        weight = latestSet.weight
        rir = latestSet.rir
    }

    private var configureLogger: some View {
        return VStack(alignment: .leading, spacing: 12) {
            TextField("Tell the coach what this day should become", text: $configurationNote, axis: .vertical)
                .lineLimit(2...5)
                .focused($focusedField, equals: .configure)
                .padding(12)
                .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))

            replyBubble(icon: "wand.and.stars", text: lastConfigReply)

            PrimaryButton(title: "Update this day", systemImage: "arrow.triangle.2.circlepath",
                          isEnabled: !configurationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                let note = configurationNote
                configurationNote = ""
                Task {
                    await appState.sendWorkoutConfigurationMessage(note)
                    lastConfigReply = appState.messages.last?.text ?? lastConfigReply
                }
            }
        }
    }

    private func replyBubble(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(CoachTheme.accent)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(CoachTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CoachTheme.glow, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
    }

    // MARK: Sets list

    private func setsList(_ workout: WorkoutDayPlan) -> some View {
        let groups = exerciseGroups(for: workout.sets)

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tracked sets", subtitle: workout.sets.isEmpty ? "No sets yet" : "\(groups.count) exercises, \(workout.sets.count) sets")

            if workout.sets.isEmpty {
                Text("Log your first set above and it'll show here.")
                    .font(.footnote)
                    .foregroundStyle(CoachTheme.Text.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(groups) { group in
                    exerciseGroupRow(group)
                }
            }
        }
    }

    private func exerciseGroupRow(_ group: ExerciseGroup) -> some View {
        let isExpanded = expandedExerciseKeys.contains(group.id)

        return VStack(spacing: 0) {
            Button {
                Haptics.soft()
                withAnimation(.snappy(duration: 0.25)) {
                    if isExpanded {
                        expandedExerciseKeys.remove(group.id)
                    } else {
                        expandedExerciseKeys.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CoachTheme.accent)
                        .frame(width: 24, height: 24)
                        .background(CoachTheme.glow, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.exercise)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(CoachTheme.Text.primary)
                        Text("\(group.sets.count) set\(group.sets.count == 1 ? "" : "s") · \(group.volume.formatted()) lb volume")
                            .font(.caption)
                            .foregroundStyle(CoachTheme.Text.muted)
                    }

                    Spacer()

                    Text(group.sets.map { "\($0.weight)×\($0.reps)" }.joined(separator: ", "))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CoachTheme.accent)
                        .lineLimit(1)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(Array(group.sets.enumerated()), id: \.element.id) { index, set in
                        setDetailRow(set, setNumber: index + 1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
        }
    }

    private func setDetailRow(_ set: ExerciseSet, setNumber: Int) -> some View {
        HStack(spacing: 12) {
            Text("Set \(setNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CoachTheme.Text.muted)
                .frame(width: 48, alignment: .leading)

            Text("\(set.weight) lb × \(set.reps)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(CoachTheme.Text.primary)

            Spacer()

            Menu {
                Button("Edit set", systemImage: "pencil") {
                    editingSet = EditableSet(id: set.id, exercise: set.exercise, reps: set.reps, weight: set.weight, rir: set.rir)
                }
                Button("Delete set", systemImage: "trash", role: .destructive) {
                    Haptics.soft()
                    appState.deleteSet(set.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CoachTheme.Text.muted)
                    .frame(width: 32, height: 32)
                    .background(CoachTheme.Fill.soft, in: Circle())
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
    }

    private func exerciseGroups(for sets: [ExerciseSet]) -> [ExerciseGroup] {
        var order: [String] = []
        var grouped: [String: [ExerciseSet]] = [:]
        var displayNames: [String: String] = [:]

        for set in sets {
            let key = normalizedExerciseName(set.exercise)
            if grouped[key] == nil {
                order.append(key)
                displayNames[key] = set.exercise
            }
            grouped[key, default: []].append(set)
        }

        return order.compactMap { key in
            guard let sets = grouped[key], let exercise = displayNames[key] else { return nil }
            return ExerciseGroup(id: key, exercise: exercise, sets: sets)
        }
    }

    private func normalizedExerciseName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct ExerciseFocusSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let exercise: String

    @State private var reps = 8
    @State private var weight = 0
    @State private var rir: Int?
    @State private var note = ""
    @State private var isSending = false
    @State private var didSeedControls = false

    private var history: [AppState.ExerciseHistoryEntry] {
        appState.exerciseHistory(for: exercise)
    }

    private var fallbackSet: ExerciseSet? {
        history.first?.sets.last
    }

    private var recommendation: AppState.OverloadRecommendation {
        appState.overloadRecommendation(
            for: exercise,
            fallbackReps: reps > 0 ? reps : (fallbackSet?.reps ?? 8),
            fallbackWeight: weight > 0 ? weight : (fallbackSet?.weight ?? 0)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    progressionSummary
                    trendCard
                    condensedLogger
                    historyList
                }
                .padding(18)
                .padding(.bottom, 28)
            }
            .background(CoachTheme.background)
            .navigationTitle(exercise)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: seedControlsIfNeeded)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconTile(systemImage: "dumbbell.fill", size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.selectedWorkoutDay.map { appState.splitTitle(for: $0) } ?? "Training")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CoachTheme.accent)
                    Text("Exercise window")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.primary)
                }
                Spacer()
            }

            Text("Review prior \(exercise) work, apply the progression target, or log this movement directly.")
                .font(.footnote)
                .foregroundStyle(CoachTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private var progressionSummary: some View {
        let rec = recommendation

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Progression", systemImage: "arrow.up.forward")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(CoachTheme.accent)
                Spacer()
                Text("\(rec.targetMinReps)-\(rec.targetMaxReps) reps")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CoachTheme.Text.faint)
            }

            HStack(spacing: 10) {
                focusMetric("Last time", rec.previousSummary)
                focusMetric("Target", rec.targetSummary)
            }

            Text(rec.reason)
                .font(.caption)
                .foregroundStyle(CoachTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.soft()
                withAnimation(.snappy(duration: 0.22)) {
                    weight = rec.suggestedWeight
                    reps = rec.suggestedReps
                }
            } label: {
                Text("Apply target")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(rec.hasHistory ? CoachTheme.accent : Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!rec.hasHistory)
            .opacity(rec.hasHistory ? 1 : 0.55)
        }
        .padding(14)
        .background(CoachTheme.glow, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent trend")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CoachTheme.Text.primary)

            let entries = Array(history.prefix(5).reversed())

            if entries.isEmpty {
                Text("No prior sets for this exercise yet.")
                    .font(.footnote)
                    .foregroundStyle(CoachTheme.Text.faint)
            } else {
                Chart {
                    ForEach(entries) { entry in
                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value("Volume", entry.volume)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(CoachTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("Date", entry.date),
                            y: .value("Volume", entry.volume)
                        )
                        .foregroundStyle(CoachTheme.ember)
                        .symbolSize(46)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: entries.map(\.date)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                            .foregroundStyle(CoachTheme.Text.faint)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel()
                            .foregroundStyle(CoachTheme.Text.faint)
                    }
                }
                .chartPlotStyle { plot in
                    plot.background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(height: 142)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
        }
    }

    private var condensedLogger: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log \(exercise)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CoachTheme.Text.primary)

            TextField("185 x 8, 8, 7", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .padding(12)
                .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))

            Button {
                sendNote()
            } label: {
                HStack {
                    if isSending {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                    }
                    Text(isSending ? "Sending..." : "Send to coach")
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(CoachTheme.accent, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
                .opacity(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)

            HStack(spacing: 10) {
                focusStepper(title: "Weight", value: weight, step: 5, range: 0...800)
                focusStepper(title: "Reps", value: reps, step: 1, range: 1...50)
            }

            HStack(spacing: 8) {
                ForEach([nil, 0, 1, 2, 3, 4], id: \.self) { value in
                    Button {
                        Haptics.soft()
                        rir = value
                    } label: {
                        Text(value.map(String.init) ?? "RIR")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(rir == value ? .white : CoachTheme.Text.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(rir == value ? CoachTheme.accent : Color.white.opacity(0.055), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                Haptics.success()
                appState.addSet(exercise: exercise, reps: reps, weight: weight, rir: rir)
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(CoachTheme.accent, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Previous \(exercise)", subtitle: history.isEmpty ? "No history yet" : "\(history.count) recent sessions")

            ForEach(history) { entry in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(CoachTheme.Text.primary)
                        Spacer()
                        Text(entry.split)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CoachTheme.accent)
                    }
                    Text(entry.summary)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.muted)
                    Text("\(entry.volume.formatted()) lb volume")
                        .font(.caption2)
                        .foregroundStyle(CoachTheme.Text.faint)
                }
                .padding(12)
                .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
            }
        }
    }

    private func focusMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(CoachTheme.Text.faint)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(CoachTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
    }

    private func focusStepper(title: String, value: Int, step: Int, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(CoachTheme.Text.faint)

            HStack {
                Button {
                    Haptics.soft()
                    if title == "Weight" {
                        weight = max(range.lowerBound, weight - step)
                    } else {
                        reps = max(range.lowerBound, reps - step)
                    }
                } label: {
                    Image(systemName: "minus")
                }

                Spacer()
                Text("\(value)")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer()

                Button {
                    Haptics.soft()
                    if title == "Weight" {
                        weight = min(range.upperBound, weight + step)
                    } else {
                        reps = min(range.upperBound, reps + step)
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(CoachTheme.Text.primary)
        }
        .padding(12)
        .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
    }

    private func seedControlsIfNeeded() {
        guard !didSeedControls else { return }
        didSeedControls = true
        let rec = recommendation
        weight = rec.hasHistory ? rec.suggestedWeight : (fallbackSet?.weight ?? 0)
        reps = rec.hasHistory ? rec.suggestedReps : (fallbackSet?.reps ?? 8)
        rir = fallbackSet?.rir
    }

    private func sendNote() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        isSending = true
        Task {
            await appState.sendExerciseWorkoutMessage(exercise: exercise, text: trimmed)
            await MainActor.run {
                note = ""
                isSending = false
            }
        }
    }
}

private struct SetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutView.EditableSet
    let onSave: (WorkoutView.EditableSet) -> Void

    init(draft: WorkoutView.EditableSet, onSave: @escaping (WorkoutView.EditableSet) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Exercise", text: $draft.exercise)
                    .textFieldStyle(.roundedBorder)

                Stepper("Reps: \(draft.reps)", value: $draft.reps, in: 1...50)
                Stepper("Weight: \(draft.weight) lb", value: $draft.weight, in: 0...800, step: 5)
                Picker("RIR", selection: Binding(
                    get: { draft.rir ?? -1 },
                    set: { draft.rir = $0 < 0 ? nil : $0 }
                )) {
                    Text("Skip").tag(-1)
                    ForEach(0...4, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()
            }
            .padding(20)
            .background(CoachTheme.background)
            .navigationTitle("Edit Set")
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
                    .disabled(draft.exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
