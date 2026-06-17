import CoreImage

/// Renders a POSITION from a WatermarkPosition preset to a CGPoint translation.
///
/// Delegates to `WatermarkPosition.translation(watermarkExtent:baseExtent:padding:)`
/// and extracts the translation X,Y as a CGPoint. This is the public API used by
/// `WatermarkEngine` when building the filter graph.
public struct PositionCalculator {

    /// Calculates the bottom-left origin position for a watermark layer.
    ///
    /// - Parameters:
    ///   - watermarkPosition: The position preset enumeration
    ///   - watermarkExtent: The extent rect of the watermark CIImage
    ///   - baseExtent: The extent rect of the base image CIImage (must be normalized to .up)
    ///   - padding: Padding in points from edges
    /// - Returns: A CGPoint (x, y) in CIImage bottom-left coordinates
    public static func position(
        for watermarkPosition: WatermarkPosition,
        watermarkExtent: CGRect,
        baseExtent: CGRect,
        padding: CGFloat
    ) -> CGPoint {
        let transform = watermarkPosition.translation(
            watermarkExtent: watermarkExtent,
            baseExtent: baseExtent,
            padding: padding
        )
        return CGPoint(x: transform.tx, y: transform.ty)
    }
}
