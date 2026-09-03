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

    /// The four gallery caption lines, already resolved against metadata, plus
    /// the brand mark the photo's manufacturer earned.
    ///
    /// Resolution happens once, before the platform branch, so both render
    /// paths draw from identical values — which is what keeps them in step.
    struct ResolvedGalleryCaption {
        var leftPrimary: String?
        var leftSecondary: String?
        var rightPrimary: String?
        var rightSecondary: String?
        var mark: BrandMarkArtwork?

        var hasText: Bool {
            leftPrimary != nil || leftSecondary != nil || rightPrimary != nil || rightSecondary != nil
        }
        var isEmpty: Bool { !hasText && mark == nil }
    }

    /// Resolves one slot, or nil when it has nothing to say.
    static func resolveSlot(_ slot: CaptionSlot, metadata: [String: Any]) -> String? {
        let raw: String
        switch slot {
        case .empty:
            return nil
        case .field(let field):
            raw = EXIFTokenParser.substitute(field.token, metadata: metadata)
        case .text(let text):
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            raw = EXIFTokenParser.substitute(text, metadata: metadata)
        }
        // A missing EXIF field substitutes as "--" (D-08). A line made only of
        // placeholders says nothing, and a line with some present values reads
        // better without the gaps — so drop the placeholders and keep the rest.
        let words = raw.split(separator: " ").filter { $0 != "--" }
        let cleaned = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func resolveGalleryCaption(
        config: WhiteFrameConfig,
        metadata: [String: Any]
    ) -> ResolvedGalleryCaption {
        guard config.metadataTextEnabled else { return ResolvedGalleryCaption() }
        let matIsLight = isLight(matColor(for: config.style))

        // Apple writes the device name into the lens string too ("iPhone 6s
        // back camera 4.15mm f/2.2"). With the device already on its own line,
        // repeating it wastes the band — the reference layout shows the lens
        // with that prefix dropped.
        let deviceName = resolveSlot(.field(.cameraModel), metadata: metadata)
        func trimmed(_ slot: CaptionSlot) -> String? {
            guard let text = resolveSlot(slot, metadata: metadata) else { return nil }
            guard let deviceName, text != deviceName,
                  text.lowercased().hasPrefix(deviceName.lowercased() + " ") else { return text }
            let stripped = String(text.dropFirst(deviceName.count)).trimmingCharacters(in: .whitespaces)
            return stripped.isEmpty ? text : stripped
        }

        return ResolvedGalleryCaption(
            leftPrimary: resolveSlot(config.leftPrimary, metadata: metadata),
            leftSecondary: trimmed(config.leftSecondary),
            rightPrimary: resolveSlot(config.rightPrimary, metadata: metadata),
            rightSecondary: trimmed(config.rightSecondary),
            mark: BrandMarkRegistry.mark(metadata: metadata,
                                         variant: config.logoVariant,
                                         matIsLight: matIsLight)
        )
    }

    /// Whether this frame's caption will draw anything at all.
    ///
    /// Callers build geometry before resolving content, so this lets the band
    /// collapse when there is nothing to put in it.
    public static func hasCaptionContent(config: WhiteFrameConfig, metadata: [String: Any]) -> Bool {
        switch config.style {
        case .classic:
            return resolveCaption(config: config, metadata: metadata) != nil
        case .gallery:
            return !resolveGalleryCaption(config: config, metadata: metadata).isEmpty
        }
    }

    /// Whether a mat is light enough that a dark mark reads on it.
    static func isLight(_ color: CGColor) -> Bool {
        let comps = color.components ?? [1]
        let luminance = comps.count >= 3
            ? 0.2126 * comps[0] + 0.7152 * comps[1] + 0.0722 * comps[2]
            : comps[0]
        return luminance > 0.5
    }

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
        let gallery = config.style == .gallery
            ? resolveGalleryCaption(config: config, metadata: metadata)
            : ResolvedGalleryCaption()

        #if canImport(UIKit)
        return try renderWithUIGraphics(
            geometry: geometry,
            attributionText: attributionText,
            gallery: gallery,
            config: config,
            scale: scale
        )
        #else
        return try renderWithCoreGraphics(
            geometry: geometry,
            attributionText: attributionText,
            gallery: gallery,
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
            geometry: FrameGeometry(
                config: config,
                sourceSize: sourceSize,
                dpi: FrameGeometry.resolveDPI(from: metadata, config: config),
                hasCaptionContent: hasCaptionContent(config: config, metadata: metadata)
            ),
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
        gallery: ResolvedGalleryCaption,
        config: WhiteFrameConfig,
        scale: CGFloat
    ) throws -> CIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.preferredRange = .extended  // HDR compatibility

        let renderer = UIGraphicsImageRenderer(size: geometry.framedSize, format: format)
        let uiImage = renderer.image { ctx in
            drawFrame(cgContext: ctx.cgContext, geometry: geometry,
                      attributionText: attributionText, gallery: gallery, config: config)
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
        gallery: ResolvedGalleryCaption,
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
                  attributionText: attributionText, gallery: gallery, config: config)

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
    static func matColor(for style: FrameStyle, metrics: FrameMetrics = .reference) -> CGColor {
        switch style {
        case .classic: return CGColor(gray: 1.0, alpha: 1.0)
        // The gallery mat is a gradient, and every contrast decision (mark
        // tone, secondary text) is made down in the caption band — so it is
        // the bottom tone that matters, not the midpoint.
        case .gallery: return CGColor(gray: metrics.matBottomWhite, alpha: 1.0)
        }
    }

    private static func drawFrame(
        cgContext: CGContext,
        geometry: FrameGeometry,
        attributionText: String?,
        gallery: ResolvedGalleryCaption,
        config: WhiteFrameConfig
    ) {
        let canvas = CGRect(origin: .zero, size: geometry.framedSize)

        // 1. Fill the mat. Gallery grades from light at the top to darker at
        //    the bottom, which is what keeps a wide border from reading as
        //    dead space and seats the caption on a firmer ground.
        switch config.style {
        case .classic:
            cgContext.setFillColor(matColor(for: config.style, metrics: geometry.metrics))
            cgContext.fill(canvas)
        case .gallery:
            let m = geometry.metrics
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let gradient = CGGradient(
                colorsSpace: space,
                colors: [CGColor(gray: m.matTopWhite, alpha: 1),
                         CGColor(gray: m.matBottomWhite, alpha: 1)] as CFArray,
                locations: [0, 1]
            ) {
                cgContext.saveGState()
                cgContext.clip(to: canvas)
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: canvas.minY),
                    end: CGPoint(x: 0, y: canvas.maxY),
                    options: []
                )
                cgContext.restoreGState()
            } else {
                cgContext.setFillColor(matColor(for: config.style, metrics: m))
                cgContext.fill(canvas)
            }
        }

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
            drawGalleryCaption(cgContext: cgContext, geometry: geometry,
                               content: gallery, config: config)
        }
    }

    /// The gallery caption: two stacked lines on the left, a brand mark, a
    /// divider rule, and two stacked lines on the right.
    ///
    /// Everything is measured from `geometry`, which is metric for this style,
    /// so the parts keep their relationship at any resolution.
    private static func drawGalleryCaption(
        cgContext: CGContext,
        geometry: FrameGeometry,
        content: ResolvedGalleryCaption,
        config: WhiteFrameConfig
    ) {
        guard !content.isEmpty else { return }

        let band = geometry.captionBand
        let fontSize = geometry.captionFontSize
        let m = geometry.metrics
        let pitch = fontSize * m.linePitchToFont
        let interlineGap = pitch * m.interlineShareOfPitch
        let lineHeight = pitch - interlineGap
        let gap = fontSize * m.columnGapToFont

        // The reference pairs a heavy dark line with a lighter grey one. The
        // secondary tone is derived from the user's caption colour rather than
        // hardcoded, so a recoloured caption keeps the contrast.
        let primaryColor = config.textColor
        let secondaryColor = lighten(config.textColor,
                                     towards: matColor(for: config.style, metrics: m),
                                     by: m.secondaryToneMix)

        // Tone marks the primary line; weight is applied only where the
        // metrics ask for it, so the card keeps a single focal point.
        func attributed(_ text: String, size: CGFloat, primary: Bool, bold: Bool) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: platformFont(ofSize: size, weight: bold ? .semibold : .regular),
                .foregroundColor: platformColor(from: primary ? primaryColor : secondaryColor),
            ])
        }

        /// One column of up to two stacked lines.
        struct Column {
            var primary: NSAttributedString?
            var secondary: NSAttributedString?
            var width: CGFloat { max(primary?.size().width ?? 0, secondary?.size().width ?? 0) }
            var isEmpty: Bool { primary == nil && secondary == nil }
        }

        func column(_ primaryText: String?, _ secondaryText: String?,
                    size: CGFloat, boldPrimary: Bool) -> Column {
            Column(primary: primaryText.map { attributed($0, size: size, primary: true, bold: boldPrimary) },
                   secondary: secondaryText.map { attributed($0, size: size, primary: false, bold: false) })
        }

        // Mark first: it takes its width from a metric height, and the columns
        // divide what is left.
        var markWidth: CGFloat = 0
        var markSize = CGSize.zero
        if let mark = content.mark {
            let height = min(geometry.logoHeight, band.height - fontSize * 0.6)
            let width = height * mark.aspectRatio
            // A 10:1 wordmark would otherwise crowd out the caption entirely.
            let maxWidth = band.width * m.markMaxWidthOfBand
            markSize = width > maxWidth
                ? CGSize(width: maxWidth, height: maxWidth / mark.aspectRatio)
                : CGSize(width: width, height: height)
            markWidth = markSize.width + gap
        }

        let dividerWidth = max(1, (fontSize * m.dividerWidthToFont).rounded())
        let hasDivider = content.mark != nil && (content.rightPrimary != nil || content.rightSecondary != nil)
        let dividerSpace = hasDivider ? dividerWidth + gap : 0

        // Each column gets half of what the mark and divider leave. Shrinking
        // is per column, so one long lens string does not shrink the device
        // name across the band from it.
        let available = max(0, band.width - markWidth - dividerSpace - gap)
        var left = column(content.leftPrimary, content.leftSecondary,
                          size: fontSize, boldPrimary: true)
        var right = column(content.rightPrimary, content.rightSecondary,
                           size: fontSize, boldPrimary: m.emphasiseRightPrimary)

        let leftAllowance = right.isEmpty ? available : available * 0.5
        let rightAllowance = left.isEmpty ? available : available * 0.5
        if left.width > leftAllowance, left.width > 0 {
            left = column(content.leftPrimary, content.leftSecondary,
                          size: fontSize * (leftAllowance / left.width), boldPrimary: true)
        }
        if right.width > rightAllowance, right.width > 0 {
            right = column(content.rightPrimary, content.rightSecondary,
                           size: fontSize * (rightAllowance / right.width),
                           boldPrimary: m.emphasiseRightPrimary)
        }

        /// Draws a column, returning the block height it occupied.
        func draw(_ col: Column, x: (NSAttributedString) -> CGFloat, top: CGFloat) {
            var y = top
            if let primary = col.primary {
                drawLine(primary, at: CGPoint(x: x(primary), y: y), in: cgContext)
                y += lineHeight + interlineGap
            }
            if let secondary = col.secondary {
                drawLine(secondary, at: CGPoint(x: x(secondary), y: y), in: cgContext)
            }
        }

        func blockHeight(_ col: Column) -> CGFloat {
            let lines = (col.primary != nil ? 1 : 0) + (col.secondary != nil ? 1 : 0)
            guard lines > 0 else { return 0 }
            return CGFloat(lines) * lineHeight + CGFloat(lines - 1) * interlineGap
        }

        let tallest = max(blockHeight(left), blockHeight(right), markSize.height)
        // Sits above the band's centre, per `contentCentreOfBand`: the gap left
        // beneath the caption then matches the mat on the other three sides.
        let contentCentre = band.minY + band.height * m.contentCentreOfBand
        let blockTop = contentCentre - tallest / 2

        // Left column hugs the left edge of the band.
        draw(left, x: { _ in band.minX }, top: blockTop + (tallest - blockHeight(left)) / 2)

        // Right column hugs the right edge; the mark and divider sit before it.
        let rightEdge = band.maxX
        draw(right, x: { rightEdge - $0.size().width },
             top: blockTop + (tallest - blockHeight(right)) / 2)

        let rightBlockWidth = right.width
        var cursor = rightEdge - rightBlockWidth
        if hasDivider {
            cursor -= gap
            let dividerHeight = max(blockHeight(right) * m.dividerHeightToBlock, markSize.height * 0.8)
            let dividerRect = CGRect(x: cursor - dividerWidth,
                                     y: contentCentre - dividerHeight / 2,
                                     width: dividerWidth, height: dividerHeight)
            cgContext.setFillColor(platformColor(from: secondaryColor).cgColor)
            cgContext.fill(dividerRect)
            cursor -= dividerWidth + gap
        } else if content.mark != nil {
            cursor -= gap
        }

        if let mark = content.mark {
            let markRect = CGRect(x: cursor - markSize.width,
                                  y: contentCentre - markSize.height / 2,
                                  width: markSize.width, height: markSize.height)
            mark.draw(in: markRect, context: cgContext)
        }
    }

    /// Moves a colour part-way towards another — used to derive the secondary
    /// caption tone from the primary one and the mat behind it.
    static func lighten(_ color: CGColor, towards target: CGColor, by amount: CGFloat) -> CGColor {
        // Both sides must be in the same space first. `CGColor(gray:alpha:)`
        // has two components, so the old `count >= 3` guard silently returned
        // the colour untouched — which is why the secondary caption line came
        // out identical to the primary instead of a lighter grey.
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let a = color.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components,
              let b = target.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components,
              a.count >= 3, b.count >= 3 else { return color }
        func mix(_ i: Int) -> CGFloat { a[i] + (b[i] - a[i]) * amount }
        return CGColor(colorSpace: sRGB,
                       components: [mix(0), mix(1), mix(2), a.count > 3 ? a[3] : 1]) ?? color
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
