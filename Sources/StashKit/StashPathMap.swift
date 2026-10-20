import Foundation

/// An SMB share mounted on this Mac, as `getmntinfo` reports it.
public struct SMBMount: Equatable, Sendable {
    public let server: String
    public let share: String
    public let mountPoint: URL

    public init(server: String, share: String, mountPoint: URL) {
        self.server = server
        self.share = share
        self.mountPoint = mountPoint
    }

    /// From a mount's source and mount point: `//user@server/S%24` on `/Volumes/S$` → server `winbox`, share `S$`.
    public init?(from source: String, on mountPoint: String) {
        guard source.hasPrefix("//") else { return nil }
        let rest = source.dropFirst(2)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        var host = rest[..<slash]
        if let at = host.lastIndex(of: "@") { host = host[host.index(after: at)...] }
        let share = String(rest[rest.index(after: slash)...])
        guard !host.isEmpty, !share.isEmpty else { return nil }
        self.init(server: String(host), share: share.removingPercentEncoding ?? share,
                  mountPoint: URL(fileURLWithPath: mountPoint, isDirectory: true))
    }

    /// The SMB shares mounted right now.
    public static func current() -> [SMBMount] {
        var list: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&list, MNT_NOWAIT)
        guard count > 0, let list else { return [] }
        return (0..<Int(count)).compactMap { i in
            var entry = list[i]
            let type = withUnsafeBytes(of: &entry.f_fstypename) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            guard type == "smbfs" else { return nil }
            let source = withUnsafeBytes(of: &entry.f_mntfromname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            let point = withUnsafeBytes(of: &entry.f_mntonname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            return SMBMount(from: source, on: point)
        }
    }
}

/// One `stash-path-map` rule: a Stash path prefix and the Mac path that replaces it.
public struct StashPathRule: Equatable, Sendable {
    public let stashPrefix: String
    public let localPrefix: String

    public init(stashPrefix: String, localPrefix: String) {
        self.stashPrefix = stashPrefix
        self.localPrefix = localPrefix
    }

    /// `stashPrefix=localPrefix` rules separated by `;`; a part without both sides is skipped.
    public static func parse(_ text: String) -> [StashPathRule] {
        text.split(separator: ";").compactMap { part in
            guard let equals = part.firstIndex(of: "=") else { return nil }
            let stash = part[..<equals].trimmingCharacters(in: .whitespaces)
            let local = part[part.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            return stash.isEmpty || local.isEmpty ? nil : StashPathRule(stashPrefix: stash, localPrefix: local)
        }
    }
}

public enum StashPathResolution: Equatable, Sendable {
    /// The file's path on a mounted share.
    case local(URL)
    /// The share is not mounted; this is the `smb://` URL to mount.
    case needsMount(URL)
    /// Neither a rule nor a share fits.
    case unmapped
}

/// Turns the Windows paths Stash keeps (`S:\Videos\…`, `\\store.local\Media-1\…`) into paths on the SMB shares mounted
/// on this Mac. Drive letters go to the `S$` admin shares of the server most of those shares are
/// mounted from; a UNC path goes to its share on the same server (`.local` and case ignored), or to the only server
/// that share is mounted from.
public struct StashPathMap: Sendable {
    private let mounts: [SMBMount]
    private let rules: [StashPathRule]
    /// The server drive letters go to: the one most mounted `?$` shares come from, else the remembered one (none of
    /// the PC's shares mounted yet after a restart).
    public let driveServer: String?

    public init(mounts: [SMBMount], rules: [StashPathRule], rememberedDriveServer: String? = nil) {
        self.mounts = mounts
        self.rules = rules.sorted { $0.stashPrefix.count > $1.stashPrefix.count }
        let driveServers = mounts.filter { Self.isDriveShare($0.share) }.map { $0.server }
        let counts = Dictionary(driveServers.map { ($0.lowercased(), 1) }, uniquingKeysWith: +)
        let top = counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key
        driveServer = driveServers.first { $0.lowercased() == top } ?? rememberedDriveServer
    }

    /// A page may hand scenes to the app only when it is the Stash server's own (same scheme, host and port; port 0
    /// is the scheme's default, as WebKit reports it).
    public static func isStashPage(scheme: String, host: String, port: Int, stashURL: URL) -> Bool {
        guard let stashScheme = stashURL.scheme?.lowercased(), let stashHost = stashURL.host?.lowercased() else { return false }
        func effective(_ port: Int?, _ scheme: String) -> Int {
            if let port, port > 0 { return port }
            return scheme == "https" ? 443 : 80
        }
        return scheme.lowercased() == stashScheme && host.lowercased() == stashHost
            && effective(port, scheme.lowercased()) == effective(stashURL.port, stashScheme)
    }

    public func resolve(_ stashPath: String) -> StashPathResolution {
        let lowered = stashPath.lowercased()
        if let rule = rules.first(where: { lowered.hasPrefix($0.stashPrefix.lowercased()) }) {
            var rest = Self.slashes(String(stashPath.dropFirst(rule.stashPrefix.count)))
            if rule.localPrefix.hasSuffix("/"), rest.hasPrefix("/") { rest.removeFirst() }
            return .local(URL(fileURLWithPath: rule.localPrefix + rest))
        }
        let characters = Array(stashPath)
        if characters.count >= 3, characters[0].isASCII, characters[0].isLetter, characters[1] == ":",
           characters[2] == "\\" || characters[2] == "/" {
            guard let driveServer else { return .unmapped }
            let share = "\(characters[0].uppercased())$"
            return locate(server: driveServer, share: share, rest: String(characters.dropFirst(3)), fallbackToShareName: false)
        }
        if stashPath.hasPrefix(#"\\"#) {
            let parts = stashPath.dropFirst(2).split(separator: "\\", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return .unmapped }
            return locate(server: String(parts[0]), share: String(parts[1]), rest: parts.count > 2 ? String(parts[2]) : "",
                          fallbackToShareName: true)
        }
        return .unmapped
    }

    private func locate(server: String, share: String, rest: String, fallbackToShareName: Bool) -> StashPathResolution {
        let host = Self.hostKey(server)
        let sameShare = mounts.filter { $0.share.caseInsensitiveCompare(share) == .orderedSame }
        var mount = sameShare.first { Self.hostKey($0.server) == host }
        if mount == nil, fallbackToShareName, Set(sameShare.map { Self.hostKey($0.server) }).count == 1 {
            mount = sameShare.first
        }
        if let mount {
            let tail = Self.slashes(rest)
            return .local(URL(fileURLWithPath: tail.isEmpty ? mount.mountPoint.path : mount.mountPoint.path + "/" + tail))
        }
        // The server under the name its other shares are mounted by: the keychain knows it by that name.
        let known = mounts.first { Self.hostKey($0.server) == host }?.server ?? server
        let encoded = share.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? share
        guard let url = URL(string: "smb://\(known)/\(encoded)") else { return .unmapped }
        return .needsMount(url)
    }

    private static func isDriveShare(_ share: String) -> Bool {
        share.count == 2 && share.first!.isASCII && share.first!.isLetter && share.last == "$"
    }

    private static func hostKey(_ host: String) -> String {
        let lowered = host.lowercased()
        return lowered.hasSuffix(".local") ? String(lowered.dropLast(6)) : lowered
    }

    private static func slashes(_ path: String) -> String { path.replacingOccurrences(of: "\\", with: "/") }
}
