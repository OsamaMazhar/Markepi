import AVFoundation
import Foundation
import Testing
@testable import MarkepiCore

@Suite("Export tiers")
struct ExportTierTests {

    @Test("Pro policy keeps everything")
    func proPolicy() {
        let p = ExportPolicy(tier: .pro)
        #expect(p.maxPixelDimension == nil)
        #expect(p.lossyQualityCap == nil)
        #expect(p.keepsGainMap)
        #expect(p.videoPreset == nil)
        #expect(!p.forcesSDRVideo)
        #expect(!p.brandMark)
    }

    @Test("Free policy reduces size, drops HDR, adds the mark")
    func freePolicy() {
        let p = ExportPolicy(tier: .free)
        #expect(p.maxPixelDimension == 2048)
        #expect(p.lossyQualityCap == 0.7)
        #expect(!p.keepsGainMap)
        #expect(p.videoPreset == AVAssetExportPreset1920x1080)
        #expect(p.forcesSDRVideo)
        #expect(p.brandMark)
    }

    @Test("Gate follows the cached entitlement")
    func gateFollowsEntitlement() {
        let suite = "test.exportTier.\(UUID().uuidString)"
        let status = PremiumStatusStore(suiteName: suite)
        let gate = ExportGate(status: status)
        #if DEBUG
        let wasForced = DebugPremium.isForced
        DebugPremium.isForced = false
        defer { DebugPremium.isForced = wasForced }
        #endif
        status.set(false)
        #expect(gate.tier == .free)
        status.set(true)
        #expect(gate.tier == .pro)
        status.set(false)
        #if DEBUG
        DebugPremium.isForced = true
        #expect(gate.tier == .pro)
        #endif
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test("Legacy quota keys are removed")
    func legacyKeysRemoved() {
        let suite = "test.exportTier.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set("2026-10-01", forKey: "exportQuota.day")
        d.set(3, forKey: "exportQuota.photoCount")
        d.set(1, forKey: "exportQuota.videoCount")
        ExportGate.removeLegacyQuotaKeys(suiteName: suite)
        #expect(d.object(forKey: "exportQuota.day") == nil)
        #expect(d.object(forKey: "exportQuota.photoCount") == nil)
        #expect(d.object(forKey: "exportQuota.videoCount") == nil)
        UserDefaults().removePersistentDomain(forName: suite)
    }
}
