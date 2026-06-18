import CoreImage
#if canImport(UIKit)
import PencilKit
import UIKit
#endif

/// Renders a PencilKit signature drawing into a CIImage with ink color
/// tint applied.
///
/// Pipeline:
///   1. Reconstruct PKDrawing from SignatureInput.strokeData
///   2. Rasterize at 3x scale for Retina-quality output on high-res sources
///   3. Apply ink color via CIFilter.colorMatrix (multiply RGB by inkColor, preserve alpha)
///   4. Return tinted CIImage for compositing
///
/// Follows the same `struct + static func` pattern as ImageWatermarkRenderer.
public struct SignatureRenderer {

    /// Renders a signature from PencilKit stroke data to a CIImage.
    ///
    /// - Parameter input: Signature configuration (stroke data, ink color, stroke width)
    /// - Returns: A CIImage of the rasterized and tinted signature
    /// - Throws: `PipelineError.invalidImageData` if stroke data cannot be reconstructed
    public static func render(input: SignatureInput) throws -> CIImage {
        #if canImport(UIKit)
        // Reconstruct PKDrawing from stroke data
        // PKDrawing(data:) throws if data is invalid, returns nil if init fails
        guard let drawing = try? PKDrawing(data: input.strokeData) else {
            throw PipelineError.invalidImageData
        }

        // Rasterize at 3x scale for Retina-quality output on high-res sources
        let rasterImage = drawing.image(from: drawing.bounds, scale: 3.0)

        // Convert UIImage → CIImage via CGImage path
        guard let cgImage = rasterImage.cgImage else {
            throw PipelineError.renderFailed
        }
        let ciImage = CIImage(cgImage: cgImage)

        // Apply ink color via color matrix — multiply RGB channels by
        // inkColor components while preserving alpha from the drawing.
        let components = input.inkColor.components ?? [0, 0, 0, 1]
        let r = CGFloat(components.count > 0 ? components[0] : 0)
        let g = CGFloat(components.count > 1 ? components[1] : 0)
        let b = CGFloat(components.count > 2 ? components[2] : 0)

        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = ciImage
        // Multiply RGB channels by ink color, pass through alpha
        colorMatrix.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
        colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        colorMatrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)

        return colorMatrix.outputImage ?? ciImage

        #else
        // Non-iOS platforms: return an empty 1x1 CIImage
        return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        #endif
    }
}
