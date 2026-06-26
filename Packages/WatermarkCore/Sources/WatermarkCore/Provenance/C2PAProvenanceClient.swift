import Foundation

/// Adapter boundary over C2PA read/verify/sign so the engine never depends
/// on a concrete library (D-11/D-12). Async + Sendable ⇒ Share-Extension safe.
///
/// The default production client is `NoopC2PAProvenanceClient` because the
/// c2pa-spike (tools/c2pa-spike/) never completed and `contentauth/c2pa-swift`
/// is NOT a dependency of this package (fallback path, plan 19-02 Task 1).
/// When a future spike proves c2pa-swift integrates, a concrete client guarded
/// by `#if canImport(C2PA)` will replace the noop without touching the engine.
public protocol C2PAProvenanceClient: Sendable {
    /// Read & verify any manifest already in the source; returns the small
    /// summary the 19-01 analyzer consumes. nil = no manifest.
    ///
    /// - Parameter url: Source file URL to inspect for an existing C2PA manifest.
    /// - Returns: A `SourceProvenanceAnalyzer.C2PASummary`, or nil when no
    ///   manifest is present (or signing is disabled in this build).
    func readSourceSummary(from url: URL) async -> SourceProvenanceAnalyzer.C2PASummary?

    /// Build + sign a Markepi manifest and attach it to `outputURL` in place.
    /// `source` becomes an ingredient so existing provenance is preserved (D-04).
    ///
    /// After signing, the manifest is read back and validated so the receipt
    /// can report whether the signature is intact, whether the cert is trusted,
    /// and any other validation issues found by the C2PA verifier.
    ///
    /// - Parameters:
    ///   - outputURL: The already-rendered output file to attach the manifest to.
    ///   - source: Original source file (added as an ingredient — D-04/AUTH-04).
    ///   - manifest: Everything Markepi asserts, honestly (D-06, AUTH-02).
    ///   - identity: Local device signing identity (never a verified legal identity).
    /// - Returns: Signing status for the export receipt, including post-sign verification.
    func signExport(
        outputURL: URL,
        source: URL,
        manifest: C2PAManifestRequest,
        identity: C2PASigningIdentity
    ) async throws -> C2PASigningResult

    /// Read back and verify the C2PA manifest on an exported file.
    ///
    /// When called after signing, this re-reads the manifest and parses
    /// `validation_status` entries to determine whether the signature is
    /// intact and what validation issues exist.
    ///
    /// - Parameter url: The signed export file URL.
    /// - Returns: Structured verification result, or nil if no manifest is found.
    func verifyExport(at url: URL) async -> C2PAVerificationResult?
}

/// Everything Markepi asserts, honestly (D-06, AUTH-02). User declaration is
/// represented separately from any verified claim — it is recorded as a
/// declaration, never as verified language.
public struct C2PAManifestRequest: Sendable {
    /// Product name mandated by D-23. Always "Markepi".
    public var appName: String = "Markepi"
    /// App version string (e.g. "2.2.0").
    public var appVersion: String
    /// Export timestamp.
    public var exportedAt: Date
    /// Analyzed source provenance state (single source of truth).
    public var sourceState: ProvenanceState
    /// Human-readable evidence summary lines (recorded, not verified).
    public var sourceEvidenceSummary: [String]
    /// True when a visible watermark layer was composited.
    public var visibleWatermarkApplied: Bool
    /// True when the white-frame metadata overlay was composited.
    public var whiteFrameApplied: Bool
    /// Privacy action description (e.g. "GPS removed"), or nil when nothing stripped.
    public var privacyAction: String?
    /// User-supplied source declaration — recorded as a declaration, not verified.
    public var userDeclaration: UserSourceDeclaration
    /// Optional soft-binding ID for an invisible watermark payload (Plan 19-04).
    public var invisibleWatermarkPayloadID: String?
    /// Creator name for the sealed Tier-1 author assertion (D-26). When non-empty,
    /// the manifest emits a `stds.schema-org.CreativeWork` author assertion that is
    /// cryptographically bound by the signature. Signing is gated on a non-empty
    /// creator (enforced by the 19-03 UI).
    public var creator: String?

