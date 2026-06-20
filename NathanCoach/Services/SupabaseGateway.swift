import Foundation

final class SupabaseGateway {
    struct Configuration {
        var projectURL: URL?
        var anonKey: String?
        var anthropicModel = "claude-3-5-haiku-latest"
    }

    var configuration = Configuration()

    var isConfigured: Bool {
        configuration.projectURL != nil && configuration.anonKey?.isEmpty == false
    }

    func describeStatus() -> String {
        if isConfigured {
            return "Cloud sync ready"
        }

        return "Local prototype mode. Add Supabase URL, anon key, and Edge Functions to enable cloud sync and Haiku."
    }
}
