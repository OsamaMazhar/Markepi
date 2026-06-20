import AVFoundation
import CoreGraphics
import CoreImage
import Foundation

/// Builds a CALayer hierarchy from a `WatermarkConfiguration` for use with
/// `AVVideoCompositionCoreAnimationTool`.
///
/// Constructs a parent `CALayer` containing a video sublayer plus watermark
/// overlay layers (text, image/logo, and white frame). Coordinates are
/// calculated using `PositionCalculator` and converted from CIImage
/// bottom-left origin to CALayer top-left origin.
///
/// This is the video-side counterpart of the CIFilter graph built in
/// `WatermarkEngine.buildFilterGraph()` — full parity with photo watermarking
/// for text, image, white frame, and all 9 positions (D-02).
public struct VideoLayerBuilder {

    /// Builds a CALayer hierarchy for watermark compositing during video export.
    ///
    /// - Parameters:
    ///   - config: Watermark configuration (layers, white frame, padding)
    ///   - videoSize: The render size of the video composition
    /// - Returns: A tuple of `(parentLayer: CALayer, videoLayer: CALayer)` where
    ///   `parentLayer` contains all sublayers and `videoLayer` is the video track layer
    /// - Throws: `PipelineError` if watermark rendering fails
    public static func buildLayers(
        config: WatermarkConfiguration,
        videoSize: CGSize
    ) throws -> (parentLayer: CALayer, videoLayer: CALayer) {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        // Build white frame layer below all watermark layers (if enabled)
        // D-02: White frame parity with photos
        if let frameConfig = config.whiteFrame, frameConfig.isEnabled {
            let frameLayer = try buildWhiteFrameLayer(
                config: frameConfig,
                baseExtent: CGRect(origin: .zero, size: videoSize),
                videoSize: videoSize
            )
            parentLayer.addSublayer(frameLayer)
        }

        // Build watermark layers in order: bottom → top (D-01, D-02)
        for watermark in config.watermarks {
            let watermarkLayer = try buildWatermarkLayer(
                watermark: watermark,
                videoSize: videoSize,
                padding: config.padding
            )
            parentLayer.addSublayer(watermarkLayer)
        }

        return (parentLayer, videoLayer)
    }

    // MARK: - Watermark Layer Building

    /// Builds a single watermark CALayer from a `WatermarkLayer` enum case.
    private static func buildWatermarkLayer(
        watermark: WatermarkLayer,
        videoSize: CGSize,
        padding: CGFloat
    ) throws -> CALayer {
        let cgImage: CGImage
        let scale: CGFloat

        switch watermark {
        case .text(let textConfig, _, let s, _, _):
            scale = s
            let ciImage = TextWatermarkRenderer.render(config: textConfig)
            cgImage = try renderToCGImage(ciImage)

        case .image(let imageConfig, _, let s, _, _):
            scale = s
            let ciImage = try ImageWatermarkRenderer.render(config: imageConfig)
            cgImage = try renderToCGImage(ciImage)

        case .signature(let signatureInput, _, let s, _, _):
            scale = s
            let ciImage = try SignatureRenderer.render(input: signatureInput)
            cgImage = try renderToCGImage(ciImage)
        }

        let wmLayer = CALayer()
        wmLayer.contents = cgImage
        wmLayer.contentsGravity = .resizeAspect

        // Scale the watermark extent relative to the video width (scale is a
        // fraction of width — see WatermarkScaling), matching the photo path
        // in WatermarkEngine.buildFilterGraph for full parity.
        let factor = WatermarkScaling.transformFactor(
            layerScale: scale,
            naturalWidth: CGFloat(cgImage.width),
            baseWidth: videoSize.width
        )
        let scaledWidth = CGFloat(cgImage.width) * factor
        let scaledHeight = CGFloat(cgImage.height) * factor
        let scaledExtent = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)

        // Calculate position using shared PositionCalculator (CIImage bottom-left coords)
        let ciPosition = PositionCalculator.position(
            for: watermark.position,
            watermarkExtent: scaledExtent,
            baseExtent: CGRect(origin: .zero, size: videoSize),
            padding: padding
        )

        // Convert CIImage bottom-left → CALayer top-left coordinates
        // CIImage: (0,0) at bottom-left, +Y up
        // CALayer:  (0,0) at top-left,    +Y down
        let calayerY = videoSize.height - ciPosition.y - scaledHeight
        wmLayer.frame = CGRect(
            origin: CGPoint(x: ciPosition.x, y: calayerY),
            size: scaledExtent.size
        )

        return wmLayer
    }

    // MARK: - White Frame Layer Building

    /// Builds a white frame CALayer for video compositing.
    ///
    /// Renders the white frame via `WhiteFrameRenderer` with empty metadata
    /// (videos don't carry EXIF in the same way as photos), converts to CGImage,
    /// and creates a CALayer with the frame contents.
    private static func buildWhiteFrameLayer(
        config: WhiteFrameConfig,
        baseExtent: CGRect,
        videoSize: CGSize
    ) throws -> CALayer {
        // Videos don't have EXIF metadata — pass empty dict
        let frameCIImage = try WhiteFrameRenderer.render(
            config: config,
            baseExtent: baseExtent,
            metadata: [:],
            scale: 1.0
        )

        let cgImage = try renderToCGImage(frameCIImage)

        let frameLayer = CALayer()
        frameLayer.contents = cgImage
        frameLayer.contentsGravity = .resizeAspect
        frameLayer.frame = CGRect(origin: .zero, size: videoSize)

        return frameLayer
    }

    // MARK: - CIImage → CGImage Rasterization

    /// Renders a CIImage to a CGImage via the shared CIContext.
    ///
    /// Uses `CIContextProvider.shared` for GPU reuse (per Pitfall 4).
    /// Uses `.RGBAh` format for HDR-capable pixel data.
    private static func renderToCGImage(_ ciImage: CIImage) throws -> CGImage {
        let extent = ciImage.extent
        guard !extent.isEmpty, !extent.isInfinite else {
            throw PipelineError.renderFailed
        }

        guard let cgImage = CIContextProvider.shared.createCGImage(
            ciImage,
            from: extent,
            format: .RGBAh,
            colorSpace: nil
        ) else {
            throw PipelineError.renderFailed
        }

        return cgImage
    }
}
