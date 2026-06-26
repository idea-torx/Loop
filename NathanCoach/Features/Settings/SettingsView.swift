import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus = "Not requested"
    @State private var healthStatus = "Not requested"
    @State private var notificationsOn = false
    @State private var healthOn = false
    @State private var cloudEmail = ""
    @State private var cloudPassword = ""

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
        .onAppear {
            cloudEmail = appState.cloudAuthEmail
            refreshPermissionStatuses()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPermissionStatuses()
        }
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
                    await refreshNotificationStatus()
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
                    refreshHealthStatus()
                    if granted {
                        await appState.refreshHealthMetrics()
                        refreshHealthStatus()
                        Haptics.success()
                    }
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

    private func refreshPermissionStatuses() {
        refreshHealthStatus()
        Task { await refreshNotificationStatus() }
    }

    private func refreshHealthStatus() {
        let status = appState.healthKitService.authorizationStatus()
        healthOn = status.isOn
        healthStatus = status.label
        appState.healthMetrics.healthKitStatus = status.label
    }

    private func refreshNotificationStatus() async {
        let status = await appState.reminderScheduler.authorizationStatus()
        notificationsOn = status.isOn
        notificationStatus = status.label
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
                Text("Supabase auth, Postgres, RLS, Edge Functions, and Claude Haiku are wired for personal cloud persistence.")
                    .font(.caption)
                    .foregroundStyle(CoachTheme.Text.faint)
                Text(appState.cloudSyncStatus)
                    .font(.caption)
                    .foregroundStyle(CoachTheme.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !appState.cloudUserID.isEmpty {
                    if appState.cloudAuthEmail.isEmpty {
                        Text("Legacy anonymous user detected. Create or sign into your permanent account below.")
                            .font(.caption)
                            .foregroundStyle(CoachTheme.Text.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Signed in as \(appState.cloudAuthEmail)")
                            .font(.caption)
                            .foregroundStyle(CoachTheme.Text.muted)
                    }
                    Text("Current Supabase user: \(appState.cloudUserID)")
                        .font(.caption2)
                        .foregroundStyle(CoachTheme.Text.faint)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if appState.cloudUserID.isEmpty || appState.cloudAuthEmail.isEmpty {
                    authFields
                }
                HStack(spacing: 10) {
                    GlassPillButton(title: "Test cloud sync", isProminent: true) {
                        Task { await appState.testCloudSync() }
                    }
                    GlassPillButton(title: "Reload cloud", isProminent: false) {
                        Task { await appState.reloadCloudData() }
                    }
                    if !appState.cloudUserID.isEmpty {
                        GlassPillButton(title: "Sign out", isProminent: false) {
                            appState.signOutOfCloud()
                            cloudPassword = ""
                        }
                    }
                }
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

    private var authFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Email", text: $cloudEmail)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .settingsField()

            SecureField("Password", text: $cloudPassword)
                .textContentType(.password)
                .settingsField()

            HStack(spacing: 10) {
                GlassPillButton(title: appState.isCloudSigningIn ? "Signing in..." : "Sign in", isProminent: true) {
                    Task { await appState.signInToCloud(email: cloudEmail, password: cloudPassword) }
                }
                GlassPillButton(title: "Create account", isProminent: false) {
                    Task { await appState.createCloudAccount(email: cloudEmail, password: cloudPassword) }
                }
            }
            .disabled(appState.isCloudSigningIn)
        }
        .padding(.top, 4)
    }
}

private extension View {
    func settingsField() -> some View {
        self
            .font(.subheadline)
            .foregroundStyle(CoachTheme.Text.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CoachTheme.Stroke.hairline, lineWidth: 1)
            }
    }
}
