import Foundation

/// Manages temporary file creation and cleanup in the app's caches directory.
///
/// Uses UUID-based filenames to prevent predictable temp file paths (threat T-01-04).
/// Temp files are created in `FileManager.default.cachesDirectory`.
/// The engine writes watermarked output to temp files, which are cleaned up
/// after sharing or on next engine initialization.
public struct TempFileManager {

    /// Creates a unique temp file URL with the correct extension for the source UTI.
    ///
    /// - Parameter uti: Source format UTI as CFString (e.g., "public.heic")
    /// - Returns: URL to the new temp file (file does not exist yet)
    /// - Throws: If caches directory is not accessible
    public static func createTempFile(uti: CFString) throws -> URL {
        let cachesDir = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let filename = "watermark_\(UUID().uuidString).\(FormatDetector.fileExtension(for: uti))"
        return cachesDir.appendingPathComponent(filename)
    }

    /// Removes a temp file at the given URL.
    ///
    /// Silently ignores if the file doesn't exist (already cleaned up).
    /// - Parameter url: The temp file URL to remove
    public static func cleanup(url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Removes stale temp files older than the specified age.
    ///
    /// Called on engine initialization to prevent temp file accumulation (T-01-04).
    /// - Parameter age: Maximum age in seconds (default: 3600 = 1 hour)
    public static func cleanupOldFiles(olderThan age: TimeInterval = 3600) throws {
        let cachesDir = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let contents = try FileManager.default.contentsOfDirectory(
            at: cachesDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        let cutoff = Date().addingTimeInterval(-age)
        for url in contents where url.lastPathComponent.hasPrefix("watermark_") {
            let attrs = try? url.resourceValues(forKeys: [.creationDateKey])
            if let created = attrs?.creationDate, created < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
