import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject private var appState: AppState
    @State private var workoutNote = ""
    @State private var configurationNote = ""
    @State private var lastCoachReply = "Tell me your sets naturally. I’ll turn them into the log."
    @State private var lastConfigReply = "Tap a day, then tell me what that workout should become."
    @State private var showsConversationalLogger = false
    @State private var showsManualLogger = false
    @State private var exercise = "Bench Press"
    @State private var reps = 5
    @State private var weight = 185

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    calendarHeader
                    weekStrip

                    if let workout = appState.selectedWorkoutDay {
                        conversationalLogger
                        workoutHeader(workout)
                        configurationCoach
                        manualLogger
                        setsList(workout)
                    }
                }
                .padding()
                .padding(.bottom, 104)
            }
            .background(CoachTheme.background)
            .navigationTitle("Workout")
        }
    }

    private var calendarHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [CoachTheme.mint.opacity(0.95), CoachTheme.blue.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 62, height: 62)
                    .shadow(color: CoachTheme.mint.opacity(0.25), radius: 18, y: 8)

                Image(systemName: "calendar")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.82))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("7 day training schedule")
                    .font(.title2.weight(.bold))
                Text("Pick a day and configure it with the coach.")
                    .font(.subheadline)
                    .foregroundStyle(CoachTheme.mutedText)
            }

            Spacer()
        }
        .padding()
        .glassPanel()
    }

    private var weekStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(appState.workoutSchedule) { day in
                    dayButton(day)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func dayButton(_ day: WorkoutDayPlan) -> some View {
        let isSelected = day.id == appState.selectedWorkoutDay?.id

        return Button {
            appState.selectWorkoutDay(day)
        } label: {
            VStack(spacing: 8) {
                Text(day.dayName)
                    .font(.caption.weight(.semibold))
                Text(day.dayNumber)
                    .font(.title3.weight(.bold))
                Circle()
                    .fill(day.isTrainingDay ? CoachTheme.mint : Color.white.opacity(0.28))
                    .frame(width: 7, height: 7)
            }
            .foregroundStyle(isSelected ? .black : .white)
            .frame(width: 72, height: 88)
            .background(isSelected ? CoachTheme.mint : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.42) : CoachTheme.panelStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func workoutHeader(_ workout: WorkoutDayPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workout.title)
                .font(.largeTitle.weight(.bold))
            Text(workout.focus)
                .foregroundStyle(CoachTheme.mutedText)
            Label("Total volume \(workout.volume.formatted()) lb", systemImage: "chart.bar.fill")
                .foregroundStyle(CoachTheme.mint)
            Text(workout.coachNotes)
                .font(.caption)
                .foregroundStyle(CoachTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassPanel()
    }

    private var configurationCoach: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Configure this day with coach", systemImage: "wand.and.stars")
                .font(.headline)

            TextField("Example: make Friday lower body, or swap this for recovery", text: $configurationNote, axis: .vertical)
                .lineLimit(2...5)
                .padding(12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(CoachTheme.mint)
                Text(lastConfigReply)
                    .font(.subheadline)
                    .foregroundStyle(CoachTheme.mutedText)
            }
            .padding()
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                let note = configurationNote
                configurationNote = ""
                Task {
                    await appState.sendWorkoutConfigurationMessage(note)
                    lastConfigReply = appState.messages.last?.text ?? lastConfigReply
                }
            } label: {
                Label("Update this day", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(CoachTheme.mint)
            .disabled(configurationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .glassPanel()
    }

    private var conversationalLogger: some View {
        DisclosureGroup(isExpanded: $showsConversationalLogger) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Examples: “bench 185 x 5, 5, 4” or “rows 145 x 8, curls 30 x 12”.")
                    .font(.caption)
                    .foregroundStyle(CoachTheme.mutedText)

                TextField("What did you just do?", text: $workoutNote, axis: .vertical)
                    .lineLimit(3...7)
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkle")
                        .foregroundStyle(CoachTheme.mint)
                    Text(lastCoachReply)
                        .font(.subheadline)
                        .foregroundStyle(CoachTheme.mutedText)
                }
                .padding()
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    let note = workoutNote
                    workoutNote = ""
                    Task {
                        await appState.sendWorkoutMessage(note)
                        lastCoachReply = appState.messages.last?.text ?? lastCoachReply
                    }
                } label: {
                    Label("Send to coach", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CoachTheme.mint)
                .foregroundStyle(.black)
                .disabled(workoutNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 12)
        } label: {
            Label("Talk through the workout", systemImage: "bubble.left.and.text.bubble.right.fill")
                .font(.headline)
        }
        .padding()
        .glassPanel()
    }

    private var manualLogger: some View {
        DisclosureGroup(isExpanded: $showsManualLogger) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Exercise", text: $exercise)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Stepper("Reps \(reps)", value: $reps, in: 1...30)
                    Stepper("\(weight) lb", value: $weight, in: 0...600, step: 5)
                }
                .font(.subheadline)

                Button {
                    appState.addSet(exercise: exercise, reps: reps, weight: weight)
                } label: {
                    Label("Add manual set", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CoachTheme.mint)
            }
            .padding(.top, 12)
        } label: {
            Label("Manual fallback", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
        .padding()
        .glassPanel()
    }

    private func setsList(_ workout: WorkoutDayPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tracked sets")
                .font(.headline)

            ForEach(workout.sets) { set in
                HStack {
                    Text(set.exercise)
                    Spacer()
                    Text("\(set.weight) x \(set.reps)")
                        .foregroundStyle(CoachTheme.mint)
                }
                .padding()
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("Ask Coach for a substitution when equipment is taken. The live Haiku function will convert that chat into structured changes.")
                .font(.caption)
                .foregroundStyle(CoachTheme.mutedText)
        }
        .padding()
        .glassPanel()
    }
}
