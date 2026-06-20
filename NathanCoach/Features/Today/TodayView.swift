import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    taskList
                    reviewCard
                    healthCard
                }
                .padding()
                .padding(.bottom, 104)
            }
            .background(CoachTheme.background)
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundStyle(CoachTheme.mint)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.08), in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(CoachTheme.panelStroke, lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView()
                    .environmentObject(appState)
                    .preferredColorScheme(.dark)
            }
        }
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Stay close to the plan.")
                .font(.largeTitle.weight(.bold))
            Text("The list does not vanish when you complete something. It stays visible, crossed out, and satisfying.")
                .font(.subheadline)
                .foregroundStyle(CoachTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassPanel()
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily adherence")
                .font(.headline)

            ForEach(appState.tasks) { task in
                Button {
                    appState.toggleTask(task)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: task.isComplete ? "xmark.circle.fill" : task.systemImage)
                            .font(.title3)
                            .foregroundStyle(task.isComplete ? .white.opacity(0.45) : CoachTheme.mint)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.body.weight(.semibold))
                                .strikethrough(task.isComplete, color: .white.opacity(0.8))
                            Text(task.detail)
                                .font(.caption)
                                .foregroundStyle(CoachTheme.mutedText)
                                .strikethrough(task.isComplete, color: .white.opacity(0.45))
                        }

                        Spacer()

                        Image(systemName: task.isComplete ? "checkmark" : "circle")
                            .foregroundStyle(task.isComplete ? CoachTheme.mint : .white.opacity(0.35))
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .background(task.isComplete ? Color.white.opacity(0.045) : Color.white.opacity(0.075))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .glassPanel()
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(appState.weeklyReview.title, systemImage: "calendar.badge.clock")
                .font(.headline)
            Text(appState.weeklyReview.summary)
                .font(.subheadline)
                .foregroundStyle(CoachTheme.mutedText)

            ForEach(appState.weeklyReview.suggestions, id: \.self) { suggestion in
                Label(suggestion, systemImage: "sparkle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassPanel()
    }

    private var healthCard: some View {
        HStack {
            metric(title: "Steps", value: appState.healthMetrics.steps.formatted())
            metric(title: "Active", value: "\(appState.healthMetrics.activeEnergy) cal")
            metric(title: "Workouts", value: "\(appState.healthMetrics.workoutsThisWeek)")
        }
        .padding()
        .glassPanel()
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(CoachTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