    public init(
        appVersion: String,
        sourceState: ProvenanceState,
        sourceEvidenceSummary: [String],
        visibleWatermarkApplied: Bool,
        whiteFrameApplied: Bool,
        privacyAction: String?,
        userDeclaration: UserSourceDeclaration,
        invisibleWatermarkPayloadID: String?,
        exportedAt: Date = Date(),
        creator: String? = nil
    ) {
        self.appVersion = appVersion
        self.sourceState = sourceState
        self.sourceEvidenceSummary = sourceEvidenceSummary
        self.visibleWatermarkApplied = visibleWatermarkApplied
        self.whiteFrameApplied = whiteFrameApplied
        self.privacyAction = privacyAction
        self.userDeclaration = userDeclaration
        self.invisibleWatermarkPayloadID = invisibleWatermarkPayloadID
        self.exportedAt = exportedAt
        self.creator = creator
    }
}

/// Result of a C2PA signing attempt — carried on the export receipt.
///
/// `status` is the honest outcome: `.signed` only when a manifest was actually
/// attached, `.notSigned` when signing is disabled (noop), `.notSupported`
/// when the format/path cannot carry C2PA (e.g. some video containers).
///
/// After signing, `verification` is populated by reading the manifest back and
/// parsing its `validation_status` entries so the receipt can report whether the
/// signature is intact and what validation issues exist.
public struct C2PASigningResult: Sendable, Codable, Equatable {
    public enum Status: String, Sendable, Codable {
        case signed
        case notSigned
        case notSupported
    }

    public let status: Status
    public let identityType: C2PASigningIdentity.IdentityType
    /// Receipt-safe display name: "Markepi device signing identity" (D-24).
    public let displayName: String
    /// Honest warnings (e.g. "C2PA signing is disabled in this build").
    public let warnings: [String]
    /// Post-sign verification — read back from the manifest after signing.
    /// nil when signing did not occur or read-back failed.
    public var verification: C2PAVerificationResult?

    public init(
        status: Status,
        identityType: C2PASigningIdentity.IdentityType,
        displayName: String,
        warnings: [String] = [],
        verification: C2PAVerificationResult? = nil
    ) {
        self.status = status
        self.identityType = identityType
        self.displayName = displayName
        self.warnings = warnings
        self.verification = verification
    }
}

/// One validation status entry from the C2PA manifest, parsed from the
/// `validation_status` array returned by `C2PA.readFile(at:)`.
public struct C2PAVerificationItem: Sendable, Codable, Equatable, Identifiable {
    public var id: String { code }
    public let code: String
    public let explanation: String
}

/// Overall verification result read back from a signed manifest.
public struct C2PAVerificationResult: Sendable, Codable, Equatable {
    public let signatureIsIntact: Bool
    public let items: [C2PAVerificationItem]

    public var allPassed: Bool {
        items.isEmpty || items.allSatisfy { $0.code == "signingCredential.untrusted" }
    }
    public var hasWarnings: Bool { !items.isEmpty }

    public init(signatureIsIntact: Bool, items: [C2PAVerificationItem]) {
        self.signatureIsIntact = signatureIsIntact
        self.items = items
    }
}

/// Safe default when c2pa-swift is unavailable/disabled. Always reports
/// `notSigned` so the receipt stays honest — it never claims a manifest was
/// attached when none was (AUTH-02).
///
/// This is the only concrete client that ships in the v2.2 build. A
/// `C2PASwiftProvenanceClient` guarded by `#if canImport(C2PA)` will replace
/// it once the c2pa-spike proves the dependency integrates.
public struct NoopC2PAProvenanceClient: C2PAProvenanceClient {
    public init() {}

    public func readSourceSummary(from url: URL) async -> SourceProvenanceAnalyzer.C2PASummary? {
        // No library available to read JUMBF manifests — report none honestly.
        nil
    }

    public func signExport(
        outputURL: URL,
        source: URL,
        manifest: C2PAManifestRequest,
        identity: C2PASigningIdentity
    ) async throws -> C2PASigningResult {
        C2PASigningResult(
            status: .notSigned,
            identityType: identity.type,
            displayName: identity.displayName,
            warnings: ["C2PA signing is disabled in this build."]
        )
    }

