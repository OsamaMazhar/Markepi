import CoreImage
import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import CoreText
#endif

#if DEBUG
private let frameLog = Logger(subsystem: "com.watermark.core", category: "WhiteFrame")
#endif

/// Renders a white frame border with device metadata text as a CIImage
/// via UIGraphicsImageRenderer (iOS) / Core Graphics (macOS testing) →
/// Core Image bridge.
///
/// The white frame is a uniform 4-sided border with proportional width
/// (3-5% of the shorter image dimension per D-05) and optional centered
/// "Taken by: [Device Model]" attribution text on the bottom frame (D-06).
///
/// Pipeline:
///   1. Calculate frame width from baseExtent shorter dimension × frameWidthRatio
///   2. Draw full white rect over entire extent, then cut transparent inner area
///      using `.clear` blend mode (per D-04: uniform border, not solid fill)
///   3. Optionally render metadata attribution text centered on bottom frame
///   4. Convert rendered image to CIImage for compositing
///
/// Uses `UIGraphicsImageRenderer` with `.extended` preferredRange on iOS for
/// HDR compatibility. On macOS (swift test), uses a CGContext-based fallback
/// that produces equivalent pixel output for structural testing.
public struct WhiteFrameRenderer {

    /// Renders the mat that surrounds a photo, as a `CIImage` the size of the
    /// framed export with a transparent hole where the photo goes.
    ///
    /// The mat is drawn *outside* the photo: the returned image is larger than
    /// the source, and the caller composites the photo into `geometry.photoRect`
    /// underneath it. Nothing of the source is covered.
    ///
    /// - Parameters:
    ///   - config: frame configuration; `style` selects the mat shape.
    ///   - geometry: where the photo sits and how big the canvas is.
    ///   - metadata: source metadata, used to resolve the caption.
    ///   - scale: rendering scale for Retina/HDR output (default: 1.0)
    /// - Returns: a `CIImage` of `geometry.framedSize` with a transparent
    ///   `photoRect`.
    /// - Throws: `PipelineError.frameRenderFailed` if image conversion fails
    public static func render(
        config: WhiteFrameConfig,
        geometry: FrameGeometry,
        metadata: [String: Any],
        scale: CGFloat = 1.0
    ) throws -> CIImage {
        let attributionText = resolveCaption(config: config, metadata: metadata)

        #if canImport(UIKit)
        return try renderWithUIGraphics(
            geometry: geometry,
            attributionText: attributionText,
            config: config,
            scale: scale
        )
        #else
        return try renderWithCoreGraphics(
            geometry: geometry,
            attributionText: attributionText,
            config: config,
            scale: scale
        )
        #endif
    }

    /// Convenience for callers that only have a source size.
    public static func render(
        config: WhiteFrameConfig,
        sourceSize: CGSize,
        metadata: [String: Any],
        scale: CGFloat = 1.0
    ) throws -> CIImage {
        try render(
            config: config,
            geometry: FrameGeometry(config: config, sourceSize: sourceSize),
            metadata: metadata,
            scale: scale
        )
    }

    /// The single caption line used by `classic`.
    ///
    /// `gallery` builds its four slots separately; this stays the classic path
    /// so that style is untouched by the new layout.
    private static func resolveCaption(config: WhiteFrameConfig, metadata: [String: Any]) -> String? {
        guard config.metadataTextEnabled else { return nil }
        if let customText = config.customAttributionText, !customText.isEmpty {
            // Legacy/advanced verbatim override (with token substitution).
            return EXIFTokenParser.substitute(customText, metadata: metadata)
        }
        // Caption assembled from the user's prefix + ticked fields.
        // Empty (no prefix, no resolvable fields) → render nothing.
        let caption = DeviceMetadataProvider.caption(
            prefix: config.captionPrefix,
            fields: config.captionFields,
            metadata: metadata
        )
        return caption.isEmpty ? nil : caption
    }

    // MARK: - iOS rendering path (UIGraphicsImageRenderer)

    #if canImport(UIKit)
    private static func renderWithUIGraphics(
        geometry: FrameGeometry,
        attributionText: String?,
        config: WhiteFrameConfig,
        scale: CGFloat
    ) throws -> CIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.preferredRange = .extended  // HDR compatibility

        let renderer = UIGraphicsImageRenderer(size: geometry.framedSize, format: format)
        let uiImage = renderer.image { ctx in
            drawFrame(cgContext: ctx.cgContext, geometry: geometry,
                      attributionText: attributionText, config: config)
        }

