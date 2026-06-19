import Testing
import CoreImage
import Foundation
@testable import WatermarkCore

/// Tests BatchProcessor actor for serial batch watermark processing
/// with cancellation support, per-item error resilience, and progress tracking.
@Suite("BatchProcessor")
struct BatchProcessorTests {

    // MARK: - Progress Capture Helper

    /// Thread-safe progress value collector for test assertions.
    /// Uses a simple class with array append since all callbacks
    /// execute on the cooperative concurrency pool (serial actor).
    private final class ProgressCollector: @unchecked Sendable {
        var values: [(Int, Int, TimeInterval?)] = []
        func append(_ current: Int, _ total: Int, _ eta: TimeInterval?) {
            values.append((current, total, eta))
        }
    }

    // MARK: - Helpers

    /// Creates a temporary file URL containing valid JPEG image data
    /// for use as a test batch item source.
    private func createTestImageFile() throws -> URL {
        let (_, jpegData) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
            size: CGSize(width: 200, height: 200)
        )
        let tmpDir = FileManager.default.temporaryDirectory
        let filename = "test_batch_\(UUID().uuidString).jpg"
        let url = tmpDir.appendingPathComponent(filename)
        try jpegData.write(to: url)
        return url
    }

    /// Creates a `BatchItem` with `.photo` media type from a test image URL.
    private func makePhotoItem(sourceURL: URL) -> BatchProcessor.BatchItem {
        return BatchProcessor.BatchItem(
            id: UUID(),
            sourceURL: sourceURL,
            mediaType: .photo
        )
    }

    // MARK: - Test 1: Single Photo Item Success

    @Test("Single photo item produces one success URL")
    func singlePhotoItemProducesSuccessURL() async throws {
        let url = try createTestImageFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let item = makePhotoItem(sourceURL: url)
        let processor = BatchProcessor()
        let config = WatermarkConfiguration()

        let result = await processor.process(items: [item], sharedConfig: config)

        #expect(result.successCount == 1, "Expected 1 success, got \(result.successCount)")
        #expect(result.failureCount == 0, "Expected 0 failures, got \(result.failureCount)")
        #expect(result.successes[0].lastPathComponent.hasPrefix("watermark_"),
                "Output URL should follow TempFileManager naming convention")

        // Clean up output temp file
        try? FileManager.default.removeItem(at: result.successes[0])
    }

    // MARK: - Test 2: Cancellation Mid-Batch

    @Test("Cancellation mid-batch stops after current item and returns partial results")
    func cancellationMidBatchReturnsPartialResults() async throws {
        // Create enough items that processing takes measurable time,
        // giving the cancellation signal time to propagate
        let urls = try (0..<20).map { _ in try createTestImageFile() }
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

        let items = urls.map { makePhotoItem(sourceURL: $0) }
        let processor = BatchProcessor()
        let config = WatermarkConfiguration()

        let task = Task {
            await processor.process(items: items, sharedConfig: config)
        }

        // Let the task start processing at least one item before cancelling
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let result = await task.value

        // After cancellation, we expect fewer than all items were processed
        #expect(result.totalCount < items.count,
                "Cancelled batch should have processed fewer than all \(items.count) items, got \(result.totalCount)")

        // Clean up output temp files (may be multiple if multiple items ran)
        for url in result.successes {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Test 3: Per-Item Error Resilience

    @Test("A failing item adds to failures but remaining items continue processing")
    func failingItemRecordsErrorButContinues() async throws {
        // Create a valid test image for the good item
        let goodURL = try createTestImageFile()
        defer { try? FileManager.default.removeItem(at: goodURL) }

        // Create a bad item with a non-existent URL that will fail during processing
        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent_file_\(UUID().uuidString).jpg")
        let badItem = BatchProcessor.BatchItem(
            id: UUID(),
            sourceURL: badURL,
            mediaType: .photo
        )
        let goodItem = makePhotoItem(sourceURL: goodURL)

        let processor = BatchProcessor()
        let config = WatermarkConfiguration()

        let result = await processor.process(items: [badItem, goodItem], sharedConfig: config)

        #expect(result.failureCount >= 1, "Expected at least 1 failure, got \(result.failureCount)")
        #expect(result.successCount == 1, "Expected 1 success (good item), got \(result.successCount)")
        #expect(result.totalCount == 2, "Expected 2 total items processed, got \(result.totalCount)")

        // Verify the bad item UUID is in failures
        #expect(result.failures[badItem.id] != nil, "Bad item ID should be in failures dict")

        // Clean up output temp files
        for url in result.successes {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Test 4: Progress Callback Accuracy

    @Test("Progress callback fires with correct (current, total) at each item boundary")
    func progressCallbackFiresCorrectValues() async throws {
        let urls = try (0..<3).map { _ in try createTestImageFile() }
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

        let items = urls.map { makePhotoItem(sourceURL: $0) }
        let processor = BatchProcessor()
        let config = WatermarkConfiguration()

        // Capture progress values
        let collector = ProgressCollector()

        let result = await processor.process(items: items, sharedConfig: config) { current, total, eta in
            collector.append(current, total, eta)
        }

        #expect(collector.values.count == 3,
                "Expected 3 progress callbacks, got \(collector.values.count)")

        // Verify each callback reports the correct total
        for (_, total, _) in collector.values {
            #expect(total == 3, "Total should always be 3, got \(total)")
        }

        // Verify current values are 1, 2, 3 in order
        let currents = collector.values.map { $0.0 }
        #expect(currents == [1, 2, 3], "Expected [1, 2, 3], got \(currents)")

        // Clean up output temp files
        for url in result.successes {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Test 5: Duration Tracking

    @Test("Duration is greater than zero after a successful batch")
    func durationGreaterThanZeroAfterBatch() async throws {
        let url = try createTestImageFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let item = makePhotoItem(sourceURL: url)
        let processor = BatchProcessor()
        let config = WatermarkConfiguration()

        let result = await processor.process(items: [item], sharedConfig: config)

        #expect(result.duration > 0, "Duration should be > 0, got \(result.duration)")

        // Clean up output temp file
        if let outputURL = result.successes.first {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
}
