import CoreImage

/// 9-position preset enum for watermark placement.
///
/// Uses CIImage bottom-left origin coordinate system:
/// - Origin (0,0) is bottom-left corner
/// - +X extends right, +Y extends up
/// - This is the OPPOSITE of UIKit (0,0 top-left, +Y down)
///
/// Always normalize EXIF orientation to `.up` before using this enum's
/// translation values — working on non-normalized images causes watermark
/// misplacement (the "double-rotation" bug).
public enum WatermarkPosition: String, CaseIterable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case center
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    /// Calculates the CGAffineTransform translation for placing a watermark at
    /// this position, using CIImage bottom-left origin coordinate math.
    ///
    /// - Parameters:
    ///   - watermarkExtent: The extent rect of the watermark `CIImage`
    ///   - baseExtent: The extent rect of the base image `CIImage`
    ///   - padding: Padding in points from edges of base image
    /// - Returns: A `CGAffineTransform` with translationX and translationY set
    ///
    /// After normalization to `.up`, top-left maps to visual top-left:
    ///   topLeft  → y = baseExtent.height - watermarkExtent.height - padding
    ///   bottomLeft → y = padding
    public func translation(
        watermarkExtent: CGRect,
        baseExtent: CGRect,
        padding: CGFloat
    ) -> CGAffineTransform {
        // STUB — RED phase: returns identity so tests fail
        // GREEN phase implements the correct translation math.
        return .identity
    }
}
