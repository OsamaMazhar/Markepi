import Testing
import ImageIO
import Foundation
@testable import WatermarkCore

@Suite("SourceProvenanceAnalyzer")
struct SourceProvenanceAnalyzerTests {
    let analyzer = SourceProvenanceAnalyzer()

    @Test("Plain image with no provenance metadata is Unknown")
    func plainImageIsUnknown() {
        let report = analyzer.analyze(metadata: [:])
        #expect(report.state == .unknown)
        #expect(report.allowsVerifiedCameraClaim == false)
        #expect(report.allowsNoAIClaim == false)
    }

    @Test("Editable camera EXIF alone stays Unknown but records evidence")
    func cameraExifAloneIsUnknown() {
        let metadata: [String: Any] = [
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: "Apple",
                kCGImagePropertyTIFFModel as String: "iPhone 17 Pro",
            ]
        ]
        let report = analyzer.analyze(metadata: metadata)
        #expect(report.state == .unknown)
        #expect(report.evidence.contains { $0.kind == .exifCameraMakeModel })
        #expect(report.allowsVerifiedCameraClaim == false)
    }

    @Test("IPTC trainedAlgorithmicMedia classifies as Marked AI")
    func iptcTrainedAlgorithmicMediaIsMarkedAI() {
        let metadata: [String: Any] = [
            kCGImagePropertyIPTCDictionary as String: [
                kCGImagePropertyIPTCExtDigitalSourceType as String:
                    "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"
            ]
        ]
        #expect(analyzer.analyze(metadata: metadata).state == .markedAI)
    }

    @Test("Marked-AI evidence wins over a contradictory user 'camera' declaration")
    func markedAIBeatsUserCameraDeclaration() {
        let metadata: [String: Any] = [
            kCGImagePropertyIPTCDictionary as String: [
                kCGImagePropertyIPTCExtDigitalSourceType as String:
                    "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"
            ]
        ]
        let report = analyzer.analyze(metadata: metadata, userDeclaration: .camera)
        #expect(report.state == .markedAI)
        #expect(report.allowsVerifiedCameraClaim == false)
    }

    @Test("User declaration on an unmarked image is recorded as User-Declared, not verified")
    func userDeclarationIsRecordedAsDeclaration() {
        let report = analyzer.analyze(metadata: [:], userDeclaration: .camera)
        #expect(report.state == .userDeclared)
        #expect(report.allowsVerifiedCameraClaim == false)
        #expect(report.userDeclaration == .camera)
    }

    @Test("Codable round-trips without losing state or evidence")
    func reportIsCodable() throws {
        let original = analyzer.analyze(metadata: [:], userDeclaration: .ai)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SourceProvenanceReport.self, from: data)
        #expect(decoded.state == original.state)
        #expect(decoded.userDeclaration == .ai)
    }

    @Test("No watermark found does not unlock No AI Used")
    func noWatermarkDoesNotUnlockNoAI() {
        let report = analyzer.analyze(metadata: [:])
        #expect(report.state == .unknown)
        #expect(report.allowsNoAIClaim == false)
    }

    @Test("Unknown state never allows verified camera claim")
    func unknownNeverAllowsVerifiedCamera() {
        let report = analyzer.analyze(metadata: [:])
        #expect(report.state == .unknown)
        #expect(report.allowsVerifiedCameraClaim == false)
    }

    @Test("User-declared state never allows verified camera claim")
    func userDeclaredNeverAllowsVerifiedCamera() {
        let report = analyzer.analyze(metadata: [:], userDeclaration: .camera)
        #expect(report.state == .userDeclared)
        #expect(report.allowsVerifiedCameraClaim == false)
    }

    @Test("User-declared state never allows no-AI claim")
    func userDeclaredNeverAllowsNoAI() {
        let report = analyzer.analyze(metadata: [:], userDeclaration: .camera)
        #expect(report.allowsNoAIClaim == false)
    }

    @Test("Suspect AI from software marker hint")
    func suspectAIFromSoftwareMarker() {
        let metadata: [String: Any] = [
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFSoftware as String: "Midjourney"
            ]
        ]
        let report = analyzer.analyze(metadata: metadata)
        #expect(report.state == .suspectedAI)
        #expect(report.allowsVerifiedCameraClaim == false)
        #expect(report.warnings.contains { $0.contains("not conclusive") })
    }

    @Test("C2PA signed AI generation returns markedAI")
    func c2paSignedAIGenerationReturnsMarkedAI() {
        let summary = SourceProvenanceAnalyzer.C2PASummary(
            isValidlySigned: true,
            indicatesAIGeneration: true,
            indicatesTrustedCapture: false
        )
        let report = analyzer.analyze(metadata: [:], c2paSummary: summary)
        #expect(report.state == .markedAI)
    }

    @Test("C2PA signed trusted capture returns verifiedCameraCapture")
    func c2paSignedTrustedCaptureReturnsVerified() {
        let summary = SourceProvenanceAnalyzer.C2PASummary(
            isValidlySigned: true,
            indicatesAIGeneration: false,
            indicatesTrustedCapture: true
        )
        let report = analyzer.analyze(metadata: [:], c2paSummary: summary)
        #expect(report.state == .verifiedCameraCapture)
        #expect(report.allowsVerifiedCameraClaim == true)
    }

    @Test("C2PA signed without AI or capture flags falls through")
    func c2paSignedNoFlagsFallsThrough() {
        let summary = SourceProvenanceAnalyzer.C2PASummary(
            isValidlySigned: true,
            indicatesAIGeneration: false,
            indicatesTrustedCapture: false
        )
        let report = analyzer.analyze(metadata: [:], c2paSummary: summary)
        #expect(report.state == .unknown)
        #expect(report.evidence.contains { $0.kind == .c2paManifest })
    }

    @Test("allowsRightsProtection is true for all states")
    func rightsProtectionTrueForAllStates() {
        for state in ProvenanceState.allCases {
            #expect(state.allowsRightsProtection == true)
        }
    }

    @Test("ProvenanceState display labels are non-empty and distinct")
    func displayLabelsAreNonEmptyAndDistinct() {
        var seen: Set<String> = []
        for state in ProvenanceState.allCases {
            let label = state.displayLabel
            #expect(!label.isEmpty)
            #expect(!seen.contains(label))
            seen.insert(label)
        }
    }
}
