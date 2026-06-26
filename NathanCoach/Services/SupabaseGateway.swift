import Foundation

/// Structured nutrition result returned by the analyze-meal Edge Function.
struct MealMacros {
    let title: String
    let calories: Int
    let protein: Int
    let shouldLog: Bool
    let confidence: String
    let confidenceReason: String
    let clarifyingQuestions: [String]
    let notes: String
}

struct HaikuCoachReply {
    let reply: String
    let updates: [[String: Any]]
}

/// An authenticated Supabase session.
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
    private enum HostedDefaults {
        static let projectURL = "https://kkejpzjrmrrlndiydocf.supabase.co"
        static let anonKey = "sb_publishable_qsriyDdvepCWWIz2IBPTfA_tdYn6TmQ"
    }

    private enum DefaultsKey {
        static let projectURL = "loop_supabase_url"
        static let anonKey = "loop_supabase_anon_key"
    }

    struct Configuration {
        var projectURL: URL?
        var anonKey: String?
        var anthropicModel = "claude-haiku-4-5"
        var source = "Not loaded"
    }

    var configuration = Configuration()
    @MainActor private(set) static var lastEvent = "Cloud has not connected yet."

    var isConfigured: Bool {
        configuration.projectURL != nil && configuration.anonKey?.isEmpty == false
    }

    /// Load Supabase URL + anon key from every durable source available to the installed app.
    /// The anon key is a publishable client key; the secret ANTHROPIC_API_KEY lives only
    /// in the Edge Function's secrets, never in the app.
    func loadConfiguration() {
        let env = ProcessInfo.processInfo.environment
        let candidates: [(source: String, url: String?, key: String?)] = [
            (
                "Xcode run environment",
                env["SUPABASE_URL"],
                env["SUPABASE_ANON_KEY"]
            ),
            (
                "Bundled Info.plist",
                Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
                Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
            ),
            (
                "On-device config cache",
                UserDefaults.standard.string(forKey: DefaultsKey.projectURL),
                UserDefaults.standard.string(forKey: DefaultsKey.anonKey)
            ),
            (
                "Baked hosted defaults",
                HostedDefaults.projectURL,
                HostedDefaults.anonKey
            )
        ]

        for candidate in candidates {
            guard let rawURL = candidate.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let rawKey = candidate.key?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawURL.isEmpty,
                  !rawKey.isEmpty,
                  let url = URL(string: rawURL),
                  url.scheme?.hasPrefix("http") == true else { continue }

            configuration.projectURL = url
            configuration.anonKey = rawKey
            configuration.source = candidate.source
            persistConfiguration(url: rawURL, key: rawKey)
            return
        }

        configuration = Configuration(source: "Missing Supabase URL/key")
    }

    func describeStatus() -> String {
        if isConfigured {
            return "Cloud sync ready · Supabase + Haiku · \(configuration.source)"
        }
        return "Local prototype mode. Set SUPABASE_URL + SUPABASE_ANON_KEY and deploy the Edge Functions to enable cloud sync."
    }

    private func persistConfiguration(url: String, key: String) {
        UserDefaults.standard.set(url, forKey: DefaultsKey.projectURL)
        UserDefaults.standard.set(key, forKey: DefaultsKey.anonKey)
    }

    // MARK: - Auth

    @MainActor
    static func signInWithPassword(base: URL, anonKey: String, email: String, password: String) async -> SupabaseSession? {
        var request = authRequest(base: base, anonKey: anonKey, path: "auth/v1/token?grant_type=password")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])
        return await sendAuth(request, successMessage: "Signed in to Supabase.")
    }

    @MainActor
    static func signUpWithPassword(base: URL, anonKey: String, email: String, password: String) async -> SupabaseSession? {
        var request = authRequest(base: base, anonKey: anonKey, path: "auth/v1/signup")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])
        return await sendAuth(request, successMessage: "Created Supabase account.")
    }

    /// Legacy anonymous sign-in kept only for debugging older builds.
    @MainActor
    static func signInAnonymously(base: URL, anonKey: String) async -> SupabaseSession? {
        var request = authRequest(base: base, anonKey: anonKey, path: "auth/v1/signup")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["data": [:]] as [String: Any])
        return await sendAuth(request, successMessage: "Authenticated anonymous Supabase user.")
    }

    @MainActor
    static func refresh(base: URL, anonKey: String, refreshToken: String) async -> SupabaseSession? {
        var request = authRequest(base: base, anonKey: anonKey, path: "auth/v1/token?grant_type=refresh_token")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        return await sendAuth(request, successMessage: "Supabase session refreshed.")
    }

    private static func authRequest(base: URL, anonKey: String, path: String) -> URLRequest {
        var request = URLRequest(url: url(base: base, path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        return request
    }

    @MainActor
    private static func sendAuth(_ request: URLRequest, successMessage: String) async -> SupabaseSession? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let refreshToken = json["refresh_token"] as? String else {
                lastEvent = responseSummary(data: data, response: response, fallback: "Auth failed")
                return nil
            }
            let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
            let user = json["user"] as? [String: Any]
            let userID = (user?["id"] as? String) ?? ""
            lastEvent = successMessage
            return SupabaseSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                userID: userID,
                expiresAt: Date().addingTimeInterval(expiresIn - 60)
            )
        } catch {
            lastEvent = "Auth network error: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - PostgREST

    /// GET rows from a table. `query` is appended raw (e.g. "select=*&order=measured_at.asc").
    @MainActor
    static func select(base: URL, anonKey: String, token: String, table: String, query: String) async -> [[String: Any]] {
        guard var components = URLComponents(url: restEndpoint(base: base, table: table), resolvingAgainstBaseURL: false) else { return [] }
        components.percentEncodedQuery = query
        guard let url = components.url else { return [] }
        let request = restRequest(url: url, method: "GET", anonKey: anonKey, token: token)
        guard let data = await send(request) else { return [] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    /// Insert rows; returns the inserted representation.
    @discardableResult
    @MainActor
    static func insert(base: URL, anonKey: String, token: String, table: String, rows: [[String: Any]], upsertOnConflict: String? = nil) async -> [[String: Any]] {
        var components = URLComponents(url: restEndpoint(base: base, table: table), resolvingAgainstBaseURL: false)
        if let conflict = upsertOnConflict {
            components?.queryItems = [URLQueryItem(name: "on_conflict", value: conflict)]
        }
        guard let url = components?.url else { return [] }
        var request = restRequest(url: url, method: "POST", anonKey: anonKey, token: token)
        var prefer = "return=representation"
        if upsertOnConflict != nil { prefer += ",resolution=merge-duplicates" }
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: rows)
        guard let data = await send(request) else { return [] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    @MainActor
    @discardableResult
    static func update(base: URL, anonKey: String, token: String, table: String, match: String, values: [String: Any]) async -> Bool {
        guard let url = restURL(base: base, table: table, query: match) else { return false }
        var request = restRequest(url: url, method: "PATCH", anonKey: anonKey, token: token)
        request.httpBody = try? JSONSerialization.data(withJSONObject: values)
        return await send(request) != nil
    }

    @MainActor
    static func delete(base: URL, anonKey: String, token: String, table: String, match: String) async {
        guard let url = restURL(base: base, table: table, query: match) else { return }
        let request = restRequest(url: url, method: "DELETE", anonKey: anonKey, token: token)
        _ = await send(request)
    }

    private static func restURL(base: URL, table: String, query: String) -> URL? {
        guard var components = URLComponents(url: restEndpoint(base: base, table: table), resolvingAgainstBaseURL: false) else { return nil }
        components.percentEncodedQuery = query
        return components.url
    }

    private static func restEndpoint(base: URL, table: String) -> URL {
        base.appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent(table)
    }

    private static func url(base: URL, path: String) -> URL {
        let pieces = path.split(separator: "?", maxSplits: 1).map(String.init)
        let url = pieces[0].split(separator: "/").reduce(base) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        guard pieces.count == 2,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.percentEncodedQuery = pieces[1]
        return components.url ?? url
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
    @MainActor
    private static func send(_ request: URLRequest) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastEvent = responseSummary(data: data, response: response, fallback: "\(request.httpMethod ?? "Request") failed")
                return nil
            }
            lastEvent = "\(request.httpMethod ?? "Request") \(request.url?.lastPathComponent ?? "Supabase") succeeded."
            return data
        } catch {
            lastEvent = "Network error: \(error.localizedDescription)"
            return nil
        }
    }

    private static func responseSummary(data: Data, response: URLResponse, fallback: String) -> String {
        let status = (response as? HTTPURLResponse)?.statusCode
        let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compactBody = body?.isEmpty == false ? " · \(body!.prefix(180))" : ""
        if let status {
            return "\(fallback) (\(status))\(compactBody)"
        }
        return "\(fallback)\(compactBody)"
    }

    // MARK: - Edge Functions

    /// Invoke an Edge Function with the user's token; returns the decoded JSON object.
    @MainActor
    static func invokeFunction(base: URL, anonKey: String, token: String, name: String, body: [String: Any]) async -> [String: Any]? {
        let url = base.appendingPathComponent("functions").appendingPathComponent("v1").appendingPathComponent(name)
        var request = restRequest(url: url, method: "POST", anonKey: anonKey, token: token)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let data = await send(request) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Ask the analyze-meal Edge Function (server-side Sonnet) to estimate macros.
    @MainActor
    static func analyzeMeal(base: URL, anonKey: String, token: String, description: String, imageData: Data?, followUpAnswers: [String] = []) async -> MealMacros? {
        var payload: [String: Any] = ["prompt": description]
        if !followUpAnswers.isEmpty {
            payload["follow_up_answers"] = followUpAnswers
        }
        if let imageData {
            payload["image_base64"] = imageData.base64EncodedString()
            payload["media_type"] = "image/jpeg"
        }
        guard let json = await invokeFunction(base: base, anonKey: anonKey, token: token, name: "analyze-meal", body: payload),
              let calories = (json["calories"] as? NSNumber)?.intValue,
              let protein = (json["protein"] as? NSNumber)?.intValue else { return nil }
        let title = (json["title"] as? String) ?? "Meal"
        let action = json["action"] as? String ?? "record_meal"
        return MealMacros(
            title: title,
            calories: calories,
            protein: protein,
            shouldLog: action == "record_meal",
            confidence: json["confidence"] as? String ?? "medium",
            confidenceReason: json["confidence_reason"] as? String ?? "",
            clarifyingQuestions: json["clarifying_questions"] as? [String] ?? [],
            notes: json["notes"] as? String ?? ""
        )
    }

    /// Ask the coach-chat Edge Function for a conversational Haiku response.
    @MainActor
    static func coachChat(base: URL, anonKey: String, token: String, message: String, context: [String: Any]) async -> HaikuCoachReply? {
        guard let json = await invokeFunction(
            base: base,
            anonKey: anonKey,
            token: token,
            name: "coach-chat",
            body: [
                "message": message,
                "recent_context": context
            ]
        ) else { return nil }

        if let reply = json["reply"] as? String {
            return HaikuCoachReply(reply: reply, updates: json["app_updates"] as? [[String: Any]] ?? [])
        }

        if let content = json["content"] as? [[String: Any]],
           let text = content.compactMap({ $0["text"] as? String }).first,
           let data = text.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let reply = parsed["reply"] as? String {
            return HaikuCoachReply(reply: reply, updates: parsed["app_updates"] as? [[String: Any]] ?? [])
        }

        return nil
    }
}
