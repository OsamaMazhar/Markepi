import Foundation
import Testing
@testable import MarkepiCore

/// The batch's progress bar and its countdown.
///
/// Reported as "it shows how many images are left, but the ETA is always 0
/// mins and the bar doesn't move continuously". Three separate faults: the
/// estimate divided the batch by item count, the bar was driven by that count,
/// and the label printed whole minutes.
@Suite("Batch progress")
struct BatchProgressTests {

    private func item(_ type: WatermarkEngine.MediaType, _ name: String) -> BatchProcessor.BatchItem {
        BatchProcessor.BatchItem(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/tmp/\(name)"),
            mediaType: type
        )
    }

    // MARK: - What an item is expected to cost

    @Test("A video counts for more of the batch than a photo")
    func videoOutweighsPhoto() async {
        // A file that does not exist loads no duration, so this is a video's
        // floor — even that has to outweigh a photo, or a mixed batch reports
        // most of its work done before the long part starts.
        let costs = await BatchProcessor.estimatedCosts(
            for: [item(.photo, "a.jpg"), item(.video, "b.mov")])
        #expect(costs[1] > costs[0])
    }

    @Test("A video's share follows its duration")
    func longerVideoCostsMore() {
        let short = BatchProcessor.videoFixedCost + BatchProcessor.videoCostPerSecond * 5
        let long = BatchProcessor.videoFixedCost + BatchProcessor.videoCostPerSecond * 120
        #expect(long > short * 5, "two minutes should not be priced like five seconds")
    }

    // MARK: - The bar

    @Test("The bar measures work, not items")
    func fractionIsWeighted() {
        // Twenty photos and one long video: finishing every photo is most of
        // the count and a small part of the work, which is exactly the case
        // where a count-driven bar lies.
        let photos = Array(repeating: BatchProcessor.photoCost, count: 20)
        let video = BatchProcessor.videoFixedCost + BatchProcessor.videoCostPerSecond * 120
        let total = photos.reduce(0, +) + video

        let afterPhotos = BatchProcessor.progress(
            completedItems: 20, totalItems: 21,
            doneCost: photos.reduce(0, +), totalCost: total, elapsed: 16)

        #expect(afterPhotos.completedItems == 20, "the count still says twenty of twenty-one")
        #expect(afterPhotos.fractionCompleted < 0.3, "but the work is mostly still ahead")
    }

    @Test("Progress inside one item moves the bar")
    func fractionMovesWithinAnItem() {
        let video = 60.0
        let early = BatchProcessor.progress(completedItems: 0, totalItems: 1,
                                            doneCost: 6, totalCost: video, elapsed: 6)
        let later = BatchProcessor.progress(completedItems: 0, totalItems: 1,
                                            doneCost: 30, totalCost: video, elapsed: 30)
        #expect(later.fractionCompleted > early.fractionCompleted,
                "a single long video used to leave the bar frozen until it finished")
    }

    // MARK: - The countdown

    @Test("The estimate is the measured pace applied to the work left")
    func etaFollowsMeasuredPace() {
        // Half the work in ten seconds: about ten seconds to go, whatever the
        // priors guessed.
        let progress = BatchProcessor.progress(completedItems: 1, totalItems: 2,
                                               doneCost: 50, totalCost: 100, elapsed: 10)
        let eta = progress.estimatedTimeRemaining
        #expect(eta != nil)
        #expect(abs((eta ?? 0) - 10) < 0.001)
    }

    @Test("A device slower than the priors is measured, not assumed")
    func etaCalibratesToTheDevice() {
        // The same work taking four times as long gives four times the estimate.
        let quick = BatchProcessor.progress(completedItems: 1, totalItems: 4,
                                            doneCost: 25, totalCost: 100, elapsed: 5)
        let slow = BatchProcessor.progress(completedItems: 1, totalItems: 4,
                                           doneCost: 25, totalCost: 100, elapsed: 20)
        #expect(abs((slow.estimatedTimeRemaining ?? 0)
                    - (quick.estimatedTimeRemaining ?? 0) * 4) < 0.001)
    }

    @Test("No estimate is offered before there is one to make")
    func noWildFirstGuess() {
        let atTheStart = BatchProcessor.progress(completedItems: 0, totalItems: 10,
                                                 doneCost: 0, totalCost: 100, elapsed: 0.05)
        #expect(atTheStart.estimatedTimeRemaining == nil)
        #expect(atTheStart.fractionCompleted == 0)
    }

    @Test("The last item leaves nothing to wait for")
    func etaEndsAtZero() {
        let done = BatchProcessor.progress(completedItems: 3, totalItems: 3,
                                           doneCost: 100, totalCost: 100, elapsed: 30)
        #expect(done.fractionCompleted == 1)
        #expect(done.estimatedTimeRemaining == 0)
    }

    // MARK: - What it says

    @Test("Under a minute is spoken in seconds, not as zero minutes")
    func shortBatchesDoNotSayZeroMinutes() {
        // The whole of a short batch used to read "ETA: 0 min".
        #expect(TimeRemaining.phrase(12) == "About 15 sec left")
        #expect(TimeRemaining.phrase(45) == "About 45 sec left")
        #expect(!TimeRemaining.phrase(30).contains("0 min"))
    }

    @Test("The edges are vague on purpose")
    func edgesAreVague() {
        #expect(TimeRemaining.phrase(nil) == "Estimating…")
        #expect(TimeRemaining.phrase(0) == "Estimating…")
        #expect(TimeRemaining.phrase(2) == "Almost done")
        #expect(TimeRemaining.phrase(75) == "About a minute left")
        #expect(TimeRemaining.phrase(200) == "About 3 min left")
    }
}
