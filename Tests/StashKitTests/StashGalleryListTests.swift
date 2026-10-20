import Foundation
import Testing
@testable import StashKit

/// A list of `count` galleries ("g0", "g1", …); `pathless` ids have no path; `short` pages come back empty.
private actor FakeFinder: StashGalleryFinding {
    let count: Int
    let pathless: Set<Int>
    let short: Set<Int>
    private var failing: Set<Int>
    private(set) var pages: [Int] = []

    init(count: Int, pathless: Set<Int> = [], short: Set<Int> = [], failing: Set<Int> = []) {
        self.count = count
        self.pathless = pathless
        self.short = short
        self.failing = failing
    }

    func heal() { failing = [] }

    func findGalleries(variables: Data, page: Int, perPage: Int) async throws -> (galleries: [StashGallery], count: Int) {
        pages.append(page)
        if failing.contains(page) { throw URLError(.networkConnectionLost) }
        if short.contains(page) { return ([], count) }
        let range = ((page - 1) * perPage)..<min(count, page * perPage)
        return (range.map { i in
            StashGallery(id: "g\(i)", title: "G\(i)", folderPath: pathless.contains(i) ? nil : "S:\\g\(i)", zipPath: nil)
        }, count)
    }
}

@Suite struct StashGalleryListTests {
    let variables = Data(#"{"filter":{}}"#.utf8)

    func id(_ step: StashGalleryStep) -> String? {
        if case .gallery(let g, _, _) = step { return g.id }
        return nil
    }

    @Test func listStepsAcrossPages() async throws {
        let list = StashGalleryList(variables: variables, finder: FakeFinder(count: 100), perPage: 40)
        #expect(id(try await list.step(from: 38, 1)) == "g39")
        let next = try await list.step(from: 39, 1)
        #expect(next == .gallery(StashGallery(id: "g40", title: "G40", folderPath: "S:\\g40", zipPath: nil),
                                 index: 40, count: 100))
        #expect(id(try await list.step(from: 40, -1)) == "g39")
    }

    @Test func listSkipsGalleriesWithoutPath() async throws {
        let list = StashGalleryList(variables: variables, finder: FakeFinder(count: 10, pathless: [5, 6]), perPage: 40)
        #expect(id(try await list.step(from: 4, 1)) == "g7")
        #expect(id(try await list.step(from: 7, -1)) == "g4")
    }

    @Test func listEndsAtBothEdges() async throws {
        let list = StashGalleryList(variables: variables, finder: FakeFinder(count: 10), perPage: 40)
        #expect(try await list.step(from: 9, 1) == .end)
        #expect(try await list.step(from: 0, -1) == .end)
    }

    @Test func shortPageEndsTheList() async throws {
        let list = StashGalleryList(variables: variables, finder: FakeFinder(count: 100, short: [3]), perPage: 40)
        #expect(try await list.step(from: 79, 1) == .end)
    }

    @Test func listPrefetchesNextPage() async throws {
        let finder = FakeFinder(count: 100)
        let list = StashGalleryList(variables: variables, finder: finder, perPage: 40)
        _ = try await list.step(from: 35, 1)   // index 36: within 5 of the page's end
        try await Task.sleep(for: .milliseconds(100))
        #expect(await finder.pages.contains(2))
    }

    @Test func aFailedPageIsAskedAgain() async throws {
        let finder = FakeFinder(count: 100, failing: [1])
        let list = StashGalleryList(variables: variables, finder: finder, perPage: 40)
        await #expect(throws: (any Error).self) { try await list.step(from: 3, 1) }
        await finder.heal()
        #expect(id(try await list.step(from: 3, 1)) == "g4")
    }
}
