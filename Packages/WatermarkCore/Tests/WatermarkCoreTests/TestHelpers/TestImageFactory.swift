import Foundation
import CoreImage
import CoreVideo
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
    ///   - size: Image dimensions in points (the raw, unrotated pixel size)
    ///   - format: CIContext render format (default .RGBA8 for test determinism)
    ///   - orientation: Optional EXIF orientation value (1–8) written into the
    ///     JPEG's `kCGImagePropertyOrientation` tag. When non-nil, the encoded
    ///     image carries this orientation so the engine's load-time normalization
    ///     (`applyOrientationProperty`) can be exercised. Default: nil (no tag,
    ///     equivalent to orientation 1).
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
        format: CIFormat = .RGBA8,
        orientation: Int? = nil
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
        // Embed the EXIF orientation tag when requested so consumers can verify
        // orientation handling end-to-end.
        let properties: CFDictionary? = orientation.map {
            [kCGImagePropertyOrientation: $0] as CFDictionary
        }
        CGImageDestinationAddImage(destination, cgImage, properties)
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

    /// Writes a HEIC file that carries an HDR gain map auxiliary data block and
    /// returns its URL, or `nil` if the platform has no HEVC encoder.
    ///
    /// The gain map is a synthetic single-channel (8-bit luminance) image at
    /// quarter resolution — enough for `CGImageSourceCopyAuxiliaryDataInfoAtIndex`
    /// to report a `kCGImageAuxiliaryDataTypeHDRGainMap` block on read-back, which
    /// is what the engine extracts and re-attaches during processing.
    ///
    /// - Parameter orientation: EXIF orientation tag written into the base image.
    ///   The gain map is stored at half of the *unrotated* (pixel) dimensions,
    ///   matching how cameras store an oriented capture. Use a non-`.up` value to
    ///   exercise the gain-map re-alignment path.
    public static func hdrHEICWithGainMap(
        size: CGSize = CGSize(width: 64, height: 48),
        orientation: CGImagePropertyOrientation = .up
    ) -> URL? {
        let width = Int(size.width)
        let height = Int(size.height)

        // Main (base) image — a solid color is sufficient.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let mainImage = ctx.makeImage() else { return nil }

        // Gain map — quarter-resolution single-channel luminance.
        let gainWidth = max(1, width / 2)
        let gainHeight = max(1, height / 2)
        let gainBytesPerRow = gainWidth
        let gainData = Data(repeating: 180, count: gainBytesPerRow * gainHeight)
        let description: [CFString: Any] = [
            "Width" as CFString: gainWidth,
            "Height" as CFString: gainHeight,
            "BytesPerRow" as CFString: gainBytesPerRow,
            "PixelFormat" as CFString: Int(kCVPixelFormatType_OneComponent8),
        ]
        let auxInfo: [CFString: Any] = [
            kCGImageAuxiliaryDataInfoData: gainData as CFData,
            kCGImageAuxiliaryDataInfoDataDescription: description as CFDictionary,
        ]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_hdr_\(UUID().uuidString).heic")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.heic.identifier as CFString, 1, nil
        ) else {
            return nil // No HEVC encoder available on this platform.
        }
        let imageProperties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation.rawValue,
        ]
        CGImageDestinationAddImage(destination, mainImage, imageProperties as CFDictionary)
        CGImageDestinationAddAuxiliaryDataInfo(
            destination, kCGImageAuxiliaryDataTypeHDRGainMap, auxInfo as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }
}
