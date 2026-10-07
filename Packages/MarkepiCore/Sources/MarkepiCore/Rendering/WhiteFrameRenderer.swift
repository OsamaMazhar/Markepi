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
private let frameLog = Logger.markepi("WhiteFrame")
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
///   1. Take the mat thickness from `FrameGeometry` (millimetres at the
///      export's resolution)
///   2. Draw full white rect over entire extent, then cut transparent inner area
///      using `.clear` blend mode (per D-04: uniform border, not solid fill)
///   3. Optionally render metadata attribution text centered on bottom frame
///   4. Convert rendered image to CIImage for compositing
///
/// Uses `UIGraphicsImageRenderer` with `.extended` preferredRange on iOS for
/// HDR compatibility. On macOS (swift test), uses a CGContext-based fallback
/// that produces equivalent pixel output for structural testing.
public struct WhiteFrameRenderer {

    /// How heavy one run of caption text is drawn.
    ///
    /// A style-level idea rather than a `UIFont.Weight`/`NSFont.Weight`, so the
    /// resolved caption model stays one type on both render paths. The case
    /// names deliberately match the platform ones.
    enum CaptionWeight {
        case regular, medium, semibold
    }

    /// A stretch of caption text at one weight.
    ///
    /// A line is an array of these. Only `print`'s credit line needs more than
    /// one — "Shot on " regular, the device model bold — and it stays a narrow
    /// primitive rather than a general rich-text caption system until some
    /// future style actually needs one.
    struct CaptionRun: Equatable {
        var text: String
        var weight: CaptionWeight

        init(_ text: String, weight: CaptionWeight = .regular) {
            self.text = text
            self.weight = weight
        }
    }

    /// The two centred lines `print` draws, resolved against metadata.
    ///
    /// The credit line is fixed by the style, not user-configurable; the detail
    /// line is the maker's name followed by the fields the user ticked. Every
    /// part is optional: no device model drops the credit line, no maker drops
    /// just the name, and nothing resolvable at all drops the caption.
    struct ResolvedCreditCaption {
        /// "Shot on " plus the device model, the model drawn heavier. Empty
        /// when the photo names no device at all.
        var credit: [CaptionRun] = []
        /// The maker's name and the selected shooting details, space-joined.
        var details: String?

        var isEmpty: Bool { credit.isEmpty && details == nil }

        /// The lines to draw, skipping whichever half has nothing to say.
        var lines: [[CaptionRun]] {
            var out: [[CaptionRun]] = []
            if !credit.isEmpty { out.append(credit) }
            if let details { out.append([CaptionRun(details)]) }
            return out
        }
    }

    /// Builds the centred credit caption.
    ///
    /// The maker's name sits at the head of the *second* line rather than
    /// trailing the model on the first: "Shot on iPhone 15 Pro Max Apple" and
    /// "Shot on ILCE-7M4 Sony" both read badly, and for Apple devices the model
    /// already carries the brand.
    static func resolveCreditCaption(
        config: WhiteFrameConfig,
        metadata: [String: Any]
    ) -> ResolvedCreditCaption {
        guard config.metadataTextEnabled else { return ResolvedCreditCaption() }

        // No device model means no "Shot on" at all — with nothing after it,
        // it is worse than silence. The user's own text still stands on its
        // own, which is what lets a photo with no metadata still be signed.
        // Through the Include list like every other entry: unticking the
        // camera drops "Shot on" too, rather than leaving the one place in the
        // app where that checkbox does not mean what it says.
        let model = config.captionFields.contains(.cameraModel)
            ? resolveField(.cameraModel, metadata: metadata)
            : nil
        let credit = creditRuns(config: config, model: model, metadata: metadata)

        // The credit line already names the device, so drop the camera field
        // from the detail line rather than printing it twice.
        let ticked = config.captionFields
        let fields = credit.isEmpty ? ticked : ticked.filter { $0 != .cameraModel }


        // The maker goes through the list like everything else. It used to be
        // pushed in front of the line as a prefix, which is why unticking every
        // entry still left "Apple" sitting on the mat.
        let details = DeviceMetadataProvider.caption(
            prefix: "",
            fields: fields,
            metadata: metadata,
            separator: runGap
        )

        return ResolvedCreditCaption(credit: credit, details: details.isEmpty ? nil : details)
    }

