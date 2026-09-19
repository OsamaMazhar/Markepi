import CoreImage

/// Normalizes EXIF orientation to `.up` so all subsequent positioning math
/// operates in a consistent coordinate space.
///
/// Without normalization, positional transforms operate on raw sensor orientation,
/// causing the "double-rotation" watermark misplacement bug (Pitfall 3).
///
/// Always call `.oriented(.up)` BEFORE any positioning calculations.
public struct OrientationNormalizer {

    /// Normalizes a CIImage's orientation to `.up`.
    ///
    /// Uses `CIImage.oriented(.up)` which handles all 8 EXIF orientation cases
    /// correctly. The returned image has its coordinate system aligned with the
    /// visual display orientation.
    ///
    /// - Parameter image: The source CIImage (may have any EXIF orientation)
    /// - Returns: A new CIImage with orientation set to `.up`
    public static func normalize(_ image: CIImage) -> CIImage {
        return image.oriented(.up)
    }
}
