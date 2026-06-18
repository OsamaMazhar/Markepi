import Testing
import ImageIO
import CoreImage
import Foundation
@testable import WatermarkCore

@Suite("ProRAW Processing")
struct ProRAWTests {

    /// Spike: verifies whether CGImageDestination supports DNG as a write destination.
    /// Records the result as a documented finding for Plan 05-03 implementation strategy.
    ///
    /// If `CGImageDestinationFinalize` returns true → DNG write IS supported → Plan 05-03 uses DNG output UTI.
    /// If it returns false → DNG write is NOT supported → Plan 05-03 falls back to HEIC output with warning.
    @Test("DNG write path verification — CGImageDestination supports DNG as destination?")
    func testDNGWritePathSupport() throws {
        // 1. Create a minimal test CGImage (64×64 solid color)
        let (cgImage, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0),
            size: CGSize(width: 64, height: 64)
        )

        // 2. Create CGImageDestination with DNG UTI
        let dngUTI = "com.adobe.raw-image" as CFString
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, dngUTI, 1, nil
        ) else {
            // CGImageDestinationCreateWithData returning nil means DNG UTI is unrecognized
            // as a destination type — this is a definitive answer.
            print("[SPIKE] CGImageDestinationCreateWithData returned nil for DNG UTI — DNG write UNSUPPORTED")
            #expect(Bool(true), "Spike completed: DNG write is NOT supported as destination format")
            return
        }

        // 3. Build minimal DNG metadata dictionary
        let dngMetadata: [CFString: Any] = [
            kCGImagePropertyDNGDictionary: [
                kCGImagePropertyDNGVersion: [1, 6, 0, 0],
                kCGImagePropertyDNGBayerGreenSplit: 0,
            ] as CFDictionary
        ]
        let combinedMetadata = dngMetadata as CFDictionary

        // 4. Add image and try to finalize
        CGImageDestinationAddImage(destination, cgImage, combinedMetadata)

        let didFinalize = CGImageDestinationFinalize(destination)

        // 5. Record result
        if didFinalize {
            let bytesWritten = data.length
            print("[SPIKE] DNG write SUPPORTED — \(bytesWritten) bytes written successfully")
            #expect(data.length > 0, "DNG output data should be non-empty")
        } else {
            print("[SPIKE] DNG write UNSUPPORTED — CGImageDestinationFinalize returned false")
        }

        // Structural assertion: spike always passes (it's a probe, not a pass/fail test)
        #expect(Bool(true), "Spike completed: DNG write is \(didFinalize ? "SUPPORTED" : "UNSUPPORTED")")
    }
}