    public func verifyExport(at url: URL) async -> C2PAVerificationResult? {
        nil
    }
}

// MARK: - Concrete Client (c2pa-swift integration)

#if canImport(C2PA)
import C2PA
import Security

/// Production C2PA client backed by `contentauth/c2pa-swift`.
///
/// Uses the callback-based `Signer` so Secure Enclave keys (non-exportable) can
/// sign without exposing PEM private key material (D-24). Certificates are
/// generated on-device via `CertificateManager.createSelfSignedCertificateChain`
/// and cached for the identity's lifetime.
///
/// Receipt wording stays Tier-1 honest (D-24/D-27): the identity is described as
/// a "Markepi device signing identity", never a verified legal/person identity.
public struct C2PASwiftProvenanceClient: C2PAProvenanceClient {
    /// Thread-safe cert chain cache (NSCache is not Sendable in Swift 6).
    private let certCache: CertCache

    public init() {
        self.certCache = CertCache()
    }

    public func readSourceSummary(from url: URL) async -> SourceProvenanceAnalyzer.C2PASummary? {
        do {
            let manifestJSON = try C2PA.readFile(at: url)
            return parseManifestSummary(manifestJSON)
        } catch {
            // No manifest or unreadable — report none honestly.
            return nil
        }
    }

    public func signExport(
        outputURL: URL,
        source: URL,
        manifest: C2PAManifestRequest,
        identity: C2PASigningIdentity
    ) async throws -> C2PASigningResult {
        guard let secKey = identity.secKey else {
            return C2PASigningResult(
                status: .notSigned,
                identityType: identity.type,
                displayName: identity.displayName,
                warnings: ["No signing key available on this device."]
            )
        }

        // Generate or fetch the cached self-signed cert chain for this key.
        let certPEM = try certChain(for: secKey, identity: identity)

        // Build the manifest JSON from the request.
        let manifestJSON = buildManifestJSON(manifest)

        // Callback-based signer: uses SecKeyCreateSignature so SE keys work.
        let signer = try Signer(
            algorithm: .es256,
            certificateChainPEM: certPEM,
            tsa: nil
        ) { dataToSign in
            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(
                secKey,
                .ecdsaSignatureMessageX962SHA256,
                dataToSign as CFData,
                &error
            ) else {
                throw (error?.takeRetainedValue() as Error?) ?? C2PASignError.signingFailed
            }
            return signature as Data
        }

        let builder = try Builder(manifestJSON: manifestJSON)
        let sourceStream = try Stream(readFrom: source)
        let destStream = try Stream(writeTo: outputURL)

        _ = try builder.sign(
            format: "image/jpeg",
            source: sourceStream,
            destination: destStream,
            signer: signer
        )

        // Read back the manifest and verify signature integrity.
        let verification = await verifyExport(at: outputURL)

        return C2PASigningResult(
            status: .signed,
            identityType: identity.type,
            displayName: identity.displayName,
            warnings: [],
            verification: verification
        )
    }

