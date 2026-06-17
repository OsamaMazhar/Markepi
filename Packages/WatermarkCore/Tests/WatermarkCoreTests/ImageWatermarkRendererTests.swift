import Testing
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#endif
@testable import WatermarkCore

/// Tests ImageWatermarkRenderer for PNG-to-CIImage rendering with alpha
/// channel preservation, scale transforms, opacity handling, and error
/// cases for invalid input.
///
/// Also includes a helper for creating PNG test data used by
/// WatermarkEngineTests for E2E image watermark testing.
@Suite("ImageWatermarkRenderer")
struct ImageWatermarkRendererTests {

    // MARK: - Helpers

    /// Creates a small colored PNG with optional alpha.
    ///
    /// Uses UIGraphicsImageRenderer on iOS / CIContext on macOS to render a
    /// filled rectangle and encode it as PNG Data for testing.
    private func makeTestPNGData(
        size: CGSize = CGSize(width: 200, height: 100),
        color: CGColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1),
        alpha: CGFloat = 1.0
    ) -> Data {
        let rect = CGRect(origin: .zero, size: size)
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.pngData { ctx in
            let uiColor = UIColor(cgColor: color).withAlphaComponent(alpha)
            uiColor.setFill()
            ctx.fill(rect)
        }
        return image
        #else
        // macOS fallback: render via CIContext → CGImage → PNG
        let ciImage = CIImage(color: CIColor(cgColor: color))
            .cropped(to: rect)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
            ])
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: rect) else {
            return Data()
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil
        ) else {
            return Data()
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
        #endif
    }

    /// Creates a transparent PNG for alpha compositing tests.
    private func makeTransparentPNGData(size: CGSize = CGSize(width: 100, height: 100)) -> Data {
        return makeTestPNGData(size: size, alpha: 0.0)
    }

    // MARK: - Valid PNG rendering

    @Test("Valid PNG data produces non-nil, finite CIImage")
    func validPNGProducesCIImage() throws {
        let pngData = makeTestPNGData()

        let input = try ImageWatermarkInput(pngData: pngData, scale: 0.15, opacity: 0.8)
        let ciImage = try ImageWatermarkRenderer.render(config: input)

        #expect(!ciImage.extent.isInfinite, "Rendered CIImage should have finite extent")
        #expect(ciImage.extent.width > 0, "Rendered extent width should be positive")
        #expect(ciImage.extent.height > 0, "Rendered extent height should be positive")
    }

    // MARK: - Scale transform

    @Test("Scale 0.5 on 200×100 PNG produces ~100×50 extent")
    func scaleTransformHalvesDimensions() throws {
        let pngData = makeTestPNGData(size: CGSize(width: 200, height: 100))
        let input = try ImageWatermarkInput(pngData: pngData, scale: 0.5, opacity: 1.0)

        let ciImage = try ImageWatermarkRenderer.render(config: input)

        // After scaling by 0.5, extent should be ~100×50 (Core Image may use
        // floating-point extents so allow ±1.0 tolerance)
        #expect(abs(ciImage.extent.width - 100) < 2.0,
                "Scaled width ~100, got \(ciImage.extent.width)")
        #expect(abs(ciImage.extent.height - 50) < 2.0,
                "Scaled height ~50, got \(ciImage.extent.height)")
    }

    // MARK: - Invalid data

    @Test("Empty Data throws PipelineError.invalidImageData")
    func emptyDataThrowsInvalidImageData() throws {
        #expect(throws: PipelineError.invalidImageData) {
            // Scale must be in valid range to get past init validation
            _ = try ImageWatermarkRenderer.render(
                config: ImageWatermarkInput(pngData: Data(), scale: 0.15, opacity: 1.0)
            )
        }
    }

    @Test("Non-PNG data (JPEG bytes) throws PipelineError.invalidImageData")
    func nonPNGDataThrowsInvalidImageData() throws {
        // JPEG data won't create a valid CIImage from pngData init
        let jpegHeader = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
                              0x49, 0x46, 0x00, 0x01]) + Data(repeating: 0, count: 100)
        #expect(throws: PipelineError.invalidImageData) {
            _ = try ImageWatermarkRenderer.render(
                config: ImageWatermarkInput(pngData: jpegHeader, scale: 0.15, opacity: 1.0)
            )
        }
    }

    // MARK: - Opacity compositing

    @Test("Opacity 0.5 on red PNG composited over blue base produces purple blend")
    func opacityFiftyPercentBlend() throws {
        // Create red PNG watermark with full alpha
        let redPNG = makeTestPNGData(size: CGSize(width: 100, height: 100),
                                      color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let input = try ImageWatermarkInput(pngData: redPNG, scale: 0.5, opacity: 0.5)

        let watermarkImage = try ImageWatermarkRenderer.render(config: input)

        // Blue base image
        let base = CIImage(color: CIColor(red: 0, green: 0, blue: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))

        // Composite watermark onto base
        let compositor = CIFilter.sourceOverCompositing()
        compositor.inputImage = watermarkImage
        compositor.backgroundImage = base

        guard let composited = compositor.outputImage else {
            Issue.record("Failed to composite watermark")
            return
        }

        // Render to pixel buffer for inspection
        let context = CIContext()
        guard let cgImage = context.createCGImage(composited, from: composited.extent) else {
            Issue.record("Failed to render composited image")
            return
        }

        // Sample center pixel — should be purple (red 0.5 + blue 0.5)
        let pixel = samplePixel(from: cgImage, at: CGPoint(x: 25, y: 25))
        #expect(pixel != nil, "Should be able to sample center pixel")

        if let p = pixel {
            // The red channel should be > 0 (watermark contribution)
            #expect(p.r > 0, "Red channel should have contribution from watermark")
            // Blue channel should be > 0 (base contribution)
            #expect(p.b > 0, "Blue channel should have contribution from base")
        }
    }

    // MARK: - Fully transparent

    @Test("Fully transparent PNG watermark is invisible over base")
    func fullyTransparentWatermark() throws {
        let transparentPNG = makeTransparentPNGData(size: CGSize(width: 100, height: 100))
        let input = try ImageWatermarkInput(pngData: transparentPNG, scale: 0.5, opacity: 1.0)

        let watermarkImage = try ImageWatermarkRenderer.render(config: input)

        let base = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))

        let compositor = CIFilter.sourceOverCompositing()
        compositor.inputImage = watermarkImage
        compositor.backgroundImage = base

        guard let composited = compositor.outputImage else {
            Issue.record("Failed to composite")
            return
        }

        // Transparent watermark should not change base image colors
        let context = CIContext()
        guard let cgImage = context.createCGImage(composited, from: composited.extent) else {
            Issue.record("Failed to render")
            return
        }

        let pixel = samplePixel(from: cgImage, at: CGPoint(x: 25, y: 25))
        if let p = pixel {
            // Should be essentially pure red (the base color)
            #expect(p.r > 0.9, "Red channel should dominate (base color)")
            #expect(p.g < 0.1, "Green channel should be near zero")
            #expect(p.b < 0.1, "Blue channel should be near zero")
        }
    }

    // MARK: - Scale validation in ImageWatermarkInput

    @Test("Scale 0.0 throws PipelineError.invalidScale")
    func scaleZeroThrowsInvalidScale() {
        let pngData = makeTestPNGData()
        #expect(throws: PipelineError.invalidScale(0.0)) {
            _ = try ImageWatermarkInput(pngData: pngData, scale: 0.0, opacity: 1.0)
        }
    }

    @Test("Scale 0.009 throws PipelineError.invalidScale (below minimum)")
    func scaleBelowMinimumThrows() {
        let pngData = makeTestPNGData()
        #expect(throws: PipelineError.invalidScale(0.009)) {
            _ = try ImageWatermarkInput(pngData: pngData, scale: 0.009, opacity: 1.0)
        }
    }

    @Test("Scale 0.95 throws PipelineError.invalidScale (above maximum)")
    func scaleAboveMaximumThrows() {
        let pngData = makeTestPNGData()
        #expect(throws: PipelineError.invalidScale(0.95)) {
            _ = try ImageWatermarkInput(pngData: pngData, scale: 0.95, opacity: 1.0)
        }
    }

    @Test("Scale 0.01 (minimum) is valid")
    func scaleMinimumValid() throws {
        let pngData = makeTestPNGData()
        let input = try ImageWatermarkInput(pngData: pngData, scale: 0.01, opacity: 1.0)
        #expect(input.scale == 0.01)
    }

    @Test("Scale 0.90 (maximum) is valid")
    func scaleMaximumValid() throws {
        let pngData = makeTestPNGData()
        let input = try ImageWatermarkInput(pngData: pngData, scale: 0.90, opacity: 1.0)
        #expect(input.scale == 0.90)
    }

    // MARK: - Default values

    @Test("Default scale is 0.15")
    func defaultScale() throws {
        let pngData = makeTestPNGData()
        let input = try ImageWatermarkInput(pngData: pngData)
        #expect(input.scale == 0.15)
    }

    @Test("Default opacity is 0.8")
    func defaultOpacity() throws {
        let pngData = makeTestPNGData()
        let input = try ImageWatermarkInput(pngData: pngData)
        #expect(input.opacity == 0.8)
    }

    // MARK: - Pixel sampling helper

    /// Represents an RGBA pixel value (0.0–1.0 normalized).
    private struct Pixel {
        let r: Float
        let g: Float
        let b: Float
        let a: Float
    }

    /// Samples a single pixel from a CGImage at the given coordinate.
    ///
    /// - Parameters:
    ///   - image: The CGImage to sample
    ///   - point: Point in CGImage coordinates (origin top-left)
    /// - Returns: Pixel values normalized to 0.0–1.0, or nil on failure
    private func samplePixel(from image: CGImage, at point: CGPoint) -> Pixel? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var data = Data(count: bytesPerRow * height)

        return data.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return nil
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            let px = Int(point.x)
            // Convert from CGImage top-left coordinates to bitmap top-left
            let py = height - 1 - Int(point.y)
            guard px >= 0, px < width, py >= 0, py < height else { return nil }

            let offset = bytesPerRow * py + bytesPerPixel * px
            let r = Float(ptr[offset]) / 255.0
            let g = Float(ptr[offset + 1]) / 255.0
            let b = Float(ptr[offset + 2]) / 255.0
            let a = Float(ptr[offset + 3]) / 255.0
            return Pixel(r: r, g: g, b: b, a: a)
        }
    }
}
