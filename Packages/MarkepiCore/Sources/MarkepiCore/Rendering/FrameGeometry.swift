import CoreGraphics
import Foundation
import ImageIO

/// Where the photo sits inside a framed export, and how big that export is.
///
/// The mat is drawn *outside* the photo: a framed export is larger than its
/// source and no part of the source is covered. Both the photo path
/// (`WatermarkEngine`) and the video path (`VideoLayerBuilder`) derive their
/// sizing from here, which is what keeps a framed photo and a framed video the
/// same shape — and lets a photo test stand in for geometry the Simulator
/// cannot exercise.
public struct FrameGeometry: Equatable, Sendable {

    /// The source image or video size, unmodified.
    public let sourceSize: CGSize

    /// Mat thickness on each edge, in pixels.
    public let top: CGFloat
    public let left: CGFloat
    public let bottom: CGFloat
    public let right: CGFloat

    /// The exported canvas: source plus mat, rounded up to even in both
    /// dimensions.
    public let framedSize: CGSize

    /// Where the source sits within `framedSize`, origin at top-left.
    public let photoRect: CGRect

    /// The proportions this frame was built from.
    public let metrics: FrameMetrics

    /// Thickness of the optional keyline. Zero when it is disabled.
    ///
    /// The keyline is stroked in the mat immediately outside `photoRect`, so it
    /// never covers any of the photo.
    public let keylineWidth: CGFloat

    /// Font size for caption text, in pixels, from the millimetre setting.
    public let captionFontSize: CGFloat

    /// Height the brand mark is drawn at, in pixels. Zero for styles that draw
    /// no mark.
    public let logoHeight: CGFloat

    /// Blur radius of the drop shadow, in pixels. Zero for styles that cast
    /// none.
    public let shadowBlur: CGFloat

    /// How far the drop shadow is pushed down, in pixels. Zero when the shadow
    /// is even on all sides, and zero for styles that cast none.
    public let shadowOffset: CGFloat

    /// How much mat a shadow needs on an edge to land on it rather than run
    /// off the canvas.
    ///
    /// A blurred shape reaches roughly its blur radius past its own edge, and
    /// the offset pushes the bottom further still.
    var shadowRoom: (sides: CGFloat, bottom: CGFloat) {
        guard shadowBlur > 0 else { return (0, 0) }
        return (shadowBlur, shadowBlur + shadowOffset)
    }

    /// Pixels per inch to convert a millimetre border against.
    ///
    /// Uses the image's own resolution when it looks like a real measurement.
    /// A great many JPEGs carry 72 DPI because that is the JFIF default, not
    /// because anyone measured anything — taking that literally would turn a
    /// 5mm border into 14px on an 8000px photo, which reads as no border at
    /// all. So only a print-intent resolution is believed; anything lower is
    /// derived from the source's own resolution instead.
    /// When `config` carries an explicit `outputDPI`, that is the answer —
    /// a resolution the user set is not a guess to be second-guessed.
    public static func resolveDPI(
        from metadata: [String: Any],
        config: WhiteFrameConfig,
        sourceSize: CGSize
    ) -> CGFloat {
        if let chosen = config.outputDPI { return chosen }
        return resolveDPI(from: metadata, sourceSize: sourceSize)
    }

    /// The short edge of the print a source is treated as, when nothing says
    /// otherwise: ten inches, about a sheet of A4.
    ///
    /// A flat fallback cannot work across media. 300 DPI was calibrated on a
    /// 12MP photo, where an 8mm border is 3.1% of the short edge — the
    /// reference card's proportion. Applied to a 1080p video the same 8mm
    /// becomes 8.8%, nearly three times as heavy, which is why footage came
    /// out looking so much more heavily framed than stills. Ten inches is what
    /// "300 DPI on a 12MP photo" always meant (3024 / 300 = 10.08"); saying it
    /// directly makes every medium agree.
    public static let referencePrintShortEdgeInches: CGFloat = 10

    /// Resolution to convert millimetres against, from the source's own
    /// metadata where it is a real print measurement, else from its size.
    public static func resolveDPI(from metadata: [String: Any], sourceSize: CGSize) -> CGFloat {
        let candidates = [
            metadata[kCGImagePropertyDPIWidth as String],
            metadata[kCGImagePropertyDPIHeight as String],
        ]
        for case let value? in candidates {
            if let dpi = (value as? NSNumber)?.doubleValue, dpi >= 150 {
                return CGFloat(dpi)
            }
        }
        let shortEdge = min(sourceSize.width, sourceSize.height)
        guard shortEdge > 0 else { return 300 }
        return shortEdge / referencePrintShortEdgeInches
    }