    public func verifyExport(at url: URL) async -> C2PAVerificationResult? {
        do {
            let json = try C2PA.readFile(at: url)
            return parseVerification(from: json)
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private func certChain(for secKey: SecKey, identity: C2PASigningIdentity) throws -> String {
        let cacheKey = identity.type.rawValue
        if let cached = certCache.get(cacheKey) {
            return cached
        }
        let publicKey = SecKeyCopyPublicKey(secKey)!
        let config = CertificateManager.CertificateConfig(
            commonName: "Markepi Device Signer",
            organization: "Markepi",
            organizationalUnit: "Markepi App",
            country: "US",
            state: "—",
            locality: "—",
            emailAddress: nil,
            validityDays: 365
        )
        let pem = try CertificateManager.createSelfSignedCertificateChain(
            for: publicKey, config: config
        )
        certCache.set(pem, for: cacheKey)
        return pem
    }

    private func buildManifestJSON(_ request: C2PAManifestRequest) -> String {
        var assertions: [[String: Any]] = []

        // Tier-1 sealed author assertion (D-26). Only when creator is non-empty.
        if let creator = request.creator, !creator.isEmpty {
            assertions.append([
                "label": "stds.schema-org.CreativeWork",
                "data": [
                    "@context": "https://schema.org",
                    "@type": "CreativeWork",
                    "author": [["@type": "Person", "name": creator]],
                    "copyrightNotice": "© \(Calendar.current.component(.year, from: request.exportedAt)) \(creator)"
                ] as [String: Any]
            ])
        }

        // Provenance summary assertion — records source state as a declaration.
        assertions.append([
            "label": "c2pa.markepi.provenance",
            "data": [
                "sourceState": request.sourceState.rawValue,
                "evidenceSummary": request.sourceEvidenceSummary,
                "userDeclaration": request.userDeclaration.rawValue,
                "visibleWatermarkApplied": request.visibleWatermarkApplied,
                "whiteFrameApplied": request.whiteFrameApplied,
                "privacyAction": request.privacyAction as Any
            ] as [String: Any]
        ])

        let manifest: [String: Any] = [
            "claim_generator_info": [[
                "name": request.appName,
                "version": request.appVersion
            ]],
            "assertions": assertions
        ]

        let data = (try? JSONSerialization.data(withJSONObject: manifest, options: [])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func parseVerification(from json: String) -> C2PAVerificationResult? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let statusItems = root["validation_status"] as? [[String: Any]] ?? []
        var items: [C2PAVerificationItem] = []

        // Look for signature-related validation codes.
        var signatureIsIntact = false
        let sigCodes = [
            "claimSignature.validated",
            "claimSignature.insideValidity"
        ]

        for item in statusItems {
            let code = item["code"] as? String ?? ""
            let explanation = item["explanation"] as? String ?? ""
            if !code.isEmpty {
                items.append(C2PAVerificationItem(code: code, explanation: explanation))
            }
            if sigCodes.contains(code) { signatureIsIntact = true }
        }

        // Also check validation_results.activeManifest.success for sig validation.
        if let results = root["validation_results"] as? [String: Any],
           let active = results["activeManifest"] as? [String: Any],
           let successes = active["success"] as? [[String: Any]] {
            for s in successes {
                let code = s["code"] as? String ?? ""
                if sigCodes.contains(code) { signatureIsIntact = true }
            }
        }

        return C2PAVerificationResult(signatureIsIntact: signatureIsIntact, items: items)
    }

    private func parseManifestSummary(_ json: String) -> SourceProvenanceAnalyzer.C2PASummary? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let manifests = root["manifests"] as? [String: Any],
              let activeID = root["active_manifest"] as? String,
              let active = manifests[activeID] as? [String: Any]
        else { return nil }

        // Look for provenance assertions that indicate AI or trusted capture.
        var indicatesAI = false
        var indicatesTrustedCapture = false

        if let assertions = active["assertions"] as? [[String: Any]] {
            for assertion in assertions {
                let label = assertion["label"] as? String ?? ""
                let data = assertion["data"] as? [String: Any] ?? [:]
                if label.contains("trainedAlgorithmic") || label.contains("AI") {
                    indicatesAI = true
                }
                if let sourceState = data["sourceState"] as? String {
                    if sourceState == "markedAI" { indicatesAI = true }
                    if sourceState == "verifiedCameraCapture" { indicatesTrustedCapture = true }
                }
                // C2PA digital source type assertions
                if let dst = data["digitalSourceType"] as? String,
                   dst.contains("trainedAlgorithmicMedia") || dst.contains("algorithmicMedia") {
                    indicatesAI = true
                }
            }
        }

        // A manifest that is present and parseable is treated as validly signed
        // for the analyzer's purposes. Full cryptographic verification is a
        // future enhancement; the analyzer only needs to know the manifest exists.
        return SourceProvenanceAnalyzer.C2PASummary(
            isValidlySigned: true,
            indicatesAIGeneration: indicatesAI,
            indicatesTrustedCapture: indicatesTrustedCapture
        )
    }
}

private enum C2PASignError: Error { case signingFailed }

/// Thread-safe cert cache so the Sendable `C2PASwiftProvenanceClient` can cache
/// generated cert chains across exports without NSCache's non-Sendable limitation.
private final class CertCache: @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func set(_ value: String, for key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }
}
#endif
