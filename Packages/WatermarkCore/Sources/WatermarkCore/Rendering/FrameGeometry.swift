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

    /// Font size for caption text, in pixels.
    ///
    /// `gallery` derives it from a millimetre setting, like everything else it
    /// measures; `classic` keeps its proportion of the source.
    public let captionFontSize: CGFloat

    /// Height the brand mark is drawn at, in pixels. Zero for styles that draw
    /// no mark.
    public let logoHeight: CGFloat

    /// Pixels per inch to convert a millimetre border against.
    ///
    /// Uses the image's own resolution when it looks like a real measurement.
    /// A great many JPEGs carry 72 DPI because that is the JFIF default, not
    /// because anyone measured anything — taking that literally would turn a
    /// 5mm border into 14px on an 8000px photo, which reads as no border at
    /// all. So only a print-intent resolution is believed; anything lower
    /// falls back to 300.
    /// When `config` carries an explicit `outputDPI`, that is the answer —
    /// a resolution the user set is not a guess to be second-guessed.
    public static func resolveDPI(from metadata: [String: Any], config: WhiteFrameConfig) -> CGFloat {
        if let chosen = config.outputDPI { return chosen }
        return resolveDPI(from: metadata)
    }

    public static func resolveDPI(from metadata: [String: Any]) -> CGFloat {
        let candidates = [
            metadata[kCGImagePropertyDPIWidth as String],
            metadata[kCGImagePropertyDPIHeight as String],
        ]
        for case let value? in candidates {
            if let dpi = (value as? NSNumber)?.doubleValue, dpi >= 150 {
                return CGFloat(dpi)
            }
        }
        return 300
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
    ///     Only `gallery` uses it; `classic` sizes proportionally.
    ///   - hasCaptionContent: whether the caption will actually draw anything.
    ///     A gallery frame whose slots all resolve to nothing — a photo with no
    ///     metadata and no typed handle — collapses its bottom band to a
    ///     uniform mat rather than leaving an empty bar.
    ///   - metrics: the proportions to build from. Defaults to the measured
    ///     reference layout.
    public init(
        config: WhiteFrameConfig,
        sourceSize: CGSize,
        dpi: CGFloat = 300,
        hasCaptionContent: Bool = true,
        metrics: FrameMetrics = .reference
    ) {
        self.sourceSize = sourceSize
        self.metrics = metrics

        let shorter = min(sourceSize.width, sourceSize.height)

        // The two styles mean different things by "border": classic is a
        // proportion of the photo, gallery is a physical size on paper.
        let mat: CGFloat
        switch config.style {
        case .classic:
            mat = (shorter * config.frameWidthRatio).rounded()
        case .gallery:
            mat = Self.pixels(millimetres: config.borderMillimetres, dpi: dpi)
        }

        // The keyline is a proportion of the mat rather than of the photo, so
        // it stays visible against the border it separates: tied to the photo
        // it came out a hairline on small images and vanished entirely.
        let keyline = config.keylineEnabled ? max(1, (mat * metrics.keylineToBorder).rounded()) : 0
        self.keylineWidth = keyline

        // Caption size follows whatever the style measures its mat in, so the
        // two cannot fight. Classic scales with the photo, like its mat does.
        // Gallery ties the text to its physical mat: if the caption kept
        // scaling with pixels, a 48MP photo would have text taller than a 5mm
        // border, and the band would stop tracking the millimetre setting.
        let fontSize: CGFloat
        switch config.style {
        case .classic:
            fontSize = shorter * config.textFontSizeRatio
            self.logoHeight = 0
        case .gallery:
            fontSize = Self.pixels(millimetres: config.captionTextMillimetres, dpi: dpi)
            self.logoHeight = Self.pixels(millimetres: config.logoHeightMillimetres, dpi: dpi)
        }
        self.captionFontSize = fontSize

        // The keyline lives in the innermost part of the mat, so a mat has to
        // be at least thick enough to hold it and still read as a mat.
        let edge = mat + keyline

        let bottomEdge: CGFloat
        switch config.style {
        case .classic:
            // A uniform border. Its single centred caption already fits the
            // mat at the existing proportions, so the bottom is not special.
            bottomEdge = edge
        case .gallery where !hasCaptionContent:
            // Nothing to say, so no bar to say it in.
            bottomEdge = edge
        case .gallery:
            // The band is a multiple of the mat, so it tracks the border
            // setting — widen the border and the caption bar widens with it.
            // It still has to clear its contents, so a very small border is
            // floored by what the caption and mark physically need rather
            // than crushing them.
            let pitch = fontSize * metrics.linePitchToFont
            let textBlock = pitch * 2
            let contentFloor = (max(textBlock, logoHeight) * 1.5).rounded() + keyline
            bottomEdge = max((mat * metrics.bandToBorder).rounded() + keyline, contentFloor)
        }

        self.top = edge
        self.left = edge
        self.right = edge
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
