import Testing
import ImageIO
import CoreImage
import Foundation
@testable import WatermarkCore

/// Verifies the export alpha-channel policy:
/// - a source with **no** alpha (JPEG/HEIC/RAW) is flattened to opaque — the
///   4th channel is *merged* onto the RGB pixels (composited over opaque white),
///   not truncated — so the file has no alpha channel and ImageIO no longer
///   warns about `AlphaPremulLast` on an opaque image; and
/// - a source with **real** transparency keeps its alpha channel when the format
///   supports it.
///
/// See `ImageWriter.flattenToOpaque`, `WatermarkEngine.outputFormatSupportsAlpha`,
/// and `ImageLoader.detectAlpha`.
@Suite("ImageWriter Alpha Preservation")
struct ImageWriterAlphaTests {

    // MARK: - Helpers

    private struct TestImageError: Error {}

    /// A CGImage with a REAL alpha channel and a partial-alpha region:
    /// left half opaque red, right half full-saturation red at 50% opacity.
    /// In a `premultipliedLast` context straight `(1,0,0,0.5)` is stored as
    /// premultiplied `(0.5,0,0)` — so flattening that over opaque white yields
    /// pink `(1.0,0.5,0.5)`, which is the signature that distinguishes a correct
    /// *merge* from a *truncation* (truncation would leave dark red `(0.5,0,0)`).
    private func imageWithTransparency(
        size: CGSize = CGSize(width: 40, height: 40)
    ) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw TestImageError()
        }
        // Left half: opaque red.
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        // Right half: full-saturation red at 50% opacity (premultiplied 0.5,0,0).
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        guard let image = context.makeImage() else { throw TestImageError() }
        return image
    }

    /// True iff the image carries a usable alpha channel (mirrors
    /// `ImageLoader.alphaInfoIndicatesAlpha`).
    private func hasRealAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly:
            return true
        @unknown default:
            return false
        }
    }

    /// Samples an RGBA8 (premultipliedLast) pixel from a CGImage.
    private func rgba(
        _ image: CGImage,
        at point: CGPoint
    ) -> (UInt8, UInt8, UInt8, UInt8)? {
        guard let data = TestImageFactory.pixelData(from: image) else { return nil }
        let bytesPerRow = image.width * 4
        let x = Int(point.x)
        let y = Int(point.y)
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        let index = y * bytesPerRow + x * 4
        guard index + 3 < data.count else { return nil }
        return (data[index], data[index + 1], data[index + 2], data[index + 3])
    }

    private func readBack(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - ImageWriter: preserveAlpha behavior

    @Test("Transparent source keeps its alpha channel when preserveAlpha is true")
    func transparentSourceKeepsAlpha() throws {
        let source = try imageWithTransparency()
        #expect(hasRealAlpha(source), "test setup: source must have a real alpha channel")

        let data = try ImageWriter.write(
            cgImage: source,
            metadata: [:],
            gainMapAuxData: nil,
            dngMetadata: nil,
            destinationUTI: "public.png",
            quality: 1.0,
            preserveAlpha: true
        )

        guard let output = readBack(data) else {
            Issue.record("Failed to read back PNG output")
            return
        }
        #expect(hasRealAlpha(output), "PNG output must retain the alpha channel")
    }

    @Test("Flatten merges alpha onto RGB and drops the channel (preserveAlpha false)")
    func flattenMergesAlphaAndDropsChannel() throws {
        let source = try imageWithTransparency()

        let data = try ImageWriter.write(
            cgImage: source,
            metadata: [:],
            gainMapAuxData: nil,
            dngMetadata: nil,
            destinationUTI: "public.png",
            quality: 1.0,
            preserveAlpha: false
        )

        guard let output = readBack(data) else {
            Issue.record("Failed to read back PNG output")
            return
        }

        // (1) The channel is dropped — output must be opaque.
        #expect(!hasRealAlpha(output), "Flattened output must have NO alpha channel")

        // (2) The alpha was MERGED onto opaque white, not truncated. The right
        // half was premultiplied (0.5,0,0) @ a=0.5; over white that composites
        // to opaque pink (255,128,128). Truncation would instead yield dark red
        // ~(128,0,0).
        let pixel = rgba(output, at: CGPoint(x: output.width * 3 / 4, y: output.height / 2))
        guard let (r, g, b, a) = pixel else {
            Issue.record("Failed to sample flattened output pixel")
            return
        }
        #expect(a >= 250, "Flattened pixel must be fully opaque, got alpha \(a)")
        #expect(abs(Int(r) - 255) <= 5, "Red should be ~255 (merged over white), got \(r)")
        #expect(abs(Int(g) - 128) <= 8, "Green should be ~128, got \(g)")
        #expect(abs(Int(b) - 128) <= 8, "Blue should be ~128, got \(b)")
    }

    @Test("Opaque JPEG export carries no alpha channel")
    func opaqueJpegHasNoAlpha() throws {
        // preserveAlpha: false mirrors the engine's path for opaque sources
        // (JPEG/HEIC/RAW). JPEG cannot encode alpha; this asserts the flatten
        // path still yields a valid, fully-opaque JPEG.
        let (source, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1),
            size: CGSize(width: 60, height: 40)
        )
        let data = try ImageWriter.write(
            cgImage: source,
            metadata: [:],
            gainMapAuxData: nil,
            dngMetadata: nil,
            destinationUTI: "public.jpeg",
            quality: 0.9,
            preserveAlpha: false
        )
        guard let output = readBack(data) else {
            Issue.record("Failed to read back JPEG output")
            return
        }
        #expect(!hasRealAlpha(output), "JPEG output must not carry an alpha channel")
    }

    // MARK: - Engine: end-to-end alpha detection + wiring

    @Test("Engine preserves alpha for a transparent PNG source (end-to-end)")
    func enginePreservesAlphaForTransparentPNG() async throws {
        // Write a transparent source PNG to disk for the engine to load.
        let transparent = try imageWithTransparency()
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alpha_src_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: inputURL) }
        guard let destination = CGImageDestinationCreateWithURL(
            inputURL as CFURL, "public.png" as CFString, 1, nil
        ) else {
            Issue.record("Failed to create CGImageDestination for source PNG")
            return
        }
        CGImageDestinationAddImage(destination, transparent, nil)
        guard CGImageDestinationFinalize(destination) else {
            Issue.record("Failed to finalize source PNG")
            return
        }

        let engine = WatermarkEngine()
        let result = try await engine.process(
            sourceURL: inputURL,
            config: WatermarkConfiguration(outputFormat: .png)
        )
        guard let outputURL = result.url else {
            Issue.record("Engine produced no output URL")
            return
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        guard let cgSource = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              let output = CGImageSourceCreateImageAtIndex(cgSource, 0, nil) else {
            Issue.record("Failed to read back engine output")
            return
        }
        #expect(
            hasRealAlpha(output),
            "Transparent PNG source exported as PNG must retain its alpha channel"
        )
    }
}
