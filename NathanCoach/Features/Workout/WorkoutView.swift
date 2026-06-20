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

    enum LoggerMode: String, CaseIterable { case talk = "Talk", manual = "Manual", configure = "Configure" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                weekStrip

                if let workout = appState.selectedWorkoutDay {
                    heroSession(workout)
                    loggerSection
                    setsList(workout)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(CoachTheme.background)
        .scrollIndicators(.hidden)
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
            .padding(.vertical, 2)
        }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("e.g. \"bench 185 x 5, 5, 4\" or \"rows 145 x 8, curls 30 x 12\".")
                .font(.caption)
                .foregroundStyle(CoachTheme.Text.muted)

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
        VStack(alignment: .leading, spacing: 12) {
            Text("Reshape this day — \"make Friday lower body\" or \"swap this for recovery\".")
                .font(.caption)
                .foregroundStyle(CoachTheme.Text.muted)

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
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tracked sets", subtitle: workout.sets.isEmpty ? "No sets yet" : "\(workout.sets.count) logged")

            if workout.sets.isEmpty {
                Text("Log your first set above and it'll show here.")
                    .font(.footnote)
                    .foregroundStyle(CoachTheme.Text.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(workout.sets.enumerated()), id: \.element.id) { index, set in
                    HStack(spacing: 14) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(CoachTheme.accent)
                            .frame(width: 26, height: 26)
                            .background(CoachTheme.glow, in: Circle())
                        Text(set.exercise)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("\(set.weight) lb × \(set.reps)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(CoachTheme.accent)
                    }
                    .padding(14)
                    .background(CoachTheme.Fill.soft, in: RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                            .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
                    }
                }
            }
        }
    }
}
