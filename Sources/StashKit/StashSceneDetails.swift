import Foundation

/// What Stash knows about one scene, read once for display (the `findScene` object). Empty strings from Stash are `nil`.
public struct StashSceneDetails: Equatable, Sendable {
    public struct Marker: Equatable, Sendable {
        public var seconds: Double
        public var title: String?
        public var primaryTag: String?

        public init(seconds: Double, title: String? = nil, primaryTag: String? = nil) {
            self.seconds = seconds
            self.title = title
            self.primaryTag = primaryTag
        }
    }

    public struct StashID: Equatable, Sendable {
        public var endpoint: String
        public var id: String

        public init(endpoint: String, id: String) {
            self.endpoint = endpoint
            self.id = id
        }
    }

    public var id: String
    public var title, date, code, director, details, studio: String?
    public var organized: Bool
    public var rating100: Int?
    public var oCounter, playCount, fileCount: Int
    public var lastPlayedAt: Date?
    public var playDuration, resumeTime: Double
    public var performers, tags, urls: [String]
    public var stashIDs: [StashID]
    public var markers: [Marker]

    /// Reads the `findScene` object; nil when it has no id.
    public init?(json: [String: Any]) {
        guard let id = Self.text(json["id"]) else { return nil }
        self.id = id
        title = Self.text(json["title"])
        date = Self.text(json["date"])
        code = Self.text(json["code"])
        director = Self.text(json["director"])
        details = Self.text(json["details"])
        studio = Self.text((json["studio"] as? [String: Any])?["name"])
        organized = json["organized"] as? Bool ?? false
        rating100 = (json["rating100"] as? NSNumber)?.intValue
        oCounter = (json["o_counter"] as? NSNumber)?.intValue ?? 0
        playCount = (json["play_count"] as? NSNumber)?.intValue ?? 0
        fileCount = (json["files"] as? [Any])?.count ?? 0
        lastPlayedAt = Self.text(json["last_played_at"]).flatMap(Self.date(from:))
        playDuration = (json["play_duration"] as? NSNumber)?.doubleValue ?? 0
        resumeTime = (json["resume_time"] as? NSNumber)?.doubleValue ?? 0
        performers = Self.names(json["performers"])
        tags = Self.names(json["tags"])
        urls = (json["urls"] as? [Any])?.compactMap(Self.text) ?? []
        stashIDs = (json["stash_ids"] as? [[String: Any]])?.compactMap { entry in
            guard let endpoint = Self.text(entry["endpoint"]), let id = Self.text(entry["stash_id"]) else { return nil }
            return StashID(endpoint: endpoint, id: id)
        } ?? []
        markers = (json["scene_markers"] as? [[String: Any]])?.compactMap { entry in
            guard let seconds = (entry["seconds"] as? NSNumber)?.doubleValue else { return nil }
            return Marker(
                seconds: seconds,
                title: Self.text(entry["title"]),
                primaryTag: Self.text((entry["primary_tag"] as? [String: Any])?["name"])
            )
        } ?? []
    }

    /// The details after Stash has taken `request` at `now`: a save moves the resume point and adds the watched
    /// seconds; a play adds one to the count and stamps the time.
    public func applying(_ request: StashActivityRequest, at now: Date) -> StashSceneDetails {
        var copy = self
        switch request {
        case let .save(resumeTime, playDuration):
            copy.resumeTime = resumeTime
            copy.playDuration += playDuration
        case .addPlay:
            copy.playCount += 1
            copy.lastPlayedAt = now
        }
        return copy
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    private static func names(_ value: Any?) -> [String] {
        (value as? [[String: Any]])?.compactMap { text($0["name"]) } ?? []
    }

    private static func date(from string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }
}

extension StashClient {
    private static let sceneQuery = """
        query($id: ID!) { findScene(id: $id) { id title date code director details organized rating100 o_counter \
        play_count last_played_at play_duration resume_time studio { name } performers { name } tags { name } urls \
        stash_ids { endpoint stash_id } scene_markers { seconds title primary_tag { name } } files { id } } }
        """

    /// One scene's details; `StashError.server` when Stash has no such scene.
    public func sceneDetails(id: String) async throws -> StashSceneDetails {
        let data = try await query(Self.sceneQuery, ["id": id])
        guard let scene = data["findScene"] else { throw StashError.badResponse }
        if scene is NSNull { throw StashError.server("Scene \(id) not found in Stash") }
        guard let object = scene as? [String: Any], let details = StashSceneDetails(json: object) else { throw StashError.badResponse }
        return details
    }
}
