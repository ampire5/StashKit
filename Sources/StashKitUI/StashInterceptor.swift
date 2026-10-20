import Foundation
import OSLog

/// A way the app changes Stash's WebUI: a script injected at document start (main frame only) and the handling of the
/// messages that script posts to the bridge handler. The app gives `StashLibraryView` the interceptors it wants;
/// the page itself assumes none of them.
public struct StashInterceptor {
    /// Injected at document start, main frame only.
    public let script: String
    /// Offered a bridge message (after the view checked it came from Stash's own main frame). Returns true when the
    /// message was this interceptor's; the view then stops offering it.
    public let handle: (Any) -> Bool

    public init(script: String, handle: @escaping (Any) -> Bool) {
        self.script = script
        self.handle = handle
    }

    /// Replaces Stash's scene player with the scene's cover and a play button that hands the scene to the app
    /// (`onOpen`), and keeps the player's queue callbacks so `StashLibraryView.step(_:)` can walk Stash's queue.
    /// `onBridgeMissing` is called when the page has no plugin API (not Stash, or a Stash without it).
    public static func scenePlayer(onOpen: @escaping (StashScene) -> Void,
                                   onBridgeMissing: @escaping () -> Void) -> StashInterceptor {
        StashInterceptor(script: StashBridgeScript.source) { body in
            if let scene = StashScene(message: body) {
                onOpen(scene)
                return true
            }
            if (body as? [String: Any])?["type"] as? String == "no-bridge" {
                Logger(subsystem: "local.stashkit", category: "Stash").error("Stash bridge: no PluginApi")
                onBridgeMissing()
                return true
            }
            return false
        }
    }
}
