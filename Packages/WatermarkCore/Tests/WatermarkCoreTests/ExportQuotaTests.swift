import Foundation
import Testing
@testable import WatermarkCore

/// Every test uses a fresh, random `UserDefaults` suite so the free-tier
/// counters never touch the real App Group the app reads on launch.
@Suite("Export quota")
struct ExportQuotaTests {

    private func makeSuite() -> String { "test.exportQuota.\(UUID().uuidString)" }

    @Test("A fresh day grants the full 3-photo / 1-video allowance")
    func freshAllowance() {
        let q = ExportQuota(suiteName: makeSuite())
        #expect(q.remainingPhotos() == 3)
        #expect(q.remainingVideos() == 1)
        #expect(q.canExport(photos: 3, videos: 1))
        #expect(!q.canExport(photos: 4))
        #expect(!q.canExport(videos: 2))
    }

    @Test("Recording draws down only the matching bucket")
    func recordDrawsDown() {
        let q = ExportQuota(suiteName: makeSuite())
        q.record(photos: 2)
        #expect(q.remainingPhotos() == 1)
        #expect(q.remainingVideos() == 1)   // video bucket untouched
        q.record(videos: 1)
        #expect(q.remainingVideos() == 0)
        #expect(!q.canExport(videos: 1))
        #expect(q.canExport(photos: 1))
    }

    @Test("Photo and video buckets are independent")
    func independentBuckets() {
        let q = ExportQuota(suiteName: makeSuite())
        q.record(videos: 1)
        #expect(!q.canExport(videos: 1))    // video exhausted…
        #expect(q.canExport(photos: 3))     // …photos still fully available
    }

    @Test("Exhausting a bucket blocks further exports from it")
    func overLimitBlocked() {
        let q = ExportQuota(suiteName: makeSuite())
        q.record(photos: 3)
        #expect(q.remainingPhotos() == 0)
        #expect(!q.canExport(photos: 1))
    }

    @Test("Counters reset when the calendar day rolls over")
    func dayRollover() {
        let q = ExportQuota(suiteName: makeSuite())
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        q.record(photos: 3, videos: 1, now: yesterday)
        #expect(q.usage(now: yesterday).photos == 3)
        #expect(!q.canExport(photos: 1, now: yesterday))

        // A new day is a clean slate without any explicit reset.
        #expect(q.remainingPhotos(now: today) == 3)
        #expect(q.remainingVideos(now: today) == 1)
        #expect(q.canExport(photos: 3, videos: 1, now: today))
    }

    @Test("reset() clears all counters")
    func resetClears() {
        let q = ExportQuota(suiteName: makeSuite())
        q.record(photos: 3, videos: 1)
        q.reset()
        #expect(q.remainingPhotos() == 3)
        #expect(q.remainingVideos() == 1)
    }
}

@Suite("Export gate")
struct ExportGateTests {

    private func makeSuite() -> String { "test.exportGate.\(UUID().uuidString)" }

    @Test("Free users are bounded by the daily quota")
    func freeUserLimited() {
        let suite = makeSuite()
        let gate = ExportGate(quota: ExportQuota(suiteName: suite),
                              status: PremiumStatusStore(suiteName: suite))
        #expect(!gate.isPremium)
        #expect(gate.canExport(photos: 3, videos: 1))
        gate.record(photos: 3, videos: 1)
        #expect(!gate.canExport(photos: 1))
        #expect(!gate.canExport(videos: 1))
    }

    @Test("Premium users bypass the quota and record nothing")
    func premiumBypass() {
        let suite = makeSuite()
        let status = PremiumStatusStore(suiteName: suite)
        status.set(true)
        let quota = ExportQuota(suiteName: suite)
        let gate = ExportGate(quota: quota, status: status)

        #expect(gate.isPremium)
        #expect(gate.canExport(photos: 100, videos: 100))
        gate.record(photos: 100, videos: 100)   // no-op for premium
        #expect(quota.usage().photos == 0)
        #expect(quota.usage().videos == 0)
    }
}
