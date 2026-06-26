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
        videoSize: CGSize,
        metadata: [String: Any] = [:]
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
                videoSize: videoSize,
                metadata: metadata
            )
            parentLayer.addSublayer(frameLayer)
        }

        // When the white frame is enabled, position watermarks within the inner
        // content rect (inset by the frame width) so corner/edge placements land
        // just inside the border and stay clear of it — matching the photo path
        // in WatermarkEngine.buildFilterGraph. Frame width matches
        // WhiteFrameRenderer: shorter dimension × frameWidthRatio.
        let frameInset: CGFloat = {
            guard let frame = config.whiteFrame, frame.isEnabled else { return 0 }
            return min(videoSize.width, videoSize.height) * frame.frameWidthRatio
        }()
        let positioningExtent = CGRect(origin: .zero, size: videoSize)
            .insetBy(dx: frameInset, dy: frameInset)

        // Build watermark layers in order: bottom → top (D-01, D-02)
        for watermark in config.watermarks {
            let watermarkLayer = try buildWatermarkLayer(
                watermark: watermark,
                videoSize: videoSize,
                positioningExtent: positioningExtent,
                padding: config.padding
            )
            parentLayer.addSublayer(watermarkLayer)
        }

        // Retro date stamp — above watermark layers, parity with the photo path
        // in WatermarkEngine.buildFilterGraph. Scaled by HEIGHT (digit height as
        // a fraction of the video height).
        if let dateConfig = config.dateStamp,
           let stampCI = DateStampRenderer.render(config: dateConfig, metadata: metadata) {
            let cgImage = try renderToCGImage(stampCI)
            let factor = WatermarkScaling.transformFactor(
                layerScale: dateConfig.sizeRatio,
                naturalWidth: CGFloat(cgImage.height),
                baseWidth: videoSize.height
            )
            let scaledWidth = CGFloat(cgImage.width) * factor
            let scaledHeight = CGFloat(cgImage.height) * factor
            let scaledExtent = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)

            var ciPosition = PositionCalculator.position(
                for: dateConfig.position,
                watermarkExtent: scaledExtent,
                baseExtent: positioningExtent,
                padding: config.padding
            )
            ciPosition.x += positioningExtent.origin.x
            ciPosition.y += positioningExtent.origin.y

            let dateLayer = CALayer()
            dateLayer.contents = cgImage
            dateLayer.contentsGravity = .resizeAspect
            let calayerY = videoSize.height - ciPosition.y - scaledHeight
            dateLayer.frame = CGRect(origin: CGPoint(x: ciPosition.x, y: calayerY), size: scaledExtent.size)
            parentLayer.addSublayer(dateLayer)
        }

        return (parentLayer, videoLayer)
    }

    // MARK: - Watermark Layer Building

    /// Builds a single watermark CALayer from a `WatermarkLayer` enum case.
    private static func buildWatermarkLayer(
        watermark: WatermarkLayer,
        videoSize: CGSize,
        positioningExtent: CGRect,
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

        // Calculate position using shared PositionCalculator (CIImage bottom-left coords).
        // Positioned against the (possibly frame-inset) inner content rect; the
        // size-relative result is then offset by the inner rect origin.
        var ciPosition = PositionCalculator.position(
            for: watermark.position,
            watermarkExtent: scaledExtent,
            baseExtent: positioningExtent,
            padding: padding
        )
        ciPosition.x += positioningExtent.origin.x
        ciPosition.y += positioningExtent.origin.y

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
    /// Renders the white frame via `WhiteFrameRenderer` with the video's
    /// metadata (device/model, creation date, dimensions, format — extracted in
    /// `VideoProcessor`), converts to CGImage, and creates the frame CALayer.
    private static func buildWhiteFrameLayer(
        config: WhiteFrameConfig,
        baseExtent: CGRect,
        videoSize: CGSize,
        metadata: [String: Any]
    ) throws -> CALayer {
        let frameCIImage = try WhiteFrameRenderer.render(
            config: config,
            baseExtent: baseExtent,
            metadata: metadata,
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
