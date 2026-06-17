import CoreImage

/// Composites ordered CIImage watermark layers onto a base image using
/// `CIFilter.sourceOverCompositing()` per layer (Pattern 1).
///
/// Layers are composited in array order: index 0 = bottom, last index = top.
/// Each layer is positioned using CIImage bottom-left origin coordinates.
///
/// The entire compositing chain is a lazy CIImage filter graph — no intermediate
/// pixel buffers. Core Image merges the graph into a single GPU Metal shader.
public struct WatermarkRenderer {

    /// Composites an ordered array of watermark layers onto a base image.
    ///
    /// - Parameters:
    ///   - layers: Array of `(layer: CIImage, position: CGPoint)` tuples in
    ///     bottom-to-top order (index 0 = closest to base)
    ///   - base: The base image CIImage (must be orientation-normalized to .up)
    /// - Returns: The fully composited CIImage, cropped to the base extent
    public static func composite(
        layers: [(CIImage, CGPoint)],
        onto base: CIImage
    ) -> CIImage {
        // STUB — RED phase: returns base unchanged, tests will fail
        return base
    }
}
