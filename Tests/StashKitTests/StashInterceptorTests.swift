import Foundation
import Testing
import StashKitUI

@Suite struct StashInterceptorTests {
    @Test func scenePlayerTakesOpenMessages() {
        var opened: [StashScene] = []
        let interceptor = StashInterceptor.scenePlayer(onOpen: { opened.append($0) }, onBridgeMissing: {})
        let body: [String: Any] = ["type": "open", "sceneID": "1", "paths": ["X:\\a.mp4"]]
        #expect(interceptor.handle(body))
        #expect(opened.count == 1)
        #expect(opened.first?.id == "1")
        #expect(opened.first?.paths == ["X:\\a.mp4"])
    }

    @Test func aSceneCanBeNamedDirectly() {
        let scene = StashScene(id: "9", paths: [], resumeTime: 12)
        #expect(scene.id == "9")
        #expect(scene.paths.isEmpty)
        #expect(scene.resumeTime == 12)
        #expect(!scene.hasQueue && !scene.automatic && scene.duration == 0)
        let fromMessage = StashScene(message: ["type": "open", "sceneID": "9", "paths": ["X:\\a.mp4"], "resumeTime": 12,
                                               "duration": 60, "hasQueue": true, "automatic": true])
        #expect(fromMessage == StashScene(id: "9", paths: ["X:\\a.mp4"], resumeTime: 12, duration: 60, hasQueue: true,
                                          automatic: true))
    }

    @Test func scenePlayerTakesNoBridge() {
        var missing = 0
        let interceptor = StashInterceptor.scenePlayer(onOpen: { _ in }, onBridgeMissing: { missing += 1 })
        #expect(interceptor.handle(["type": "no-bridge"]))
        #expect(missing == 1)
    }

    @Test func scenePlayerIgnoresOthers() {
        var calls = 0
        let interceptor = StashInterceptor.scenePlayer(onOpen: { _ in calls += 1 }, onBridgeMissing: { calls += 1 })
        #expect(!interceptor.handle(["type": "gallery"]))
        #expect(!interceptor.handle("not a dictionary"))
        #expect(calls == 0)
    }

    @Test func newTabClicksIgnoredByDefault() {
        let script = StashInterceptor.galleryOpener(onOpen: { _ in }).script
        #expect(script.contains("const takesNewTabClicks = false;"))
        #expect(!script.contains("takesNewTabClicks = true"))
        #expect(!script.contains("auxclick"))
    }

    @Test func newTabClicksTakenWhenAsked() {
        let script = StashInterceptor.galleryOpener(interceptsNewTabClicks: true, onOpen: { _ in }).script
        #expect(script.contains("const takesNewTabClicks = true;"))
        #expect(!script.contains("takesNewTabClicks = false"))
        #expect(script.contains("auxclick"))
        #expect(script.contains("mousedown"))
    }

    @Test func pickParsesNewTab() {
        #expect(StashGalleryPick(message: ["type": "gallery", "id": "7", "newTab": true])?.newTab == true)
        #expect(StashGalleryPick(message: ["type": "gallery", "id": "7", "newTab": false])?.newTab == false)
        #expect(StashGalleryPick(message: ["type": "gallery", "id": "7"])?.newTab == false)
        #expect(StashGalleryPick(message: ["type": "gallery", "id": "7", "newWindow": true])?.newWindow == true)
        #expect(StashGalleryPick(message: ["type": "gallery", "id": "7"])?.newWindow == false)
        let made = StashGalleryPick(id: "7", list: nil, newWindow: true)
        #expect(made.id == "7" && made.list == nil && !made.newTab && made.newWindow)
    }
}
