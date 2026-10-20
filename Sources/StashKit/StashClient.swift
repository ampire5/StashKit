import Foundation

/// The parts of Stash's UI settings that decide how plays are recorded.
public struct StashUISettings: Equatable, Sendable {
    public var trackActivity = true
    public var minimumPlayPercent = 0.0

    public init(trackActivity: Bool = true, minimumPlayPercent: Double = 0) {
        self.trackActivity = trackActivity
        self.minimumPlayPercent = minimumPlayPercent
    }
}

public enum StashError: LocalizedError, Equatable {
    case http(Int)
    case server(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case let .http(status): "Stash answered HTTP \(status)"
        case let .server(message): message
        case .badResponse: "Stash's answer could not be read"
        }
    }
}

/// Stash's GraphQL API at `<stash-url>/graphql`: just what the app writes back and checks.
public final class StashClient: Sendable {
    private let endpoint: URL
    private let apiKey: String?
    private let session: URLSession

    public init(baseURL: URL, apiKey: String?, session: URLSession = .shared) {
        endpoint = baseURL.appendingPathComponent("graphql")
        self.apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 }
        self.session = session
    }

    public func version() async throws -> String {
        let data = try await query("query { version { version } }")
        guard let version = (data["version"] as? [String: Any])?["version"] as? String else { throw StashError.badResponse }
        return version
    }

    public func uiSettings() async throws -> StashUISettings {
        let data = try await query("query { configuration { ui } }")
        let ui = (data["configuration"] as? [String: Any])?["ui"] as? [String: Any] ?? [:]
        var settings = StashUISettings()
        if let track = ui["trackActivity"] as? Bool { settings.trackActivity = track }
        if let percent = (ui["minimumPlayPercent"] as? NSNumber)?.doubleValue { settings.minimumPlayPercent = percent }
        return settings
    }

    public func send(_ request: StashActivityRequest, sceneID: String) async throws {
        switch request {
        case let .save(resumeTime, playDuration):
            _ = try await query("""
                mutation($id: ID!, $resume_time: Float, $playDuration: Float) {
                  sceneSaveActivity(id: $id, resume_time: $resume_time, playDuration: $playDuration)
                }
                """, ["id": sceneID, "resume_time": resumeTime, "playDuration": playDuration])
        case .addPlay:
            _ = try await query("mutation($id: ID!) { sceneAddPlay(id: $id) { count } }", ["id": sceneID])
        }
    }

    /// Deletes the scene, its file and its generated files (covers, sprites, previews).
    public func destroyScene(_ sceneID: String) async throws {
        _ = try await query("""
            mutation($id: ID!) { scenesDestroy(input: {ids: [$id], delete_file: true, delete_generated: true}) }
            """, ["id": sceneID])
    }

    /// The first file of the first scene, for Settings → Stash → Check.
    public func firstScenePath() async throws -> String? {
        let data = try await query("query { findScenes(filter: {per_page: 1}) { scenes { files { path } } } }")
        let scenes = (data["findScenes"] as? [String: Any])?["scenes"] as? [[String: Any]]
        return (scenes?.first?["files"] as? [[String: Any]])?.first?["path"] as? String
    }

    func query(_ text: String, _ variables: [String: Any] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "ApiKey") }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": text, "variables": variables])
        let (body, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 { throw StashError.http(status) }
        // Stash names no charset; JSON is UTF-8 whatever the headers say.
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw StashError.badResponse }
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            throw StashError.server(errors.compactMap { $0["message"] as? String }.joined(separator: "; "))
        }
        guard let data = json["data"] as? [String: Any] else { throw StashError.badResponse }
        return data
    }
}
