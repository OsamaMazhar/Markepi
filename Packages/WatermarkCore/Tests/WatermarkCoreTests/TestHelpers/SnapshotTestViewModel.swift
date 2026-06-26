#if os(iOS)
import Foundation
import UIKit
import SwiftUI
import WatermarkCore

/// Test-only ViewModel conforming to `ShareExtensionRendering` with
/// pre-populated watermark configuration for snapshot testing.
///
/// Provides the complete ViewModel surface needed by
/// `ShareExtensionRootView`, avoiding dependency on the real
/// `ShareExtensionViewModel`, `NSExtensionContext`, and `CGImageSource`.
@MainActor
@Observable
final class SnapshotTestViewModel {

    // MARK: - WatermarkConfigurable Protocol

    var config: WatermarkConfiguration
    var activeLayerIndex: Int = 1
    var renderingState: RenderingState = .idle
    var errorMessage: String? = nil
    var showError: Bool = false
    var showSaveTemplateAlert: Bool = false
    var showTemplateList: Bool = false
    var hasMultiplePhotos: Bool = false
    var sourceHasHDR: Bool = false
    var sourceFormatLabel: String? = nil

    var outputFormat: OutputFormat {
        get { config.outputFormat }
        set { config.outputFormat = newValue }
    }

    var outputQuality: Float {
        get { config.outputQuality }
        set { config.outputQuality = newValue }
    }

    var whiteFrameEnabled: Bool {
        config.whiteFrame?.isEnabled ?? false
    }

    // MARK: - ShareExtensionRendering Properties

    var previewImage: UIImage? = nil
    var isVideo: Bool = false
    var isLoadingMedia: Bool = false
    var isMultiItem: Bool = false
    var currentItemIndex: Int = 0
    var totalItemCount: Int = 0
    var multiItemProgress: String = ""
    var showHDRWarning: Bool = false
    var hdrWarningMessage: String? = nil
    var showAudioWarning: Bool = false
    var sourceURL: URL? = nil
    var previewIdentifier: String = UUID().uuidString
    var showShareSheet: Bool = false
    var showExportReceipt: Bool = false
    var lastExportReceipt: ExportReceipt? = nil
    var sourceProvenanceReport: SourceProvenanceReport? = nil
    var fullResResult: ProcessingResult? = nil
    var unsupportedType: Bool = false
    var completeRequest: (() -> Void)? = nil

    // MARK: - Protocol Method Stubs

    func renderAndPrepareShare() async {}
    func presentShareSheet() {}
    func cancelVideoExport() {}
    func cancelBatchProcessing() {}
    func cancelProcessing() {}
    func handleShareDismiss() {}
    func generatePreview() async {}
    func processNextItem() async {}
    func openInMainApp() {}

    // MARK: - Init

    /// Creates a SnapshotTestViewModel with pre-populated watermark configuration:
    /// - Text watermark at bottomRight ("Sample Watermark", scale 0.15, opacity 1.0)
    /// - Image watermark at bottomRight (1×1 transparent PNG, scale 0.15, opacity 1.0)
    /// - White frame enabled (isEnabled: true)
    /// - Output format: preserveSource, quality: 1.0
    init() {
        let textLayer = WatermarkLayer.text(
            TextWatermarkInput(
                text: "Sample Watermark",
                fontSize: 48,
                color: CGColor(gray: 1, alpha: 1),
                opacity: 1.0
            ),
            position: .bottomRight,
            scale: 0.15,
            opacity: 1.0,
            isVisible: true
        )

        // 1×1 transparent PNG (67 bytes) — validates layout, not pixel content
        let transparentPNG = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,
            0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00,
            0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
            0x60, 0x82,
        ])

        let imageLayer = WatermarkLayer.image(
            try! ImageWatermarkInput(pngData: transparentPNG),
            position: .bottomRight,
            scale: 0.15,
            opacity: 1.0,
            isVisible: true
        )

        self.config = WatermarkConfiguration(
            watermarks: [textLayer, imageLayer],
            whiteFrame: WhiteFrameConfig(isEnabled: true),
            outputFormat: .preserveSource,
            outputQuality: 1.0
        )
    }
}

// MARK: - Protocol Conformances

