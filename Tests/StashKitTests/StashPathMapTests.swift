import Foundation
import Testing
@testable import StashKit

@Suite struct StashPathMapTests {
    private static func mount(_ server: String, _ share: String) -> SMBMount {
        SMBMount(server: server, share: share, mountPoint: URL(fileURLWithPath: "/Volumes/\(share)"))
    }

    private static let pcDrives = "ABCDEFGHIJKLMNOPQRST".map { mount("winbox", "\($0)$") }
    private static let mounts = pcDrives.filter { $0.share != "T$" } + [mount("store", "Media-1"), mount("store", "Media-2"),
        mount("store", "Media-3"), mount("store2", "Archive-1"), mount("store2", "Archive-2")]
    private let map = StashPathMap(mounts: mounts, rules: [])

    @Test func mountFromName() throws {
        let drive = try #require(SMBMount(from: "//alice@winbox/S%24", on: "/Volumes/S$"))
        #expect(drive == SMBMount(server: "winbox", share: "S$", mountPoint: URL(fileURLWithPath: "/Volumes/S$", isDirectory: true)))
        #expect(SMBMount(from: "//bob@store/Media-1", on: "/Volumes/Media-1")?.server == "store")
        #expect(SMBMount(from: "//guest:@store2/Archive-3", on: "/Volumes/Archive-3")?.server == "store2")
        #expect(SMBMount(from: "/dev/disk3s1", on: "/") == nil)
    }

    @Test func driveLetter() {
        #expect(map.resolve(#"S:\Videos\Shows\a.mp4"#) == .local(URL(fileURLWithPath: "/Volumes/S$/Videos/Shows/a.mp4")))
        #expect(map.resolve(#"s:\Videos\Shows\a.mp4"#) == .local(URL(fileURLWithPath: "/Volumes/S$/Videos/Shows/a.mp4")))
    }

    @Test func uncWithLocalSuffix() {
        #expect(map.resolve(#"\\store.local\Media-1\Videos\a.mp4"#) == .local(URL(fileURLWithPath: "/Volumes/Media-1/Videos/a.mp4")))
        #expect(map.resolve(#"\\STORE2\Archive-2\x.mkv"#) == .local(URL(fileURLWithPath: "/Volumes/Archive-2/x.mkv")))
    }

    @Test func uniqueShareNameFallback() {
        #expect(map.resolve(#"\\192.0.2.50\Media-3\a.mp4"#) == .local(URL(fileURLWithPath: "/Volumes/Media-3/a.mp4")))
    }

    @Test func needsMount() {
        #expect(map.resolve(#"T:\Stash\a.mp4"#) == .needsMount(URL(string: "smb://winbox/T$")!))
        // store2's other shares are mounted as "store2": the keychain knows the server by that name.
        #expect(map.resolve(#"\\store2.local\Archive-4\a.mp4"#) == .needsMount(URL(string: "smb://store2/Archive-4")!))
        #expect(map.resolve(#"\\other.local\x\a.mp4"#) == .needsMount(URL(string: "smb://other.local/x")!))
    }

    @Test func unmapped() {
        let bare = StashPathMap(mounts: [Self.mount("store", "Media-1")], rules: [])
        #expect(bare.resolve(#"S:\a.mp4"#) == .unmapped)
        #expect(map.resolve("/home/a.mp4") == .unmapped)
    }

    @Test func rulesFirstLongestPrefix() {
        let rules = StashPathRule.parse(#"S:\=/Volumes/Other/;S:\Videos\=/Volumes/W/"#)
        #expect(rules == [StashPathRule(stashPrefix: #"S:\"#, localPrefix: "/Volumes/Other/"),
                          StashPathRule(stashPrefix: #"S:\Videos\"#, localPrefix: "/Volumes/W/")])
        let ruled = StashPathMap(mounts: Self.mounts, rules: rules)
        #expect(ruled.resolve(#"S:\Videos\a.mp4"#) == .local(URL(fileURLWithPath: "/Volumes/W/a.mp4")))
        #expect(ruled.resolve(#"s:\videos\a.mp4"#) == .local(URL(fileURLWithPath: "/Volumes/W/a.mp4")))
        #expect(ruled.resolve(#"S:\Clips\b.mp4"#) == .local(URL(fileURLWithPath: "/Volumes/Other/Clips/b.mp4")))
        #expect(StashPathRule.parse(" ; =x;broken;a=b ") == [StashPathRule(stashPrefix: "a", localPrefix: "b")])
    }

    @Test func rememberedDriveServerWhenNoDriveShareIsMounted() {
        let bare = StashPathMap(mounts: [Self.mount("store", "Media-1")], rules: [], rememberedDriveServer: "winbox")
        #expect(bare.resolve(#"S:\a.mp4"#) == .needsMount(URL(string: "smb://winbox/S$")!))
        #expect(bare.driveServer == "winbox")
        #expect(map.driveServer == "winbox")   // from the mounted ?$ shares
        #expect(StashPathMap(mounts: [], rules: []).driveServer == nil)
    }

    @Test func stashOriginIsCheckedBySchemeHostAndPort() {
        let stash = URL(string: "http://192.0.2.10:9999")!
        #expect(StashPathMap.isStashPage(scheme: "http", host: "192.0.2.10", port: 9999, stashURL: stash))
        #expect(!StashPathMap.isStashPage(scheme: "http", host: "evil.example", port: 9999, stashURL: stash))
        #expect(!StashPathMap.isStashPage(scheme: "http", host: "192.0.2.10", port: 80, stashURL: stash))
        #expect(!StashPathMap.isStashPage(scheme: "https", host: "192.0.2.10", port: 9999, stashURL: stash))
        let plain = URL(string: "http://Stash.local")!
        #expect(StashPathMap.isStashPage(scheme: "http", host: "stash.local", port: 0, stashURL: plain))   // 0: the default port
        #expect(StashPathMap.isStashPage(scheme: "http", host: "stash.local", port: 80, stashURL: plain))
    }

    @Test func driveServerByMajority() {
        let mixed = StashPathMap(mounts: [Self.mount("winbox", "A$"), Self.mount("winbox", "B$"), Self.mount("winbox", "C$"),
                                          SMBMount(server: "old", share: "S$", mountPoint: URL(fileURLWithPath: "/Volumes/S$-1"))],
                                 rules: [])
        #expect(mixed.resolve(#"S:\a.mp4"#) == .needsMount(URL(string: "smb://winbox/S$")!))
        #expect(mixed.resolve(#"A:\a.mp4"#) == .local(URL(fileURLWithPath: "/Volumes/A$/a.mp4")))
    }

    @Test func unusualCharactersSurvive() throws {
        let resolved = map.resolve(#"S:\Videos\Папка #1\100% real \a b.mp4"#)
        #expect(resolved == .local(URL(fileURLWithPath: "/Volumes/S$/Videos/Папка #1/100% real /a b.mp4")))
        guard case let .local(url) = resolved else { Issue.record("not local"); return }
        #expect(url.path == "/Volumes/S$/Videos/Папка #1/100% real /a b.mp4")
    }
}
