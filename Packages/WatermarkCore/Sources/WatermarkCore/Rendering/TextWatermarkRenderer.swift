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
/// ready for GPU compositing. The `UIFont`/`NSFont` are transient and used
/// only to build the attributed string.
///
/// Cross-platform: uses `UIFont` on iOS, `NSFont` on macOS (for testing only).
public struct TextWatermarkRenderer {

    /// Renders a configured text watermark to a CIImage.
    ///
    /// - Parameter config: Text watermark configuration (text, font size, color, opacity)
    /// - Returns: A CIImage representing the rendered text
    ///
    /// Uses system font per D-02 (SF system fonts).
    /// Single-line text with `.byTruncatingTail` to prevent unexpected wrapping.
    public static func render(config: TextWatermarkInput) -> CIImage {
        // STUB — RED phase: empty CIImage, tests will fail
        return CIImage.empty()
    }

    /// Creates a platform-appropriate font for the given size.
    #if canImport(UIKit)
    private static func systemFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: weight)
    }
    #elseif canImport(AppKit)
    private static func systemFont(ofSize size: CGFloat, weight: CGFloat) -> NSFont {
        return NSFont.systemFont(ofSize: size, weight: NSFont.Weight(rawValue: weight))
    }
    #endif
}
