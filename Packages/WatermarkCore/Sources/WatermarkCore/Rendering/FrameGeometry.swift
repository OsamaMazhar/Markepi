import CoreGraphics
import Foundation

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

    /// Thickness of the optional keyline. Zero when it is disabled.
    ///
    /// The keyline is stroked in the mat immediately outside `photoRect`, so it
    /// never covers any of the photo.
    public let keylineWidth: CGFloat

    /// Font size for caption text, derived from the source rather than the
    /// framed canvas so that adding a mat does not change how big the text is.
    public let captionFontSize: CGFloat

    /// Creates the geometry for a source of `sourceSize` under `config`.
    ///
    /// - Parameters:
    ///   - config: the frame configuration; `style` selects the mat shape.
    ///   - sourceSize: the unframed source size in pixels.
    public init(config: WhiteFrameConfig, sourceSize: CGSize) {
        self.sourceSize = sourceSize

        let shorter = min(sourceSize.width, sourceSize.height)
        // Mat thickness keeps the existing rule — a proportion of the shorter
        // dimension — so a frame looks the same at any export resolution.
        let mat = (shorter * config.frameWidthRatio).rounded()
        let fontSize = shorter * config.textFontSizeRatio
        self.captionFontSize = fontSize

        let keyline = config.keylineEnabled ? max(1, (shorter * 0.0015).rounded()) : 0
        self.keylineWidth = keyline

        // The keyline lives in the innermost part of the mat, so a mat has to
        // be at least thick enough to hold it and still read as a mat.
        let edge = mat + keyline

        let bottomEdge: CGFloat
        switch config.style {
        case .classic:
            // A uniform border. Its single centred caption already fits the
            // mat at the existing proportions, so the bottom is not special.
            bottomEdge = edge
        case .gallery:
            // The bottom band has to hold two stacked lines of caption. Derive
            // its height from that text rather than picking a fraction: line
            // height plus the gap between the two lines, plus breathing room
            // above and below scaled to the same text.
            let lineHeight = fontSize * 1.25
            let interlineGap = fontSize * 0.25
            let verticalPadding = fontSize * 0.85
            let captionBlock = lineHeight * 2 + interlineGap
            bottomEdge = max(edge, (captionBlock + verticalPadding * 2).rounded() + keyline)
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
