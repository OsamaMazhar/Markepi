import CoreImage
import Foundation

/// Renders a white frame border with device metadata text as a CIImage
/// via UIGraphicsImageRenderer → Core Image bridge.
///
/// The white frame is a uniform 4-sided border with proportional width
/// (3-5% of the shorter image dimension per D-05) and optional centered
/// "Taken by: [Device Model]" attribution text on the bottom frame (D-06).
///
/// Pipeline:
///   1. Calculate frame width from baseExtent shorter dimension × frameWidthRatio
///   2. Draw full white rect over entire extent, then cut transparent inner area
///   3. Optionally render metadata attribution text centered on bottom frame
///   4. Convert rendered UIImage to CIImage for compositing
///
/// Uses `UIGraphicsImageRenderer` with `.extended` preferredRange for HDR
/// compatibility. Output is a full-extent CIImage (baseExtent.size) with
/// white border + transparent center.
public struct WhiteFrameRenderer {

    /// Renders a white frame border with optional metadata text.
    ///
    /// - Parameters:
    ///   - config: White frame configuration (isEnabled, frameWidthRatio, text settings)
    ///   - baseExtent: The base image extent (determines frame dimensions)
    ///   - metadata: Source image metadata dictionary with String keys (for device model extraction)
    ///   - scale: Display scale factor for Retina/HDR rendering (default: 1.0)
    /// - Returns: A CIImage with the white frame border + optional text
    /// - Throws: `PipelineError.frameRenderFailed` if rendering fails (RED stub)
    public static func render(
        config: WhiteFrameConfig,
        baseExtent: CGRect,
        metadata: [String: Any],
        scale: CGFloat = 1.0
    ) throws -> CIImage {
        // RED: stub — throws to fail tests until GREEN implementation
        throw PipelineError.frameRenderFailed
    }
}
