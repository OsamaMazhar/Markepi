import CoreGraphics

/// Translates a watermark layer's `scale` value into a concrete affine scale
/// factor to apply to the watermark's natural (rendered) pixel dimensions.
///
/// `scale` is interpreted as **the fraction of the base image's width** that the
/// watermark should occupy. This makes the value resolution-independent: a
/// `scale` of `0.30` renders a watermark that is 30% of the image width whether
/// the source is 800px or 6000px wide. Both the image dimensions (`baseWidth`)
/// and the watermark's own dimensions (`naturalWidth`) are used to derive the
/// factor, so the watermark is sized relative to the photo it sits on rather
/// than as an absolute multiple of a fixed font/PNG size.
public enum WatermarkScaling {

    /// Returns the affine scale factor to apply to a watermark of intrinsic
    /// width `naturalWidth` so that it occupies `layerScale` of `baseWidth`.
    ///
    /// - Parameters:
    ///   - layerScale: Fraction of the base image width the watermark should fill (0...1).
    ///   - naturalWidth: The watermark's intrinsic rendered width in pixels.
    ///   - baseWidth: The base image (or video) width in pixels.
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
}
