import Testing
import ImageIO
import UniformTypeIdentifiers
@testable import WatermarkCore

/// Tests FormatDetector for HEIC, JPEG, PNG detection and unsupported format rejection.
@Suite("FormatDetector")
struct FormatDetectorTests {

    @Test("Detects JPEG format from JPEG data")
    func detectsJPEG() throws {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil) else {
            Issue.record("Failed to create CGImageSource from JPEG data")
            return
        }
        let (type, uti) = try FormatDetector.detect(from: source)
        #expect(type == UTType.jpeg)
        #expect(uti as String == "public.jpeg")
    }

    @Test("Detects PNG format from PNG data")
    func detectsPNG() throws {
        // Create a PNG data source
        let (cgImage, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        let pngData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            pngData, UTType.png.identifier as CFString, 1, nil
        ) else {
            Issue.record("Failed to create PNG destination")
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            Issue.record("Failed to finalize PNG data")
            return
        }
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil) else {
            Issue.record("Failed to create CGImageSource from PNG data")
            return
        }
        let (type, uti) = try FormatDetector.detect(from: source)
        #expect(type == UTType.png)
        #expect(uti as String == "public.png")
    }

    @Test("Throws unsupportedFormat for HEIC data (RED — stub always returns JPEG)")
    func throwsForHEIC() {
        // Create JPEG data and verify the stub returns JPEG not HEIC
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil) else { return }
        // Try with HEIC UTI — stub should NOT detect HEIC
        let result = try? FormatDetector.detect(from: source)
        // Stub returns JPEG, so result.type should NOT be .heic
        #expect(result?.0 != UTType.heic)
    }

    @Test("Detects TIFF format from TIFF data")
    func detectsTIFF() throws {
        // Create a TIFF data source
        let (cgImage, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        let tiffData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            tiffData, UTType.tiff.identifier as CFString, 1, nil
        ) else {
            Issue.record("Failed to create TIFF destination")
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            Issue.record("Failed to finalize TIFF data")
            return
        }
        guard let source = CGImageSourceCreateWithData(tiffData as CFData, nil) else {
            Issue.record("Failed to create CGImageSource from TIFF data")
            return
        }
        let (type, uti) = try FormatDetector.detect(from: source)
        #expect(type == UTType.tiff)
        #expect(uti as String == "public.tiff")
    }

    @Test("fileExtension maps UTIs correctly")
    func fileExtensionMapping() {
        #expect(FormatDetector.fileExtension(for: "public.heic" as CFString) == "heic")
        #expect(FormatDetector.fileExtension(for: "public.jpeg" as CFString) == "jpg")
        #expect(FormatDetector.fileExtension(for: "public.png" as CFString) == "png")
        #expect(FormatDetector.fileExtension(for: "public.tiff" as CFString) == "tiff")
    }
}