    /// The credit line: the user's own text, the device credit, and the user's
    /// own text again, in that order and each optional.
    ///
    /// The model stays the only emphasised run. A signature set as heavy as the
    /// device it sits beside gives the line two focal points and neither reads.
    private static func creditRuns(
        config: WhiteFrameConfig,
        model: String?,
        metadata: [String: Any]
    ) -> [CaptionRun] {
        /// Substituted like any other caption text, so "© {date}" resolves.
        func typed(_ text: String) -> String? {
            let resolved = EXIFTokenParser.substitute(text, metadata: metadata)
                .trimmingCharacters(in: .whitespaces)
            return resolved.isEmpty ? nil : resolved
        }

        // One space. The detail line below joins its fields with three, but
        // that is a list of separate readings; this is one phrase with a name
        // attached to it, and a wide gap made it read as two captions.
        let gap = " "
        var runs: [CaptionRun] = []
        if let prefix = typed(config.creditPrefixText) {
            runs.append(CaptionRun(prefix))
        }
        if let model {
            runs.append(CaptionRun(runs.isEmpty ? "Shot on " : gap + "Shot on "))
            runs.append(CaptionRun(model, weight: .semibold))
        }
        if let suffix = typed(config.creditSuffixText) {
            runs.append(CaptionRun(runs.isEmpty ? suffix : gap + suffix))
        }
        return runs
    }

    /// What separates one reading from the next on a caption line.
    static let runGap = "   "

