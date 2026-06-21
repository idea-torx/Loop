import Foundation

/// Structured macros returned by the analyze-meal Edge Function (Haiku).
struct MealMacros {
    let title: String
    let calories: Int
    let protein: Int
}

/// An authenticated Supabase session (anonymous user).
struct SupabaseSession: Sendable {
    let accessToken: String
    let refreshToken: String
    let userID: String
    let expiresAt: Date
}

/// Config holder + stateless networking for Supabase Auth, PostgREST, and Edge Functions.
///
/// Networking is exposed as `static` functions taking only Sendable values so the
/// gateway instance is never sent across an `await` (keeps Swift concurrency happy).
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
            return "Cloud sync ready · Supabase + Haiku"
        }
        return "Local prototype mode. Set SUPABASE_URL + SUPABASE_ANON_KEY and deploy the Edge Functions to enable cloud sync."
    }

    // MARK: - Auth

    /// Create (or restore) an anonymous session. Requires "Enable anonymous sign-ins" in Supabase Auth.
    static func signInAnonymously(base: URL, anonKey: String) async -> SupabaseSession? {
        var request = authRequest(base: base, anonKey: anonKey, path: "auth/v1/signup")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:] as [String: Any])
        return await sendAuth(request)
    }

    static func refresh(base: URL, anonKey: String, refreshToken: String) async -> SupabaseSession? {
        var request = authRequest(base: base, anonKey: anonKey, path: "auth/v1/token?grant_type=refresh_token")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        return await sendAuth(request)
    }

    private static func authRequest(base: URL, anonKey: String, path: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        return request
    }

    private static func sendAuth(_ request: URLRequest) async -> SupabaseSession? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let refreshToken = json["refresh_token"] as? String else { return nil }
            let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
            let user = json["user"] as? [String: Any]
            let userID = (user?["id"] as? String) ?? ""
            return SupabaseSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                userID: userID,
                expiresAt: Date().addingTimeInterval(expiresIn - 60)
            )
        } catch {
            return nil
        }
    }

    // MARK: - PostgREST

    /// GET rows from a table. `query` is appended raw (e.g. "select=*&order=measured_at.asc").
    static func select(base: URL, anonKey: String, token: String, table: String, query: String) async -> [[String: Any]] {
        guard var components = URLComponents(url: base.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false) else { return [] }
        components.percentEncodedQuery = query
        guard let url = components.url else { return [] }
        let request = restRequest(url: url, method: "GET", anonKey: anonKey, token: token)
        guard let data = await send(request) else { return [] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    /// Insert rows; returns the inserted representation.
    @discardableResult
    static func insert(base: URL, anonKey: String, token: String, table: String, rows: [[String: Any]], upsertOnConflict: String? = nil) async -> [[String: Any]] {
        var path = "rest/v1/\(table)"
        if let conflict = upsertOnConflict { path += "?on_conflict=\(conflict)" }
        let url = base.appendingPathComponent(path)
        var request = restRequest(url: url, method: "POST", anonKey: anonKey, token: token)
        var prefer = "return=representation"
        if upsertOnConflict != nil { prefer += ",resolution=merge-duplicates" }
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: rows)
        guard let data = await send(request) else { return [] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    static func update(base: URL, anonKey: String, token: String, table: String, match: String, values: [String: Any]) async {
        let url = base.appendingPathComponent("rest/v1/\(table)?\(match)")
        var request = restRequest(url: url, method: "PATCH", anonKey: anonKey, token: token)
        request.httpBody = try? JSONSerialization.data(withJSONObject: values)
        _ = await send(request)
    }

    static func delete(base: URL, anonKey: String, token: String, table: String, match: String) async {
        let url = base.appendingPathComponent("rest/v1/\(table)?\(match)")
        let request = restRequest(url: url, method: "DELETE", anonKey: anonKey, token: token)
        _ = await send(request)
    }

    private static func restRequest(url: URL, method: String, anonKey: String, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    @discardableResult
    private static func send(_ request: URLRequest) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Edge Functions

    /// Invoke an Edge Function with the user's token; returns the decoded JSON object.
    static func invokeFunction(base: URL, anonKey: String, token: String, name: String, body: [String: Any]) async -> [String: Any]? {
        let url = base.appendingPathComponent("functions/v1/\(name)")
        var request = restRequest(url: url, method: "POST", anonKey: anonKey, token: token)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let data = await send(request) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Ask the analyze-meal Edge Function (server-side Haiku) to estimate macros.
    static func analyzeMeal(base: URL, anonKey: String, token: String, description: String, imageData: Data?) async -> MealMacros? {
        var payload: [String: Any] = ["prompt": description]
        if let imageData {
            payload["image_base64"] = imageData.base64EncodedString()
            payload["media_type"] = "image/jpeg"
        }
        guard let json = await invokeFunction(base: base, anonKey: anonKey, token: token, name: "analyze-meal", body: payload),
              let calories = (json["calories"] as? NSNumber)?.intValue,
              let protein = (json["protein"] as? NSNumber)?.intValue else { return nil }
        let title = (json["title"] as? String) ?? "Meal"
        return MealMacros(title: title, calories: calories, protein: protein)
    }
}
