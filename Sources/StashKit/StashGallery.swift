import Foundation

/// A Stash gallery as Loupe opens it: a folder or a zip file on the Stash server's disks, or neither (a virtual
/// gallery made in Stash).
public struct StashGallery: Equatable, Sendable {
    public let id: String
    public let title: String
    public let folderPath: String?
    public let zipPath: String?

    public init(id: String, title: String, folderPath: String?, zipPath: String?) {
        self.id = id
        self.title = title
        self.folderPath = folderPath
        self.zipPath = zipPath
    }

    /// The path to open: the zip file of a zip gallery, else the folder; nil for a virtual gallery.
    public var path: String? { zipPath ?? folderPath }

    /// From a `findGallery` / `findGalleries` item (`id title folder { path } files { path }`). The title falls back
    /// to the path's last component, then to `Gallery <id>`.
    init?(json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        let folder = (json["folder"] as? [String: Any])?["path"] as? String
        let zip = (json["files"] as? [[String: Any]])?.first?["path"] as? String
        let path = zip ?? folder
        let last = path?.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init)
        let title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? last ?? "Gallery \(id)"
        self.init(id: id, title: title, folderPath: folder, zipPath: zip)
    }
}

/// Where a gallery was picked in a Stash list: the list's own `FindGalleries` variables (as JSON, exactly as the
/// page sent them: filter, sort, search, the criteria a performer's or tag's tab adds) and the gallery's position in
/// the whole list, and the list's length when the page's answer said it.
public struct StashGalleryListContext: Equatable, Sendable {
    public let variables: Data
    public let index: Int
    public let count: Int?

    public init(variables: Data, index: Int, count: Int? = nil) {
        self.variables = variables
        self.index = index
        self.count = count
    }
}

/// One page of a gallery list (`StashClient` answers it; tests fake it).
public protocol StashGalleryFinding: Sendable {
    func findGalleries(variables: Data, page: Int, perPage: Int) async throws -> (galleries: [StashGallery], count: Int)
}

extension StashClient: StashGalleryFinding {
    private static let galleryFields = "id title folder { path } files { path }"

    public func gallery(id: String) async throws -> StashGallery? {
        let data = try await query("query($id: ID!) { findGallery(id: $id) { \(Self.galleryFields) } }", ["id": id])
        return (data["findGallery"] as? [String: Any]).flatMap(StashGallery.init(json:))
    }

    /// The list's page `page` of `perPage` galleries, with the list's `variables` otherwise unchanged.
    public func findGalleries(variables: Data, page: Int, perPage: Int) async throws -> (galleries: [StashGallery], count: Int) {
        var all = (try? JSONSerialization.jsonObject(with: variables) as? [String: Any]) ?? [:]
        var filter = all["filter"] as? [String: Any] ?? [:]
        filter["page"] = page
        filter["per_page"] = perPage
        all["filter"] = filter
        let data = try await query("""
            query($filter: FindFilterType, $gallery_filter: GalleryFilterType) {
              findGalleries(filter: $filter, gallery_filter: $gallery_filter) { count galleries { \(Self.galleryFields) } }
            }
            """, all)
        let found = data["findGalleries"] as? [String: Any] ?? [:]
        let galleries = (found["galleries"] as? [[String: Any]] ?? []).compactMap(StashGallery.init(json:))
        return (galleries, (found["count"] as? NSNumber)?.intValue ?? galleries.count)
    }

    /// The first gallery's path, for Loupe's Settings → Stash → Check.
    public func firstGalleryPath() async throws -> String? {
        try await findGalleries(variables: Data("{}".utf8), page: 1, perPage: 1).galleries.first?.path
    }
}
