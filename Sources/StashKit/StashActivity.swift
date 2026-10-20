/// What to tell Stash about the scene being watched.
public enum StashActivityRequest: Equatable, Sendable {
    /// `sceneSaveActivity`: where it was left and the seconds watched since the last save.
    case save(resumeTime: Double, playDuration: Double)
    /// `sceneAddPlay`: one more play.
    case addPlay
}

/// Watched time and plays of a scene opened from Stash, counted as Stash's own player counts them
/// (`track-activity.ts`): forward playback at 1× or faster, in seconds of the file; a save every
/// 10 s of it, on pause and on leaving; the resume point cleared at 98 %; one play once the watched time reaches
/// `minimumPlayPercent` of the scene.
public struct StashActivity: Sendable {
    public static let sendEvery = 10.0
    private let duration: Double
    private var minimumPlayPercent: Double
    private var enabled: Bool
    private var lastPosition: Double?
    private var total = 0.0
    private var unsent = 0.0
    private var sinceSend = 0.0
    private var playAdded = false

    public init(duration: Double, minimumPlayPercent: Double, enabled: Bool) {
        self.duration = duration
        self.minimumPlayPercent = minimumPlayPercent
        self.enabled = enabled
    }

    /// Called about once a second while the scene is open: `position` is the playhead in seconds, `elapsed` the
    /// seconds since the last call. A move further than playback at `speed` could make is a seek and does not count.
    public mutating func tick(position: Double, elapsed: Double, playingForward: Bool, speed: Double) -> [StashActivityRequest] {
        defer { lastPosition = position }
        guard enabled, let last = lastPosition, playingForward, speed >= 1 else { return [] }
        let delta = position - last
        guard delta > 0, delta <= elapsed * speed * 1.25 + 0.05 else { return [] }
        total += delta
        unsent += delta
        sinceSend += delta
        guard sinceSend >= Self.sendEvery else { return [] }
        return send(position: position)
    }

    /// Pause, leaving the scene or quitting: what was watched since the last save.
    public mutating func flush(position: Double) -> [StashActivityRequest] {
        guard enabled, unsent > 0 else { return [] }
        return send(position: position)
    }

    /// Stash's own settings, known only now: they decide what is sent from here on, what was held back included.
    public mutating func apply(minimumPlayPercent: Double, enabled: Bool) {
        self.minimumPlayPercent = minimumPlayPercent
        self.enabled = enabled
    }

    /// A request did not reach Stash: its watched time goes with the next save, a play is asked for again.
    public mutating func failed(_ request: StashActivityRequest) {
        switch request {
        case let .save(_, playDuration): unsent += playDuration
        case .addPlay: playAdded = false
        }
    }

    private mutating func send(position: Double) -> [StashActivityRequest] {
        let resume = duration > 0 && position >= duration * 0.98 ? 0 : position
        var requests: [StashActivityRequest] = [.save(resumeTime: resume, playDuration: unsent)]
        unsent = 0
        sinceSend = 0
        if !playAdded, total > 0, total >= duration * minimumPlayPercent / 100 {
            playAdded = true
            requests.append(.addPlay)
        }
        return requests
    }
}
