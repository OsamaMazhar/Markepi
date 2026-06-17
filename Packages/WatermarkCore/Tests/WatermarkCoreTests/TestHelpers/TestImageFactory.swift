import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Test helper for creating in-memory test images.
///
/// Avoids reading from disk fixtures for unit tests — all test images
/// are generated programmatically with known properties (color, size, format).
/// Used by PositionCalculatorTests, WatermarkRendererTests, ImageWriterTests,
/// and WatermarkEngineTests to avoid external file dependencies.
public struct TestImageFactory {

    /// Creates a solid-color CGImage and its JPEG data representation.
    ///
    /// - Parameters:
    ///   - color: The fill color (use CGColor with sRGB or displayP3)
    ///   - size: Image dimensions in points
    ///   - format: CIContext render format (default .RGBA8 for test determinism)
    /// - Returns: A tuple of `(CGImage, Data)` where Data is JPEG-encoded bytes
    ///
    /// Example:
    /// ```swift
    /// let (image, data) = TestImageFactory.solidColorImage(
    ///     color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
    ///     size: CGSize(width: 800, height: 600)
    /// )
    /// ```
    public static func solidColorImage(
        color: CGColor,
        size: CGSize,
        format: CIFormat = .RGBA8
    ) -> (CGImage, Data) {
        let rect = CGRect(origin: .zero, size: size)
        let ciImage = CIImage(color: CIColor(cgColor: color)).cropped(to: rect)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: rect) else {
            fatalError("TestImageFactory: Failed to create CGImage")
        }
        // Encode to JPEG Data for test usage
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            fatalError("TestImageFactory: Failed to create CGImageDestination")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("TestImageFactory: Failed to finalize JPEG data")
        }
        return (cgImage, data as Data)
    }

    /// Creates pixel data from a CGImage for test assertions.
    ///
    /// Renders the CGImage to an RGBA8 bitmap and returns the raw pixel bytes.
    /// Useful for verifying pixel color values at specific coordinates.
    public static func pixelData(from cgImage: CGImage) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = Data(count: bytesPerRow * height)

        return pixelData.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress,
                  let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return nil as Data?
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return Data(ptr)
        }
    }

    /// Creates a CGImageSource from JPEG data for format detection tests.
    ///
    /// Returns nil if the data does not represent a valid image.
    public static func imageSource(from data: Data) -> CGImageSource? {
        return CGImageSourceCreateWithData(data as CFData, nil)
    }
}
