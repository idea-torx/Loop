import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject private var appState: AppState
    @State private var workoutNote = ""
    @State private var configurationNote = ""
    @State private var lastCoachReply = "Tell me your sets naturally. I'll turn them into the log."
    @State private var lastConfigReply = "Tap a day, then tell me what that workout should become."
    @State private var loggerMode: LoggerMode = .talk
    @State private var exercise = "Bench Press"
    @State private var reps = 5
    @State private var weight = 185
    @State private var expandedExerciseKeys: Set<String> = []
    @State private var editingSet: EditableSet?

    enum LoggerMode: String, CaseIterable { case talk = "Talk", manual = "Manual", configure = "Configure" }

    struct EditableSet: Identifiable {
        let id: ExerciseSet.ID
        var exercise: String
        var reps: Int
        var weight: Int
    }

    struct ExerciseGroup: Identifiable {
        let id: String
        let exercise: String
        let sets: [ExerciseSet]

        var volume: Int {
            sets.reduce(0) { $0 + ($1.reps * $1.weight) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                weekStrip

                if let workout = appState.selectedWorkoutDay {
                    loggerSection
                    heroSession(workout)
                    setsList(workout)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(CoachTheme.background)
        .scrollIndicators(.hidden)
        .sheet(item: $editingSet) { draft in
            SetEditorSheet(draft: draft) { updated in
                Haptics.success()
                appState.updateSet(updated.id, exercise: updated.exercise, reps: updated.reps, weight: updated.weight)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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
                    .foregroundStyle(isSelected ? .black.opacity(0.7) : CoachTheme.Text.muted)
                Text(day.dayNumber)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .black : CoachTheme.Text.primary)
                Circle()
                    .fill(day.isTrainingDay ? (isSelected ? .black.opacity(0.7) : CoachTheme.accent) : Color.white.opacity(0.25))
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

    // MARK: Logger

    private var loggerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Log your work")

            Picker("Mode", selection: $loggerMode) {
                ForEach(LoggerMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch loggerMode {
            case .talk: talkLogger
            case .manual: manualLogger
            case .configure: configureLogger
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private var talkLogger: some View {
        return VStack(alignment: .leading, spacing: 12) {
            TextField("What did you just do?", text: $workoutNote, axis: .vertical)
                .lineLimit(3...7)
                .padding(12)
                .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))

            replyBubble(icon: "sparkle", text: lastCoachReply)

            PrimaryButton(title: "Send to coach", systemImage: "arrow.up",
                          isEnabled: !workoutNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                let note = workoutNote
                workoutNote = ""
                Task {
                    await appState.sendWorkoutMessage(note)
                    lastCoachReply = appState.messages.last?.text ?? lastCoachReply
                }
            }
        }
    }

    private var manualLogger: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Exercise", text: $exercise)
                .padding(12)
                .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))

            HStack(spacing: 12) {
                stepperTile("Reps", value: $reps, range: 1...30, step: 1)
                stepperTile("Weight", value: $weight, range: 0...600, step: 5, suffix: " lb")
            }

            PrimaryButton(title: "Add set", systemImage: "plus") {
                Haptics.success()
                appState.addSet(exercise: exercise, reps: reps, weight: weight)
            }
        }
    }

    private func stepperTile(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(CoachTheme.Text.faint)
            HStack {
                Text("\(value.wrappedValue)\(suffix)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Spacer()
                Stepper("", value: value, in: range, step: step)
                    .labelsHidden()
                    .tint(CoachTheme.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous))
    }

    private var configureLogger: some View {
        return VStack(alignment: .leading, spacing: 12) {
            TextField("Tell the coach what this day should become", text: $configurationNote, axis: .vertical)
                .lineLimit(2...5)
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
                    editingSet = EditableSet(id: set.id, exercise: set.exercise, reps: set.reps, weight: set.weight)
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
