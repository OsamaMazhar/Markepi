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
        onProgress: (@Sendable (Double, TimeInterval?) -> Void)? = nil
    ) async throws -> (outputURL: URL, validation: ExportValidator.ExportValidationResult) {
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
            os_log(.error, "WatermarkCore VideoProcessor: Audio track count mismatch — source=%{public}d, composition=%{public}d",
                   audioTracks.count, compositionAudioCount)
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

        // Step 4: Build CALayer hierarchy via VideoLayerBuilder (D-01, D-02)
        let (parentLayer, videoLayer) = try VideoLayerBuilder.buildLayers(
            config: config,
            videoSize: videoSize
        )

        // Step 5: Detect HDR and configure AVVideoComposition (D-09, D-10)
        // Detect HDR by inspecting format descriptions for HDR transfer functions
        let formatDescsForHDR = try await videoTrack.load(.formatDescriptions)
        let isHDR = formatDescsForHDR.contains { desc in
            let extensions = CMFormatDescriptionGetExtensions(desc) as NSDictionary?
            let transfer = extensions?[kCVImageBufferTransferFunctionKey] as? String
            return transfer?.contains("HLG") == true || transfer?.contains("2084") == true
        }
        var hdrPreservationAttempted = false

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoSize
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

        // Step 6: Export with source format matching (D-04)
        let presetName: String
        if isHDR {
            presetName = AVAssetExportPresetHEVCHighestQuality
        } else {
            presetName = AVAssetExportPresetHighestQuality
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: presetName
        ) else {
            throw PipelineError.videoExportSessionCreationFailed
        }

        // Create output temp file
        let sourceUTI = (try? sourceURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier)
            ?? UTType.mpeg4Movie.identifier
        let outputURL = try TempFileManager.createTempFile(uti: sourceUTI as CFString)

        exportSession.outputURL = outputURL
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = false  // D-04: quality over streaming

        // Match source container type (D-04)
        await matchSourceFormat(asset: asset, exportSession: exportSession)

        // Step 6: Export with progress tracking via iOS 18 async API (D-11, D-12)
        let outputFileType: AVFileType = exportSession.outputFileType ?? .mp4

        if let onProgress = onProgress {
            nonisolated(unsafe) let callback = onProgress
            let startTime = Date()

            // Create states sequence before spawning concurrent work
            let states = exportSession.states(updateInterval: 0.1)
            let statesTask = Task {
                do {
                    for try await state in states {
                        if case .exporting(let progress) = state {
                            let fraction = progress.fractionCompleted
                            let elapsed = Date().timeIntervalSince(startTime)
                            let eta: TimeInterval? = fraction > 0.01
                                ? elapsed / max(fraction, 0.01) - elapsed
                                : nil
                            callback(fraction, eta)
                        }
                    }
                } catch {
                    // States sequence ends when export completes, fails, or is cancelled
                }
            }

            // Execute export (throws on failure/cancellation)
            do {
                try await exportSession.export(to: outputURL, as: outputFileType)
            } catch {
                statesTask.cancel()
                throw error
            }

            // Ensure states task completes
            _ = await statesTask.value
        } else {
            // Backward compat: no progress reporting, but still use new API
            try await exportSession.export(to: outputURL, as: outputFileType)
        }

        // Step 7: Post-export validation (D-12)
        let validationResult = try await ExportValidator.validate(
            outputURL: outputURL,
            sourceAsset: asset,
            wasHDR: isHDR
        )

        // Log validation warnings
        for warning in validationResult.warnings {
            os_log(.default, "WatermarkCore ExportValidator: %{public}@", warning)
        }

        // D-10: Log HDR fallback warning
        if isHDR && hdrPreservationAttempted && !validationResult.hdrPreserved {
            os_log(.default, "WatermarkCore VideoProcessor: HDR was flattened to SDR during watermark compositing")
        }

        if !validationResult.audioTrackCountMatch {
            os_log(.default, "WatermarkCore VideoProcessor: Audio track count mismatch in output")
        }

        // Step 8: Return output URL with validation result
        return (outputURL, validationResult)
    }

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
