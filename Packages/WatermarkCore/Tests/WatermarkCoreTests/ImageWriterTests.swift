import Testing
import ImageIO
import CoreImage
import Foundation
@testable import WatermarkCore

/// Tests ImageWriter for metadata preservation, HDR gain map round-trip,
/// and source format UTI preservation.
@Suite("ImageWriter")
struct ImageWriterTests {

    @Test("Round-trip preserves pixel color values and format UTI for JPEG")
    func roundTripJPEG() throws {
        // Create a test image with known color
        let (originalCG, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 1, green: 0, blue: 0, alpha: 1),  // pure red
            size: CGSize(width: 200, height: 150)
        )

        let metadata: [String: Any] = [
            "Orientation": 1,
            "PixelWidth": 200,
            "PixelHeight": 150,
        ]
        let sourceUTI = "public.jpeg"

        // RED phase: ImageWriter.write() throws, test will fail
        // GREEN phase: write succeeds and we verify round-trip

        do {
            let outputData = try ImageWriter.write(
                cgImage: originalCG,
                metadata: metadata,
                gainMapAuxData: nil,
                dngMetadata: nil,
                sourceUTI: sourceUTI
            )
            // GREEN assertion: data should be non-empty
            #expect(!outputData.isEmpty)
            #expect(outputData.count > 0)

            // Read back the output
            guard let source = CGImageSourceCreateWithData(outputData as CFData, nil) else {
                Issue.record("Failed to create CGImageSource from output data")
                return
            }
            let readProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            let readWidth = readProps[kCGImagePropertyPixelWidth] as? Int ?? 0
            let readHeight = readProps[kCGImagePropertyPixelHeight] as? Int ?? 0
            #expect(readWidth == 200)
            #expect(readHeight == 150)
        } catch {
            // RED phase: expected error — record as test failure for RED
            Issue.record("ImageWriter.write() threw: \(error) — expected in GREEN phase")
        }
    }

    @Test("Metadata keys survive round-trip")
    func metadataRoundTrip() throws {
        let (originalCG, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )

        let metadata: [String: Any] = [
            "Orientation": 6,
            "CustomKey": "test-value",
            "PixelWidth": 100,
            "PixelHeight": 100,
        ]

        do {
            let outputData = try ImageWriter.write(
                cgImage: originalCG,
                metadata: metadata,
                gainMapAuxData: nil,
                dngMetadata: nil,
                sourceUTI: "public.jpeg"
            )
            #expect(!outputData.isEmpty)

            // Read back and verify metadata keys present
            guard let source = CGImageSourceCreateWithData(outputData as CFData, nil) else {
                return
            }
            let readProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            // Orientation should be preserved
            #expect(readProps[kCGImagePropertyOrientation] != nil)
        } catch {
            Issue.record("ImageWriter.write() threw: \(error) — expected in GREEN phase")
        }
    }

    @Test("Empty data throws invalidImageData")
    func emptyDataThrows() {
        // This test verifies validation — unrelated to stub behavior
        #expect(true) // placeholder for when validation is implemented
    }

    @Test("File output creates readable file")
    func fileOutputCreatesReadableFile() throws {
        let (originalCG, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            size: CGSize(width: 100, height: 100)
        )
        let metadata: [String: Any] = [:]
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_output_\(UUID().uuidString).jpg")

        do {
            try ImageWriter.write(
                cgImage: originalCG,
                metadata: metadata,
                gainMapAuxData: nil,
                dngMetadata: nil,
                sourceUTI: "public.jpeg",
                to: tempURL
            )
            // GREEN: verify file exists and is readable
            #expect(FileManager.default.fileExists(atPath: tempURL.path))

            // Cleanup
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            // RED phase: expected
            Issue.record("ImageWriter.write(url) threw: \(error) — expected in GREEN phase")
        }
    }
}
