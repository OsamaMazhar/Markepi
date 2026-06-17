import CoreImage
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders a text watermark as a CIImage using SF system fonts (D-02).
///
/// Uses `CIFilter.attributedTextImageGenerator()` to create a CIImage from
/// an `NSAttributedString`. This stays within Core Image's lazy filter graph
/// and preserves HDR-capable pixel formats.
///
/// Never uses UIImage in the rendering path — the output is a pure CIImage
/// ready for GPU compositing. The font objects are transient and used
/// only to build the attributed string.
///
/// Cross-platform: uses `UIFont` on iOS, `NSFont` on macOS (for testing).
public struct TextWatermarkRenderer {

    /// Renders a configured text watermark to a CIImage.
    ///
    /// - Parameter config: Text watermark configuration (text, font size, color, opacity)
    /// - Returns: A CIImage representing the rendered text
    ///
    /// Uses system font with `.semibold` weight per RESEARCH.md Pattern 1.
    /// Single-line text with `.byTruncatingTail` to prevent unexpected wrapping
    /// (per Open Question #2 in RESEARCH.md).
    public static func render(config: TextWatermarkInput) -> CIImage {
        // Build the attributed string with SF system font (D-02)
        let attributes = buildAttributes(config: config)
        let attributed = NSAttributedString(string: config.text, attributes: attributes)

        // Use CIAttributedTextImageGenerator to create a CIImage
        // This stays within Core Image's lazy filter graph (Pattern 1)
        let filter = CIFilter.attributedTextImageGenerator()
        filter.text = attributed
        filter.scaleFactor = 1.0

        // force-unwrap is safe per Apple docs: attributedTextImageGenerator always
        // produces output for valid input
        return filter.outputImage!
    }

    /// Builds the NSAttributedString attributes dictionary from watermark config.
    private static func buildAttributes(config: TextWatermarkInput) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail  // Prevent wrapping (Open Question #2)

        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: config.fontSize, weight: .semibold)
        let foregroundColor = UIColor(cgColor: config.color).withAlphaComponent(config.opacity)
        #elseif canImport(AppKit)
        let font = NSFont.systemFont(ofSize: config.fontSize, weight: .semibold)
        let foregroundColor = NSColor(cgColor: config.color)?.withAlphaComponent(config.opacity) ?? NSColor.white
        #endif

        return [
            .font: font,
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraphStyle,
        ]
    }
}