    /// One field's value, or nil when it has nothing to say.
    ///
    /// - Parameter shown: every entry this caption is printing. Only the lens
    ///   reads it, to drop the readings its neighbours already carry.
    static func resolveField(_ field: CaptionField, metadata: [String: Any],
                             alongside shown: Set<CaptionField> = []) -> String? {
        if field.isPlace {
            return EXIFTokenParser.placeText(metadata: metadata, fields: shown.union([field]))
        }
        let raw = field == .lens
            ? EXIFTokenParser.lensText(metadata: metadata,
                                       omitFocal: shown.contains(.focalLength),
                                       omitAperture: shown.contains(.aperture))
            : EXIFTokenParser.substitute(field.token, metadata: metadata, gpsFormat: .place)
        // A missing EXIF field substitutes as "--" (D-08). Drop the
        // placeholders and keep whatever is left.
        let words = raw.split(separator: " ").filter { $0 != "--" }
        let cleaned = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Whether this frame's caption will draw anything at all.
    ///
    /// Callers build geometry before resolving content, so this lets the band
    /// collapse when there is nothing to put in it.
    public static func hasCaptionContent(config: WhiteFrameConfig, metadata: [String: Any]) -> Bool {
        switch config.style {
        case .classic:
            return resolveCaption(config: config, metadata: metadata) != nil
        case .print:
            return !resolveCreditCaption(config: config, metadata: metadata).isEmpty
        default:
            return !resolveRowCaption(config: config, metadata: metadata).isEmpty
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
    ///   - sourceImage: a small copy of the photo being framed. Read only by
    ///     the styles that take their colour or backdrop from it
    ///     (`FrameStyle.readsPhoto`); they fall back to a neutral surround
    ///     without it.
    /// - Returns: a `CIImage` of `geometry.framedSize` with a transparent
    ///   `photoRect`.
    /// - Throws: `PipelineError.frameRenderFailed` if image conversion fails
    public static func render(
        config: WhiteFrameConfig,
        geometry: FrameGeometry,
        metadata: [String: Any],
        scale: CGFloat = 1.0,
        sourceImage: CGImage? = nil
    ) throws -> CIImage {
        if config.style.isModern {
            return try renderModern(config: config, geometry: geometry,
                                    metadata: metadata, sourceImage: sourceImage)
        }
        let attributionText = resolveCaption(config: config, metadata: metadata)
        let row = config.style == .gallery || config.style == .banner
            ? resolveRowCaption(config: config, metadata: metadata)
            : ResolvedRowCaption()
        let credit = config.style == .print
            ? resolveCreditCaption(config: config, metadata: metadata)
            : ResolvedCreditCaption()

        #if canImport(UIKit)
        return try renderWithUIGraphics(
            geometry: geometry,
            attributionText: attributionText,
            row: row,
            credit: credit,
            config: config,
            scale: scale
        )
        #else
        return try renderWithCoreGraphics(
            geometry: geometry,
            attributionText: attributionText,
            row: row,
            credit: credit,
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
        scale: CGFloat = 1.0,
        sourceImage: CGImage? = nil
    ) throws -> CIImage {
        try render(
            config: config,
            geometry: FrameGeometry(
                config: config,
                sourceSize: sourceSize,
                dpi: FrameGeometry.resolveDPI(from: metadata, config: config, sourceSize: sourceSize),
                hasCaptionContent: hasCaptionContent(config: config, metadata: metadata)
            ),
            metadata: metadata,
            scale: scale,
            sourceImage: sourceImage
        )
    }

    /// The single caption line used by `classic`.
    ///
    /// The two-column styles use `resolveRowCaption`; `print` its credit.
    static func resolveCaption(config: WhiteFrameConfig, metadata: [String: Any]) -> String? {
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
        row: ResolvedRowCaption,
        credit: ResolvedCreditCaption,
        config: WhiteFrameConfig,
        scale: CGFloat
    ) throws -> CIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.preferredRange = .extended  // HDR compatibility

        let renderer = UIGraphicsImageRenderer(size: geometry.framedSize, format: format)
        let uiImage = renderer.image { ctx in
            drawFrame(cgContext: ctx.cgContext, geometry: geometry,
                      attributionText: attributionText, row: row,
                      credit: credit, config: config)
        }

        guard let cgImage = uiImage.cgImage else {
            throw PipelineError.frameRenderFailed
        }
        return applyingShadow(to: CIImage(cgImage: cgImage), geometry: geometry, config: config)
    }
    #endif

    // MARK: - macOS rendering path (Core Graphics fallback for swift test)

    #if !canImport(UIKit)
    private static func renderWithCoreGraphics(
        geometry: FrameGeometry,
        attributionText: String?,
        row: ResolvedRowCaption,
        credit: ResolvedCreditCaption,
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
                  attributionText: attributionText, row: row,
                  credit: credit, config: config)

        guard let cgImage = cgContext.makeImage() else {
            throw PipelineError.frameRenderFailed
        }
        return applyingShadow(to: CIImage(cgImage: cgImage), geometry: geometry, config: config)
    }
    #endif

    // MARK: - Shared drawing logic (platform-agnostic Core Graphics)

    /// How a style fills its mat: one flat tone, or a top-to-bottom gradient.
    ///
    /// A property a style picks rather than a branch drawn inline, so adding a
    /// style is choosing a fill instead of copying gradient code. Not
    /// user-configurable — each style commits to a look.
    enum MatFill: Equatable {
        case flat(CGColor)
        case graduated(top: CGColor, bottom: CGColor)

        /// The single tone every contrast decision is made against.
        ///
        /// For a gradient that is the *bottom*, not the midpoint: the mark
        /// tone and the secondary text tone are chosen down in the caption
        /// band, which is where the mat is darkest.
        var contrastTone: CGColor {
            switch self {
            case .flat(let color): return color
            case .graduated(_, let bottom): return bottom
            }
        }
    }

    /// The mat fill for a configuration.
    ///
    /// Takes the whole config rather than just the style because `gallery`'s
    /// mat is graduated or flat at the user's choice — that switch is the only
    /// thing that used to separate it from a second style of its own.
    static func matFill(for config: WhiteFrameConfig,
                        metrics: FrameMetrics = .reference) -> MatFill {
        switch config.style {
        case .classic, .print, .banner:
            return .flat(CGColor(gray: 1.0, alpha: 1.0))
        // The modern styles draw their own surround in `renderModern`; white
        // is only the tone their unused gallery-style contrast checks see.
        case .float, .tone, .swatch, .spine, .noir, .readout, .ambient, .aura,
             .blend, .emboss, .sunlight, .glow:
            return .flat(CGColor(gray: 1.0, alpha: 1.0))
        case .gallery:
            guard config.gradientEnabled else {
                // Plain white, the same mat `classic` and `print` use. It was
                // briefly the gradient's own bottom tone, on the reasoning that
                // extending the caption's ground kept every contrast decision
                // untouched — but that is a mid grey, and asked for a mat
                // without a gradient nobody means grey.
                return .flat(CGColor(gray: 1.0, alpha: 1.0))
            }
            return .graduated(top: CGColor(gray: metrics.matTopWhite, alpha: 1.0),
                              bottom: CGColor(gray: metrics.matBottomWhite, alpha: 1.0))
        }
    }

    /// The mat colour a configuration's contrast decisions are made against.
    ///
    /// Identical whether the mat is graduated or flat, which is why turning the
    /// gradient off needs no other change: the mark's tone and the secondary
    /// text tone were always chosen against the bottom of the mat.
    static func matColor(for config: WhiteFrameConfig,
                         metrics: FrameMetrics = .reference) -> CGColor {
        matFill(for: config, metrics: metrics).contrastTone
    }

    /// Fills `canvas` with a style's mat fill.
    private static func drawMat(_ fill: MatFill, in canvas: CGRect, cgContext: CGContext) {
        switch fill {
        case .flat(let color):
            cgContext.setFillColor(color)
            cgContext.fill(canvas)
        case .graduated(let top, let bottom):
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let gradient = CGGradient(colorsSpace: space,
                                            colors: [top, bottom] as CFArray,
                                            locations: [0, 1]) else {
                cgContext.setFillColor(bottom)
                cgContext.fill(canvas)
                return
            }
            cgContext.saveGState()
            cgContext.clip(to: canvas)
            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: canvas.minY),
                end: CGPoint(x: 0, y: canvas.maxY),
                options: []
            )
            cgContext.restoreGState()
        }
    }

