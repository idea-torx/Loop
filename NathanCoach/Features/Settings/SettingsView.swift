import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var notificationStatus = "Not requested"
    @State private var healthStatus = "Not requested"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    profileCard
                    permissionsCard
                    backendCard
                    guardrailCard
                }
                .padding()
            }
            .background(CoachTheme.background)
            .navigationTitle("Settings")
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appState.profile.displayName)
                .font(.title.bold())
            Text(appState.profile.goal)
                .foregroundStyle(CoachTheme.mutedText)
            Label(appState.settings.notificationTone, systemImage: "bell.badge.fill")
                .font(.caption)
            Label(appState.settings.mealTiming, systemImage: "clock.fill")
                .font(.caption)
            Label(appState.settings.gymDays, systemImage: "calendar")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassPanel()
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.headline)

            Button {
                Task {
                    let granted = await appState.reminderScheduler.requestAuthorization()
                    notificationStatus = granted ? "Notifications enabled" : "Notifications denied"
                    if granted {
                        await appState.reminderScheduler.scheduleDailyNudges(tone: appState.settings.notificationTone)
                    }
                }
            } label: {
                Label(notificationStatus, systemImage: "bell.fill")
            }

            Button {
                Task {
                    let granted = await appState.healthKitService.requestAuthorization()
                    healthStatus = granted ? "HealthKit connected" : "HealthKit unavailable or denied"
                    appState.healthMetrics.healthKitStatus = healthStatus
                }
            } label: {
                Label(healthStatus, systemImage: "heart.text.square.fill")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.bordered)
        .tint(CoachTheme.mint)
        .padding()
        .glassPanel()
    }

    private var backendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cloud and AI")
                .font(.headline)
            Text(appState.gateway.describeStatus())
                .font(.subheadline)
                .foregroundStyle(CoachTheme.mutedText)
            Text("Supabase anonymous auth, Postgres, RLS, Edge Functions, and Claude Haiku plug in here next.")
                .font(.caption)
                .foregroundStyle(CoachTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassPanel()
    }

    private var guardrailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coach guardrails")
                .font(.headline)
            Text("The coach can update routine preferences naturally. Deleting data, changing HealthKit permissions, severe diet targets, and injury-related training changes should require explicit confirmation.")
                .font(.subheadline)
                .foregroundStyle(CoachTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassPanel()
    }
}
