import Foundation
import NetFS

/// Mounts an SMB share the way the Finder does: the password from the keychain, or the system's sign-in dialog when
/// there is none; the share lands at its usual place in /Volumes.
public enum ShareMounter {
    public struct Failure: LocalizedError {
        public let errorDescription: String?
    }

    /// Mounts `smbURL` (`smb://winbox/S$`), giving up after `timeout` seconds. An already mounted share counts as done.
    public static func mount(_ smbURL: URL, timeout: TimeInterval = 15, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        let openOptions = NSMutableDictionary()
        openOptions[kNAUIOptionKey] = kNAUIOptionAllowUI
        var request: AsyncRequestID?
        var finished = false
        func finish(_ result: Result<Void, Error>) {
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                MainActor.assumeIsolated { completion(result) }
            }
        }
        let status = NetFSMountURLAsync(smbURL as CFURL, nil, nil, nil, openOptions, nil, &request, DispatchQueue.main) { status, _, _ in
            if status == 0 || status == EEXIST {
                finish(.success(()))
            } else {
                let reason = status == ECANCELED || status == Int32(userCanceledErr) ? "cancelled"
                    : String(cString: strerror(status))
                finish(.failure(Failure(errorDescription: reason)))
            }
        }
        guard status == 0 else {
            finish(.failure(Failure(errorDescription: String(cString: strerror(status)))))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            guard !finished else { return }
            if let request { NetFSMountURLCancel(request) }
            finish(.failure(Failure(errorDescription: "no answer in \(Int(timeout)) s")))
        }
    }
}