        guard let cgImage = uiImage.cgImage else {
            throw PipelineError.frameRenderFailed
        }
        return CIImage(cgImage: cgImage)
    }
    #endif

    // MARK: - macOS rendering path (Core Graphics fallback for swift test)

    #if !canImport(UIKit)
    private static func renderWithCoreGraphics(
        geometry: FrameGeometry,
        attributionText: String?,
        config: WhiteFrameConfig,
        scale: CGFloat
    ) throws -> CIImage {
        let width = Int((geometry.framedSize.width * scale).rounded())
        let height = Int((geometry.framedSize.height * scale).rounded())

        guard let cgContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4 * width,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PipelineError.frameRenderFailed
        }

        // Flip to a top-left origin so the drawing code matches UIKit, and fold
        // the scale into the same transform so `drawFrame` can work in
        // unscaled coordinates on both platforms.
        cgContext.translateBy(x: 0, y: CGFloat(height))
        cgContext.scaleBy(x: scale, y: -scale)

        drawFrame(cgContext: cgContext, geometry: geometry,
                  attributionText: attributionText, config: config)

        guard let cgImage = cgContext.makeImage() else {
            throw PipelineError.frameRenderFailed
        }
        return CIImage(cgImage: cgImage)
    }
    #endif

    // MARK: - Shared drawing logic (platform-agnostic Core Graphics)

    /// The mat colour for a style.
    ///
    /// Not configurable: each style commits to a look. Classic is the white it
    /// has always been; gallery is the light grey the reference layout uses,
    /// which is what makes a dark caption and a colour mark read on it.
    static func matColor(for style: FrameStyle) -> CGColor {
        switch style {
        case .classic: return CGColor(gray: 1.0, alpha: 1.0)
        case .gallery: return CGColor(gray: 0.855, alpha: 1.0)
        }
    }

    private static func drawFrame(
        cgContext: CGContext,
        geometry: FrameGeometry,
        attributionText: String?,
        config: WhiteFrameConfig
    ) {
        let canvas = CGRect(origin: .zero, size: geometry.framedSize)

        // 1. Fill the whole canvas with the mat colour.
        cgContext.setFillColor(matColor(for: config.style))
        cgContext.fill(canvas)

        // 2. Punch a transparent hole for the photo. The caller composites the
        //    photo underneath, so the mat never covers any of it.
        cgContext.setBlendMode(.clear)
        cgContext.fill(geometry.photoRect)
        cgContext.setBlendMode(.normal)

        // 3. Keyline, stroked in the mat immediately outside the photo.
        if geometry.keylineWidth > 0 {
            cgContext.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            cgContext.setLineWidth(geometry.keylineWidth)
            cgContext.stroke(geometry.keylineRect)
        }

        // 4. Caption.
        switch config.style {
        case .classic:
            drawClassicCaption(cgContext: cgContext, geometry: geometry,
                               attributionText: attributionText, config: config)
        case .gallery:
            // Laid out in the two-column pass; see the gallery caption work.
            break
        }
    }

    /// Classic's single centred line, sitting in the bottom mat.
    private static func drawClassicCaption(
        cgContext: CGContext,
        geometry: FrameGeometry,
        attributionText: String?,
        config: WhiteFrameConfig
    ) {
        guard let text = attributionText, geometry.bottom > 0 else { return }
        let textColor = platformColor(from: config.textColor)

        func makeAttributed(fontSize size: CGFloat) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: platformFont(ofSize: size, weight: .medium),
                .foregroundColor: textColor,
            ])
        }

        // Auto-shrink so a long shooting-details line fits the width instead of
        // clipping at the edges.
        let maxTextWidth = geometry.framedSize.width * 0.94
        var attributed = makeAttributed(fontSize: geometry.captionFontSize)
        let naturalWidth = attributed.size().width
        if naturalWidth > maxTextWidth, naturalWidth > 0 {
            attributed = makeAttributed(fontSize: geometry.captionFontSize * (maxTextWidth / naturalWidth))
        }

        let textSize = attributed.size()
        let band = geometry.captionBand
        let textX = (geometry.framedSize.width - textSize.width) / 2
        let textY = band.midY - textSize.height / 2

        drawLine(attributed, at: CGPoint(x: textX, y: textY), in: cgContext)
    }

    /// Draws one already-styled line with its top-left at `origin`.
    ///
    /// The two platforms need different calls here, and getting the macOS one
    /// wrong is silent: the context is flipped to a top-left origin so frame
    /// rects match iOS, but glyph outlines are defined +y up, so without a
    /// matching text matrix the text renders upside-down and mirrored. Flip the
    /// text matrix back and position on the BASELINE (box top + ascent).
    static func drawLine(_ attributed: NSAttributedString, at origin: CGPoint, in cgContext: CGContext) {
        #if canImport(UIKit)
        attributed.draw(in: CGRect(origin: origin, size: attributed.size()))
        #else
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        cgContext.saveGState()
        cgContext.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        cgContext.textPosition = CGPoint(x: origin.x, y: origin.y + ascent)
        CTLineDraw(line, cgContext)
        cgContext.restoreGState()
        #endif
    }

    // MARK: - Cross-platform font/color helpers

    #if canImport(UIKit)
    private static func platformFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    private static func platformColor(from cgColor: CGColor) -> UIColor {
        return UIColor(cgColor: cgColor)
    }
    #elseif canImport(AppKit)
    private static func platformFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    private static func platformColor(from cgColor: CGColor) -> NSColor {
        return NSColor(cgColor: cgColor) ?? NSColor.darkGray
    }
    #endif
}