    private static func drawFrame(
        cgContext: CGContext,
        geometry: FrameGeometry,
        attributionText: String?,
        row: ResolvedRowCaption,
        credit: ResolvedCreditCaption,
        config: WhiteFrameConfig
    ) {
        let canvas = CGRect(origin: .zero, size: geometry.framedSize)

        // 1. Fill the mat. Gallery grades from light at the top to darker at
        //    the bottom, which is what keeps a wide border from reading as
        //    dead space and seats the caption on a firmer ground. Every other
        //    style is flat.
        drawMat(matFill(for: config, metrics: geometry.metrics),
                in: canvas, cgContext: cgContext)

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
        //
        //    The drop shadow is NOT drawn here — it is applied to the finished
        //    mat in `applyingShadow`, after the platform branch. See there.
        switch config.style {
        case .classic:
            drawCentredCaption(cgContext: cgContext, geometry: geometry,
                               lines: attributionText.map { [[CaptionRun($0, weight: .medium)]] } ?? [],
                               config: config)
        case .print:
            drawCentredCaption(cgContext: cgContext, geometry: geometry,
                               lines: credit.lines, config: config)
        case .gallery, .banner:
            drawMatRow(cgContext: cgContext, geometry: geometry, caption: row, config: config)
        case .float, .tone, .swatch, .spine, .noir, .readout, .ambient, .aura,
             .blend, .emboss, .sunlight, .glow:
            break  // Routed to `renderModern` before this point.
        }
    }

    /// Casts `print`'s drop shadow onto the finished mat.
    ///
    /// Deliberately Core Image, and deliberately *after* the platform branch,
    /// rather than a `CGContext.setShadow` inside `drawFrame`.
    ///
    /// Core Graphics resolves a shadow offset against the context's base user
    /// space, and the two render paths do not agree on which way that space
    /// points — the UIKit renderer bakes its flip into the base, while the
    /// macOS path applies its own on top. The same offset therefore casts the
    /// shadow downwards on one and upwards on the other, and there is no way
    /// to verify both from one machine. Doing it here sidesteps the question:
    /// one code path, one coordinate space, identical output on both.
    ///
    /// Masked to where the mat is opaque, so the shadow can never darken the
    /// photograph itself — only the mat it is cast onto.
    static func applyingShadow(
        to mat: CIImage,
        geometry: FrameGeometry,
        config: WhiteFrameConfig
    ) -> CIImage {
        guard geometry.shadowBlur > 0 else { return mat }
        let canvas = CGRect(origin: .zero, size: geometry.framedSize)

        // `photoRect` is top-left origin; Core Image is bottom-left. Down the
        // page is therefore *minus* y here.
        let photo = CGRect(
            x: geometry.photoRect.minX,
            y: geometry.framedSize.height - geometry.photoRect.maxY,
            width: geometry.photoRect.width,
            height: geometry.photoRect.height
        )
        let caster = photo.offsetBy(dx: 0, dy: -geometry.shadowOffset)

        let shape = CIImage(color: CIColor(red: 0, green: 0, blue: 0,
                                           alpha: geometry.metrics.shadowOpacity))
            .cropped(to: caster)
        // Sigma is about half the blur radius, which is the usual reading of a
        // "blur radius" in a box shadow.
        let blurred = shape
            .applyingGaussianBlur(sigma: Double(geometry.shadowBlur) / 2)
            .cropped(to: canvas)

        // Keep the shadow only where the mat is opaque. The mat's hole is
        // transparent, so this is what stops the shadow washing over the photo.
        let onMatOnly = blurred.applyingFilter(
            "CISourceInCompositing",
            parameters: [kCIInputBackgroundImageKey: mat]
        )
        return onMatOnly.composited(over: mat).cropped(to: canvas)
    }

