import Foundation

/// What a step through a gallery list found: the next gallery with a path (and its place in the list), or the end.
public enum StashGalleryStep: Equatable, Sendable {
    case gallery(StashGallery, index: Int, count: Int)
    case end
}

/// The Stash list a gallery was picked in, read page by page with the list's own variables:
/// `step(from:_:)` gives the next or previous gallery with a path after a list index (the caller keeps its place, so
/// a step that comes to nothing moves nothing); the ends, and a page that comes back shorter than the count said
/// (the list changed), give `.end`. Pages are kept; when a step lands within `prefetchMargin` of a page's edge, the
/// page beyond it is fetched ahead.
public actor StashGalleryList {
    private let variables: Data
    private let finder: StashGalleryFinding
    private let perPage: Int
    private var count: Int?
    private var pages: [Int: Task<[StashGallery], Error>] = [:]
    static let prefetchMargin = 5

    public init(variables: Data, finder: StashGalleryFinding, perPage: Int = 40) {
        self.variables = variables
        self.finder = finder
        self.perPage = perPage
    }

    /// The next (`direction` > 0) or previous gallery with a path after list index `index`.
    public func step(from index: Int, _ direction: Int) async throws -> StashGalleryStep {
        let delta = direction > 0 ? 1 : -1
        var i = index
        while true {
            i += delta
            if i < 0 { return .end }
            if let count, i >= count { return .end }
            let page = i / perPage + 1, offset = i % perPage
            let galleries = try await self.page(page)
            guard offset < galleries.count, let count else { return .end }
            let gallery = galleries[offset]
            guard gallery.path != nil else { continue }
            if offset >= perPage - Self.prefetchMargin, page * perPage < count { prefetch(page + 1) }
            if offset < Self.prefetchMargin, page > 1 { prefetch(page - 1) }
            return .gallery(gallery, index: i, count: count)
        }
    }

    private func page(_ n: Int) async throws -> [StashGallery] {
        let task = pages[n] ?? fetch(n)
        do {
            return try await task.value
        } catch {
            pages[n] = nil   // a failed page is asked again next time
            throw error
        }
    }

    private func fetch(_ n: Int) -> Task<[StashGallery], Error> {
        let finder = self.finder, variables = self.variables, perPage = self.perPage
        let task = Task { [weak self] in
            let found = try await finder.findGalleries(variables: variables, page: n, perPage: perPage)
            await self?.setCount(found.count)
            return found.galleries
        }
        pages[n] = task
        return task
    }

    private func setCount(_ n: Int) { count = n }

    private func prefetch(_ n: Int) {
        guard pages[n] == nil else { return }
        _ = fetch(n)
    }
}
