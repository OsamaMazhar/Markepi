#if canImport(C2PA)
import C2PA
import CoreGraphics
import Foundation
import ImageIO
import Security
import Testing
@testable import WatermarkCore

/// Integration tests that exercise the REAL `C2PASwiftProvenanceClient` against
/// the actual c2pa library — no mocks. These prove whether a signed export file
/// genuinely carries an embedded, readable C2PA manifest for each output format
/// the app can produce (`OutputFormat`: JPEG, HEIC, PNG, TIFF).
///
/// On the Simulator the Secure Enclave is unavailable, so signing uses the
/// local Keychain software identity — the same fallback the app uses there.
@Suite("Real C2PA signing integration")
struct C2PARealSigningIntegrationTests {

    private func makeTestFile(uti: CFString, ext: String) throws -> URL {
        let (cgImage, _) = TestImageFactory.solidColorImage(
            color: CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1),
            size: CGSize(width: 64, height: 64)
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("c2pa-real-sign-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        let dest = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, uti, 1, nil
        ))
        CGImageDestinationAddImage(dest, cgImage, nil)
        try #require(CGImageDestinationFinalize(dest))
        return url
    }

    private func manifestRequest() -> C2PAManifestRequest {
        C2PAManifestRequest(
            appVersion: "test",
            sourceState: .unknown,
            sourceEvidenceSummary: ["test evidence"],
            visibleWatermarkApplied: true,
            whiteFrameApplied: false,
            privacyAction: nil,
            userDeclaration: .none,
            invisibleWatermarkPayloadID: nil,
            creator: "Jane Doe"
        )
    }

    private func signAndVerify(uti: CFString, ext: String) async throws {
        let url = try makeTestFile(uti: uti, ext: ext)
        defer { try? FileManager.default.removeItem(at: url) }

        // The bare xctest runner has no keychain access, so the store's
        // persistent-key paths return nil there. Fall back to an ephemeral
        // in-memory EC P-256 key — same algorithm the app signs with — so the
        // real c2pa embed/sign/read-back path is exercised either way.
        let identity = try ephemeralIdentityIfNeeded(C2PASigningIdentityStore().currentIdentity())

        let client = C2PASwiftProvenanceClient()
        let result = try await client.signExport(
            outputURL: url,
            source: url,
            manifest: manifestRequest(),
            identity: identity
        )

        #expect(result.status == .signed, "\(ext): expected .signed, got \(result.status)")
        #expect(result.verification?.signatureIsIntact == true,
                "\(ext): read-back signature not intact: \(String(describing: result.verification))")

        // Independent read-back from the replaced output file — this is the
        // file the user actually shares.
        let readBack = await client.verifyExport(at: url)
        #expect(readBack != nil, "\(ext): shared file carries no readable C2PA manifest")
        #expect(readBack?.signatureIsIntact == true,
                "\(ext): shared file signature not intact: \(String(describing: readBack))")
    }

    /// Signs a source file first, then signs a second "export" file with the
    /// first as its parent ingredient — and proves the export's manifest store
    /// still carries the SOURCE's manifest (C2PA metadata + signature preserved
    /// through the edit, the spec's ingredient-chain model).
    @Test("Source C2PA manifest is preserved into the export as a parentOf ingredient")
    func sourceManifestPreservedAsIngredient() async throws {
        let sourceURL = try makeTestFile(uti: "public.jpeg" as CFString, ext: "jpg")
        let exportURL = try makeTestFile(uti: "public.jpeg" as CFString, ext: "jpg")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: exportURL)
        }

        let identity = try ephemeralIdentityIfNeeded(C2PASigningIdentityStore().currentIdentity())
        let client = C2PASwiftProvenanceClient()

        // 1. Give the SOURCE its own Content Credentials.
        let sourceResult = try await client.signExport(
            outputURL: sourceURL, source: sourceURL,
            manifest: manifestRequest(), identity: identity
        )
        try #require(sourceResult.status == .signed)

        // 2. Sign the export with the credentialed source as ingredient.
        let exportResult = try await client.signExport(
            outputURL: exportURL, source: sourceURL,
            manifest: manifestRequest(), identity: identity
        )
        #expect(exportResult.status == .signed)
        #expect(exportResult.verification?.signatureIsIntact == true)

        // 3. The export's manifest store must contain BOTH manifests (the
        //    source's original one rides along inside the store) and the active
        //    manifest must reference the source as a parentOf ingredient.
        let json = try await readManifestJSON(at: exportURL)
        let jsonData = try #require(json.data(using: .utf8))
        let root = try #require(
            try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        )
        let manifests = try #require(root["manifests"] as? [String: Any])
        #expect(manifests.count >= 2,
                "Export store should carry the source's manifest too, found \(manifests.count)")

        let activeID = try #require(root["active_manifest"] as? String)
        let active = try #require(manifests[activeID] as? [String: Any])
        let ingredients = try #require(active["ingredients"] as? [[String: Any]])
        #expect(ingredients.contains { ($0["relationship"] as? String) == "parentOf" },
                "Active manifest must list the source as a parentOf ingredient")
    }

    private func ephemeralIdentityIfNeeded(_ identity: C2PASigningIdentity) throws -> C2PASigningIdentity {
        guard identity.secKey == nil else { return identity }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        let key = try #require(
            SecKeyCreateRandomKey(attrs as CFDictionary, &error),
            "Could not create an ephemeral test signing key"
        )
        return C2PASigningIdentity(type: .localSoftware, secKey: key)
    }

    private func readManifestJSON(at url: URL) async throws -> String {
        try C2PA.readFile(at: url)
    }

    /// End-to-end through the ENGINE: a source that already carries Content
    /// Credentials keeps them through a full watermark export — with the user
    /// NOT opted into signing (no provenance options at all). This is the
    /// "C2PA metadata must be preserved along with other metadata" requirement.
    @Test("Engine export preserves source Content Credentials without user opt-in")
    func engineExportPreservesSourceCredentials() async throws {
        let sourceURL = try makeTestFile(uti: "public.jpeg" as CFString, ext: "jpg")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        // Give the source real Content Credentials first.
        let identity = try ephemeralIdentityIfNeeded(C2PASigningIdentityStore().currentIdentity())
        let client = C2PASwiftProvenanceClient()
        let sourceResult = try await client.signExport(
            outputURL: sourceURL, source: sourceURL,
            manifest: manifestRequest(), identity: identity
        )
        try #require(sourceResult.status == .signed)

        // Full engine export with provenance options OFF — like a user who
        // never touched the Content Credentials controls.
        let result = try await WatermarkEngine.shared.process(
            sourceURL: sourceURL,
            config: WatermarkConfiguration(),
            provenance: nil,
            preserveSourceCredentials: true
        )
        let outputURL = try #require(result.url)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let json = try await readManifestJSON(at: outputURL)
        let jsonData = try #require(json.data(using: .utf8))
        let root = try #require(
            try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        )
        let manifests = try #require(root["manifests"] as? [String: Any])
        #expect(manifests.count >= 2,
                "Export must carry the source's original manifest in its store")
        let activeID = try #require(root["active_manifest"] as? String)
        let active = try #require(manifests[activeID] as? [String: Any])
        let ingredients = try #require(active["ingredients"] as? [[String: Any]])
        #expect(ingredients.contains { ($0["relationship"] as? String) == "parentOf" })

        // Preservation must not fabricate an author assertion the user never made.
        let assertions = (active["assertions"] as? [[String: Any]]) ?? []
        #expect(!assertions.contains { ($0["label"] as? String) == "stds.schema-org.CreativeWork" },
                "Preservation manifest must not carry an author assertion")
    }

    /// A source with NO credentials and no signing opt-in must stay unsigned —
    /// preservation never invents Content Credentials from nothing.
    @Test("Engine export does not invent credentials for plain sources")
    func engineExportDoesNotInventCredentials() async throws {
        let sourceURL = try makeTestFile(uti: "public.jpeg" as CFString, ext: "jpg")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let result = try await WatermarkEngine.shared.process(
            sourceURL: sourceURL,
            config: WatermarkConfiguration(),
            provenance: nil,
            preserveSourceCredentials: true
        )
        let outputURL = try #require(result.url)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let readBack = await C2PASwiftProvenanceClient().verifyExport(at: outputURL)
        #expect(readBack == nil, "Plain source export must carry no manifest")
    }

    @Test("JPEG export carries an intact embedded manifest")
    func jpegSigning() async throws {
        try await signAndVerify(uti: "public.jpeg" as CFString, ext: "jpg")
    }

    @Test("HEIC export carries an intact embedded manifest")
    func heicSigning() async throws {
        try await signAndVerify(uti: "public.heic" as CFString, ext: "heic")
    }

    @Test("PNG export carries an intact embedded manifest")
    func pngSigning() async throws {
        try await signAndVerify(uti: "public.png" as CFString, ext: "png")
    }

    @Test("TIFF export carries an intact embedded manifest")
    func tiffSigning() async throws {
        try await signAndVerify(uti: "public.tiff" as CFString, ext: "tiff")
    }
}
#endif
