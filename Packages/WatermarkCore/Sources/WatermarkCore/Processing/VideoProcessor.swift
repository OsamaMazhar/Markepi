import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import os.log
import UniformTypeIdentifiers

/// Processes video files through an AVFoundation pipeline: load → compose →
/// CALayer overlay → export → validate.
///
/// Uses `AVMutableComposition` to preserve all audio tracks, `AVVideoComposition`
/// with `AVVideoCompositionCoreAnimationTool` for CALayer-based watermark
/// compositing (D-01), and `AVAssetExportSession` for export with source format
/// matching (D-04).
///
/// HDR detection and preservation via `AVAssetTrack.hasMediaCharacteristic`
/// and explicit color property configuration on `AVMutableVideoComposition` (D-09).
/// Falls back to SDR with tone mapping when HDR cannot be preserved (D-10).
///
/// Post-export validation inspects HDR metadata and audio track counts (D-12).
///
/// Uses `public struct` with static method pattern (not actor) — AVFoundation
/// handles its own threading internally.
public struct VideoProcessor {

    // MARK: - Entry Point

    /// Processes a video file, applying watermark overlay via AVFoundation
    /// CALayer compositing with HDR preservation and audio passthrough.
    ///
    /// Pipeline stages:
    ///   1. Load AVAsset and validate video track existence
    ///   2. Build AVMutableComposition with video + ALL audio tracks (D-11)
    ///   3. Determine render size accounting for portrait orientation
    ///   4. Build CALayer hierarchy via VideoLayerBuilder (D-01, D-02)
    ///   5. Detect HDR and configure AVVideoComposition color properties (D-09)
    ///   6. Export with source format matching (D-04)
    ///   7. Post-export validation (D-12)
    ///   8. Return output URL
    ///
    /// - Parameters:
    ///   - sourceURL: File URL to the source video
    ///   - config: Watermark configuration (layers, position, scale, white frame)
    ///   - onProgress: Optional callback receiving progress (0.0–1.0) and
    ///     estimated time remaining in seconds (nil when progress < 0.01).
    ///     Default nil for backward compatibility.
    /// - Returns: A tuple containing the output temp file URL and the post-export
    ///   validation result for surfacing HDR/audio warnings to the caller
    /// - Throws: `PipelineError` for any pipeline stage failure
    @available(iOS 18, macOS 15, *)
    public static func process(
        sourceURL: URL,
        config: WatermarkConfiguration,
        onProgress: (@Sendable (Double, TimeInterval?) -> Void)? = nil,
        provenance: ProvenanceExportOptions? = nil
    ) async throws -> (outputURL: URL, validation: ExportValidator.ExportValidationResult, provenanceReceipt: ExportReceipt?) {
        let asset = AVURLAsset(url: sourceURL)

        // Step 1: Load duration and validate video track
        let duration = try await asset.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw PipelineError.videoTrackNotFound
        }

        // Step 2: Build AVMutableComposition with video + ALL audio tracks (D-11)
        let composition = AVMutableComposition()

