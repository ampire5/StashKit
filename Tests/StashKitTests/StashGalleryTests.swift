import Foundation
import Testing
@testable import StashKit
import StashKitUI

/// Galleries for Loupe: the client's gallery queries. In `StashClientTests` (serialized):
/// they share its `StubProtocol`.
extension StashClientTests {
    @Test func galleryParsesFolderAndZip() async throws {
        answer(#"{"data":{"findGallery":{"id":"4","title":"","folder":null,"files":[{"path":"A:\\x\\G.zip"}]}}}"#)
        let zip = try #require(try await client().gallery(id: "4"))
        #expect(zip == StashGallery(id: "4", title: "G.zip", folderPath: nil, zipPath: #"A:\x\G.zip"#))
        #expect(zip.path == #"A:\x\G.zip"#)
        #expect((StubProtocol.lastBody?["variables"] as? [String: Any])?["id"] as? String == "4")
        answer(#"{"data":{"findGallery":{"id":"5","title":"Set","folder":{"path":"S:\\pics\\set"},"files":[]}}}"#)
        let folder = try #require(try await client().gallery(id: "5"))
        #expect(folder.folderPath == #"S:\pics\set"# && folder.zipPath == nil && folder.title == "Set")
        answer(#"{"data":{"findGallery":{"id":"6","title":"","folder":null,"files":[]}}}"#)
        let virtual = try #require(try await client().gallery(id: "6"))
        #expect(virtual.path == nil && virtual.title == "Gallery 6")
        answer(#"{"data":{"findGallery":null}}"#)
        #expect(try await client().gallery(id: "7") == nil)
    }

    @Test func findGalleriesSendsPageAndPerPage() async throws {
        answer(#"{"data":{"findGalleries":{"count":3,"galleries":[{"id":"1","title":"a","folder":{"path":"S:\\a"},"files":[]}]}}}"#)
        let variables = Data(#"{"filter":{"q":"x","sort":"title","direction":"DESC","page":1,"per_page":25},"gallery_filter":{"organized":true}}"#.utf8)
        let page = try await client().findGalleries(variables: variables, page: 3, perPage: 40)
        #expect(page.count == 3 && page.galleries.map(\.id) == ["1"])
        let sent = try #require(StubProtocol.lastBody?["variables"] as? [String: Any])
        let filter = try #require(sent["filter"] as? [String: Any])
        #expect(filter["page"] as? Int == 3 && filter["per_page"] as? Int == 40)
        #expect(filter["q"] as? String == "x" && filter["sort"] as? String == "title")
        #expect((sent["gallery_filter"] as? [String: Any])?["organized"] as? Bool == true)
        #expect((StubProtocol.lastBody?["query"] as? String)?.contains("findGalleries") == true)
    }

    @Test func firstGalleryPath() async throws {
        answer(#"{"data":{"findGalleries":{"count":1,"galleries":[{"id":"1","title":"","folder":null,"files":[{"path":"A:\\g.zip"}]}]}}}"#)
        #expect(try await client().firstGalleryPath() == #"A:\g.zip"#)
    }
}

@Suite struct StashGalleryPickTests {
    @Test func pickParsesWithAndWithoutList() throws {
        let body: [String: Any] = ["type": "gallery", "id": "67",
                                   "list": ["index": 80, "variables": ["filter": ["page": 3, "per_page": 40]]]]
        let pick = try #require(StashGalleryPick(message: body))
        #expect(pick.id == "67" && pick.list?.index == 80 && pick.list?.count == nil)
        let variables = try #require(try JSONSerialization.jsonObject(with: pick.list!.variables) as? [String: Any])
        #expect((variables["filter"] as? [String: Any])?["page"] as? Int == 3)
        let bare = try #require(StashGalleryPick(message: ["type": "gallery", "id": "1", "list": NSNull()]))
        #expect(bare.list == nil)
    }

    @Test func pickCarriesTheListCount() throws {
        let body: [String: Any] = ["type": "gallery", "id": "7", "list": ["index": 3, "count": 1195, "variables": [:]]]
        #expect(try #require(StashGalleryPick(message: body)).list?.count == 1195)
    }

    @Test func pickRejectsOtherMessages() {
        #expect(StashGalleryPick(message: ["type": "open", "id": "1"]) == nil)
        #expect(StashGalleryPick(message: ["type": "gallery"]) == nil)
        #expect(StashGalleryPick(message: "text") == nil)
    }

    @Test func galleryOpenerHandlesOnlyGalleryMessages() {
        var picks: [StashGalleryPick] = []
        let opener = StashInterceptor.galleryOpener { picks.append($0) }
        #expect(opener.handle(["type": "gallery", "id": "9"]))
        #expect(!opener.handle(["type": "open", "sceneID": "1", "paths": []]))
        #expect(picks.map(\.id) == ["9"])
        #expect(opener.script.contains("FindGalleries") && opener.script.contains(".GalleryWallCard"))
    }
}
