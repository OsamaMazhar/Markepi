import AVFoundation
import CoreVideo
import Foundation

/// Post-export validation for watermarked video output.
///
/// Inspects output video tracks for HDR metadata (color primaries, transfer function)
/// and compares audio track counts against the source asset. Does NOT modify the
/// output — read-only inspection and reporting.
///
/// Full implementation in Task 2. Minimal skeleton here for VideoProcessor compilation.
public struct ExportValidator {

    /// Structured result of post-export validation.
    public struct ExportValidationResult: Sendable {
        /// Whether HDR metadata was found in the output
        public let hdrPreserved: Bool
        /// Whether audio track counts match between source and output
        public let audioTrackCountMatch: Bool
        /// Human-readable warnings for any issues found
        public let warnings: [String]

        public init(hdrPreserved: Bool, audioTrackCountMatch: Bool, warnings: [String]) {
            self.hdrPreserved = hdrPreserved
            self.audioTrackCountMatch = audioTrackCountMatch
            self.warnings = warnings
        }
    }

    /// Validates the exported video output against the source asset.
    ///
    /// - Parameters:
    ///   - outputURL: File URL of the exported video
    ///   - sourceAsset: The source AVAsset used for comparison
    ///   - wasHDR: Whether the source was detected as HDR
    /// - Returns: `ExportValidationResult` with HDR status, audio match, and warnings
    public static func validate(
        outputURL: URL,
        sourceAsset: AVAsset,
        wasHDR: Bool
    ) async throws -> ExportValidationResult {
        let outputAsset = AVURLAsset(url: outputURL)
        var warnings: [String] = []

        // Check audio track count
        let sourceAudioCount = try await sourceAsset.loadTracks(withMediaType: .audio).count
        let outputAudioCount = try await outputAsset.loadTracks(withMediaType: .audio).count
        let audioMatch = sourceAudioCount == outputAudioCount
        if !audioMatch {
            warnings.append("Audio track count mismatch: source=\(sourceAudioCount), output=\(outputAudioCount)")
        }

        // Check HDR metadata
        var hdrPreserved = false
        if wasHDR {
            let outputVideoTracks = try await outputAsset.loadTracks(withMediaType: .video)
            if let videoTrack = outputVideoTracks.first {
                let formatDescs = try await videoTrack.load(.formatDescriptions)
                if let formatDesc = formatDescs.first {
                    let extensions = CMFormatDescriptionGetExtensions(formatDesc) as NSDictionary?
                    let primaries = extensions?[kCVImageBufferColorPrimariesKey] as? String
                    let transfer = extensions?[kCVImageBufferTransferFunctionKey] as? String
                    hdrPreserved = (primaries?.contains("2020") == true)
                        || (transfer?.contains("HLG") == true)
                        || (transfer?.contains("2084") == true)
                    if !hdrPreserved {
                        warnings.append("HDR metadata not found in output — source HDR was flattened to SDR")
                    }
                }
            }
        }

        return ExportValidationResult(
            hdrPreserved: hdrPreserved,
            audioTrackCountMatch: audioMatch,
            warnings: warnings
        )
    }
}
