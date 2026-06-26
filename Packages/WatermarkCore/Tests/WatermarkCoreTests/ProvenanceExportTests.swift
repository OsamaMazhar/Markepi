import Testing
import ImageIO
import Foundation
@testable import WatermarkCore

@Suite("ProvenanceExport")
struct ProvenanceExportTests {

    // MARK: - Task 2: C2PA Signing Identity Store

    @Suite("C2PASigningIdentityStore")
    struct SigningIdentityStoreTests {

        @Test("Current identity always returns a non-nil display name")
        func identityHasDisplayName() {
            let store = C2PASigningIdentityStore()
            let identity = store.currentIdentity()
            #expect(identity.displayName == "Markepi device signing identity")
        }

        @Test("Identity type is one of secureEnclave / localSoftware / unsupported")
        func identityTypeIsValid() {
            let store = C2PASigningIdentityStore()
            let identity = store.currentIdentity()
            switch identity.type {
            case .secureEnclave, .localSoftware, .unsupported:
                break // valid
            }
        }

        @Test("Identity type raw value is stable for receipt encoding")
        func identityTypeRawValueStable() {
            #expect(C2PASigningIdentity.IdentityType.secureEnclave.rawValue == "secureEnclave")
            #expect(C2PASigningIdentity.IdentityType.localSoftware.rawValue == "localSoftware")
            #expect(C2PASigningIdentity.IdentityType.unsupported.rawValue == "unsupported")
        }

        @Test("Display name never describes a verified legal identity (D-24)")
        func displayNameIsNotVerifiedLegalIdentity() {
            let store = C2PASigningIdentityStore()
            let name = store.currentIdentity().displayName
            #expect(!name.lowercased().contains("verified"))
            #expect(!name.lowercased().contains("legal"))
            #expect(name.contains("device"))
        }
    }

    // MARK: - Task 3: C2PAProvenanceClient Protocol + NoopC2PAProvenanceClient

    @Suite("NoopC2PAProvenanceClient")
    struct NoopC2PAProvenanceClientTests {

        @Test("Noop client reads no source manifest (returns nil)")
        func noopReadsNoManifest() async {
            let client = NoopC2PAProvenanceClient()
            let summary = await client.readSourceSummary(from: URL(fileURLWithPath: "/tmp/none"))
            #expect(summary == nil)
        }

        @Test("Noop client honestly reports 'not signed' with a warning")
        func noopReportsNotSigned() async throws {
            let client = NoopC2PAProvenanceClient()
            let identity = C2PASigningIdentity(type: .unsupported, secKey: nil)
            let manifest = C2PAManifestRequest(
                appVersion: "2.2.0",
                sourceState: .unknown,
                sourceEvidenceSummary: [],
                visibleWatermarkApplied: false,
                whiteFrameApplied: false,
                privacyAction: nil,
                userDeclaration: .none,
                invisibleWatermarkPayloadID: nil
            )
            let result = try await client.signExport(
                outputURL: URL(fileURLWithPath: "/tmp/out"),
                source: URL(fileURLWithPath: "/tmp/src"),
                manifest: manifest,
                identity: identity
            )
            #expect(result.status == .notSigned)
            #expect(result.identityType == .unsupported)
            #expect(result.displayName == "Markepi device signing identity")
            #expect(!result.warnings.isEmpty)
        }

        @Test("C2PAManifestRequest carries product name 'Markepi' (D-23)")
        func manifestAppNameIsMarkepi() {
            let manifest = C2PAManifestRequest(
                appVersion: "1.0",
                sourceState: .unknown,
                sourceEvidenceSummary: [],
                visibleWatermarkApplied: false,
                whiteFrameApplied: false,
                privacyAction: nil,
                userDeclaration: .none,
                invisibleWatermarkPayloadID: nil
            )
            #expect(manifest.appName == "Markepi")
        }

