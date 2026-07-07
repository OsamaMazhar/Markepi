import Foundation
import os.log

#if DEBUG
private let inboxLog = Logger(subsystem: "com.osamamazhar.markepi", category: "SharedInbox")
#endif

/// Hands shared media from the Share Extension to the main app via the App Group
/// container.
///
/// The Share Extension is a thin bridge: it copies each shared photo/video into
/// the shared `PendingShares` inbox, then opens the main app. The app drains the
/// inbox on launch / URL open and loads the files into the full editor — giving
/// the share flow exact feature + design parity with the app (it *is* the app),
/// without the ~120MB extension memory ceiling that made in-extension rendering
/// fragile.
///
/// Each shared item lives in its own UUID subdirectory so the original filename
/// (and thus EXIF/GPS/HDR metadata carried in the bytes) is preserved without
/// collisions:
///
/// ```
/// <AppGroupContainer>/PendingShares/<UUID>/IMG_0369.HEIC
/// ```
public enum SharedInboxStore {

    /// App Group identifier — must match both targets' entitlements.
    public static let appGroupIdentifier = AppGroupConfigSync.suiteName

    /// URL of the shared `PendingShares` directory inside the App Group container,
    /// created on demand. Returns `nil` if the container is unavailable (which
    /// indicates a misconfigured App Group entitlement).
    public static func inboxDirectory() -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            #if DEBUG
            os_log(.error, "[SharedInboxStore] App Group container unavailable for '%@'", appGroupIdentifier)
            #endif
            return nil
        }
        let dir = container.appendingPathComponent("PendingShares", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Write (Share Extension side)

    /// Copies an incoming file (from `NSItemProvider.loadFileRepresentation`) into
    /// its own subdirectory in the inbox, preserving the original filename and
    /// bytes (and therefore all source metadata).
    ///
    /// - Parameter sourceURL: The ephemeral file URL handed to the extension.
    /// - Returns: The destination URL inside the inbox, or `nil` on failure.
    @discardableResult
    public static func copy(from sourceURL: URL) -> URL? {
        guard let dir = inboxDirectory() else { return nil }
        let itemDir = dir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filename = sourceURL.lastPathComponent.isEmpty ? "shared.dat" : sourceURL.lastPathComponent
        let dest = itemDir.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            #if DEBUG
            inboxLog.info("Wrote shared item to inbox: \(dest.path, privacy: .public)")
            #endif
            return dest
        } catch {
            #if DEBUG
            inboxLog.error("Failed to copy incoming file: \(error.localizedDescription, privacy: .public)")
            #endif
            try? FileManager.default.removeItem(at: itemDir)
            return nil
        }
    }

    // MARK: - Read (App side)

    /// All pending shared files, sorted oldest-first (by item-directory creation
    /// date) so the app loads them in the order they were shared.
    public static func pendingURLs() -> [URL] {
        guard let dir = inboxDirectory() else { return [] }
        let itemDirs = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles])) ?? []

        let sorted = itemDirs.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return l < r
        }

        let files = sorted.compactMap { itemDir in
            (try? FileManager.default.contentsOfDirectory(
                at: itemDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]))?.first
        }
        #if DEBUG
        inboxLog.info("pendingURLs: \(files.count, privacy: .public) item(s) in \(dir.path, privacy: .public)")
        #endif
        return files
    }

    /// Whether any shared media is waiting to be imported.
    public static var hasPending: Bool { !pendingURLs().isEmpty }

    /// Removes a shared item from the inbox after the app has copied it into its
    /// own sandbox. Deletes the enclosing UUID subdirectory (never the inbox root).
    public static func remove(_ url: URL) {
        guard let inbox = inboxDirectory() else { return }
        let itemDir = url.deletingLastPathComponent()
        guard itemDir.path != inbox.path else { return }
        try? FileManager.default.removeItem(at: itemDir)
    }

    /// Removes every pending item. Used to recover from a stuck inbox.
    public static func clearAll() {
        guard let dir = inboxDirectory() else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
