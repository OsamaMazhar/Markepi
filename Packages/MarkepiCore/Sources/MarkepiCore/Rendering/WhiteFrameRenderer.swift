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
        let model = resolveSlot(included(.field(.cameraModel), config: config), metadata: metadata)
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

    /// The caption `banner` draws: a brand mark and a credit at the far left,
    /// the shooting values and the device at the far right.
    ///
    /// Every part is optional and each is dropped on its own, the same way
    /// `gallery` drops its mark: an unrecognised maker costs the left block,
    /// a photo with no shooting data costs the values line, and nothing at all
    /// costs the bar itself.
    struct ResolvedBannerCaption {
        /// The maker's name, set under the fixed lead-in.
        var maker: String?
        /// The shooting values, space-joined: focal length, aperture, speed, ISO.
        var values: String?
        /// The device and its lens.
        var device: String?
        var mark: BrandMarkArtwork?

        var isEmpty: Bool { maker == nil && values == nil && device == nil && mark == nil }
    }

    /// What separates one reading from the next on a detail line — and so
    /// where such a line may be broken when it outgrows its column.
    static let runGap = "   "

    /// The fixed lead-in above the maker's name.
    ///
    /// Not user-configurable, for the same reason `print`'s "Shot on" is not:
    /// it is the style's own wording, and the caption-prefix field would let
    /// the user set it twice.
    static let bannerLead = "Captured with"

    /// The fields that name the equipment rather than the exposure.
    ///
    /// They go on the second line, so the first can be the shooting values
    /// alone — which is what gives the bar its two distinct registers.
    static let bannerDeviceFields: [CaptionField] = [.cameraModel, .lens]

    /// Builds the bar's caption.
    static func resolveBannerCaption(
        config: WhiteFrameConfig,
        metadata: [String: Any]
    ) -> ResolvedBannerCaption {
        guard config.metadataTextEnabled else { return ResolvedBannerCaption() }

        // Resolved through the same path that picks the mark, so the name and
        // the logo beside it can never disagree — and gated by the list, so
        // unticking the brand takes the credit with it.
        let maker = config.captionFields.contains(.maker)
            ? BrandMarkRegistry.displayName(metadata: metadata)
            : nil

        func line(_ fields: [CaptionField], separator: String) -> String? {
            let text = DeviceMetadataProvider.caption(
                prefix: "", fields: fields, metadata: metadata, separator: separator)
            return text.isEmpty ? nil : text
        }

        // Both lines are driven by the user's ticked fields, so unticking the
        // camera empties the device line rather than leaving it stuck on.
        let ticked = config.captionFields
        let shown = Set(ticked)
        let valueFields = ticked.filter { !bannerDeviceFields.contains($0) }
        let deviceParts = bannerDeviceFields
            .filter { shown.contains($0) }
            .compactMap { resolveSlot(.field($0), metadata: metadata, alongside: shown) }

        return ResolvedBannerCaption(
            maker: maker,
            values: line(valueFields, separator: runGap),
            device: deviceParts.isEmpty ? nil : deviceParts.joined(separator: " • "),
            mark: config.logoEnabled
                ? BrandMarkRegistry.mark(metadata: metadata,
                                         variant: config.logoVariant,
                                         matIsLight: isLight(matColor(for: config)))
                : nil
        )
    }

    /// A slot the user has unticked in the Include list, emptied.
    ///
    /// The Include list is the master switch for what a frame may say, in every
    /// style. `gallery` then decides *where* each entry sits, which is a
    /// different question from whether it appears at all — untick Location and
    /// the line it was assigned to simply goes quiet. Free text is nobody's
    /// field and is never filtered.
    static func included(_ slot: CaptionSlot, config: WhiteFrameConfig) -> CaptionSlot {
        guard case .field(let field) = slot else { return slot }
        return config.captionFields.contains(field) ? slot : .empty
    }

    /// Resolves one slot, or nil when it has nothing to say.
    ///
    /// - Parameter shown: every entry this caption is printing. Only the lens
    ///   reads it, to drop the readings its neighbours already carry.
    static func resolveSlot(_ slot: CaptionSlot, metadata: [String: Any],
                            alongside shown: Set<CaptionField> = []) -> String? {
        let raw: String
        switch slot {
        case .empty:
            return nil
        case .field(.lens):
            raw = EXIFTokenParser.lensText(metadata: metadata,
                                           omitFocal: shown.contains(.focalLength),
                                           omitAperture: shown.contains(.aperture))
        case .field(let field):
            raw = EXIFTokenParser.substitute(field.token, metadata: metadata, gpsFormat: .place)
        case .text(let text):
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            raw = EXIFTokenParser.substitute(text, metadata: metadata, gpsFormat: .place)
        }
        // A missing EXIF field substitutes as "--" (D-08). A line made only of
        // placeholders says nothing, and a line with some present values reads
        // better without the gaps — so drop the placeholders and keep the rest.
        let words = raw.split(separator: " ").filter { $0 != "--" }
        let cleaned = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Which column an unplaced entry falls to: what the photograph *is* on
    /// the left — the device, when, and where — and what the camera was doing
    /// on the right, down to the file it wrote.
    ///
    /// The seam is the subject, not the source: under a device name the reader
    /// expects the place it was carried to, not its shutter speed, and the
    /// readings belong together in one column where they can be read as a row.
    static let galleryLeftFields: [CaptionField] = [.maker, .cameraModel, .date, .time, .gps]

    static func resolveGalleryCaption(
        config: WhiteFrameConfig,
        metadata: [String: Any]
    ) -> ResolvedGalleryCaption {
        guard config.metadataTextEnabled else { return ResolvedGalleryCaption() }
        let matIsLight = isLight(matColor(for: config))

        let shown = Set(config.captionFields)
        func slot(_ slot: CaptionSlot) -> String? {
            resolveSlot(included(slot, config: config), metadata: metadata, alongside: shown)
        }


        // Everything ticked that no slot already names. Without this a tick
        // was only visible when a slot happened to be assigned to that field,
        // so seven ticked entries could show as none — the four slots are
        // where an entry sits, not whether it appears.
        let named = Set([config.leftPrimary, config.leftSecondary,
                         config.rightPrimary, config.rightSecondary]
            .compactMap { slot -> CaptionField? in
                guard case .field(let field) = slot else { return nil }
                return field
            })
        let runOn = config.captionFields
        let spare = CaptionField.allCases.filter {
            runOn.contains($0) && !named.contains($0)
        }

        /// The ticked-but-unplaced fields for one column, run together.
        func spareLine(_ wanted: (CaptionField) -> Bool) -> String? {
            let parts = spare.filter(wanted).compactMap {
                resolveSlot(.field($0), metadata: metadata, alongside: shown)
            }
            return parts.isEmpty ? nil : parts.joined(separator: runGap)
        }
        /// A slot's own value with the spare fields run on after it.
        func line(_ assigned: String?, _ spare: String?) -> String? {
            let parts = [assigned, spare].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: runGap)
        }

        return ResolvedGalleryCaption(
            leftPrimary: slot(config.leftPrimary),
            leftSecondary: line(slot(config.leftSecondary),
                                spareLine(galleryLeftFields.contains)),
            rightPrimary: slot(config.rightPrimary),
            rightSecondary: line(slot(config.rightSecondary),
                                 spareLine { !galleryLeftFields.contains($0) }),
            mark: config.logoEnabled
                ? BrandMarkRegistry.mark(metadata: metadata,
                                         variant: config.logoVariant,
                                         matIsLight: matIsLight)
                : nil
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
        case .print:
            return !resolveCreditCaption(config: config, metadata: metadata).isEmpty
        case .banner:
            return !resolveBannerCaption(config: config, metadata: metadata).isEmpty
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
        let gallery = config.style.usesGalleryCaption
            ? resolveGalleryCaption(config: config, metadata: metadata)
            : ResolvedGalleryCaption()
        let credit = config.style == .print
            ? resolveCreditCaption(config: config, metadata: metadata)
            : ResolvedCreditCaption()
        let banner = config.style == .banner
            ? resolveBannerCaption(config: config, metadata: metadata)
            : ResolvedBannerCaption()

        #if canImport(UIKit)
        return try renderWithUIGraphics(
            geometry: geometry,
            attributionText: attributionText,
            gallery: gallery,
            credit: credit,
            banner: banner,
            config: config,
            scale: scale
        )
        #else
        return try renderWithCoreGraphics(
            geometry: geometry,
            attributionText: attributionText,
            gallery: gallery,
            credit: credit,
            banner: banner,
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
                dpi: FrameGeometry.resolveDPI(from: metadata, config: config, sourceSize: sourceSize),
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
        gallery: ResolvedGalleryCaption,
        credit: ResolvedCreditCaption,
        banner: ResolvedBannerCaption,
        config: WhiteFrameConfig,
        scale: CGFloat
    ) throws -> CIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.preferredRange = .extended  // HDR compatibility

        let renderer = UIGraphicsImageRenderer(size: geometry.framedSize, format: format)
        let uiImage = renderer.image { ctx in
            drawFrame(cgContext: ctx.cgContext, geometry: geometry,
                      attributionText: attributionText, gallery: gallery,
                      credit: credit, banner: banner, config: config)
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
        gallery: ResolvedGalleryCaption,
        credit: ResolvedCreditCaption,
        banner: ResolvedBannerCaption,
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
                  attributionText: attributionText, gallery: gallery,
                  credit: credit, banner: banner, config: config)

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
        gallery: ResolvedGalleryCaption,
        credit: ResolvedCreditCaption,
        banner: ResolvedBannerCaption,
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
        case .gallery:
            drawGalleryCaption(cgContext: cgContext, geometry: geometry,
                               content: gallery, config: config)
        case .print:
            drawCentredCaption(cgContext: cgContext, geometry: geometry,
                               lines: credit.lines, config: config)
        case .banner:
            drawBannerCaption(cgContext: cgContext, geometry: geometry,
                              content: banner, config: config)
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

    /// `text` broken across at most `limit` lines at its own separators.
    ///
    /// A detail line is a run of readings joined by `runGap`, so the gaps are
    /// where it may be broken — a reading is never split down the middle.
    /// Anything still over after the last line is left on it to be shrunk,
    /// which is what stops a band with room for two lines growing a third it
    /// cannot hold.
    ///
    /// Breaking rather than shrinking is the point: text scaled down to fit a
    /// fixed column never grows when the frame does, so the caption size could
    /// follow the mat and the readings would still look identical.
    static func wrappedRuns(
        _ text: String, width: CGFloat, limit: Int,
        measure: (String) -> CGFloat
    ) -> [String] {
        let parts = text.components(separatedBy: runGap)
        guard parts.count > 1, width > 0, limit > 1 else { return [text] }

        var lines: [String] = []
        var current = ""
        for part in parts {
            let candidate = current.isEmpty ? part : current + runGap + part
            // The last line takes whatever is left, however wide.
            if current.isEmpty || lines.count == limit - 1 || measure(candidate) <= width {
                current = candidate
            } else {
                lines.append(current)
                current = part
            }
        }
        lines.append(current)
        return lines
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
                                     towards: matColor(for: config, metrics: m),
                                     by: m.secondaryToneMix)

        // Tone marks the primary line; weight is applied only where the
        // metrics ask for it, so the card keeps a single focal point.
        func attributed(_ text: String, size: CGFloat, primary: Bool, bold: Bool) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: platformFont(ofSize: size, weight: bold ? .semibold : .regular),
                .foregroundColor: platformColor(from: primary ? primaryColor : secondaryColor),
            ])
        }

        /// One column of stacked lines, the first of them the heading.
        struct Column {
            var lines: [NSAttributedString] = []
            var width: CGFloat { lines.map { $0.size().width }.max() ?? 0 }
            var isEmpty: Bool { lines.isEmpty }
        }

        /// One line, set at the caption size, or shrunk on its own to fit the
        /// width its column is allowed.
        ///
        /// The last resort, not the first: a detail line too long for its
        /// column is broken onto another line before it is made smaller. Text
        /// shrunk to fit a fixed width never grows when the frame does, which
        /// is the whole reason the caption size follows the mat.
        func fitted(_ text: String, primary: Bool, bold: Bool, width: CGFloat) -> NSAttributedString {
            let drawn = attributed(text, size: fontSize, primary: primary, bold: bold)
            let natural = drawn.size().width
            guard natural > width, width > 0 else { return drawn }
            return attributed(text, size: fontSize * (width / natural), primary: primary, bold: bold)
        }

        func wrapped(_ text: String, width: CGFloat, limit: Int) -> [String] {
            wrappedRuns(text, width: width, limit: limit) {
                attributed($0, size: fontSize, primary: false, bold: false).size().width
            }
        }

        func column(_ primaryText: String?, _ secondaryText: String?,
                    boldPrimary: Bool, width: CGFloat, limit: Int) -> Column {
            var lines: [NSAttributedString] = []
            if let primaryText {
                lines.append(fitted(primaryText, primary: true, bold: boldPrimary, width: width))
            }
            if let secondaryText {
                let room = max(1, limit - lines.count)
                lines += wrapped(secondaryText, width: width, limit: room)
                    .map { fitted($0, primary: false, bold: false, width: width) }
            }
            return Column(lines: lines)
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
        let leftHasText = content.leftPrimary != nil || content.leftSecondary != nil
        let rightHasText = content.rightPrimary != nil || content.rightSecondary != nil
        let leftAllowance = rightHasText ? available * 0.5 : available
        let rightAllowance = leftHasText ? available * 0.5 : available

        // How many lines the band can actually hold at this size. The band is
        // a multiple of the mat, so a wider frame is what buys a caption the
        // room to break onto another line rather than shrink.
        let limit = max(2, Int(band.height / pitch))

        let left = column(content.leftPrimary, content.leftSecondary,
                          boldPrimary: true, width: leftAllowance, limit: limit)
        let right = column(content.rightPrimary, content.rightSecondary,
                           boldPrimary: m.emphasiseRightPrimary, width: rightAllowance, limit: limit)

        func draw(_ col: Column, x: (NSAttributedString) -> CGFloat, top: CGFloat) {
            var y = top
            for line in col.lines {
                drawLine(line, at: CGPoint(x: x(line), y: y), in: cgContext)
                y += lineHeight + interlineGap
            }
        }

        func blockHeight(_ col: Column) -> CGFloat {
            guard !col.lines.isEmpty else { return 0 }
            return CGFloat(col.lines.count) * lineHeight
                + CGFloat(col.lines.count - 1) * interlineGap
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

    /// The caption bar `banner` draws beneath a full-bleed photo.
    ///
    /// Two blocks hugging opposite ends: the mark and the maker's credit at the
    /// left, the shooting values and the device at the right. Nothing is
    /// centred and there is no divider — with no mat around the photo, the
    /// bar's own edges are what the content aligns to.
    ///
    /// Set in caps with a little tracking. Caps at a body font's default
    /// spacing read as a cramped row of labels, and the whole bar is caps.
    private static func drawBannerCaption(
        cgContext: CGContext,
        geometry: FrameGeometry,
        content: ResolvedBannerCaption,
        config: WhiteFrameConfig
    ) {
        guard !content.isEmpty else { return }

        // The full canvas width, not `captionBand`'s: the band is the photo's
        // width, and rounding the canvas up to even can leave the bar a pixel
        // wider than that.
        let band = CGRect(x: 0, y: geometry.captionBand.minY,
                          width: geometry.framedSize.width,
                          height: geometry.framedSize.height - geometry.captionBand.minY)
        guard band.height > 0, band.width > 0 else { return }

        let fontSize = geometry.captionFontSize
        let m = geometry.metrics
        let pitch = fontSize * m.linePitchToFont
        let interlineGap = pitch * m.interlineShareOfPitch
        let lineHeight = pitch - interlineGap
        // One measure for the side inset and the internal gaps, so the bar's
        // rhythm is even across it.
        let gap = fontSize * m.columnGapToFont

        let primaryColor = config.textColor
        let secondaryColor = lighten(config.textColor,
                                     towards: matColor(for: config, metrics: m),
                                     by: m.secondaryToneMix)

        func attributed(_ text: String, size: CGFloat, primary: Bool) -> NSAttributedString {
            NSAttributedString(string: text.uppercased(), attributes: [
                .font: platformFont(ofSize: size, weight: primary ? .semibold : .regular),
                .foregroundColor: platformColor(from: primary ? primaryColor : secondaryColor),
                .kern: size * m.bannerTrackingToFont,
            ])
        }

        // The lead-in is the quiet line and the maker the loud one, which is
        // the reverse of the right block — the eye lands on the name, then on
        // the values it is paired with.
        var leftText: [(String, Bool)] = []
        if let maker = content.maker {
            leftText.append((bannerLead, false))
            leftText.append((maker, true))
        }
        var rightText: [(String, Bool)] = []
        if let values = content.values { rightText.append((values, true)) }
        if let device = content.device { rightText.append((device, false)) }

        func block(_ text: [(String, Bool)], size: CGFloat) -> [NSAttributedString] {
            text.map { attributed($0.0, size: size, primary: $0.1) }
        }
        func width(_ lines: [NSAttributedString]) -> CGFloat {
            lines.map { $0.size().width }.max() ?? 0
        }
        func height(_ lines: [NSAttributedString]) -> CGFloat {
            guard !lines.isEmpty else { return 0 }
            return CGFloat(lines.count) * lineHeight + CGFloat(lines.count - 1) * interlineGap
        }

        // Mark first: its width comes from a metric height, and the two blocks
        // divide what is left.
        var markSize = CGSize.zero
        if let mark = content.mark {
            let tall = min(geometry.logoHeight, band.height - fontSize * 0.6)
            let wide = tall * mark.aspectRatio
            let maxWidth = band.width * m.markMaxWidthOfBand
            markSize = wide > maxWidth
                ? CGSize(width: maxWidth, height: maxWidth / mark.aspectRatio)
                : CGSize(width: wide, height: tall)
        }
        let markSpace = markSize.width > 0 ? markSize.width + gap : 0

        var left = block(leftText, size: fontSize)
        var right = block(rightText, size: fontSize)
        let available = max(0, band.width - gap * 2 - markSpace - gap)
        // Shrink per block, so one long lens string does not shrink the maker's
        // name across the bar from it.
        let leftAllowance = right.isEmpty ? available : available * 0.5
        let rightAllowance = left.isEmpty ? available : available * 0.5
        if width(left) > leftAllowance, width(left) > 0 {
            left = block(leftText, size: fontSize * (leftAllowance / width(left)))
        }
        if width(right) > rightAllowance, width(right) > 0 {
            right = block(rightText, size: fontSize * (rightAllowance / width(right)))
        }

        // Centred on the bar itself. `contentCentreOfBand` sits the gallery's
        // caption high so the space beneath it matches the mat on the other
        // three sides; here there are no other sides to match.
        let centre = band.midY

        func draw(_ lines: [NSAttributedString], x: (NSAttributedString) -> CGFloat) {
            var y = centre - height(lines) / 2
            for line in lines {
                drawLine(line, at: CGPoint(x: x(line), y: y), in: cgContext)
                y += lineHeight + interlineGap
            }
        }

        var cursor = band.minX + gap
        if let mark = content.mark {
            mark.draw(in: CGRect(x: cursor, y: centre - markSize.height / 2,
                                 width: markSize.width, height: markSize.height),
                      context: cgContext)
            cursor += markSpace
        }
        draw(left, x: { _ in cursor })
        draw(right, x: { band.maxX - gap - $0.size().width })
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
    private static func platformFont(ofSize size: CGFloat, weight: CaptionWeight) -> UIFont {
        let uiWeight: UIFont.Weight
        switch weight {
        case .regular: uiWeight = .regular
        case .medium: uiWeight = .medium
        case .semibold: uiWeight = .semibold
        }
        return UIFont.systemFont(ofSize: size, weight: uiWeight)
    }

    private static func platformColor(from cgColor: CGColor) -> UIColor {
        return UIColor(cgColor: cgColor)
    }
    #elseif canImport(AppKit)
    private static func platformFont(ofSize size: CGFloat, weight: CaptionWeight) -> NSFont {
        let nsWeight: NSFont.Weight
        switch weight {
        case .regular: nsWeight = .regular
        case .medium: nsWeight = .medium
        case .semibold: nsWeight = .semibold
        }
        return NSFont.systemFont(ofSize: size, weight: nsWeight)
    }

    private static func platformColor(from cgColor: CGColor) -> NSColor {
        return NSColor(cgColor: cgColor) ?? NSColor.darkGray
    }
    #endif
}