extension SnapshotTestViewModel: ShareExtensionRendering {}

// MARK: - SnapshotRenderer

/// Test-only helper that renders a SwiftUI `View` to PNG `Data` using
/// `UIHostingController` and `UIGraphicsImageRenderer`.
///
/// Uses `UIHostingController` rather than `ImageRenderer` for accurate
/// extension-context layout (RESEARCH.md Pitfall 1).
@MainActor
enum SnapshotRenderer {

    enum SnapshotError: Error {
        case renderingFailed
    }

    /// Renders a SwiftUI view to PNG data.
    ///
    /// - Parameters:
    ///   - view: The SwiftUI `View` to render.
    ///   - size: The render bounds in points (default: 430×932, iPhone 16 Pro Max).
    ///   - scale: The render scale factor (default: 3.0, matching iPhone 16 Pro Max).
    /// - Returns: PNG `Data` for the rendered view.
    /// - Throws: `SnapshotError.renderingFailed` if PNG conversion fails.
    static func render<V: View>(
        _ view: V,
        size: CGSize = CGSize(width: 430, height: 932),
        scale: CGFloat = 3.0
    ) throws -> Data {
        let rootView = view.frame(width: size.width, height: size.height)
        let host = UIHostingController(rootView: rootView)

        host.view.bounds = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale

        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format)
        let image = renderer.image { ctx in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }

        guard let pngData = image.pngData() else {
            throw SnapshotError.renderingFailed
        }
        return pngData
    }

    /// Compares two PNG images pixel-by-pixel with a tolerance threshold.
    ///
    /// Uses `UIGraphicsImageRenderer` to decode both images into a common
    /// RGBA bitmap format, then counts per-pixel differences. Returns `true`
    /// when the fraction of different pixels is ≤ `pixelTolerance`.
    ///
    /// - Parameters:
    ///   - actual: PNG `Data` of the rendered view.
    ///   - reference: PNG `Data` of the committed reference image.
    ///   - pixelTolerance: Maximum fraction of differing pixels (default: 0.02).
    /// - Returns: `true` if images match within tolerance, `false` otherwise.
    static func compare(
        actual: Data,
        reference: Data,
        pixelTolerance: Double = 0.02
    ) -> Bool {
        guard let actualImage = UIImage(data: actual),
              let referenceImage = UIImage(data: reference),
              actualImage.size.width == referenceImage.size.width,
              actualImage.size.height == referenceImage.size.height
        else { return false }

        let size = actualImage.size
        guard size.width > 0, size.height > 0 else { return false }

        // Render both images into the same bitmap context for pixel comparison
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let normalizedActual = renderToBitmap(actualImage, size: size, format: format)
        let normalizedReference = renderToBitmap(referenceImage, size: size, format: format)

        guard let normA = normalizedActual, let normR = normalizedReference else { return false }

        let width = Int(size.width)
        let height = Int(size.height)
        let totalPixels = width * height
        guard totalPixels > 0 else { return false }
        let bytesPerRow = 4 * width

        var differentPixelCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                if normA[offset] != normR[offset]
                    || normA[offset + 1] != normR[offset + 1]
                    || normA[offset + 2] != normR[offset + 2]
                    || normA[offset + 3] != normR[offset + 3] {
                    differentPixelCount += 1
                }
            }
        }

        let differenceRatio = Double(differentPixelCount) / Double(totalPixels)
        return differenceRatio <= pixelTolerance
    }

    /// Renders a UIImage into a raw RGBA bitmap using UIGraphicsImageRenderer
    /// and extracts the pixel data via CGContext.
    private static func renderToBitmap(
        _ image: UIImage,
        size: CGSize,
        format: UIGraphicsImageRendererFormat
    ) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = normalized.cgImage else { return nil }

        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerRow = 4 * width
        let totalBytes = bytesPerRow * height

        let pixelData = UnsafeMutableRawPointer.allocate(byteCount: totalBytes, alignment: 1)
        defer { pixelData.deallocate() }
        pixelData.initializeMemory(as: UInt8.self, repeating: 0, count: totalBytes)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.byteOrder32Big)

        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.flush()

        return Data(bytes: pixelData, count: totalBytes)
    }
}
#endif
