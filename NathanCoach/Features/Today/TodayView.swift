import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsSettings = false
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CoachTheme.Space.xl) {
                    card(0) { header }
                    card(1) { taskList }
                    card(2) { reviewCard }
                    card(3) { healthCard }
                }
                .padding()
                .padding(.bottom, 104)
            }
            .background(CoachTheme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundStyle(CoachTheme.accent)
                            .frame(width: 38, height: 38)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .overlay { Circle().stroke(CoachTheme.Stroke.panel, lineWidth: 1) }
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView()
                    .environmentObject(appState)
                    .preferredColorScheme(.dark)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    /// Staggered fade/slide entrance for each card.
    private func card<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
            .animation(.easeOut(duration: 0.5).delay(Double(index) * 0.08), value: appeared)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let period: String

        switch hour {
        case 5..<12:
            period = "Good morning"
        case 12..<17:
            period = "Good afternoon"
        case 17..<22:
            period = "Good evening"
        default:
            period = "Good night"
        }

        return "\(period), Leo"
    }

    private var header: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: CoachTheme.Space.xs) {
                Text("Stay close to the plan.")
                    .font(.largeTitle.weight(.bold))
                Text("The list does not vanish when you complete something. It stays visible, crossed out, and satisfying.")
                    .font(.subheadline)
                    .foregroundStyle(CoachTheme.Text.muted)
            }
        }
    }

    private var taskList: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: CoachTheme.Space.md) {
                Text("Daily adherence")
                    .font(.headline)

                ForEach(appState.tasks) { task in
                    taskRow(task)
                }
            }
        }
    }

    private func taskRow(_ task: DailyTask) -> some View {
        Button {
            complete(task)
        } label: {
            HStack(spacing: CoachTheme.Space.lg) {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : task.systemImage)
                    .font(.title3)
                    .foregroundStyle(task.isComplete ? CoachTheme.accent : CoachTheme.accent.opacity(0.85))
                    .frame(width: 32)
                    .symbolEffect(.bounce, value: task.isComplete)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(task.isComplete, color: .white.opacity(0.8))
                    Text(task.detail)
                        .font(.caption)
                        .foregroundStyle(CoachTheme.Text.muted)
                        .strikethrough(task.isComplete, color: .white.opacity(0.45))
                }

                Spacer()

                Image(systemName: task.isComplete ? "checkmark" : "circle")
                    .foregroundStyle(task.isComplete ? CoachTheme.accent : CoachTheme.Text.faint)
            }
            .foregroundStyle(.white)
            .opacity(task.isComplete ? 0.7 : 1)
            .padding()
            .modifier(TaskChipStyle(isComplete: task.isComplete))
        }
        .buttonStyle(.pressable)
        // Swipe-to-complete: a rightward drag marks the task done.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width > 40 && !task.isComplete {
                        complete(task)
                    }
                }
        )
    }

    private func complete(_ task: DailyTask) {
        Haptics.light()
        withAnimation(.snappy(duration: 0.3)) {
            appState.toggleTask(task)
        }
    }

    private var reviewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: CoachTheme.Space.sm) {
                Label(appState.weeklyReview.title, systemImage: "calendar.badge.clock")
                    .font(.headline)
                Text(appState.weeklyReview.summary)
                    .font(.subheadline)
                    .foregroundStyle(CoachTheme.Text.muted)

                ForEach(appState.weeklyReview.suggestions, id: \.self) { suggestion in
                    Label(suggestion, systemImage: "sparkle")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
        }
    }

    private var healthCard: some View {
        GlassCard {
            HStack {
                MetricTile(title: "Steps", value: appState.healthMetrics.steps.formatted())
                MetricTile(title: "Active", value: "\(appState.healthMetrics.activeEnergy) cal")
                MetricTile(title: "Workouts", value: "\(appState.healthMetrics.workoutsThisWeek)")
            }
        }
    }
}

/// Selection-aware background for a task row.
private struct TaskChipStyle: ViewModifier {
    let isComplete: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous)
                    .fill(isComplete ? CoachTheme.glow : CoachTheme.Fill.soft)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CoachTheme.Radius.sm, style: .continuous)
                    .stroke(isComplete ? CoachTheme.accent.opacity(0.5) : CoachTheme.Stroke.hairline, lineWidth: 1)
            }
    }
}
