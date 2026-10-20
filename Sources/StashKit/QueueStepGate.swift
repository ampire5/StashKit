/// One step through Stash's queue at a time: the app asks the page for the next or previous scene
/// and waits for it; another press meanwhile is dropped, and no answer in 5 s means the end of the list.
public struct QueueStepGate: Sendable {
    public static let timeout = 5.0
    private var startedAt: Double?

    public init() {}

    public var isPending: Bool { startedAt != nil }

    /// A step may start: none is waiting, or the one waiting is older than the timeout.
    public mutating func begin(at now: Double) -> Bool {
        if let startedAt, now - startedAt < Self.timeout { return false }
        startedAt = now
        return true
    }

    /// The page sent the scene the step asked for.
    public mutating func answered() { startedAt = nil }

    /// The user left the file (⌘W, another file): an answer still on its way is no longer wanted.
    public mutating func cancel() { startedAt = nil }

    /// True once, when the waiting step has had no answer for the timeout.
    public mutating func timedOut(at now: Double) -> Bool {
        guard let startedAt, now - startedAt >= Self.timeout else { return false }
        self.startedAt = nil
        return true
    }
}
