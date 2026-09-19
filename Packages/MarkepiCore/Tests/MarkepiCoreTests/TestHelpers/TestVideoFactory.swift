import AVFoundation
import CoreVideo
import Foundation

/// Test helper for synthesizing short H.264 `.mov` videos at runtime.
///
/// Avoids committing binary video fixtures to the repo. Produces a small,
/// short, solid-color clip with a real video track — enough to exercise the
/// `VideoProcessor` / `processVideo` pipeline (load → compose → export).
public enum TestVideoFactory {

    public enum FactoryError: Error {
        case writerInitFailed
        case pixelBufferCreationFailed
        case exportFailed(String)
    }

    /// Writes a short solid-color H.264 `.mov` to a temp file and returns its URL.
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels (default 128).
    ///   - height: Frame height in pixels (default 96).
    ///   - seconds: Clip duration (default 0.5s — kept tiny for fast tests).
    ///   - fps: Frame rate (default 15).
    /// - Returns: File URL to the written `.mov`. Caller is responsible for cleanup.
    public static func makeTestVideo(
        width: Int = 128,
        height: Int = 96,
        seconds: Double = 0.5,
        fps: Int32 = 15
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_video_\(UUID().uuidString).mov")

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            throw FactoryError.writerInitFailed
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelAttributes
        )

        guard writer.canAdd(input) else { throw FactoryError.writerInitFailed }
        writer.add(input)
        guard writer.startWriting() else {
            throw FactoryError.exportFailed("startWriting failed: \(String(describing: writer.error))")
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int(Double(fps) * seconds))
        for frame in 0..<frameCount {
            // Spin until the input can accept more data.
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let buffer = try makePixelBuffer(width: width, height: height, frame: frame)
            let time = CMTime(value: CMTimeValue(frame), timescale: fps)
            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()
        // Use the completion-handler API via a continuation. The bare
        // `finishWriting()` is the deprecated *synchronous* call, which blocks a
        // Swift-concurrency cooperative thread and can crash the test process.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }

        guard writer.status == .completed else {
            throw FactoryError.exportFailed("finishWriting status \(writer.status.rawValue): \(String(describing: writer.error))")
        }
        return url
    }

    /// Creates a solid-color ARGB pixel buffer. The fill shifts slightly per
    /// frame so the encoder has non-identical frames to work with.
    private static func makePixelBuffer(width: Int, height: Int, frame: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw FactoryError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let fillByte = UInt8(truncatingIfNeeded: 40 + frame * 8)
            memset(base, Int32(fillByte), bytesPerRow * height)
        }
        return buffer
    }
}
