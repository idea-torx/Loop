import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: AppTab = .today

    var body: some View {
        ZStack {
            CoachTheme.background.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .today:
                    TodayView()
                case .coach:
                    CoachView()
                case .workout:
                    WorkoutView()
                case .trends:
                    TrendsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Spacer()
                ModernTabBar(selectedTab: $selectedTab)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .ignoresSafeArea(.keyboard)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            appState.bootstrap()
        }
    }
}

enum AppTab: CaseIterable {
    case today
    case coach
    case workout
    case trends

    var accessibilityTitle: String {
        switch self {
        case .today: "Today"
        case .coach: "Coach"
        case .workout: "Workout"
        case .trends: "Trends"
        }
    }
}

struct ModernTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        selectedTab = tab
                    }
                } label: {
                    LucideStyleIcon(tab: tab, isSelected: selectedTab == tab)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.accessibilityTitle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .background(Color.white.opacity(0.012), in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .shadow(color: CoachTheme.mint.opacity(0.045), radius: 16, y: 5)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}

struct LucideStyleIcon: View {
    let tab: AppTab
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(CoachTheme.mint.opacity(0.16))
                    .frame(width: 36, height: 36)
            }

            TabLineIcon(tab: tab)
                .stroke(
                    isSelected ? CoachTheme.mint : Color.white.opacity(0.58),
                    style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 25, height: 25)
        }
    }
}

struct TabLineIcon: Shape {
    let tab: AppTab

    func path(in rect: CGRect) -> Path {
        switch tab {
        case .today:
            TodayLineIcon().path(in: rect)
        case .coach:
            ChatLineIcon().path(in: rect)
        case .workout:
            DumbbellLineIcon().path(in: rect)
        case .trends:
            TrendLineIcon().path(in: rect)
        }
    }
}

struct TodayLineIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.addRoundedRect(in: CGRect(x: w * 0.16, y: h * 0.12, width: w * 0.68, height: h * 0.76), cornerSize: CGSize(width: 4, height: 4))
        path.move(to: CGPoint(x: w * 0.32, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.43, y: h * 0.46))
        path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.29))
        path.move(to: CGPoint(x: w * 0.33, y: h * 0.64))
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.64))
        return path
    }
}

struct ChatLineIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.addRoundedRect(in: CGRect(x: w * 0.12, y: h * 0.16, width: w * 0.76, height: h * 0.56), cornerSize: CGSize(width: 6, height: 6))
        path.move(to: CGPoint(x: w * 0.36, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.27, y: h * 0.88))
        path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.72))
        path.move(to: CGPoint(x: w * 0.32, y: h * 0.42))
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.42))
        path.move(to: CGPoint(x: w * 0.32, y: h * 0.56))
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.56))
        return path
    }
}

struct DumbbellLineIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.26, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.74, y: h * 0.5))
        path.addRoundedRect(in: CGRect(x: w * 0.08, y: h * 0.32, width: w * 0.16, height: h * 0.36), cornerSize: CGSize(width: 2, height: 2))
        path.addRoundedRect(in: CGRect(x: w * 0.24, y: h * 0.24, width: w * 0.12, height: h * 0.52), cornerSize: CGSize(width: 2, height: 2))
        path.addRoundedRect(in: CGRect(x: w * 0.64, y: h * 0.24, width: w * 0.12, height: h * 0.52), cornerSize: CGSize(width: 2, height: 2))
        path.addRoundedRect(in: CGRect(x: w * 0.76, y: h * 0.32, width: w * 0.16, height: h * 0.36), cornerSize: CGSize(width: 2, height: 2))
        return path
    }
}

struct TrendLineIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.14, y: h * 0.82))
        path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.18))
        path.move(to: CGPoint(x: w * 0.14, y: h * 0.82))
        path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.82))
        path.move(to: CGPoint(x: w * 0.24, y: h * 0.66))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.52))
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.32))
        path.move(to: CGPoint(x: w * 0.68, y: h * 0.32))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.32))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.42))
        return path
    }
}
