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
        metadata: [String: Any] = [:],
        isHDR: Bool = false
    ) throws -> (parentLayer: CALayer, videoLayer: CALayer, renderSize: CGSize) {
        // Match overlay rasterization to the export bit depth. Half-float only
        // for HDR; 8-bit for SDR so the CoreAnimation compositor / VT compression
        // session isn't handed an unsupported pixel format (see VideoProcessor).
        let overlayFormat: CIFormat = isHDR ? .RGBAh : .RGBA8

        // The mat sits outside the video, so a framed export is larger than its
        // source — same rule as photos, from the same type, which is what keeps
        // the two geometries comparable.
        let frameConfig = config.whiteFrame?.isEnabled == true ? config.whiteFrame : nil
        let geometry = frameConfig.map {
            FrameGeometry(config: $0, sourceSize: videoSize,
                          dpi: FrameGeometry.resolveDPI(from: metadata),
                          hasCaptionContent: WhiteFrameRenderer.hasCaptionContent(
                              config: $0, metadata: metadata))
        }
        let renderSize = geometry?.framedSize ?? videoSize

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)

        let videoLayer = CALayer()
        // Where the video sits inside the framed canvas. Core Animation's
        // compositing space is y-up, so the vertical offset is the BOTTOM mat —
        // for gallery that is the tall caption band, not the thin top edge.
        // This is the one piece of the geometry the Simulator cannot verify
        // (its CoreMedia XPC fault aborts video export), so it is what a device
        // check is actually checking.
        videoLayer.frame = geometry.map {
            CGRect(x: $0.left, y: $0.bottom, width: videoSize.width, height: videoSize.height)
        } ?? parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        // Mat layer above the video, covering the whole canvas; its transparent
        // hole lines up with videoLayer.
        if let frameConfig, let geometry {
            let frameLayer = try buildWhiteFrameLayer(
                config: frameConfig,
                geometry: geometry,
                metadata: metadata,
                format: overlayFormat
            )
            parentLayer.addSublayer(frameLayer)
        }

        // Watermarks position against the video itself, offset into the canvas.
        // They used to be inset by the frame width because the mat covered the
        // video's outer edge; with the mat outside there is nothing to dodge.
        let positioningExtent = videoLayer.frame

        // Build watermark layers in order: bottom → top (D-01, D-02)
        for watermark in config.watermarks {
            let watermarkLayer = try buildWatermarkLayer(
                watermark: watermark,
                videoSize: videoSize,
                positioningExtent: positioningExtent,
                padding: config.padding,
                format: overlayFormat
            )
            parentLayer.addSublayer(watermarkLayer)
        }

        // Retro date stamp — above watermark layers, parity with the photo path
        // in WatermarkEngine.buildFilterGraph. Scaled by HEIGHT (digit height as
        // a fraction of the video height).
        if let dateConfig = config.dateStamp,
           let stampCI = DateStampRenderer.render(config: dateConfig, metadata: metadata) {
            let cgImage = try renderToCGImage(stampCI, format: overlayFormat)
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
            // PositionCalculator + standalone CALayer both use a bottom-left
            // origin, so ciPosition maps directly to frame.origin (no flip).
            dateLayer.frame = CGRect(origin: ciPosition, size: scaledExtent.size)
            parentLayer.addSublayer(dateLayer)
        }

        return (parentLayer, videoLayer, renderSize)
    }

    // MARK: - Watermark Layer Building

    /// Builds a single watermark CALayer from a `WatermarkLayer` enum case.
    private static func buildWatermarkLayer(
        watermark: WatermarkLayer,
        videoSize: CGSize,
        positioningExtent: CGRect,
        padding: CGFloat,
        format: CIFormat
    ) throws -> CALayer {
        let cgImage: CGImage
        let scale: CGFloat
        // Width the scale factor keys off. For a rotated logo this is the
        // UPRIGHT width so rotation doesn't change apparent size — parity with
        // the photo path, which scales BEFORE rotating (text keys off height).
        let scaleNaturalWidth: CGFloat

        switch watermark {
        case .text(let textConfig, _, let s, _, _):
            scale = s
            let ciImage = TextWatermarkRenderer.render(config: textConfig)
            cgImage = try renderToCGImage(ciImage, format: format)
            scaleNaturalWidth = CGFloat(cgImage.height)

        case .image(let imageConfig, _, let s, _, _):
            scale = s
            let ciImage = try ImageWatermarkRenderer.render(config: imageConfig)
            scaleNaturalWidth = ciImage.extent.width
            let rotated = ImageWatermarkRenderer.rotated(ciImage, degrees: imageConfig.rotationDegrees)
            cgImage = try renderToCGImage(rotated, format: format)

        case .signature(let signatureInput, _, let s, _, _):
            scale = s
            let ciImage = try SignatureRenderer.render(input: signatureInput)
            cgImage = try renderToCGImage(ciImage, format: format)
            scaleNaturalWidth = CGFloat(cgImage.width)
        }

        let wmLayer = CALayer()
        wmLayer.contents = cgImage
        wmLayer.contentsGravity = .resizeAspect

        // Scale watermark relative to the video, matching the photo path in
        // WatermarkEngine.buildFilterGraph for full parity.
        //
        // Text scales by HEIGHT so editing the text — which changes its width —
        // does not change the apparent font size (scale == font height as a
        // fraction of video height; see WatermarkConfiguration.defaultTextScale).
        // Image/signature scale by WIDTH, where the aspect ratio is fixed so
        // width is the natural control.
        //
        // IMPORTANT: this used to scale EVERY layer (text included) by width.
        // Because text's `scale` semantically means "fraction of height", that
        // made the font render far too small on landscape video AND shifted the
        // corner-placement geometry (PositionCalculator keys off the scaled
        // extent), so a `.bottomRight` text watermark could land at the top.
        let factor: CGFloat
        if case .text = watermark {
            factor = WatermarkScaling.transformFactor(
                layerScale: scale,
                naturalWidth: scaleNaturalWidth,
                baseWidth: videoSize.height
            )
        } else {
            factor = WatermarkScaling.transformFactor(
                layerScale: scale,
                naturalWidth: scaleNaturalWidth,
                baseWidth: videoSize.width
            )
        }
        let scaledWidth = CGFloat(cgImage.width) * factor
        let scaledHeight = CGFloat(cgImage.height) * factor
        let scaledExtent = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)

        // Calculate position using shared PositionCalculator (bottom-left coords).
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

        // A standalone CALayer rendered by AVVideoCompositionCoreAnimationTool
        // uses a BOTTOM-LEFT origin — the same convention as CIImage, which is
        // what PositionCalculator produces. So ciPosition maps directly to the
        // layer's frame.origin with NO vertical flip.
        //
        // (The previous `videoSize.height - y - scaledHeight` flip assumed a
        // UIKit-backed top-left layer origin. That inverted every vertical
        // position: bottom presets rendered at the top, and vice versa. It was
        // masked by the prior text-scaling-by-width bug, which mis-sized the
        // extent enough to coincidentally land text near the bottom.)
        wmLayer.frame = CGRect(
            origin: ciPosition,
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
        geometry: FrameGeometry,
        metadata: [String: Any],
        format: CIFormat
    ) throws -> CALayer {
        let frameCIImage = try WhiteFrameRenderer.render(
            config: config,
            geometry: geometry,
            metadata: metadata,
            scale: 1.0
        )

        let cgImage = try renderToCGImage(frameCIImage, format: format)

        let frameLayer = CALayer()
        frameLayer.contents = cgImage
        frameLayer.contentsGravity = .resizeAspect
        frameLayer.frame = CGRect(origin: .zero, size: geometry.framedSize)

        return frameLayer
    }

    // MARK: - CIImage → CGImage Rasterization

    /// Renders a CIImage to a CGImage via the shared CIContext.
    ///
    /// Uses `CIContextProvider.shared` for GPU reuse (per Pitfall 4).
    /// `format` matches the export bit depth: `.RGBAh` (16-bit half-float) for
    /// HDR, `.RGBA8` (8-bit) for SDR. An SDR export handed half-float overlay
    /// layers drives the CoreAnimation compositor / VT compression session down
    /// an unsupported-pixel-format path that aborts in CoreMedia's XPC layer.
    private static func renderToCGImage(_ ciImage: CIImage, format: CIFormat) throws -> CGImage {
        let extent = ciImage.extent
        guard !extent.isEmpty, !extent.isInfinite else {
            throw PipelineError.renderFailed
        }

        guard let cgImage = CIContextProvider.shared.createCGImage(
            ciImage,
            from: extent,
            format: format,
            colorSpace: nil
        ) else {
            throw PipelineError.renderFailed
        }

        return cgImage
    }
}
