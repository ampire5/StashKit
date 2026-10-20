import Foundation
import Testing
@testable import StashKit

/// Answers every request of its session with `StubProtocol.respond` and keeps the last request.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var respond: (URLRequest) -> (Int, [String: String], Data) = { _ in (200, [:], Data()) }
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: [String: Any]?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            stream.close()
            Self.lastBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        } else if let body = request.httpBody {
            Self.lastBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        }
        let (status, headers, data) = Self.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct StashClientTests {
    func client(apiKey: String? = nil) -> StashClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return StashClient(baseURL: URL(string: "http://h:9999")!, apiKey: apiKey, session: URLSession(configuration: configuration))
    }

    func answer(_ json: String, status: Int = 200, type: String = "application/graphql-response+json") {
        StubProtocol.respond = { _ in (status, ["Content-Type": type], Data(json.utf8)) }
    }

    @Test func postsToGraphQLWithApiKey() async throws {
        answer(#"{"data":{"version":{"version":"v0.31.1"}}}"#)
        _ = try await client(apiKey: "k").version()
        let request = try #require(StubProtocol.lastRequest)
        #expect(request.url?.absoluteString == "http://h:9999/graphql")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "ApiKey") == "k")
        #expect((StubProtocol.lastBody?["query"] as? String)?.contains("version") == true)
        _ = try await client(apiKey: "").version()
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "ApiKey") == nil)
        _ = try await client().version()
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "ApiKey") == nil)
    }

    @Test func decodesUTF8WithoutCharset() async throws {
        answer(#"{"data":{"version":{"version":"v0.31.1 — тест"}}}"#)
        #expect(try await client().version() == "v0.31.1 — тест")
    }

    @Test func uiSettingsDefaults() async throws {
        answer(#"{"data":{"configuration":{"ui":{}}}}"#)
        #expect(try await client().uiSettings() == StashUISettings())
        answer(#"{"data":{"configuration":{"ui":{"trackActivity":false,"minimumPlayPercent":25}}}}"#)
        #expect(try await client().uiSettings() == StashUISettings(trackActivity: false, minimumPlayPercent: 25))
    }

    @Test func saveSendsVariables() async throws {
        answer(#"{"data":{"sceneSaveActivity":true}}"#)
        try await client().send(.save(resumeTime: 12.5, playDuration: 10), sceneID: "42")
        let variables = try #require(StubProtocol.lastBody?["variables"] as? [String: Any])
        #expect(variables["id"] as? String == "42")
        #expect(variables["resume_time"] as? Double == 12.5)
        #expect(variables["playDuration"] as? Double == 10)
        answer(#"{"data":{"sceneAddPlay":{"count":1}}}"#)
        try await client().send(.addPlay, sceneID: "42")
        #expect((StubProtocol.lastBody?["query"] as? String)?.contains("sceneAddPlay") == true)
    }

    @Test func destroySendsTheScene() async throws {
        answer(#"{"data":{"scenesDestroy":true}}"#)
        try await client().destroyScene("7")
        let variables = try #require(StubProtocol.lastBody?["variables"] as? [String: Any])
        #expect(variables["id"] as? String == "7")
        #expect((StubProtocol.lastBody?["query"] as? String)?.contains("delete_file: true") == true)
    }

    @Test func firstScenePath() async throws {
        answer(#"{"data":{"findScenes":{"scenes":[{"files":[{"path":"S:\\Videos\\a.mp4"}]}]}}}"#)
        #expect(try await client().firstScenePath() == #"S:\Videos\a.mp4"#)
        answer(#"{"data":{"findScenes":{"scenes":[]}}}"#)
        #expect(try await client().firstScenePath() == nil)
    }

    @Test func errorsReadWell() {
        #expect(StashError.server("scene not found").localizedDescription == "scene not found")
        #expect(StashError.http(502).localizedDescription == "Stash answered HTTP 502")
        #expect(StashError.badResponse.localizedDescription == "Stash's answer could not be read")
    }

    @Test func graphQLErrorsThrow() async throws {
        answer(#"{"errors":[{"message":"scene not found"}]}"#)
        await #expect(throws: StashError.server("scene not found")) { try await client().destroyScene("1") }
        answer("oops", status: 500, type: "text/plain")
        await #expect(throws: StashError.http(500)) { try await client().version() }
    }
}
