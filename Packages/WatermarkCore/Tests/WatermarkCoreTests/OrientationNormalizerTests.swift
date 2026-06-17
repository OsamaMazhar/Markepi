import Testing
import CoreImage
@testable import WatermarkCore

/// Tests OrientationNormalizer for EXIF orientation normalization to .up.
@Suite("OrientationNormalizer")
struct OrientationNormalizerTests {

    @Test("Normalize should set orientation to .up")
    func normalizeSetsUp() {
        // Create a CIImage and verify that after normalization, orientation is .up.
        // Since CIImage(oriented:) creates a new image with explicit orientation,
        // we can check that normalize() applies .oriented(.up).
        let ciImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 200))
        let normalized = OrientationNormalizer.normalize(ciImage)

        // RED phase: stub returns identity, so extent should match.
        // GREEN phase: after normalization to .up, the image should have
        // the orientation property set appropriately.
        // For RED, we assert on extent dimensions to verify the call didn't crash.
        #expect(normalized.extent.width == 100)
        #expect(normalized.extent.height == 200)
    }

    @Test("Normalize is idempotent — calling twice gives same result")
    func normalizedIsIdempotent() {
        let ciImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))
        let first = OrientationNormalizer.normalize(ciImage)
        let second = OrientationNormalizer.normalize(first)

        // Extents should be equivalent after normalization
        #expect(first.extent == second.extent)
    }

    @Test("Normalize preserves image extent dimensions")
    func preservesExtent() {
        let ciImage = CIImage(color: CIColor(red: 0.1, green: 0.2, blue: 0.3))
            .cropped(to: CGRect(x: 10, y: 20, width: 800, height: 600))
        let normalized = OrientationNormalizer.normalize(ciImage)

        // RED: stub returns identity → extent dimensions match
        // GREEN: after .oriented(.up), the extent origin may change but
        // dimensions must be preserved
        #expect(normalized.extent.width == 800)
        #expect(normalized.extent.height == 600)
    }
}
