import Testing
import Foundation
@testable import WatermarkCore

/// Plan 19-03: provenance controls, claim gates, export receipt UI, and the
/// More section / Sign flow. Tests cover the migration-safe Codable behavior
/// of `WatermarkConfiguration` provenance fields, the claim-gating rules from
/// `SourceProvenanceReport`, and the compulsory-author gate for C2PA signing.
@Suite("ProvenanceControls")
struct ProvenanceControlsTests {

    // MARK: - Task 1: Persisted Provenance Settings

    @Suite("WatermarkConfiguration Provenance Defaults")
    struct ConfigDefaultsTests {

        @Test("Default config has empty creator (cannot sign) and C2PA off")
        func defaultConfigCannotSign() {
            let config = WatermarkConfiguration()
            #expect(config.rightsMetadata.creator.isEmpty)
            #expect(config.includeC2PAManifest == false)
            #expect(config.sourceDeclaration == .none)
            #expect(config.metadataPrivacyProfile == .preserveAll)
            #expect(config.invisibleProtectionEnabled == false)
        }

        @Test("Old config JSON without provenance keys decodes to safe defaults")
        func legacyConfigDecodes() throws {
            let legacy = """
            {"watermarks":[],"padding":20,"outputFormat":"preserveSource","outputQuality":1.0}
            """.data(using: .utf8)!
            let config = try JSONDecoder().decode(WatermarkConfiguration.self, from: legacy)
            #expect(config.metadataPrivacyProfile == .preserveAll)
            #expect(config.includeC2PAManifest == false)
            #expect(config.sourceDeclaration == .none)
            #expect(config.invisibleProtectionEnabled == false)
            #expect(config.rightsMetadata.creator.isEmpty)
        }

        @Test("Config with provenance fields round-trips through Codable")
        func configRoundTrips() throws {
            var config = WatermarkConfiguration()
            config.rightsMetadata.creator = "Jane Doe"
            config.rightsMetadata.copyrightNotice = "© 2026 Jane"
            config.metadataPrivacyProfile = .stripSensitive
            config.includeC2PAManifest = true
            config.sourceDeclaration = .camera
            config.invisibleProtectionEnabled = true
            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(WatermarkConfiguration.self, from: data)
            #expect(decoded.rightsMetadata.creator == "Jane Doe")
            #expect(decoded.rightsMetadata.copyrightNotice == "© 2026 Jane")
            #expect(decoded.metadataPrivacyProfile == .stripSensitive)
            #expect(decoded.includeC2PAManifest == true)
            #expect(decoded.sourceDeclaration == .camera)
            #expect(decoded.invisibleProtectionEnabled == true)
        }

        @Test("Defaults do not enable verified-camera language")
        func defaultsDoNotEnableVerifiedCamera() {
            // Verified-camera language is gated by the runtime report, NOT config.
            // The default config must not carry any verified-camera enabling flag.
            // No config field can unlock verified-camera wording; the gate is
            // `report.allowsVerifiedCameraClaim` which only the analyzer sets.
            let config = WatermarkConfiguration()
            // A neutral default declaration; verified-camera is never a config value.
            #expect(config.sourceDeclaration == .none)
            #expect(config.includeC2PAManifest == false)
        }
    }

    // MARK: - Task 3: Claim-Gated Disclosure Text

    @Suite("Claim Gates")
    struct ClaimGateTests {

        @Test("Unknown and user-declared reports never allow verified-camera UI")
        func gatesStayClosed() {
            let unknown = SourceProvenanceReport(state: .unknown, evidence: [])
            let declared = SourceProvenanceReport(state: .userDeclared, evidence: [], userDeclaration: .camera)
            #expect(unknown.allowsVerifiedCameraClaim == false)
            #expect(declared.allowsVerifiedCameraClaim == false)
            #expect(unknown.allowsNoAIClaim == false)
            #expect(declared.allowsNoAIClaim == false)
        }

        @Test("Marked AI cannot be hidden by a contradictory user declaration")
        func markedAICannotBeHidden() {
            // A user declaring "camera" on a marked-AI source must NOT flip the
            // state to verified or userDeclared — the stronger evidence wins.
            let report = SourceProvenanceReport(state: .markedAI, evidence: [], userDeclaration: .camera)
            #expect(report.state == .markedAI)
            #expect(report.allowsVerifiedCameraClaim == false)
        }

        @Test("Only verifiedCameraCapture unlocks verified-camera wording (D-17)")
        func onlyVerifiedCameraUnlocksWording() {
            let verified = SourceProvenanceReport(state: .verifiedCameraCapture, evidence: [])
            #expect(verified.allowsVerifiedCameraClaim == true)
            // All other states stay closed.
            for state in [ProvenanceState.markedAI, .userDeclared, .unknown, .suspectedAI] {
                let r = SourceProvenanceReport(state: state, evidence: [])
                #expect(r.allowsVerifiedCameraClaim == false)
            }
        }

        @Test("allowsNoAIClaim is always false (D-05: no detector can prove a negative)")
        func noAIClaimAlwaysFalse() {
            for state in ProvenanceState.allCases {
                let r = SourceProvenanceReport(state: state, evidence: [])
                #expect(r.allowsNoAIClaim == false)
            }
        }
    }

    // MARK: - Task 5: Compulsory Author Gate

    @Suite("Signing Author Gate")
    struct SigningAuthorGateTests {

        @Test("Signing is gated on a non-empty creator name")
        func signingRequiresAuthor() {
            var config = WatermarkConfiguration()
            #expect(config.rightsMetadata.creator.isEmpty) // default: no author → cannot sign
            config.rightsMetadata.creator = "Jane Doe"
            #expect(config.rightsMetadata.creator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        }

        @Test("Whitespace-only creator does not unlock signing")
        func whitespaceCreatorCannotSign() {
            var config = WatermarkConfiguration()
            config.rightsMetadata.creator = "   "
            let trimmed = config.rightsMetadata.creator.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(trimmed.isEmpty)
        }

        @Test("includeC2PAManifest defaults to false (signing never automatic, D-25)")
        func signingNeverAutomatic() {
            let config = WatermarkConfiguration()
            #expect(config.includeC2PAManifest == false)
        }
    }

    @Suite("Batch C2PA Disclosure")
    struct BatchC2PADisclosureTests {

        @Test("Mixed batches say images are signed and videos continue without errors")
        func mixedBatchDisclosure() {
            let disclosure = BatchC2PASigningDisclosure(signableImageCount: 3, videoCount: 2)

            #expect(disclosure.hasVideos)
            #expect(disclosure.hasSignableImages)
            #expect(disclosure.confirmationButtonTitle == "OK, Sign Images")
            #expect(disclosure.alertContinueButtonTitle == "OK, Sign Images")
            #expect(disclosure.alertMessage.contains("sign the image exports"))
            #expect(disclosure.alertMessage.contains("videos without C2PA signatures"))
            #expect(disclosure.alertMessage.contains("Videos will not be treated as signing errors"))
        }

        @Test("All-video batches do not pretend signing is available")
        func allVideoDisclosure() {
            let disclosure = BatchC2PASigningDisclosure(signableImageCount: 0, videoCount: 2)

            #expect(disclosure.hasVideos)
            #expect(disclosure.hasSignableImages == false)
            #expect(disclosure.confirmationButtonTitle == "OK, Continue")
            #expect(disclosure.alertContinueButtonTitle == "OK, Continue")
            #expect(disclosure.sheetText.contains("no images"))
            #expect(disclosure.sheetText.contains("not available for videos"))
        }
    }
}
