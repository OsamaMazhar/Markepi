import AVFoundation
import CoreImage
import Foundation
import ImageIO
import os.log
import UniformTypeIdentifiers

#if DEBUG
private let engineLog = Logger(subsystem: "com.watermark.core", category: "Engine")
#endif

/// Actor-isolated photo watermarking engine (Pattern 3).
///
/// Orchestrates the full input → render → output pipeline:
///   1. Load: `ImageLoader.load(from:)` — extract metadata, HDR, CIImage
///   2. Normalize: `OrientationNormalizer.normalize(_:)` — EXIF → .up
///   3. Build filter graph: composite watermark layers via `WatermarkRenderer`
///   4. Render: `CIContextProvider.shared.createCGImage(...)` — GPU rasterize
///   5. Write: `ImageWriter.write(...)` — re-attach metadata + HDR
///
/// Owns the shared `CIContext` (reused, not created per-operation per Pitfall 4).
/// `CIImage` objects are Sendable-safe and cross actor boundaries.
/// `CIFilter` instances are NOT thread-safe and are created fresh per call.
public actor WatermarkEngine {

    public static let shared = WatermarkEngine()

    /// Shared CIContext with RGBAh + displayP3 configuration (Pitfall 4)
    private let context = CIContextProvider.shared

    // MARK: - Media Type Detection

    /// Detects whether a URL points to a photo, video, or unknown media type.
    public enum MediaType: Sendable {
        case photo
        case video
        case livePhoto
        case unknown
    }

    /// Detects the media type of a file URL by inspecting its UTI.
    ///
    /// - Parameter url: File URL to inspect
    /// - Returns: `.photo`, `.video`, or `.unknown`
    public static func mediaType(for url: URL) -> MediaType {
        guard let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
              let type = UTType(uti) else {
            return .unknown
        }

        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
            return .video
        }

        if type.conforms(to: .image) {
            return .photo
        }

        return .unknown
    }

    // MARK: - Photo Processing
    ///
    /// - Parameters:
    ///   - sourceURL: File URL to the source photo
    ///   - config: Watermark configuration (layers, frame, output format)
    /// - Returns: `ProcessingResult` with the output file URL and format info
    /// - Throws: `PipelineError` for any pipeline stage failure
    ///
    /// Pipeline stages:
    ///   a. Load from URL with metadata/HDR extraction
    ///   b. Normalize EXIF orientation to .up
    ///   c. Build Core Image filter graph (watermark layers composited)
    ///   d. Render via shared CIContext to CGImage
    ///   e. Write to temp file with metadata + HDR re-attached
    ///   f. Return ProcessingResult with temp file URL
    ///
    /// When `provenance` is non-nil (Plan 19-02), the pipeline additionally:
    ///   - analyzes the source provenance (19-01 analyzer),
    ///   - applies the metadata privacy profile to the outgoing metadata dict,
    ///   - merges IPTC rights metadata into the outgoing metadata dict,
    ///   - signs the output with the injected C2PA client when requested,
    ///   - returns an `ExportReceipt` on the `ProcessingResult`.
    /// When `preserveSourceCredentials` is true (real exports — not previews)
    /// and the SOURCE file already carries a C2PA manifest, the export always
    /// gets a new device-signed manifest embedding the source's manifest +
    /// signature as its `parentOf` ingredient — even when the user did not opt
    /// into Content Credentials signing. A C2PA signature is bound to the exact
    /// source bytes, so it cannot be byte-copied onto watermarked pixels
    /// (verifiers would report tampering); the ingredient chain is the
    /// C2PA-standard way existing credentials survive an edit.
    public func process(
        sourceURL: URL,
        config: WatermarkConfiguration,
        metadataOverride: [String: Any]? = nil,
        provenance: ProvenanceExportOptions? = nil,
        preserveSourceCredentials: Bool = false
    ) async throws -> ProcessingResult {
        // 1. Load (validates size, extracts metadata + HDR + CIImage)
        let loaded = try ImageLoader.load(from: sourceURL)

        // 2. Normalize orientation (Pitfall 3 prevention)
        let normalized = OrientationNormalizer.normalize(loaded.ciImage)

        // 3. Build filter graph (pure CIImage ops, no context needed).
        // `metadataOverride` lets a caller supply the caption's source metadata —
        // used by the VIDEO preview, which renders an extracted PNG frame but
        // must show the *video's* device/date/dimensions/format, not the PNG's.
        var graphMetadata: [String: Any]
        if let metadataOverride {
            graphMetadata = metadataOverride
            graphMetadata["_SourceUTI"] = metadataOverride["_SourceUTI"] ?? loaded.sourceUTI
        } else {
            // Inject the source UTI so the white-frame caption's {format} token and
            // detailed-attribution line can show the file format (HEIC/JPEG/…).
            graphMetadata = loaded.metadata
            graphMetadata["_SourceUTI"] = loaded.sourceUTI
            // Use the true (orientation-normalized) output size for the {dimensions}
            // caption token so it's always present and correct.
            graphMetadata["PixelWidth"] = Int(normalized.extent.width.rounded())
            graphMetadata["PixelHeight"] = Int(normalized.extent.height.rounded())
        }
        let composited = try buildFilterGraph(
            base: normalized,
            config: config,
            metadata: graphMetadata
        )

        // 4. Render via shared CIContext → CGImage.
        // Only honor the source color space when it is RGB; for missing,
        // unknown, or monochrome profiles render into the guaranteed-valid RGB
        // working space (CGColorSpace(name: .displayP3) can fail on Simulator,
        // which left the output space nil and desaturated untagged images).
        let outputColorSpace: CGColorSpace = {
            if let cs = loaded.colorSpace, cs.model == .rgb {
                return cs
            }
            return CIContextProvider.workingColorSpace
        }()

        // Destination + alpha decision are resolved BEFORE the render so they can
        // pick the render bit-depth (below); both are reused for the write step.
        let destinationUTI = config.outputFormat.uti ?? loaded.sourceUTI
        let preserveAlpha = loaded.sourceHasAlpha
            && Self.outputFormatSupportsAlpha(destinationUTI)

        // Render bit-depth. `.RGBAh` (half-float) keeps precision for the
        // lossless-alpha formats (PNG/TIFF) whose CGImage is handed straight to
        // ImageIO. But when the image will be flattened (preserveAlpha == false →
        // `ImageWriter.flattenToOpaque` redraws it through a CoreGraphics 8-bit
        // context), a half-float source renders BLACK on the iOS Simulator —
        // CoreGraphics there cannot sample `kCGBitmapFloatComponents` images. 8-bit
        // is correct for that path and loses no HDR: the base is SDR and HDR rides
        // on the re-attached gain map, not the base bit-depth.
        let renderFormat: CIFormat = preserveAlpha ? .RGBAh : .RGBA8

        #if DEBUG
        let srcSample = samplePixel(loaded.ciImage)
        let compSample = samplePixel(composited)
        engineLog.debug(
            "render: uti=\(loaded.sourceUTI, privacy: .public) size=\(Int(composited.extent.width))x\(Int(composited.extent.height)) srcCSModel=\(loaded.colorSpace?.model.rawValue ?? -99) inCIImageCSModel=\(composited.colorSpace?.model.rawValue ?? -99) outCSModel=\(outputColorSpace.model.rawValue) renderFmt=\(renderFormat == CIFormat.RGBAh ? "RGBAh" : "RGBA8", privacy: .public) whiteFrame=\(config.whiteFrame?.isEnabled == true) srcRGB=\(srcSample) compRGB=\(compSample)"
        )
        #endif
        guard let cgImage = context.createCGImage(
            composited,
            from: composited.extent,
            format: renderFormat,
            colorSpace: outputColorSpace
        ) else {
            throw PipelineError.renderFailed
        }

        // 5. Write to temp file with metadata + HDR re-attached.
        // Provenance hook (Plan 19-02): when `provenance` options are supplied,
        // analyze the source, apply the privacy profile, and merge IPTC rights
        // into the outgoing metadata dict BEFORE ImageWriter.write. C2PA signing
        // happens AFTER write (the manifest attaches to the already-written file).
        // `destinationUTI` and `preserveAlpha` were resolved before the render
        // (they pick the render bit-depth). `preserveAlpha` drives whether
        // ImageWriter keeps the 4th channel or flattens it onto the RGB pixels —
        // opaque sources stay lossless (alpha was 1.0 everywhere) and JPEG/HEIC
        // export without ImageIO's "AlphaPremulLast on opaque image" warning.
        let outputURL = try TempFileManager.createTempFile(uti: destinationUTI as CFString)
        #if DEBUG
        engineLog.debug(
            "alpha: sourceHasAlpha=\(loaded.sourceHasAlpha, privacy: .public) formatSupportsAlpha=\(Self.outputFormatSupportsAlpha(destinationUTI), privacy: .public) preserveAlpha=\(preserveAlpha, privacy: .public)"
        )
        #endif

        var outgoing: [String: Any] = loaded.metadata
        var report: SourceProvenanceReport?
        var receiptRights = RightsMetadata()
        var receiptPrivacyProfile: MetadataPrivacyProfile = .preserveAll
        var receiptPrivacyActions: [String] = []

        // Source C2PA summary — read once, shared by the provenance analysis
        // and the source-credential preservation path below.
        var sourceC2PASummary: SourceProvenanceAnalyzer.C2PASummary?

        if let prov = provenance {
            receiptRights = prov.rights
            receiptPrivacyProfile = prov.privacyProfile
            receiptPrivacyActions = privacyActions(for: prov.privacyProfile)
            // (a) Analyze source provenance — reads C2PA summary via the client.
            sourceC2PASummary = await prov.c2paClient.readSourceSummary(from: sourceURL)
            report = SourceProvenanceAnalyzer().analyze(
                metadata: loaded.metadata,
                userDeclaration: prov.userDeclaration,
                c2paSummary: sourceC2PASummary
            )
            // (c) Apply privacy profile (GPS strip, serial removal) — D-10.
            outgoing = MetadataPreservationPolicy().apply(prov.privacyProfile, to: outgoing)
            // (d) Merge IPTC rights metadata — AUTH-03, D-07.
            outgoing = IPTCRightsMetadataWriter().merged(into: outgoing, rights: prov.rights)
        } else if preserveSourceCredentials {
            // No provenance options, but this is a real export: still check the
            // source for existing Content Credentials so they aren't dropped.
            sourceC2PASummary = await Self.preservationC2PAClient.readSourceSummary(from: sourceURL)
        }

        // Re-align the HDR gain map to the exported base BEFORE writing. The base
        // pixels were rotated upright and the orientation tag reset to 1, but the
        // gain map was extracted in the source's stored orientation — so re-attach
        // it verbatim only when nothing moved. Otherwise rotate it to match and,
        // when a white frame is applied, zero the gain under the border band so
        // the opaque SDR-white frame doesn't glow with residual HDR boost.
        let alignedGainMap = GainMapProcessor.aligned(
            auxData: loaded.gainMapAuxData,
            type: loaded.gainMapType ?? .appleHDR,
            sourceOrientation: loaded.sourceOrientation,
            frameEnabled: config.whiteFrame?.isEnabled == true,
            frameWidthRatio: config.whiteFrame?.frameWidthRatio ?? 0
        )

        try ImageWriter.write(
            cgImage: cgImage,
            metadata: outgoing,
            gainMapAuxData: alignedGainMap,
            dngMetadata: loaded.dngMetadata,
            destinationUTI: destinationUTI,
            quality: config.outputQuality,
            preserveAlpha: preserveAlpha,
            to: outputURL
        )

        // (e) C2PA signing — AFTER ImageWriter.write. The manifest attaches to
        // the already-written file. Noop client reports 'not signed' honestly.
        //
        // Two triggers:
        //   1. Explicit — the user opted into Content Credentials signing
        //      (prov.includeC2PA). Failures throw: the user asked to sign.
        //   2. Preservation — the SOURCE already carries a C2PA manifest and
        //      this is a real export. The manifest cannot be byte-copied onto
        //      the watermarked pixels (its signature binds to the source
        //      bytes), so the export gets a new device-signed manifest whose
        //      `parentOf` ingredient embeds the source's manifest + signature.
        //      Best-effort: a preservation failure must not block the export,
        //      but the receipt (when one exists) reports it honestly.
        var receipt: ExportReceipt?
        var signing: C2PASigningResult?
        let explicitSigning = provenance?.includeC2PA == true && report != nil
        let creator = (provenance?.rights.creator ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wantsPreservation = preserveSourceCredentials && sourceC2PASummary != nil

        if explicitSigning || wantsPreservation {
            let client = provenance?.c2paClient ?? Self.preservationC2PAClient
            let identity = C2PASigningIdentityStore().currentIdentity()

            if explicitSigning, creator.isEmpty, !wantsPreservation {
                // Explicit signing is gated on a creator name (D-26, 19-03 UI)
                // and there are no source credentials that must be carried over.
                signing = C2PASigningResult(
                    status: .notSigned,
                    identityType: identity.type,
                    displayName: identity.displayName,
                    warnings: ["Add a creator name before signing with Content Credentials."]
                )
            } else {
                // The sealed author assertion is only attached when the user
                // explicitly opted into signing AND provided a creator name.
                // A preservation-only manifest records lineage, never authorship.
                let signedCreator = (explicitSigning && !creator.isEmpty) ? creator : nil
                let manifest = C2PAManifestRequest(
                    appVersion: provenance?.appVersion ?? Self.hostAppVersion,
                    sourceState: report?.state ?? .unknown,
                    sourceEvidenceSummary: report?.evidence.map(\.summary) ?? [],
                    visibleWatermarkApplied: !config.watermarks.isEmpty,
                    whiteFrameApplied: config.whiteFrame?.isEnabled == true,
                    privacyAction: (provenance?.privacyProfile ?? .preserveAll) == .preserveAll
                        ? nil : "Sensitive metadata removed",
                    userDeclaration: provenance?.userDeclaration ?? .none,
                    invisibleWatermarkPayloadID: nil,
                    creator: signedCreator
                )
                do {
                    var result = try await client.signExport(
                        outputURL: outputURL,
                        source: sourceURL,
                        manifest: manifest,
                        identity: identity
                    )
                    if result.status == .signed,
                       result.verification?.signatureIsIntact != true {
                        throw PipelineError.c2paSignatureVerificationFailed
                    }
                    if explicitSigning, creator.isEmpty, result.status == .signed {
                        result = C2PASigningResult(
                            status: result.status,
                            identityType: result.identityType,
                            displayName: result.displayName,
                            warnings: result.warnings + [
                                "No creator name was set, so the Content Credentials were signed without an author name."
                            ],
                            verification: result.verification
                        )
                    }
                    signing = result
                } catch {
                    if explicitSigning { throw error }
                    signing = C2PASigningResult(
                        status: .notSigned,
                        identityType: identity.type,
                        displayName: identity.displayName,
                        warnings: ["The source photo's Content Credentials could not be carried into this export."]
                    )
                }
            }
        }

        if let report {
            receipt = ExportReceipt(
                report: report,
                signingResult: signing,
                rightsMetadata: receiptRights,
                privacyProfile: receiptPrivacyProfile,
                privacyActions: receiptPrivacyActions
            )
        }

        // 6. Return result
        return ProcessingResult(
            url: outputURL,
            data: nil,
            outputUTI: destinationUTI,
            provenanceReceipt: receipt
        )
    }

    /// Processes a video file, applying watermark via AVFoundation CALayer overlay.
    ///
    /// Delegates to `VideoProcessor.process(sourceURL:config:onProgress:)` for the full
    /// AVFoundation pipeline: load → compose → CALayer overlay → export → validate.
    /// Returns a `ProcessingResult` with the output URL, source UTI, and
    /// post-export validation data (HDR preservation, audio track count).
    ///
    /// - Parameters:
    ///   - sourceURL: File URL to the source video
    ///   - config: Watermark configuration (layers, frame, output format)
    ///   - onProgress: Optional callback for export progress (0.0–1.0) and
    ///     estimated time remaining in seconds. Passed through to VideoProcessor.
    /// - Returns: `ProcessingResult` with the output file URL and video validation
    /// - Throws: `PipelineError` for any pipeline stage failure
    public func processVideo(
        sourceURL: URL,
        config: WatermarkConfiguration,
        onProgress: (@Sendable (Double, TimeInterval?) -> Void)? = nil,
        provenance: ProvenanceExportOptions? = nil
    ) async throws -> ProcessingResult {
        let (outputURL, validation, receipt) = try await VideoProcessor.process(
            sourceURL: sourceURL,
            config: config,
            onProgress: onProgress,
            provenance: provenance
        )

        let sourceUTI = (try? sourceURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier)
            ?? "public.mpeg-4"

        return ProcessingResult(
            url: outputURL,
            data: nil,
            outputUTI: sourceUTI,
            videoValidation: validation,
            provenanceReceipt: receipt
        )
    }

    /// Processes a Live Photo pair (still image + video component),
    /// applying watermark to both via the existing photo and video pipelines.
    ///
    /// Delegates to `LivePhotoProcessor.process(stillImageURL:videoURL:config:)`
    /// for coordinated processing of the paired assets. Returns a
    /// `ProcessingResult` with both the watermarked still URL and a reference
    /// to the watermarked video URL via `livePhotoVideoURL`.
    ///
    /// - Parameters:
    ///   - stillImageURL: File URL to the still image component of the Live Photo
    ///   - videoURL: File URL to the video component of the Live Photo
    ///   - config: Watermark configuration
    /// - Returns: `ProcessingResult` with the watermarked still output URL
    ///            and the watermarked video URL in `livePhotoVideoURL`
    /// - Throws: `PipelineError` for any pipeline stage failure
    @available(iOS 18, macOS 15, *)
    public func processLivePhoto(
        stillImageURL: URL,
        videoURL: URL,
        config: WatermarkConfiguration,
        provenance: ProvenanceExportOptions? = nil
    ) async throws -> ProcessingResult {
        let pair = try await LivePhotoProcessor.process(
            stillImageURL: stillImageURL,
            videoURL: videoURL,
            config: config,
            provenance: provenance
        )
        // Determine source UTI from still image
        let sourceUTI = (try? stillImageURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier)
            ?? pair.stillOutputUTI
        return ProcessingResult(
            url: pair.watermarkedStillURL,
            data: nil,
            outputUTI: sourceUTI,
            livePhotoVideoURL: pair.watermarkedVideoURL,
            provenanceReceipt: pair.provenanceReceipt
        )
    }

    /// Renders the center pixel of a CIImage to RGBA8 for diagnostics. Returns
    /// "r,g,b" so we can tell whether color is intact (r≠g≠b) or crushed to grey
    /// (r≈g≈b) at a given pipeline stage.
    private func samplePixel(_ image: CIImage) -> String {
        let e = image.extent
        guard e.width.isFinite, e.height.isFinite, e.width >= 1, e.height >= 1 else { return "n/a" }
        let rect = CGRect(x: e.midX, y: e.midY, width: 1, height: 1)
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: rect,
            format: .RGBA8,
            colorSpace: CIContextProvider.workingColorSpace
        )
        return "\(bytes[0]),\(bytes[1]),\(bytes[2])"
    }

    /// Client used by the source-credential preservation path when the caller
    /// supplied no provenance options (Content Credentials toggle off). Real
    /// client when c2pa-swift is linked, Noop otherwise.
    private static let preservationC2PAClient = ProvenanceExportOptions.defaultClient()

    /// Host app version for preservation manifests signed without provenance
    /// options (which normally carry the app version).
    private static let hostAppVersion: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"

    /// Returns true iff a destination format can encode an alpha/transparency
    /// channel. JPEG and HEIC/HEIF cannot (always opaque); PNG/TIFF/WebP and
    /// most others can. Used to decide whether to preserve the source alpha or
    /// flatten it onto the RGB pixels on export.
    private static func outputFormatSupportsAlpha(_ uti: String) -> Bool {
        switch uti {
        case "public.jpeg", "public.heic", "public.heif":
            return false
        default:
            return true
        }
    }

    private func privacyActions(for profile: MetadataPrivacyProfile) -> [String] {
        switch profile {
        case .preserveAll:
            return []
        case .stripSensitive:
            return ["Location and device-identifying metadata removed"]
        case .minimalPublic:
            return ["Only rights/provenance and essential technical metadata retained"]
        }
    }

    /// Builds the Core Image filter graph for watermark compositing.
    ///
    /// Pure CIImage operations — no CIContext needed. This is synchronous
    /// and called from within the actor-isolated context.
    ///
    /// - Parameters:
    ///   - base: The source CIImage (assumed already orientation-normalized)
    ///   - config: Watermark configuration
    ///   - metadata: Source image metadata dictionary (for device model extraction
    ///               in white frame rendering)
    /// - Returns: Composited CIImage ready for rendering
    ///
    /// Flow:
    ///   1. Normalize orientation again as safety net (Pitfall 3 double-check)
    ///   2. Render white frame below all watermark layers (if enabled)
    ///   3. Build watermark layers from config in order (per D-01)
    ///   4. For each layer: render CIImage → scale → position → collect
    ///   5. Composite all layers onto base via WatermarkRenderer
    ///
    /// Note: Supports both `.text` and `.image` watermark layers (Plan 01 + Plan 02)
    ///       plus white frame compositing (Plan 03).
    private func buildFilterGraph(
        base: CIImage,
        config: WatermarkConfiguration,
        metadata: [String: Any]
    ) throws -> CIImage {
        // Safety net: normalize orientation before positioning (Pitfall 3)
        let normalized = OrientationNormalizer.normalize(base)

        let composited = normalized

        var layers: [(CIImage, CGPoint)] = []
        let extent = composited.extent

        // Watermarks position against the whole photo. They used to be inset by
        // the frame width, because the mat was composited over the photo's outer
        // edge and would otherwise bury a corner watermark. The mat now sits
        // outside the photo, so there is nothing to dodge.
        let positioningExtent = extent

        // Edge padding scales with the image instead of being a fixed 20px,
        // which was invisible on multi-thousand-pixel photos. ~4% of the shorter
        // dimension gives a comfortable, resolution-independent margin.
        let effectivePadding = max(config.padding, min(extent.width, extent.height) * 0.04)

        // Build layers in order: bottom layer first, top layer last (D-01)
        for watermark in config.watermarks {
            // MULT-02: Skip hidden layers
            guard watermark.isVisible else { continue }

            let watermarkImage: CIImage

            switch watermark {
            case .text(let textConfig, _, _, _, _):
                // EXIF-01: Token substitution before rendering (Plan 05-02 integration)
                watermarkImage = TextWatermarkRenderer.render(config: textConfig, metadata: metadata)

            case .image(let imageConfig, _, _, _, _):
                watermarkImage = try ImageWatermarkRenderer.render(config: imageConfig)

            case .signature(let signatureInput, _, _, _, _):
                watermarkImage = try SignatureRenderer.render(input: signatureInput)
            }

            // Scale watermark relative to the base image (resolution-independent).
            // Text scales by HEIGHT so editing the text — which changes its width —
            // does not change the apparent font size (scale == font height as a
            // fraction of image height). Image/signature scale by WIDTH, where the
            // aspect ratio is fixed so width is the natural control.
            let factor: CGFloat
            if case .text = watermark {
                factor = WatermarkScaling.transformFactor(
                    layerScale: watermark.scale,
                    naturalWidth: watermarkImage.extent.height,
                    baseWidth: extent.height
                )
            } else {
                factor = WatermarkScaling.transformFactor(
                    layerScale: watermark.scale,
                    naturalWidth: watermarkImage.extent.width,
                    baseWidth: extent.width
                )
            }
            var scaled = watermarkImage.transformed(
                by: CGAffineTransform(scaleX: factor, y: factor)
            )

            // Logo rotation — applied AFTER scaling so the scale factor keys off
            // the upright width (rotation must not change the apparent size), and
            // BEFORE positioning so PositionCalculator sees the rotated bounding
            // box. Only image layers carry a rotation.
            if case .image(let imageConfig, _, _, _, _) = watermark {
                scaled = ImageWatermarkRenderer.rotated(scaled, degrees: imageConfig.rotationDegrees)
            }

            // MULT-02: Per-layer opacity via CIFilter.colorMatrix
            let opacityAdjusted: CIImage
            if watermark.opacity < 1.0 {
                let matrix = CIFilter.colorMatrix()
                matrix.inputImage = scaled
                matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(watermark.opacity))
                matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
                opacityAdjusted = matrix.outputImage ?? scaled
            } else {
                opacityAdjusted = scaled
            }

            // Calculate position using CIImage bottom-left origin coordinates
            // Uses configurable padding from WatermarkConfiguration (default 20).
            // Positioned against the (possibly frame-inset) inner content rect.
            var position = PositionCalculator.position(
                for: watermark.position,
                watermarkExtent: opacityAdjusted.extent,
                baseExtent: positioningExtent,
                padding: effectivePadding
            )
            // Re-apply the inner rect's origin offset (PositionCalculator is
            // size-relative and assumes a (0,0) origin). No-op when no frame.
            position.x += positioningExtent.origin.x
            position.y += positioningExtent.origin.y

            layers.append((opacityAdjusted, position))
        }

        // Retro date stamp — composited above all watermark layers, positioned
        // within the same (frame-inset) content rect so it stays clear of the
        // white border. Scales by HEIGHT like text (sizeRatio == digit height as
        // a fraction of image height).
        if let dateConfig = config.dateStamp,
           let stampImage = DateStampRenderer.render(config: dateConfig, metadata: metadata) {
            let factor = WatermarkScaling.transformFactor(
                layerScale: dateConfig.sizeRatio,
                naturalWidth: stampImage.extent.height,
                baseWidth: extent.height
            )
            let scaled = stampImage.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            var position = PositionCalculator.position(
                for: dateConfig.position,
                watermarkExtent: scaled.extent,
                baseExtent: positioningExtent,
                padding: effectivePadding
            )
            position.x += positioningExtent.origin.x
            position.y += positioningExtent.origin.y
            layers.append((scaled, position))
        }

        // D-12: Composite watermark layers onto base (text → image, bottom to top)
        let watermarkedResult = WatermarkRenderer.composite(layers: layers, onto: composited)

        // D-12: the mat is the outermost layer, and it enlarges the canvas.
        if let frameConfig = config.whiteFrame, frameConfig.isEnabled {
            let geometry = FrameGeometry(
                config: frameConfig,
                sourceSize: watermarkedResult.extent.size,
                dpi: FrameGeometry.resolveDPI(from: metadata)
            )
            let mat = try WhiteFrameRenderer.render(
                config: frameConfig,
                geometry: geometry,
                metadata: metadata,
                scale: 1.0
            )

            // Core Image works bottom-left up while FrameGeometry is expressed
            // top-left down, so the photo's vertical offset inside the framed
            // canvas is the BOTTOM mat — which for gallery is the tall caption
            // band, not the thin top edge. Getting this backwards silently
            // shifts the photo into the caption.
            let e = watermarkedResult.extent
            let placedPhoto = watermarkedResult.transformed(
                by: CGAffineTransform(translationX: geometry.left - e.minX,
                                      y: geometry.bottom - e.minY)
            )

            let frameFilter = CIFilter.sourceOverCompositing()
            frameFilter.inputImage = mat
            frameFilter.backgroundImage = placedPhoto
            let framed = frameFilter.outputImage ?? placedPhoto
            return framed.cropped(to: CGRect(origin: .zero, size: geometry.framedSize))
        }

        return watermarkedResult
    }
}
