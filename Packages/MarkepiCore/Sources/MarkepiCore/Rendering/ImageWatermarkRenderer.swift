import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Renders a PNG-based image watermark as a CIImage with alpha channel
/// preservation, configurable scale, and opacity.
///
/// Pipeline:
///   1. `CIImage(data:)` — decodes PNG with alpha channel intact
///   2. `CGAffineTransform(scaleX:scaleY:)` — sizes the overlay proportionally
///   3. `CIFilter.colorMatrix()` — adjusts alpha channel for opacity < 1.0
///
/// The output CIImage is ready for compositing via WatermarkRenderer.composite().
/// Follows the same `static func render(config:)` pattern as TextWatermarkRenderer.
///
/// Opacity is applied via CIFilter.colorMatrix alpha vector (multiply alpha by
/// opacity value) rather than through CISourceOverCompositing — this gives the
/// compositor correct control over blend without modifying the PNG data.
public struct ImageWatermarkRenderer {

    /// Renders a configured image watermark to a CIImage.
    ///
    /// - Parameter config: Image watermark configuration (PNG data, scale, opacity)
    /// - Returns: A scaled CIImage with alpha adjusted for opacity
    /// - Throws: `PipelineError.invalidImageData` if PNG data cannot be decoded
    ///           by Core Image
    public static func render(config: ImageWatermarkInput) throws -> CIImage {
        // Decode PNG data to CIImage (preserves alpha channel)
        // CIImage(data:) returns nil for non-image data including non-PNG formats
        guard let ciImage = CIImage(data: config.pngData) else {
            throw PipelineError.invalidImageData
        }

        // Scale the watermark relative to base image
        let scaled = ciImage.transformed(
            by: CGAffineTransform(scaleX: config.scale, y: config.scale)
        )

        // Apply opacity via alpha channel modulation when < 1.0
        // CIFilter.colorMatrix scales just the alpha component while leaving
        // RGB untouched — the CISourceOverCompositing blend at the compositor
        // stage then uses the modulated alpha for correct transparency.
        if config.opacity < 1.0 {
            let opacity = CGFloat(config.opacity)
            let colorMatrix = CIFilter.colorMatrix()
            colorMatrix.inputImage = scaled
            // Default matrix is identity. Only modify the alpha vector:
            // outputAlpha = 0*R + 0*G + 0*B + opacity*A + 0
            colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: opacity)
            colorMatrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)

            guard let output = colorMatrix.outputImage else {
                // Fallback: return scaled image if filter fails (should not happen)
                return scaled
            }
            return output
        }

        return scaled
    }

    /// Rotates a CIImage clockwise by `degrees` about its own center, then
    /// re-normalizes the extent origin back to (0, 0).
    ///
    /// Positioning math (`PositionCalculator` / `WatermarkPosition`) assumes the
    /// watermark's extent starts at the origin, so after rotating about (0,0)
    /// — which shifts the extent — we translate it back. The returned image's
    /// bounding box is the rotated logo, ready to place like any other layer.
    ///
    /// Degrees are treated as clockwise as the viewer perceives the final image.
    /// Core Image's y-up space makes a positive `rotationAngle` counter-clockwise,
    /// so the angle is negated.
    public static func rotated(_ image: CIImage, degrees: CGFloat) -> CIImage {
        let normalized = ImageWatermarkInput.normalizeDegrees(degrees)
        guard normalized != 0 else { return image }
        let radians = -normalized * .pi / 180
        let rotated = image.transformed(by: CGAffineTransform(rotationAngle: radians))
        return rotated.transformed(
            by: CGAffineTransform(translationX: -rotated.extent.origin.x, y: -rotated.extent.origin.y)
        )
    }
}
