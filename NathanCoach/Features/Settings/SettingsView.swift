import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var notificationStatus = "Not requested"
    @State private var healthStatus = "Not requested"
    @State private var notificationsOn = false
    @State private var healthOn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                profileHero
                preferencesCard
                permissionsCard
                infoCard
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(CoachTheme.background)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top) { topBar }
    }

    private var topBar: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Spacer()
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CoachTheme.Text.primary)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.clear)
    }

    // MARK: Profile

    private var profileHero: some View {
        VStack(spacing: 14) {
            Text(String(appState.profile.displayName.prefix(1)))
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 78, height: 78)
                .background(
                    LinearGradient(colors: [CoachTheme.flame, CoachTheme.ember],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .shadow(color: CoachTheme.ember.opacity(0.4), radius: 16, y: 8)

            VStack(spacing: 4) {
                Text(appState.profile.displayName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(appState.profile.goal)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CoachTheme.Text.muted)
            }

            Text(appState.profile.trainingLevel.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(CoachTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(CoachTheme.glow, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassPanel(radius: CoachTheme.Radius.xl)
    }

    // MARK: Preferences

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Coaching preferences")
            settingRow(icon: "bell.badge.fill", title: "Notification tone", value: appState.settings.notificationTone)
            divider
            settingRow(icon: "clock.fill", title: "Meal timing", value: appState.settings.mealTiming)
            divider
            settingRow(icon: "calendar", title: "Gym rhythm", value: appState.settings.gymDays)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private func settingRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            IconTile(systemImage: icon, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(CoachTheme.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var divider: some View {
        Rectangle().fill(CoachTheme.Stroke.hairline).frame(height: 1)
    }

    // MARK: Permissions

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Permissions")

            permissionRow(
                icon: "bell.fill",
                title: "Notifications",
                status: notificationStatus,
                isOn: notificationsOn
            ) {
                Task {
                    let granted = await appState.reminderScheduler.requestAuthorization()
                    notificationsOn = granted
                    notificationStatus = granted ? "Daily nudges enabled" : "Denied"
                    if granted {
                        Haptics.success()
                        await appState.reminderScheduler.scheduleDailyNudges(tone: appState.settings.notificationTone)
                    }
                }
            }

            divider

            permissionRow(
                icon: "heart.text.square.fill",
                title: "HealthKit",
                status: healthStatus,
                isOn: healthOn
            ) {
                Task {
                    let granted = await appState.healthKitService.requestAuthorization()
                    healthOn = granted
                    healthStatus = granted ? "Connected" : "Unavailable or denied"
                    appState.healthMetrics.healthKitStatus = healthStatus
                    if granted { Haptics.success() }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }

    private func permissionRow(icon: String, title: String, status: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            IconTile(systemImage: icon, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(status)
                    .font(.caption)
                    .foregroundStyle(isOn ? .green : CoachTheme.Text.muted)
            }
            Spacer()
            if isOn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            } else {
                GlassPillButton(title: "Enable", isProminent: true, action: action)
            }
        }
    }

    // MARK: Info

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Cloud & AI", systemImage: "cloud.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CoachTheme.accent)
                Text(appState.gateway.describeStatus())
                    .font(.subheadline)
                    .foregroundStyle(CoachTheme.Text.muted)
                Text("Supabase auth, Postgres, RLS, Edge Functions, and Claude Haiku plug in here next.")
                    .font(.caption)
                    .foregroundStyle(CoachTheme.Text.faint)
            }

            divider

            VStack(alignment: .leading, spacing: 8) {
                Label("Coach guardrails", systemImage: "lock.shield.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CoachTheme.accent)
                Text("The coach updates routine preferences naturally. Deleting data, changing HealthKit permissions, severe diet targets, and injury-related changes require explicit confirmation.")
                    .font(.caption)
                    .foregroundStyle(CoachTheme.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: CoachTheme.Radius.lg)
    }
}