        // Insert video track
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw PipelineError.videoTrackNotFound
        }
        try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)

        // Insert ALL audio tracks — no mixdown (D-11)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for audioTrack in audioTracks {
            guard let compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw PipelineError.videoAudioTrackInsertionFailed
            }
            try compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        // Verify audio track insertion (Pitfall 3 guard)
        let compositionAudioCount = composition.tracks(withMediaType: .audio).count
        if compositionAudioCount != audioTracks.count {
            #if DEBUG
            os_log(.error, "WatermarkCore VideoProcessor: Audio track count mismatch — source=%{public}d, composition=%{public}d",
                   audioTracks.count, compositionAudioCount)
            #endif
        }

        // Step 3: Determine video size accounting for portrait orientation
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let videoSize: CGSize
        if transform.isPortrait {
            videoSize = CGSize(width: naturalSize.height, height: naturalSize.width)
        } else {
            videoSize = naturalSize
        }

        // Extract the video's metadata (device/model, creation date, dimensions,
        // format) so the white-frame caption can show real details — not just
        // resolution — matching the photo path.
        let videoMetadata = await extractCaptionMetadata(
            asset: asset,
            videoTrack: videoTrack,
            sourceURL: sourceURL,
            videoSize: videoSize
        )

        // Detect HDR by inspecting format descriptions for HDR transfer functions.
        // Done BEFORE building layers so watermark overlays are rasterized at the
        // video's bit depth: 16-bit half-float (.RGBAh) only for HDR, 8-bit
        // (.RGBA8) for SDR. Handing half-float overlay layers to
        // AVVideoCompositionCoreAnimationTool for an SDR export drives the VT
        // compression session down an unsupported-pixel-format path
        // (VT-CS err -12900) that aborts inside CoreMedia's XPC layer.
        let formatDescsForHDR = try await videoTrack.load(.formatDescriptions)
        let isHDR = formatDescsForHDR.contains { desc in
            let extensions = CMFormatDescriptionGetExtensions(desc) as NSDictionary?
            let transfer = extensions?[kCVImageBufferTransferFunctionKey] as? String
            return transfer?.contains("HLG") == true || transfer?.contains("2084") == true
        }

        // Step 4: Build CALayer hierarchy via VideoLayerBuilder (D-01, D-02)
        let (parentLayer, videoLayer, framedRenderSize) = try VideoLayerBuilder.buildLayers(
            config: config,
            videoSize: videoSize,
            metadata: videoMetadata,
            isHDR: isHDR
        )

        // Step 5: Configure AVVideoComposition (D-09, D-10)
        var hdrPreservationAttempted = false

        let videoComposition = AVMutableVideoComposition()
        // Framing enlarges the canvas, so the composition renders at the framed
        // size rather than the source's.
        videoComposition.renderSize = framedRenderSize
        videoComposition.frameDuration = try await videoTrack.load(.minFrameDuration)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        if isHDR {
            // Extract source color properties from format descriptions
            let colorProps = try await extractColorProperties(from: videoTrack)

            videoComposition.colorPrimaries = colorProps.primaries
                ?? AVVideoColorPrimaries_ITU_R_2020
            videoComposition.colorTransferFunction = colorProps.transfer
                ?? AVVideoTransferFunction_ITU_R_2100_HLG
            videoComposition.colorYCbCrMatrix = colorProps.matrix
                ?? AVVideoYCbCrMatrix_ITU_R_2020

            // HDR color fidelity is maintained through AVVideoComposition
            // color properties and CGImage pixel format (.RGBAh).
            // CALayer.colorspace is a macOS-only enhancement not critical
            // for correct HDR output on iOS.

            hdrPreservationAttempted = true
        }
        // For SDR: leave color properties nil (system propagates SDR correctly)

        // An AVMutableVideoComposition handed to AVAssetExportSession MUST carry
        // at least one instruction with a layer instruction spanning the whole
        // time range — otherwise `-[AVAssetExportSession setVideoComposition:]`
        // raises NSInvalidArgumentException ("video composition must have
        // composition instructions") and crashes the export. The layer
        // instruction also applies the source track's preferredTransform so
        // portrait/rotated footage renders upright into `renderSize`.
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(
            assetTrack: compositionVideoTrack
        )
        layerInstruction.setTransform(compositionVideoTrack.preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Step 6: Export with source format matching (D-04)
        // Pick the highest-quality preset that actually yields a session for
        // this composition. `AVAssetExportSession(asset:presetName:)` returns
        // nil when a preset is incompatible — and the "HighestQuality" presets
        // need hardware encoders that aren't always present (notably the
        // Simulator). The synchronous `exportPresets(compatibleWith:)` is
        // deprecated and unreliable (returns []), so probe by construction:
        // try presets in priority order and take the first that succeeds.
        let preferredPresets: [String] = isHDR
            ? [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality,
               AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720,
               AVAssetExportPreset960x540, AVAssetExportPreset640x480, AVAssetExportPresetMediumQuality]
            : [AVAssetExportPresetHighestQuality,
               AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720,
               AVAssetExportPreset960x540, AVAssetExportPreset640x480, AVAssetExportPresetMediumQuality]

        var resolvedSession: AVAssetExportSession?
        for candidate in preferredPresets {
            if let session = AVAssetExportSession(asset: composition, presetName: candidate) {
                resolvedSession = session
                break
            }
        }
        guard let exportSession = resolvedSession else {
            #if DEBUG
            os_log(.error, "WatermarkCore VideoProcessor: no export preset produced a session for the composition")
            #endif
            throw PipelineError.videoExportSessionCreationFailed
        }

        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = false  // D-04: quality over streaming

        // Preserve source-level metadata (creation date, GPS location, device
        // make/model, software, and other QuickTime/MP4 items). AVAssetExportSession
        // DROPS these by default — only an explicit `metadata` assignment carries
        // them into the exported file. We gather metadata across every format the
        // asset advertises so location and capture date survive the re-encode.
        let preserved = await preservedMetadata(for: asset)
        exportSession.metadata = metadataItems(
            applying: provenance?.privacyProfile ?? .preserveAll,
            rights: provenance?.rights,
            to: preserved
        )

        // Match source container type (D-04) BEFORE creating the temp file so the
        // file's extension matches the chosen container. A mismatch (e.g. MOV
        // bytes in a file named `.mp4`) makes AVFoundation reopen fail with
        // "Cannot Open" (AVErrorFileFormatNotRecognized) during validation.
        await matchSourceFormat(asset: asset, exportSession: exportSession)

        // Step 6: Export with progress tracking via iOS 18 async API (D-11, D-12)
        let outputFileType: AVFileType = exportSession.outputFileType ?? .mp4

        // The AVFileType raw value *is* the container UTI (e.g. .mov →
        // "com.apple.quicktime-movie"), so the temp file extension matches the
        // bytes we actually write.
        let outputURL = try TempFileManager.createTempFile(uti: outputFileType.rawValue as CFString)
        exportSession.outputURL = outputURL
        #if DEBUG
        os_log(.default,
               "WatermarkCore VideoProcessor: exporting as %{public}@ → %{public}@ (renderSize=%{public}@, hdr=%d)",
               outputFileType.rawValue, outputURL.lastPathComponent, "\(videoSize)", isHDR)
        #endif

        if let onProgress = onProgress {
            let callback = onProgress
            let startTime = Date()

            // Create states sequence before spawning concurrent work
            let states = exportSession.states(updateInterval: 0.1)
            let statesTask = Task {
                // States sequence ends when export completes, fails, or is cancelled
                for await state in states {
                    if case .exporting(let progress) = state {
                        let fraction = progress.fractionCompleted
                        let elapsed = Date().timeIntervalSince(startTime)
                        let eta: TimeInterval? = fraction > 0.01
                            ? elapsed / max(fraction, 0.01) - elapsed
                            : nil
                        callback(fraction, eta)
                    }
                }
            }

            // Execute export (throws on failure/cancellation)
            do {
                try await exportSession.export(to: outputURL, as: outputFileType)
            } catch {
                statesTask.cancel()
                #if DEBUG
                logVideoError("export(to:as:)", error)
                #endif
                throw PipelineError.videoExportFailed(error)
            }

            // Ensure states task completes
            _ = await statesTask.value
        } else {
            // Backward compat: no progress reporting, but still use new API
            do {
                try await exportSession.export(to: outputURL, as: outputFileType)
            } catch {
                #if DEBUG
                logVideoError("export(to:as:)", error)
                #endif
                throw PipelineError.videoExportFailed(error)
            }
        }

        // Step 7: Post-export validation (D-12). This is ADVISORY ONLY — it
        // reopens the output to report HDR/audio warnings. A validation failure
        // (e.g. a transient "Cannot Open") must NOT fail an export that actually
        // produced a file, so swallow its errors and continue.
        let validationResult: ExportValidator.ExportValidationResult
        do {
            validationResult = try await ExportValidator.validate(
                outputURL: outputURL,
                sourceAsset: asset,
                wasHDR: isHDR
            )
        } catch {
            #if DEBUG
            logVideoError("post-export validation (non-fatal)", error)
            #endif
            validationResult = ExportValidator.ExportValidationResult(
                hdrPreserved: false,
                audioTrackCountMatch: true,
                warnings: []
            )
        }

        // Log validation warnings
        #if DEBUG
        for warning in validationResult.warnings {
            os_log(.default, "WatermarkCore ExportValidator: %{public}@", warning)
        }
        #endif

        // D-10: Log HDR fallback warning
        if isHDR && hdrPreservationAttempted && !validationResult.hdrPreserved {
            #if DEBUG
            os_log(.default, "WatermarkCore VideoProcessor: HDR was flattened to SDR during watermark compositing")
            #endif
        }

        if !validationResult.audioTrackCountMatch {
            #if DEBUG
            os_log(.default, "WatermarkCore VideoProcessor: Audio track count mismatch in output")
            #endif
        }

        // Plan 19-02 Task 6: video C2PA signing is format-limited in this build.
        // When a caller requests C2PA for video, surface an honest receipt
        // warning rather than silently claiming success.
        var finalValidation = validationResult
        var receipt: ExportReceipt?
        if let provenance {
            let report = SourceProvenanceReport(
                state: .unknown,
                evidence: [],
                warnings: ["Video source provenance is not analyzed in this version."],
                userDeclaration: provenance.userDeclaration
            )
            if provenance.includeC2PA {
                let creator = provenance.rights.creator.trimmingCharacters(in: .whitespacesAndNewlines)
                let identity = C2PASigningIdentityStore().currentIdentity()
                let signing = C2PASigningResult(
                    status: creator.isEmpty ? .notSigned : .notSupported,
                    identityType: identity.type,
                    displayName: identity.displayName,
                    warnings: [
                        creator.isEmpty
                            ? "Add a creator name before signing with Content Credentials."
                            : "Video Content Credentials not available for this format",
                    ]
                )
                receipt = ExportReceipt(
                    report: report,
                    signingResult: signing,
                    rightsMetadata: provenance.rights,
                    privacyProfile: provenance.privacyProfile,
                    privacyActions: privacyActionDescriptions(for: provenance.privacyProfile)
                )
            } else {
                receipt = ExportReceipt(
                    report: report,
                    rightsMetadata: provenance.rights,
                    privacyProfile: provenance.privacyProfile,
                    privacyActions: privacyActionDescriptions(for: provenance.privacyProfile)
                )
            }
        }

        if let provenance,
           provenance.includeC2PA,
           !provenance.rights.creator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let warning = "Video Content Credentials not available for this format"
            #if DEBUG
            os_log(.default, "WatermarkCore VideoProcessor: %{public}@", warning)
            #endif
            finalValidation = ExportValidator.ExportValidationResult(
                hdrPreserved: validationResult.hdrPreserved,
                audioTrackCountMatch: validationResult.audioTrackCountMatch,
                warnings: validationResult.warnings + [warning]
            )
        }

        // Step 8: Return output URL with validation result
        return (outputURL, finalValidation, receipt)
    }

    // MARK: - Metadata Preservation

    /// Collects every metadata item the source asset carries — each
    /// format-specific group (QuickTime user/metadata, iTunes, ID3), falling
    /// back to common metadata — so an export can re-attach creation date, GPS
    /// location (`com.apple.quicktime.location.ISO6709`), and device make/model
    /// that `AVAssetExportSession` would otherwise discard.
    ///
    /// Items are de-duplicated by identifier; items without an identifier are
    /// always kept (they carry no stable key to compare on).
    private static func preservedMetadata(for asset: AVAsset) async -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        var seen = Set<String>()

        func add(_ candidates: [AVMetadataItem]) {
            for item in candidates {
                if let id = item.identifier?.rawValue {
                    guard seen.insert(id).inserted else { continue }
                }
                items.append(item)
            }
        }

        // Format-specific metadata holds the raw QuickTime/MP4 items (location,
        // creation date, make, model, software) we most want to preserve.
        if let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                if let formatItems = try? await asset.loadMetadata(for: format) {
                    add(formatItems)
                }
            }
        }

        // Fall back to common metadata if the asset advertised no format groups.
        if items.isEmpty, let common = try? await asset.load(.commonMetadata) {
            add(common)
        }

        return items
    }

    private static func metadataItems(
        applying profile: MetadataPrivacyProfile,
        rights: RightsMetadata?,
        to items: [AVMetadataItem]
    ) -> [AVMetadataItem] {
        var output: [AVMetadataItem]
        switch profile {
        case .preserveAll:
            output = items
        case .stripSensitive:
            output = items.filter { !isSensitiveVideoMetadata($0) }
        case .minimalPublic:
            output = []
        }
        if let rights {
            output.append(contentsOf: videoRightsMetadataItems(rights))
        }
        return output
    }

    private static func privacyActionDescriptions(for profile: MetadataPrivacyProfile) -> [String] {
        switch profile {
        case .preserveAll:
            return []
        case .stripSensitive:
            return ["Location metadata removed from video export"]
        case .minimalPublic:
            return ["Source video metadata minimized; rights records retained"]
        }
    }

    private static func isSensitiveVideoMetadata(_ item: AVMetadataItem) -> Bool {
        guard let id = item.identifier else { return false }
        return id == .commonIdentifierLocation
            || id == .quickTimeMetadataLocationISO6709
            || id == .quickTimeUserDataLocationISO6709
    }

    private static func videoRightsMetadataItems(_ rights: RightsMetadata) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        appendMetadataItem(.commonIdentifierCreator, value: rights.creator, to: &items)
        appendMetadataItem(.commonIdentifierCopyrights, value: rights.copyrightNotice, to: &items)
        appendMetadataItem(.commonIdentifierContributor, value: rights.creditLine, to: &items)
        appendMetadataItem(.commonIdentifierDescription, value: rights.usageTerms, to: &items)
        appendMetadataItem(.quickTimeMetadataAuthor, value: rights.creator, to: &items)
        appendMetadataItem(.quickTimeMetadataCopyright, value: rights.copyrightNotice, to: &items)
        appendMetadataItem(.quickTimeMetadataComment, value: rights.usageTerms, to: &items)
        return items
    }

    private static func appendMetadataItem(
        _ identifier: AVMetadataIdentifier,
        value: String,
        to items: inout [AVMetadataItem]
    ) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        items.append(item)
    }

    // MARK: - Caption Metadata Extraction

    /// Loads a video and returns its caption metadata (device, date, dimensions,
    /// format, GPS). Used by the live preview so the extracted-frame render shows
    /// the *video's* metadata — identical to the exported video's caption.
    @available(iOS 18, macOS 15, *)
    public static func captionMetadata(for url: URL) async -> [String: Any] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return [:]
        }
        let naturalSize = (try? await track.load(.naturalSize)) ?? .zero
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let size = transform.isPortrait
            ? CGSize(width: naturalSize.height, height: naturalSize.width)
            : naturalSize
        return await extractCaptionMetadata(
            asset: asset, videoTrack: track, sourceURL: url, videoSize: size
        )
    }

    /// Builds a metadata dictionary (in the same shape `EXIFTokenParser` /
    /// `DeviceMetadataProvider` read for photos) from a video's asset metadata,
    /// so the white-frame caption can show device, date, dimensions, and format.
    private static func extractCaptionMetadata(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        sourceURL: URL,
        videoSize: CGSize
    ) async -> [String: Any] {
        var meta: [String: Any] = [:]

        // Dimensions ({dimensions}) and source format ({format}).
        meta["PixelWidth"] = Int(videoSize.width.rounded())
        meta["PixelHeight"] = Int(videoSize.height.rounded())
        if let uti = try? sourceURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
            meta["_SourceUTI"] = uti
        }

        // Walk common + QuickTime metadata for device model, make, and date.
        var model: String?
        var make: String?
        var creationDate: Date?
        var locationISO6709: String?

        if let items = try? await asset.load(.metadata) {
            for item in items {
                guard let id = item.identifier else { continue }
                switch id {
                case .quickTimeMetadataModel, .commonIdentifierModel, .quickTimeUserDataModel:
                    if model == nil, let s = try? await item.load(.stringValue), !s.isEmpty { model = s }
                case .quickTimeMetadataMake, .commonIdentifierMake, .quickTimeUserDataMake:
                    if make == nil, let s = try? await item.load(.stringValue), !s.isEmpty { make = s }
                case .quickTimeMetadataCreationDate, .commonIdentifierCreationDate, .quickTimeUserDataCreationDate:
                    if creationDate == nil {
                        if let d = try? await item.load(.dateValue) { creationDate = d }
                        else if let s = try? await item.load(.stringValue) { creationDate = isoDate(s) }
                    }
                case .quickTimeMetadataLocationISO6709, .commonIdentifierLocation, .quickTimeUserDataLocationISO6709:
                    if locationISO6709 == nil, let s = try? await item.load(.stringValue), !s.isEmpty { locationISO6709 = s }
                default:
                    break
                }
            }
        }
        if creationDate == nil,
           let cd = try? await asset.load(.creationDate),
           let d = try? await cd.load(.dateValue) {
            creationDate = d
        }

        // {camera_model} reads {TIFF}.Model; prefer the model, fall back to make.
        if let device = (model ?? make), !device.isEmpty {
            meta["{TIFF}"] = ["Model": device]
        }
        // {date} reads {Exif}.DateTimeOriginal in EXIF's "yyyy:MM:dd HH:mm:ss".
        if let creationDate {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            meta["{Exif}"] = ["DateTimeOriginal": f.string(from: creationDate)]
        }
        // {gps} reads {GPS}.Latitude/Longitude — iPhone videos store location as
        // an ISO-6709 string (e.g. "+37.7858-122.4064+010.000/").
        if let locationISO6709, let coord = parseISO6709(locationISO6709) {
            meta["{GPS}"] = [
                "Latitude": abs(coord.lat),
                "Longitude": abs(coord.lon),
                "LatitudeRef": coord.lat >= 0 ? "N" : "S",
                "LongitudeRef": coord.lon >= 0 ? "E" : "W",
            ]
        }

        return meta
    }

    /// Parses an ISO-6709 location string into signed latitude/longitude.
    /// Handles the leading lat/lon pair (ignores altitude and trailing fields).
    private static func parseISO6709(_ string: String) -> (lat: Double, lon: Double)? {
        // Latitude and longitude are sign-prefixed (+/-) decimal runs.
        let scalars = Array(string)
        var numbers: [Double] = []
        var i = 0
        while i < scalars.count && numbers.count < 2 {
            guard scalars[i] == "+" || scalars[i] == "-" else { i += 1; continue }
            var token = String(scalars[i])
            i += 1
            while i < scalars.count, scalars[i].isNumber || scalars[i] == "." {
                token.append(scalars[i]); i += 1
            }
            if let value = Double(token) { numbers.append(value) }
        }
        guard numbers.count == 2 else { return nil }
        return (numbers[0], numbers[1])
    }

    /// Parses an ISO-8601 date string (common in QuickTime creation-date tags).
    private static func isoDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: string) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: string)
    }

    // MARK: - Diagnostics

    /// Logs the full NSError detail for a failed video stage so "Cannot Open"
    /// style failures can be traced to a domain/code (e.g. AVFoundationErrorDomain
    /// -11829 = AVErrorFileFormatNotRecognized).
    #if DEBUG
    private static func logVideoError(_ stage: String, _ error: Error) {
        let ns = error as NSError
        os_log(.error,
               "WatermarkCore VideoProcessor: %{public}@ failed — \"%{public}@\" [domain=%{public}@ code=%d underlying=%{public}@]",
               stage,
               error.localizedDescription,
               ns.domain,
               ns.code,
               (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.description ?? "none")
    }
    #endif

    // MARK: - HDR Color Property Extraction

    /// Extracts color properties (primaries, transfer function, YCbCr matrix)
    /// from a video track's format descriptions for HDR preservation.
    private static func extractColorProperties(
        from videoTrack: AVAssetTrack
    ) async throws -> (primaries: String?, transfer: String?, matrix: String?) {
        let formatDescs = try await videoTrack.load(.formatDescriptions)
        guard let formatDesc = formatDescs.first else {
            return (nil, nil, nil)
        }

        let extensions = CMFormatDescriptionGetExtensions(formatDesc) as NSDictionary?

        let primaries = extensions?[kCVImageBufferColorPrimariesKey] as? String
        let transfer = extensions?[kCVImageBufferTransferFunctionKey] as? String
        let matrix = extensions?[kCVImageBufferYCbCrMatrixKey] as? String

        return (primaries, transfer, matrix)
    }

    // MARK: - Source Format Matching

    /// Matches the export session output file type to the source container type.
    ///
    /// Uses `AVAssetExportSession.determineCompatibleFileTypes()` to find
    /// compatible types and matches the source UTI. Falls back to `.mp4`
    /// if source type cannot be determined or is not compatible.
    private static func matchSourceFormat(
        asset: AVAsset,
        exportSession: AVAssetExportSession
    ) async {
        let compatibleTypes: [AVFileType] = await withCheckedContinuation { continuation in
            exportSession.determineCompatibleFileTypes { types in
                continuation.resume(returning: types)
            }
        }

        // Try to match source container type
        if let sourceURL = (asset as? AVURLAsset)?.url,
           let sourceUTI = try? sourceURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
            let sourceFileType = AVFileType(sourceUTI)
            if compatibleTypes.contains(sourceFileType) {
                exportSession.outputFileType = sourceFileType
                return
            }
        }

        // Fallback: determine from available types
        if compatibleTypes.contains(AVFileType.mp4) {
            exportSession.outputFileType = .mp4
        } else if compatibleTypes.contains(AVFileType.mov) {
            exportSession.outputFileType = .mov
        }
        // If no known type is compatible, leave the default (system will pick)
    }
}

// MARK: - CGAffineTransform Portrait Detection

extension CGAffineTransform {
    /// Returns `true` if the transform indicates a portrait orientation
    /// (90° or 270° rotation with possible mirroring).
    ///
    /// In portrait video, the natural size is landscape (e.g., 1920×1080)
    /// but the preferredTransform applies a 90° rotation. This property
    /// detects that case so we can swap width/height for correct rendering.
    var isPortrait: Bool {
        // A portrait transform has the form:
        //   | 0   ±1   0 |
        //   | ∓1   0   0 |   (a≈0, b=±1, c=∓1, d≈0)
        // The exact values for iOS portrait video are:
        //   Portrait (home button bottom):  a=0, b=1,  c=-1, d=0
        //   Portrait upside-down:           a=0, b=-1, c=1,  d=0
        return abs(a) < 0.01 && abs(d) < 0.01 && abs(abs(b) - 1.0) < 0.01 && abs(abs(c) - 1.0) < 0.01
    }
}
