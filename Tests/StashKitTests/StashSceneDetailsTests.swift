import Foundation
import Testing
@testable import StashKit

struct StashSceneDetailsTests {
    private func fixtureText() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "find-scene", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func findScene(_ data: Data) throws -> [String: Any] {
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let answer = try #require(root["data"] as? [String: Any])
        return try #require(answer["findScene"] as? [String: Any])
    }

    private func details(_ json: String) throws -> StashSceneDetails {
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        return try #require(StashSceneDetails(json: object))
    }

    @Test func parsesTheFullAnswer() throws {
        let scene = try #require(StashSceneDetails(json: try findScene(fixtureText())))
        #expect(scene.id == "357")
        #expect(scene.title == "Example Scene Title")
        #expect(scene.date == "2024-05-01")
        #expect(scene.code == "EX-0001")
        #expect(scene.director == "Director A")
        #expect(scene.details == "An invented description of the example scene.")
        #expect(scene.studio == "Example Studio")
        #expect(scene.organized)
        #expect(scene.rating100 == 80)
        #expect(scene.oCounter == 2)
        #expect(scene.playCount == 5)
        #expect(scene.fileCount == 2)
        #expect(scene.lastPlayedAt == Date(timeIntervalSince1970: 1_714_645_800))
        #expect(scene.playDuration == 1234.5)
        #expect(scene.resumeTime == 321.25)
        #expect(scene.performers == ["Performer A", "Performer B"])
        #expect(scene.tags == ["Tag One", "Tag Two", "Tag Three"])
        #expect(scene.urls == ["https://example.com/scene/1", "https://example.com/scene/1/alt"])
        #expect(scene.stashIDs == [.init(endpoint: "https://stashdb.example.com/graphql", id: "00000000-0000-4000-8000-000000000001")])
        #expect(scene.markers == [
            .init(seconds: 12.5, title: "Intro", primaryTag: "Marker Tag A"),
            .init(seconds: 95, title: nil, primaryTag: "Marker Tag B"),
        ])
    }

    @Test func parsesNullsAndEmptyStrings() throws {
        let scene = try details("""
            {"id":"9","title":"","date":null,"code":"","director":null,"details":"","organized":false,"rating100":null,
             "o_counter":0,"play_count":0,"last_played_at":null,"play_duration":0,"resume_time":0,"studio":null,
             "performers":[],"tags":[],"urls":[],"stash_ids":[],"scene_markers":[],"files":[{"id":"1"}]}
            """)
        #expect(scene.id == "9")
        #expect(scene.title == nil)
        #expect(scene.date == nil)
        #expect(scene.code == nil)
        #expect(scene.director == nil)
        #expect(scene.details == nil)
        #expect(scene.studio == nil)
        #expect(scene.rating100 == nil)
        #expect(scene.lastPlayedAt == nil)
        #expect(!scene.organized)
        #expect(scene.performers.isEmpty && scene.tags.isEmpty && scene.urls.isEmpty)
        #expect(scene.stashIDs.isEmpty && scene.markers.isEmpty)
        #expect(scene.fileCount == 1)
        #expect(scene.playDuration == 0 && scene.resumeTime == 0)
    }

    @Test func withoutAnIDThereIsNoScene() {
        #expect(StashSceneDetails(json: ["title": "x"]) == nil)
    }

    @Test func applyingSaveAndPlay() throws {
        let scene = try details(#"{"id":"1","play_count":3,"play_duration":100,"resume_time":10,"last_played_at":null}"#)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let saved = scene.applying(.save(resumeTime: 42, playDuration: 7.5), at: now)
        #expect(saved.resumeTime == 42)
        #expect(saved.playDuration == 107.5)
        #expect(saved.playCount == 3)
        #expect(saved.lastPlayedAt == nil)
        let played = saved.applying(.addPlay, at: now)
        #expect(played.playCount == 4)
        #expect(played.lastPlayedAt == now)
        #expect(played.resumeTime == 42)
    }
}

extension StashClientTests {
    @Test func sendsTheSceneQuery() async throws {
        answer(try String(contentsOf: Bundle.module.url(forResource: "find-scene", withExtension: "json", subdirectory: "Fixtures")!, encoding: .utf8))
        let scene = try await client().sceneDetails(id: "357")
        #expect(scene.title == "Example Scene Title")
        let variables = try #require(StubProtocol.lastBody?["variables"] as? [String: Any])
        #expect(variables["id"] as? String == "357")
        #expect((StubProtocol.lastBody?["query"] as? String)?.contains("findScene") == true)
    }

    @Test func missingSceneThrows() async throws {
        answer(#"{"data":{"findScene":null}}"#)
        await #expect(throws: StashError.server("Scene 5 not found in Stash")) { try await client().sceneDetails(id: "5") }
    }
}
