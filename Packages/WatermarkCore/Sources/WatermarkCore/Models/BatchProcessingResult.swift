import Foundation

/// Result container for batch watermark processing operations.
///
/// Captures the outcome of a multi-item batch run: successfully processed
/// output URLs, per-item failure entries keyed by UUID, and the wall-clock
/// duration of the entire batch operation. This struct is lightweight and
/// Sendable-safe for crossing actor boundaries back to the UI layer.
public struct BatchProcessingResult: Sendable {
    /// Temp file URLs for successfully processed items (in submission order).
    public let successes: [URL]

    /// Per-item errors keyed by the item's UUID. Each entry represents
    /// a single item that failed during processing (any Error type).
    /// Remaining items continue processing even after individual failures.
    public let failures: [UUID: any Error]

    /// Wall-clock duration from first item start to last item completion,
    /// measured in seconds.
    public let duration: TimeInterval

    // MARK: - Computed Properties

    /// Number of successfully processed items.
    public var successCount: Int { successes.count }

    /// Number of items that failed during processing.
    public var failureCount: Int { failures.count }

    /// Total number of items processed (successes + failures).
    public var totalCount: Int { successes.count + failures.count }

    // MARK: - Init

    /// Creates a batch processing result.
    ///
    /// - Parameters:
    ///   - successes: Output temp file URLs for successful items
    ///   - failures: Per-item errors keyed by item UUID
    ///   - duration: Wall-clock batch duration in seconds
    public init(
        successes: [URL],
        failures: [UUID: any Error],
        duration: TimeInterval
    ) {
        self.successes = successes
        self.failures = failures
        self.duration = duration
    }
}