        @Test("C2PASigningResult status encodes signed/notSigned/notSupported")
        func signingResultStatusValues() {
            let signed = C2PASigningResult(
                status: .signed, identityType: .secureEnclave,
                displayName: "Markepi device signing identity"
            )
            let notSigned = C2PASigningResult(
                status: .notSigned, identityType: .unsupported,
                displayName: "Markepi device signing identity",
                warnings: ["disabled"]
            )
            let notSupported = C2PASigningResult(
                status: .notSupported, identityType: .unsupported,
                displayName: "Markepi device signing identity"
            )
            #expect(signed.status == .signed)
            #expect(notSigned.status == .notSigned)
            #expect(notSupported.status == .notSupported)
            #expect(signed.warnings.isEmpty)
            #expect(notSigned.warnings == ["disabled"])
        }
    }

    // MARK: - Task 4: IPTC Rights Metadata Writer

    @Suite("IPTCRightsMetadataWriter")
    struct IPTCRightsMetadataWriterTests {

        let writer = IPTCRightsMetadataWriter()

        @Test("Merges creator into IPTC byline without dropping existing EXIF")
        func mergesCreatorPreservingExif() {
            let metadata: [String: Any] = [
                kCGImagePropertyExifDictionary as String: [
                    kCGImagePropertyExifExposureTime as String: 0.001
                ]
            ]
            var rights = RightsMetadata()
            rights.creator = "Jane Photographer"
            let out = writer.merged(into: metadata, rights: rights)
            let exif = out[kCGImagePropertyExifDictionary as String] as? [String: Any]
            #expect(exif?[kCGImagePropertyExifExposureTime as String] as? Double == 0.001)
            let iptc = out[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
            #expect(iptc?[kCGImagePropertyIPTCByline as String] as? [String] == ["Jane Photographer"])
        }

        @Test("Writes copyright notice to IPTC and TIFF")
        func writesCopyrightToIPTCAndTIFF() {
            var rights = RightsMetadata()
            rights.copyrightNotice = "© 2026 Jane Photographer"
            let out = writer.merged(into: [:], rights: rights)
            let iptc = out[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
            #expect(iptc?[kCGImagePropertyIPTCCopyrightNotice as String] as? String == "© 2026 Jane Photographer")
            let tiff = out[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
            #expect(tiff?[kCGImagePropertyTIFFCopyright as String] as? String == "© 2026 Jane Photographer")
        }

        @Test("Writes credit line and usage terms")
        func writesCreditAndUsageTerms() {
            var rights = RightsMetadata()
            rights.creditLine = "Markepi"
            rights.usageTerms = "All rights reserved"
            let out = writer.merged(into: [:], rights: rights)
            let iptc = out[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
            #expect(iptc?[kCGImagePropertyIPTCCredit as String] as? String == "Markepi")
            #expect(iptc?[kCGImagePropertyIPTCRightsUsageTerms as String] as? String == "All rights reserved")
        }

        @Test("Digital Source Type can represent trained algorithmic media")
        func digitalSourceTypeTrainedAlgorithmic() {
            var rights = RightsMetadata()
            rights.digitalSourceType =
                "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"
            let out = writer.merged(into: [:], rights: rights)
            let iptc = out[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
            #expect(iptc?[kCGImagePropertyIPTCExtDigitalSourceType as String] as? String ==
                "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia")
        }

        @Test("Empty rights metadata leaves IPTC dict untouched (no empty keys)")
        func emptyRightsLeavesNoEmptyKeys() {
            let rights = RightsMetadata()
            let out = writer.merged(into: [:], rights: rights)
            let iptc = out[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
            // IPTC dict exists but carries no creator/copyright/credit keys
            #expect(iptc?[kCGImagePropertyIPTCByline as String] == nil)
            #expect(iptc?[kCGImagePropertyIPTCCopyrightNotice as String] == nil)
        }

        @Test("RightsMetadata encodes and decodes")
        func rightsMetadataCodable() throws {
            var rights = RightsMetadata()
            rights.creator = "C"
            rights.copyrightNotice = "©"
            rights.creditLine = "Cr"
            rights.usageTerms = "UT"
            rights.licensorURL = "https://example.com"
            rights.digitalSourceType = "http://cv.iptc.org/newscodes/digitalsourcetype/photoCapture"
            let data = try JSONEncoder().encode(rights)
            let decoded = try JSONDecoder().decode(RightsMetadata.self, from: data)
            #expect(decoded == rights)
        }
    }
}