    /// Resolution for a video frame.
    ///
    /// DPI is a print idea and a video is never printed, so neither its own
    /// metadata nor a print resolution the user chose for their photos means
    /// anything here — honouring a 600 DPI setting would frame 1080p footage
    /// like a contact print. Video always uses the reference print, which
    /// makes a millimetre a fixed share of the frame and so identical to what
    /// the same setting gives on a photo.
    public static func videoDPI(videoSize: CGSize) -> CGFloat {
        let shortEdge = min(videoSize.width, videoSize.height)
        guard shortEdge > 0 else { return 300 }
        return shortEdge / referencePrintShortEdgeInches
    }

    /// The source's short edge in millimetres at `dpi` — the span every
    /// millimetre setting is a fraction of, and what lets a layer sized in
    /// millimetres mean the same thing on a photo and on a video.
    public static func shortEdgeMillimetres(sourceSize: CGSize, dpi: CGFloat) -> CGFloat {
        guard dpi > 0 else { return 0 }
        return min(sourceSize.width, sourceSize.height) / dpi * 25.4
    }

    /// Converts millimetres to pixels at `dpi`.
    public static func pixels(millimetres mm: CGFloat, dpi: CGFloat) -> CGFloat {
        (mm / 25.4 * dpi).rounded()
    }

