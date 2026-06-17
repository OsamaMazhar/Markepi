/// Configuration for the white frame border overlay.
///
/// Full white frame rendering with border width, device metadata text, and
/// UIGraphicsImageRenderer pipeline is deferred to Plan 03. This stub exists
/// so the WatermarkConfiguration can reference white frame settings.
public struct WhiteFrameConfig: Sendable {
    /// Whether the white frame overlay is enabled
    public var isEnabled: Bool

    /// Creates a white frame configuration.
    /// - Parameter isEnabled: Whether to apply the white frame (default: false)
    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}
