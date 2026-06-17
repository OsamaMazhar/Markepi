import Foundation

/// Output result from the watermark processing pipeline.
///
/// Contains either a temp file URL (when output is written to disk) or an
/// in-memory Data buffer (when output is kept in memory). At least one of
/// `url` or `data` is always non-nil.
///
/// The `outputUTI` identifies the file format (e.g., "public.heic", "public.jpeg").
public struct ProcessingResult: Sendable {
    /// Temp file URL when output is written to disk (via TempFileManager)
    public let url: URL?

    /// In-memory data buffer when no file I/O is needed
    public let data: Data?

    /// Output format UTI (from source or explicit override)
    public let outputUTI: String

    public init(url: URL?, data: Data?, outputUTI: String) {
        self.url = url
        self.data = data
        self.outputUTI = outputUTI
    }
}
