import CoreImage
import CoreImage.CIFilterBuiltins

/// Composites ordered CIImage watermark layers onto a base image using
/// `CIFilter.sourceOverCompositing()` per layer (Pattern 1).
///
/// Layers are composited in array order: index 0 = bottom, last index = top.
/// Each layer is positioned using CIImage bottom-left origin coordinates
/// via `CIImage.transformed(by: CGAffineTransform)`.
///
/// The entire compositing chain is a lazy CIImage filter graph — no intermediate
/// pixel buffers. Core Image merges the graph into a single GPU Metal shader.
public struct WatermarkRenderer {

    /// Composites an ordered array of watermark layers onto a base image.
    ///
    /// - Parameters:
    ///   - layers: Array of `(layer: CIImage, position: CGPoint)` tuples in
    ///     bottom-to-top order (index 0 = closest to base).
    ///     Positions use CIImage bottom-left origin coordinates.
    ///   - base: The base image CIImage (must be orientation-normalized to .up)
    /// - Returns: The fully composited CIImage, cropped to the base extent
    ///
    /// Uses `CIFilter.sourceOverCompositing()` for each layer — the canonical
    /// Core Image blend for watermark overlays. The filter graph is lazy;
    /// actual GPU rendering happens when `CIContext.createCGImage()` is called.
    public static func composite(
        layers: [(CIImage, CGPoint)],
        onto base: CIImage
    ) -> CIImage {
        var composited = base
        let baseExtent = base.extent

        for (layer, position) in layers {
            // Position the layer via CGAffineTransform translation
            let transform = CGAffineTransform(translationX: position.x, y: position.y)
            let positioned = layer.transformed(by: transform)

            // Composite using source-over blend
            let filter = CIFilter.sourceOverCompositing()
            filter.inputImage = positioned
            filter.backgroundImage = composited

            // Fallback to previous state if filter fails (should not happen)
            composited = filter.outputImage ?? composited
        }

        // Crop final result to base extent — prevents layers from expanding bounds
        return composited.cropped(to: baseExtent)
    }
}
