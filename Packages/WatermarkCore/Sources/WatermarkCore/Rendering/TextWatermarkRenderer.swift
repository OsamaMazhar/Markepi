import CoreImage
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders a text watermark as a CIImage using configurable fonts.
///
/// When `TextWatermarkInput.fontName` is nil, falls back to SF system font
/// at `.semibold` weight (backward-compatible).
///
/// When `fontName` is set, uses `FontRegistry.cascadingFont()` to load the
/// named font with cascade fallback to HelveticaNeue for missing glyphs
/// (recursive font support for multilingual text).
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
        // Empty text is allowed (no watermark text yet) — return a fully
        // transparent CIImage so compositing is a no-op. Without this guard,
        // `attributedTextImageGenerator` returns nil for empty input and
        // any caller force-unwrapping the result crashes with
        // "Unexpectedly found nil while unwrapping an Optional value".
        if config.text.isEmpty {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
                .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        // Build the attributed string with SF system font (D-02)
        let attributes = buildAttributes(config: config)
        let attributed = NSAttributedString(string: config.text, attributes: attributes)

        // Use CIAttributedTextImageGenerator to create a CIImage
        // This stays within Core Image's lazy filter graph (Pattern 1)
        let filter = CIFilter.attributedTextImageGenerator()
        filter.text = attributed
        filter.scaleFactor = 1.0

        guard let textImage = filter.outputImage else {
            // Filter can return nil for edge-case attribute sets (e.g. nil
            // font). Return a transparent 1×1 image so compositing stays safe.
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
                .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        // CRITICAL: `attributedTextImageGenerator` always emits an extended-GRAY
        // CIImage regardless of the foreground color. The previous code "promoted"
        // it by copying the gray luminance into R, G and B — which forces R==G==B,
        // i.e. grey, for ANY non-white color (red's luminance ≈ 0.2 → dark grey).
        // Instead, draw the glyphs white (a clean coverage mask) and shape a SOLID
        // color image by the text's alpha. This applies the chosen color exactly,
        // preserves anti-aliasing, and yields an RGB image so compositing keeps
        // the color (same technique as SignatureRenderer).
        let rgbImage = tint(textImage, color: config.color, opacity: config.opacity)

        // CRITICAL: `attributedTextImageGenerator`'s output extent matches
        // the font's typographic line bounds (ascent + descent + leading),
        // NOT the visible glyph bounds. When the watermark is positioned
        // at a corner, the extent bottom/right is placed at `padding` from
        // the image edge — but the visible glyph bottom/right sits ABOVE/
        // LEFT of the extent edge by `descent` (and `leading` above). This
        // makes the visible vertical spacing from the bottom edge larger
        // than the visible horizontal spacing from the right edge — the
        // text appears off-center toward the corner.
        //
        // Crop the extent to just the visible glyph bounds using the
        // font's actual ascent/descent metrics. This makes the CIImage
        // extent match what the eye sees, so positioning math produces
        // equal visible spacing on all sides.
        return cropToVisibleGlyphBounds(rgbImage, attributes: attributes)
    }

    /// Colors a white glyph-coverage image by masking a solid color with the
    /// text's alpha, then applies element opacity. Produces correctly-colored,
    /// anti-aliased text in an RGB color space.
    private static func tint(_ textImage: CIImage, color: CGColor, opacity: CGFloat) -> CIImage {
        let solid = CIImage(color: CIColor(cgColor: color)).cropped(to: textImage.extent)
        let masked = CIFilter.sourceInCompositing()
        masked.inputImage = solid          // foreground: solid text color
        masked.backgroundImage = textImage // shape/alpha: the rendered glyphs
        let colored = masked.outputImage ?? textImage

        guard opacity < 1.0 else { return colored }
        let alpha = CIFilter.colorMatrix()
        alpha.inputImage = colored
        alpha.aVector = CIVector(x: 0, y: 0, z: 0, w: opacity)
        return alpha.outputImage ?? colored
    }

    /// Crops the text CIImage to just the visible glyph bounds using the
    /// font's actual ascent/descent metrics.
    ///
    /// `attributedTextImageGenerator` produces an extent that includes
    /// typographic line metrics (leading above, descent below). For
    /// watermark positioning, we want the extent to match the visible
    /// glyphs so that `padding` produces equal visible spacing on all
    /// sides of the image.
    private static func cropToVisibleGlyphBounds(
        _ image: CIImage,
        attributes: [NSAttributedString.Key: Any]
    ) -> CIImage {
        #if canImport(UIKit)
        guard let font = attributes[.font] as? UIFont else { return image }
        #elseif canImport(AppKit)
        guard let font = attributes[.font] as? NSFont else { return image }
        #endif

        // The attributedTextImageGenerator output extent starts at (0, -leading)
        // with height = ascent + descent + leading. The visible glyphs occupy
        // (0, descent) to (width, ascent + descent) within this extent
        // (CIImage bottom-left origin: y=descent is the baseline, y=ascent+descent
        // is the top of capital letters). The space y=0 to y=descent below the
        // baseline is empty for text with no descenders (e.g. "Osama").
        //
        // Crop to the visible glyph region starting at the baseline, then
        // translate the image so the extent bottom aligns with the visible
        // glyph bottom. This ensures corner-positioning padding produces equal
        // visible spacing on all sides of the image.
        let extent = image.extent
        let ascent = font.ascender
        let descent = abs(font.descender)

        // Skip if the font metrics are zero/invalid — fallback to original
        guard ascent > 0, descent > 0 else { return image }

        // Baseline position in the extent coordinate space
        let baselineY = extent.origin.y + descent
        let visibleHeight = ascent

        // Guard against invalid rect before cropping
        guard visibleHeight > 0,
              baselineY + visibleHeight <= extent.origin.y + extent.height + 0.5 else {
            return image
        }

        let visibleRect = CGRect(
            x: extent.origin.x,
            y: baselineY,
            width: extent.width,
            height: visibleHeight
        )

        let cropped = image.cropped(to: visibleRect)

        // Translate the cropped image down by baselineY so the extent origin
        // becomes (0, 0). After this, the visible glyph bottom (the baseline)
        // sits at the extent's bottom edge, and corner-positioning padding
        // calculations produce equal visible spacing.
        let adjusted = cropped.transformed(by: CGAffineTransform(translationX: 0, y: -baselineY))
        return adjusted
    }

    /// Renders a text watermark with EXIF token substitution applied to the text string.
    /// Token substitution happens BEFORE NSAttributedString creation per D-07.
    /// - Parameters:
    ///   - config: Text watermark configuration (text may contain {tokens})
    ///   - metadata: Source image metadata dictionary (for token resolution via EXIFTokenParser)
    /// - Returns: A CIImage with token-substituted text rendered at the configured position
    public static func render(config: TextWatermarkInput, metadata: [String: Any]) -> CIImage {
        let substitutedText = EXIFTokenParser.substitute(config.text, metadata: metadata)
        let substitutedConfig = TextWatermarkInput(
            text: substitutedText,
            fontSize: config.fontSize,
            color: config.color,
            opacity: config.opacity,
            fontName: config.fontName
        )
        return render(config: substitutedConfig)
    }

    /// Builds the NSAttributedString attributes dictionary from watermark config.
    private static func buildAttributes(config: TextWatermarkInput) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail  // Prevent wrapping (Open Question #2)

        #if canImport(UIKit)
        let font: UIFont
        if let fontName = config.fontName,
           let watermarkFont = FontCatalog.font(byPostScriptName: fontName) {
            font = FontRegistry.font(for: watermarkFont, size: config.fontSize)
        } else if let fontName = config.fontName {
            font = FontRegistry.cascadingFont(
                primaryName: fontName,
                size: config.fontSize,
                fallbackNames: ["HelveticaNeue"],
                fallbackToSystemFont: true
            )
        } else {
            font = UIFont.systemFont(ofSize: config.fontSize, weight: .semibold)
        }
        // Draw white; the real color + opacity are applied via an alpha mask in
        // `tint(_:color:opacity:)` (the generator emits gray, so coloring here
        // would be lost). White gives the cleanest glyph coverage mask.
        let foregroundColor = UIColor.white
        #elseif canImport(AppKit)
        let font: NSFont
        if let fontName = config.fontName,
           let watermarkFont = FontCatalog.font(byPostScriptName: fontName) {
            font = FontRegistry.font(for: watermarkFont, size: config.fontSize)
        } else if let fontName = config.fontName {
            font = FontRegistry.cascadingFont(
                primaryName: fontName,
                size: config.fontSize,
                fallbackNames: ["HelveticaNeue"],
                fallbackToSystemFont: true
            )
        } else {
            font = NSFont.systemFont(ofSize: config.fontSize, weight: .semibold)
        }
        // Draw white; real color + opacity are applied via an alpha mask in tint().
        let foregroundColor = NSColor.white
        #endif

        return [
            .font: font,
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraphStyle,
        ]
    }
}
