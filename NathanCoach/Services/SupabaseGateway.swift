import Foundation

/// Structured macros returned by the analyze-meal Edge Function (Haiku).
struct MealMacros {
    let title: String
    let calories: Int
    let protein: Int
}

final class SupabaseGateway {
    struct Configuration {
        var projectURL: URL?
        var anonKey: String?
        var anthropicModel = "claude-haiku-4-5"
    }

    var configuration = Configuration()

    var isConfigured: Bool {
        configuration.projectURL != nil && configuration.anonKey?.isEmpty == false
    }

    /// Load Supabase URL + anon key from the environment (Xcode scheme) or Info.plist.
    /// The anon key is a publishable client key; the secret ANTHROPIC_API_KEY lives only
    /// in the Edge Function's secrets, never in the app.
    func loadConfiguration() {
        let env = ProcessInfo.processInfo.environment
        let urlString = env["SUPABASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let key = env["SUPABASE_ANON_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String

        if let urlString, let url = URL(string: urlString) {
            configuration.projectURL = url
        }
        configuration.anonKey = key
    }

    func describeStatus() -> String {
        if isConfigured {
            return "Cloud sync ready · meals analyzed by Haiku"
        }
        return "Local prototype mode. Add SUPABASE_URL + SUPABASE_ANON_KEY and deploy the Edge Functions to enable Haiku meal analysis."
    }

    /// Ask the analyze-meal Edge Function (server-side Haiku) to estimate macros.
    /// Static so only Sendable values cross the await — the gateway instance is never sent.
    /// Returns nil if the request fails — callers fall back locally.
    static func analyzeMeal(base: URL, anonKey: String, description: String, imageData: Data?) async -> MealMacros? {
        let endpoint = base.appendingPathComponent("functions/v1/analyze-meal")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        var payload: [String: Any] = ["prompt": description]
        if let imageData {
            payload["image_base64"] = imageData.base64EncodedString()
            payload["media_type"] = "image/jpeg"
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let calories = (json["calories"] as? NSNumber)?.intValue,
                  let protein = (json["protein"] as? NSNumber)?.intValue else { return nil }
            let title = (json["title"] as? String) ?? "Meal"
            return MealMacros(title: title, calories: calories, protein: protein)
        } catch {
            return nil
        }
    }
}
