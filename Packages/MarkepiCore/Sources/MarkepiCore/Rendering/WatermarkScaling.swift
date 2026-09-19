import CoreGraphics

/// Translates a watermark layer's `scale` value into a concrete affine scale
/// factor to apply to the watermark's natural (rendered) pixel dimensions.
///
/// `scale` is a fraction of the frame's SHORTER side, which is what makes it
/// mean the same thing on any medium. Keyed to a specific edge it did not: at
/// one setting, text sized by height came out about 45% heavier on a 9:16 video
/// than on a 3:4 photo, and a logo sized by width came out that much heavier on
/// 16:9 footage — "fine on photos, too big on video". The short edge is also
/// what the watermark padding measures against.
public enum WatermarkScaling {

    /// The dimension a layer's `scale` is a fraction of.
    public static func reference(_ size: CGSize) -> CGFloat {
        min(size.width, size.height)
    }

    /// Returns the affine scale factor for `layer` drawn on a `baseSize` frame.
    ///
    /// Text measures its HEIGHT: editing the words changes their width, and the
    /// apparent font size must not change with it. Logos and signatures have a
    /// fixed aspect ratio, so width is the natural control. Every surface —
    /// photo, video, share extension, editor overlay — goes through here, so
    /// they cannot drift apart.
    ///
    /// - Parameters:
    ///   - layer: The layer being drawn; its `scale` and kind pick the rule.
    ///   - naturalSize: The watermark's intrinsic rendered size in pixels.
    ///   - baseSize: The photo or video frame the watermark sits on.
    public static func transformFactor(
        for layer: WatermarkLayer,
        naturalSize: CGSize,
        baseSize: CGSize
    ) -> CGFloat {
        let natural: CGFloat
        if case .text = layer {
            natural = naturalSize.height
        } else {
            natural = naturalSize.width
        }
        return transformFactor(
            layerScale: layer.scale, naturalWidth: natural, baseWidth: reference(baseSize))
    }

    /// Returns the affine scale factor to apply to a watermark of intrinsic
    /// size `naturalWidth` so that it occupies `layerScale` of `baseWidth`.
    ///
    /// - Parameters:
    ///   - layerScale: Fraction of `baseWidth` the watermark should fill (0...1).
    ///   - naturalWidth: The watermark's intrinsic rendered size in pixels, on
    ///     the axis being measured.
    ///   - baseWidth: The reference dimension in pixels — normally the frame's
    ///     shorter side, via `reference(_:)`.
    /// - Returns: The factor to pass to `CGAffineTransform(scaleX:y:)`. Falls back
    ///   to `layerScale` when dimensions are degenerate (zero/negative) so callers
    ///   never divide by zero.
    public static func transformFactor(
        layerScale: CGFloat,
        naturalWidth: CGFloat,
        baseWidth: CGFloat
    ) -> CGFloat {
        guard naturalWidth > 0, baseWidth > 0 else { return layerScale }
        let targetWidth = layerScale * baseWidth
        return targetWidth / naturalWidth
    }

    // MARK: - Millimetres

    /// The grid every millimetre setting sits on.
    ///
    /// Sizes are shown to one decimal, so a value off this grid reads as an
    /// arbitrary 10.9 or 11.4 and steps to another arbitrary number. Snapping
    /// the value itself — not just the number on screen — is what keeps what
    /// is drawn and what is displayed the same size.
    public static let millimetreStep: CGFloat = 0.5

    /// Rounds a millimetre value onto `millimetreStep`.
    public static func snapped(millimetres: CGFloat) -> CGFloat {
        (millimetres / millimetreStep).rounded() * millimetreStep
    }

    /// Every user-facing size is stated in millimetres of a reference print,
    /// and a layer's `scale` is a fraction of the frame's short edge — so the
    /// two are related by the reference print's short edge and nothing else.
    ///
    /// That is what keeps a setting meaning the same thing on a 12MP still and
    /// on 1080p footage: both are treated as the same size print, so the same
    /// millimetres are the same share of the frame. Pixels never enter into it,
    /// which is why nothing here needs a resolution passed in.
    public static var referenceShortEdgeMillimetres: CGFloat {
        FrameGeometry.referencePrintShortEdgeInches * 25.4
    }

    /// A layer's `scale` expressed in millimetres, on the grid.
    public static func millimetres(forScale scale: CGFloat) -> CGFloat {
        snapped(millimetres: scale * referenceShortEdgeMillimetres)
    }

    /// Millimetres expressed as a layer `scale`, snapped first so the size
    /// drawn is the size shown.
    public static func scale(forMillimetres millimetres: CGFloat) -> CGFloat {
        guard referenceShortEdgeMillimetres > 0 else { return 0 }
        return snapped(millimetres: millimetres) / referenceShortEdgeMillimetres
    }

    /// Edge padding in pixels for a frame of `baseSize`.
    ///
    /// A fixed pixel padding cannot serve both media: 20px is 0.7% of a 12MP
    /// photo's short edge and 1.9% of 1080p footage's, so watermarks sat much
    /// closer to the edge on video. The photo path used to paper over this with
    /// a 4% floor that the video path did not apply — the same number, derived
    /// the same way, now serves both.
    public static func padding(millimetres: CGFloat, baseSize: CGSize) -> CGFloat {
        reference(baseSize) * scale(forMillimetres: millimetres)
    }
}
