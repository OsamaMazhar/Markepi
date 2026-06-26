import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders the retro date stamp — an amber, softly glowing date in a
/// monospaced face, mimicking an old film-camera databack.
///
/// Produces a self-contained CIImage (extent origin at `(0, 0)`) that the
/// engine scales and positions exactly like a text watermark, so the same
/// renderer feeds both the photo pipeline (`WatermarkEngine.buildFilterGraph`)
/// and the video pipeline (`VideoLayerBuilder`).
///
/// The date is taken from the source's capture date in `metadata`
/// (`{Exif}.DateTimeOriginal`, the same shape photos and videos both expose),
/// falling back to "now" so the stamp always appears when enabled.
public struct DateStampRenderer {

    /// Classic databack amber (#FF7A18).
    private static let amber = CGColor(red: 1.0, green: 0.478, blue: 0.094, alpha: 1.0)

    /// Base digit height the stamp is drawn at before the engine scales it to
    /// `sizeRatio × image dimension`. Large enough that the glow blur is smooth.
    private static let baseFontSize: CGFloat = 200

    /// Renders the date stamp, or returns `nil` when disabled or empty.
    ///
    /// - Parameters:
    ///   - config: The date-stamp configuration (enabled flag + format).
    ///   - metadata: Source metadata in the `{Exif}` shape used across the app.
    /// - Returns: A glowing amber date CIImage with origin at `(0, 0)`, or `nil`.
    public static func render(config: DateStampConfig, metadata: [String: Any]) -> CIImage? {
        guard config.isEnabled else { return nil }

        let date = captureDate(from: metadata) ?? Date()
        let text = string(for: date, format: config.format)
        guard !text.isEmpty else { return nil }

        // White glyph-coverage mask via the attributed-text generator (the
        // generator emits gray regardless of color, so we color it afterwards).
        #if canImport(UIKit)
        let font = UIFont.monospacedSystemFont(ofSize: baseFontSize, weight: .bold)
        let white = UIColor.white
        #elseif canImport(AppKit)
        let font = NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .bold)
        let white = NSColor.white
        #endif

        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: white,
        ])

        let generator = CIFilter.attributedTextImageGenerator()
        generator.text = attributed
        generator.scaleFactor = 1.0
        guard let rawMask = generator.outputImage, !rawMask.extent.isEmpty, !rawMask.extent.isInfinite else {
            return nil
        }

        // Crop the generator's typographic line box down to the visible glyph
        // ink so the size slider maps to the digit height, not the line height
        // (same technique as TextWatermarkRenderer).
        let mask = cropToInk(rawMask, attributed: attributed, font: font)

        // Color the coverage mask amber (solid amber kept only where glyphs are).
        let amberText = tint(mask, color: amber)

        // Soft warm glow: blur a copy, dim it, and sit the crisp text on top.
        let glowSigma = baseFontSize * 0.08
        let margin = glowSigma * 1.6
        let glowExtent = amberText.extent.insetBy(dx: -margin, dy: -margin)
        let blurred = amberText
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(glowSigma))
            .cropped(to: glowExtent)

        let dim = CIFilter.colorMatrix()
        dim.inputImage = blurred
        dim.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.55) // halo at ~55% alpha
        let glow = dim.outputImage ?? blurred

        let over = CIFilter.sourceOverCompositing()
        over.inputImage = amberText
        over.backgroundImage = glow
        let composed = (over.outputImage ?? amberText).cropped(to: glowExtent.integral)

        // Re-origin so the extent's bottom-left is (0, 0) — the contract the
        // engine's positioning/compositing assumes for watermark images.
        let origin = composed.extent.origin
        return composed.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
    }

    // MARK: - Helpers

    #if canImport(UIKit)
    private typealias PlatformFont = UIFont
    #elseif canImport(AppKit)
    private typealias PlatformFont = NSFont
    #endif

    /// Crops the generator's typographic line box to the visible glyph ink and
    /// re-origins to `(0, 0)`. Mirrors `TextWatermarkRenderer`'s glyph-bounds
    /// crop so positioning and sizing are based on what the eye sees.
    private static func cropToInk(
        _ image: CIImage,
        attributed: NSAttributedString,
        font: PlatformFont
    ) -> CIImage {
        let extent = image.extent
        let descent = abs(font.descender)
        guard descent.isFinite, extent.height > 0 else { return image }

        let line = CTLineCreateWithAttributedString(attributed)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard ink.height > 0, ink.width > 0 else { return image }

        // Baseline sits `descent` above the extent's bottom; ink origin is at the
        // baseline, so map ink into extent coordinates and crop.
        let cropY = extent.origin.y + descent + ink.minY
        guard cropY >= extent.origin.y - 1.0,
              cropY + ink.height <= extent.origin.y + extent.height + 1.0 else {
            return image
        }
        let visible = CGRect(x: extent.origin.x + max(0, ink.minX),
                             y: cropY, width: ink.width, height: ink.height)
        return image.cropped(to: visible)
            .transformed(by: CGAffineTransform(translationX: -(extent.origin.x + max(0, ink.minX)),
                                               y: -cropY))
    }

    /// Colors a white coverage mask by keeping a solid color only where the
    /// mask is opaque (matches the technique in `TextWatermarkRenderer`).
    private static func tint(_ mask: CIImage, color: CGColor) -> CIImage {
        let solid = CIImage(color: CIColor(cgColor: color)).cropped(to: mask.extent)
        let masked = CIFilter.sourceInCompositing()
        masked.inputImage = solid
        masked.backgroundImage = mask
        return masked.outputImage ?? mask
    }

    /// The capture date from `{Exif}.DateTimeOriginal` (EXIF "yyyy:MM:dd HH:mm:ss").
    /// Both the photo loader and `VideoProcessor` populate this key, so one path
    /// serves stills and video frames alike. Returns `nil` when absent.
    private static func captureDate(from metadata: [String: Any]) -> Date? {
        let exif = metadata["{Exif}"] as? [String: Any]
        let tiff = metadata["{TIFF}"] as? [String: Any]
        let raw = (exif?["DateTimeOriginal"] as? String)
            ?? (exif?["DateTimeDigitized"] as? String)
            ?? (exif?["DateTime"] as? String)
            ?? (tiff?["DateTime"] as? String)
        guard let raw else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.date(from: raw)
    }

    /// Formats `date` per the selected stamp format, uppercased so abbreviated
    /// month names (e.g. "JUN") read like a databack.
    private static func string(for date: Date, format: DateStampFormat) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format.dateFormat
        return f.string(from: date).uppercased()
    }
}