    /// Creates the geometry for a source of `sourceSize` under `config`.
    ///
    /// - Parameters:
    ///   - config: the frame configuration; `style` selects the mat shape.
    ///   - sourceSize: the unframed source size in pixels.
    ///   - dpi: resolution used to turn a millimetre border into pixels.
    ///     Only `gallery` uses it; `classic` sizes proportionally. Omit it to
    ///     derive one from `sourceSize` — a fixed default silently assumed a
    ///     12MP photo, and on anything smaller (a test fixture, a video frame)
    ///     produced a border several times too heavy.
    ///   - hasCaptionContent: whether the caption will actually draw anything.
    ///     A gallery frame whose slots all resolve to nothing — a photo with no
    ///     metadata and no typed handle — collapses its bottom band to a
    ///     uniform mat rather than leaving an empty bar.
    ///   - metrics: the proportions to build from. Defaults to the measured
    ///     reference layout.
    public init(
        config: WhiteFrameConfig,
        sourceSize: CGSize,
        dpi: CGFloat? = nil,
        hasCaptionContent: Bool = true,
        metrics: FrameMetrics = .reference
    ) {
        self.sourceSize = sourceSize
        self.metrics = metrics
        let dpi = dpi ?? Self.resolveDPI(from: [:], sourceSize: sourceSize)

        // Both styles measure the border the same way: a physical size on
        // paper. Classic used to take a percentage of the photo, so the printed
        // border moved with the camera's megapixels and no two exports matched.
        let mat = Self.pixels(millimetres: config.borderMillimetres, dpi: dpi)

        // The keyline is a proportion of the mat rather than of the photo, so
        // it stays visible against the border it separates: tied to the photo
        // it came out a hairline on small images and vanished entirely.
        // `print` draws no keyline whatever the setting: the shadow already
        // separates the photo from the mat, and a heavy black rule around a
        // lifted print reads as a mistake. The stored preference is untouched,
        // so switching back to another style finds it as the user left it.
        let keyline = (config.keylineEnabled && config.style.offersKeyline)
            ? max(1, (mat * metrics.keylineToBorder).rounded()) : 0
        self.keylineWidth = keyline

        // Caption text is physical too, so it cannot fight the mat it sits in:
        // sized in pixels, a 48MP photo would grow text taller than an 8mm
        // border, and the band would stop tracking the millimetre setting.
        let fontSize = Self.pixels(millimetres: config.captionTextMillimetres, dpi: dpi)
        self.captionFontSize = fontSize
        // Only the styles that place a mark need a height for one.
        self.logoHeight = config.style.drawsBrandMark
            ? Self.pixels(millimetres: config.logoHeightMillimetres, dpi: dpi)
            : 0

        // Derived from the mat, like the keyline: a shadow fixed in pixels is a
        // smudge on a small photo and invisible on a large one.
        let blur = config.style.castsShadow
            ? (mat * metrics.shadowBlurToBorder).rounded() : 0
        self.shadowBlur = blur
        self.shadowOffset = (config.style.castsShadow && config.shadow == .bottom)
            ? (blur * metrics.shadowOffsetToBlur).rounded() : 0

        // The keyline lives in the innermost part of the mat, so a mat has to
        // be at least thick enough to hold it and still read as a mat. A
        // shadow needs its own room on top of that, or it runs off the canvas
        // and reads as a hard grey band instead of a soft one.
        let edge = max(mat + keyline, blur > 0 ? blur : 0)

        // `banner` has no mat on three sides: the photo bleeds to the top and
        // both edges and the caption sits in a bar beneath it. The border
        // setting still means something — it is what the bar's height is
        // measured from, exactly as in `gallery`.
        let sideEdge = config.style.hasSideMat ? edge : 0

        let bottomEdge: CGFloat
        switch config.style {
        case .classic, .print:
            // A uniform border — but the caption is now sized independently of
            // it, so the bottom has to be able to hold the lines it is given.
            // Only a caption set larger than its border pushes it out of
            // uniform, which is the user asking for exactly that.
            //
            // Print stacks two centred lines where classic has one, so it asks
            // for one more line's worth of room; the half-line on top is the
            // breathing space either way. The user's own credit text wraps
            // that first line rather than adding a third, so the count does not
            // move with it.
            let lineCount: CGFloat = config.style == .print ? 2 : 1
            let padding = config.style == .print
                ? metrics.printCaptionBlockPaddingLines
                : metrics.captionBlockPaddingLines
            let block = (fontSize * metrics.linePitchToFont * (lineCount + padding)).rounded() + keyline
            // The shadow and the caption stack rather than share: the shadow
            // spills from the photo's bottom edge downwards, and the caption
            // sits clear beneath it. Taking the larger of the two instead
            // would print the caption on top of the shadow.
            let shadowRoom = blur + self.shadowOffset
            bottomEdge = shadowRoom > 0
                ? max(edge, shadowRoom + (hasCaptionContent ? block : 0))
                // No shadow: exactly what it always was.
                : (hasCaptionContent ? max(edge, block) : edge)
        case .gallery, .banner:
            // The band is a multiple of the mat, so it tracks the border
            // setting — widen the border and the caption bar widens with it.
            // It still has to clear its contents, so a very small border is
            // floored by what the caption and mark physically need rather
            // than crushing them. Nothing to say means no bar to say it in.
            //
            // Spelled as an `if` rather than a `case ... where`: a `where` on a
            // comma-separated pattern list binds to the last pattern only, so
            // `case .gallery, .other where !hasCaptionContent` would have
            // collapsed every gallery band unconditionally.
            if hasCaptionContent {
                let pitch = fontSize * metrics.linePitchToFont
                let textBlock = pitch * 2
                let contentFloor = (max(textBlock, logoHeight) * 1.5).rounded() + keyline
                bottomEdge = max((mat * metrics.bandToBorder).rounded() + keyline, contentFloor)
            } else {
                // Nothing to say leaves `gallery` a uniform mat — and leaves
                // `banner` no frame at all, which is right: a bar with nothing
                // in it is not a style, it is a white stripe.
                bottomEdge = sideEdge
            }
        }

        self.top = sideEdge
        self.left = sideEdge
        self.right = sideEdge
        self.bottom = bottomEdge

        // Round the canvas up to even in both dimensions: H.264 and HEVC want
        // even render sizes, and photos follow the same rule so photo and video
        // geometry stay comparable. Any pixel added by rounding goes to the mat,
        // never to the photo.
        let rawWidth = sourceSize.width + left + right
        let rawHeight = sourceSize.height + top + bottomEdge
        let evenWidth = (rawWidth / 2).rounded(.up) * 2
        let evenHeight = (rawHeight / 2).rounded(.up) * 2
        self.framedSize = CGSize(width: evenWidth, height: evenHeight)

        self.photoRect = CGRect(
            x: left,
            y: top,
            width: sourceSize.width,
            height: sourceSize.height
        )
    }

    /// The rect the caption is laid out in: the bottom band, inside the side
    /// mats and clear of the photo.
    public var captionBand: CGRect {
        CGRect(
            x: left,
            y: photoRect.maxY + keylineWidth,
            width: sourceSize.width,
            height: framedSize.height - photoRect.maxY - keylineWidth
        )
    }

    /// The rect the keyline is stroked around: `photoRect` grown by half the
    /// stroke, so the stroke lands entirely in the mat.
    public var keylineRect: CGRect {
        photoRect.insetBy(dx: -keylineWidth / 2, dy: -keylineWidth / 2)
    }
}