    /// `gallery`'s and `banner`'s caption: the standard row (`drawRow`), in the
    /// user's caption colour, with the brand mark at the user's size.
    ///
    /// Gallery centres it where `contentCentreOfBand` puts it, so the space
    /// beneath matches the mat on the other three sides; banner centres it on
    /// its bar, inset by one column gap since the bar runs edge to edge.
    private static func drawMatRow(
        cgContext: CGContext,
        geometry: FrameGeometry,
        caption: ResolvedRowCaption,
        config: WhiteFrameConfig
    ) {
        guard !caption.isEmpty else { return }
        let m = geometry.metrics
        let ink = config.textColor
        let sub = lighten(ink, towards: matColor(for: config, metrics: m), by: m.secondaryToneMix)
        let look = Look(surround: .flat(.white), ink: RGB(ink), sub: RGB(sub), tintsMark: false)

        let captionBand = geometry.captionBand
        let band: CGRect
        if config.style == .banner {
            let gap = geometry.captionFontSize * m.columnGapToFont
            band = CGRect(x: gap, y: captionBand.minY,
                          width: geometry.framedSize.width - gap * 2,
                          height: geometry.framedSize.height - captionBand.minY)
        } else {
            let centre = captionBand.minY + captionBand.height * m.contentCentreOfBand
            band = CGRect(x: captionBand.minX, y: centre - captionBand.height / 2,
                          width: captionBand.width, height: captionBand.height)
        }
        guard band.width > 0, band.height > 0 else { return }
        drawRow(cgContext, band: band, font: geometry.captionFontSize, caption: caption, look: look)
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

    /// A centred block of caption lines, sitting in the bottom mat.
    ///
    /// `classic` passes exactly one line and renders as it always has;
    /// `print` passes two. Each line is a list of runs, so one line can carry
    /// more than one weight — which is the only thing print's credit line
    /// needs that no earlier style did.
    private static func drawCentredCaption(
        cgContext: CGContext,
        geometry: FrameGeometry,
        lines: [[CaptionRun]],
        config: WhiteFrameConfig
    ) {
        guard !lines.isEmpty, geometry.bottom > 0 else { return }
        let textColor = platformColor(from: config.textColor)

        /// One line's runs, concatenated into a single drawable string.
        func makeAttributed(_ runs: [CaptionRun], fontSize size: CGFloat) -> NSAttributedString {
            let line = NSMutableAttributedString()
            for run in runs {
                line.append(NSAttributedString(string: run.text, attributes: [
                    .font: platformFont(ofSize: size, weight: run.weight),
                    .foregroundColor: textColor,
                ]))
            }
            return line
        }

        // Auto-shrink so a long shooting-details line fits the width instead of
        // clipping at the edges. One factor for the whole block, taken from the
        // widest line, so the lines keep their relative sizes.
        let maxTextWidth = geometry.framedSize.width * 0.94
        var attributed = lines.map { makeAttributed($0, fontSize: geometry.captionFontSize) }
        let widest = attributed.map { $0.size().width }.max() ?? 0
        if widest > maxTextWidth, widest > 0 {
            let shrunk = geometry.captionFontSize * (maxTextWidth / widest)
            attributed = lines.map { makeAttributed($0, fontSize: shrunk) }
        }

        // Stack the lines and centre the block on the band, so a one-line
        // caption lands exactly where it always did.
        let sizes = attributed.map { $0.size() }
        let interline = geometry.captionFontSize
            * geometry.metrics.linePitchToFont
            * geometry.metrics.interlineShareOfPitch
        let blockHeight = sizes.reduce(0) { $0 + $1.height }
            + interline * CGFloat(max(0, sizes.count - 1))

        let band = geometry.captionBand
        var y = band.midY - blockHeight / 2
        for (line, size) in zip(attributed, sizes) {
            let x = (geometry.framedSize.width - size.width) / 2
            drawLine(line, at: CGPoint(x: x, y: y), in: cgContext)
            y += size.height + interline
        }
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
    static func platformFont(ofSize size: CGFloat, weight: CaptionWeight) -> UIFont {
        let uiWeight: UIFont.Weight
        switch weight {
        case .regular: uiWeight = .regular
        case .medium: uiWeight = .medium
        case .semibold: uiWeight = .semibold
        }
        return UIFont.systemFont(ofSize: size, weight: uiWeight)
    }

    static func platformColor(from cgColor: CGColor) -> UIColor {
        return UIColor(cgColor: cgColor)
    }
    #elseif canImport(AppKit)
    static func platformFont(ofSize size: CGFloat, weight: CaptionWeight) -> NSFont {
        let nsWeight: NSFont.Weight
        switch weight {
        case .regular: nsWeight = .regular
        case .medium: nsWeight = .medium
        case .semibold: nsWeight = .semibold
        }
        return NSFont.systemFont(ofSize: size, weight: nsWeight)
    }

    static func platformColor(from cgColor: CGColor) -> NSColor {
        return NSColor(cgColor: cgColor) ?? NSColor.darkGray
    }
    #endif
}
