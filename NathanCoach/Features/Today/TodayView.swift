import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsSettings = false
    @State private var appeared = false

    private var completedCount: Int { appState.tasks.filter(\.isComplete).count }
    private var totalCount: Int { appState.tasks.count }
    private var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                stagger(0) { topBar }
                stagger(1) { heroCard }
                stagger(2) { taskSection }
                stagger(3) { insightCard }
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
        .onAppear {
            withAnimation { appeared = true }
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

    // MARK: Hero

    private var heroCard: some View {
        HStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: appeared ? progress : 0, lineWidth: 13, size: 132)
                VStack(spacing: 0) {
                    Text("\(completedCount)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.primary)
                        .contentTransition(.numericText())
                    Text("of \(totalCount) done")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CoachTheme.Text.muted)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                HeroStat(value: appState.healthMetrics.steps.formatted(), label: "Steps", systemImage: "figure.walk")
                HeroStat(value: "\(appState.healthMetrics.activeEnergy)", label: "Active cal", systemImage: "flame.fill")
                HeroStat(value: "\(appState.healthMetrics.workoutsThisWeek)", label: "Workouts", systemImage: "dumbbell.fill")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.xl)
    }

    // MARK: Tasks

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Today's focus", subtitle: "\(completedCount)/\(totalCount) complete · swipe to check off")

            VStack(spacing: 10) {
                ForEach(appState.tasks) { task in
                    TaskRowView(task: task) { complete(task) }
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

    // MARK: Insight

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(systemImage: "sparkles", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.weeklyReview.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Coach insight")
                        .font(.caption)
                        .foregroundStyle(CoachTheme.accent)
                }
            }

            Text(appState.weeklyReview.summary)
                .font(.subheadline)
                .foregroundStyle(CoachTheme.Text.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(appState.weeklyReview.suggestions, id: \.self) { suggestion in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(CoachTheme.accent)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(suggestion)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.xl)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(CoachTheme.accent)
                .frame(width: 4)
                .padding(.vertical, 22)
        }
    }
}

// MARK: - Task row with swipe-to-complete

private struct TaskRowView: View {
    let task: DailyTask
    let onComplete: () -> Void

    @State private var drag: CGFloat = 0
    private let threshold: CGFloat = 72

    var body: some View {
        ZStack(alignment: .leading) {
            // Reveal behind the row as it slides right (only while dragging).
            if !task.isComplete && drag > 0 {
                RoundedRectangle(cornerRadius: CoachTheme.Radius.md, style: .continuous)
                    .fill(CoachTheme.ember)
                    .overlay(alignment: .leading) {
                        Image(systemName: drag > threshold ? "checkmark.circle.fill" : "checkmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.leading, 22)
                            .opacity(Double(min(drag / threshold, 1)))
                    }
            }

            rowContent
                .offset(x: drag)
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { value in
                            guard !task.isComplete else { return }
                            drag = max(0, min(value.translation.width, 110))
                        }
                        .onEnded { _ in
                            if drag > threshold && !task.isComplete {
                                onComplete()
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = 0 }
                        }
                )
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
                    Text(task.detail)
                        .font(.caption)
                        .foregroundStyle(CoachTheme.Text.muted)
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
    }
}
