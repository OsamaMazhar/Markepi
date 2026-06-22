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

    /// The stroke width the signature canvas captures at. `SignatureInput.strokeWidth`
    /// is interpreted relative to this: width == reference renders 1:1, larger
    /// values thicken the strokes, smaller values thin them. Decoupling capture
    /// geometry from display thickness lets thickness be adjusted live after
    /// capture (the "press thick/thin and see it immediately" control).
    public static let referenceStrokeWidth: CGFloat = 3.0

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

        // Apply the configured stroke width as a thickness multiplier by
        // rebuilding each stroke's points with scaled `size`. PencilKit bakes
        // pen width into the per-point geometry, so re-tinting alone cannot
        // change thickness — the points themselves must be rescaled.
        let scaledDrawing = scaleStrokeWidth(of: drawing, by: input.strokeWidth / referenceStrokeWidth)

        // Rasterize at 3x scale for Retina-quality output on high-res sources.
        // Guard against an empty drawing (no strokes) producing a zero-size bounds.
        let bounds = scaledDrawing.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
                .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let rasterImage = scaledDrawing.image(from: bounds, scale: 3.0)

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

    #if canImport(UIKit)
    /// Rebuilds a `PKDrawing` with every stroke point's `size` multiplied by
    /// `factor`, producing thicker (factor > 1) or thinner (factor < 1) strokes
    /// while preserving the drawn shape, ink, transform, and timing. A factor of
    /// exactly 1 returns the drawing untouched (the common, hot path).
    private static func scaleStrokeWidth(of drawing: PKDrawing, by factor: CGFloat) -> PKDrawing {
        let clamped = max(0.1, min(factor, 6.0))
        guard abs(clamped - 1.0) > 0.001 else { return drawing }

        let scaledStrokes: [PKStroke] = drawing.strokes.map { stroke in
            let points: [PKStrokePoint] = stroke.path.map { point in
                PKStrokePoint(
                    location: point.location,
                    timeOffset: point.timeOffset,
                    size: CGSize(width: point.size.width * clamped, height: point.size.height * clamped),
                    opacity: point.opacity,
                    force: point.force,
                    azimuth: point.azimuth,
                    altitude: point.altitude
                )
            }
            let newPath = PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate)
            return PKStroke(ink: stroke.ink, path: newPath, transform: stroke.transform, mask: stroke.mask)
        }
        return PKDrawing(strokes: scaledStrokes)
    }
    #endif
}
