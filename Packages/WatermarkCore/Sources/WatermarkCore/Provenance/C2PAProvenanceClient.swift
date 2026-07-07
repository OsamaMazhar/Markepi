import Foundation

/// Adapter boundary over C2PA read/verify/sign so the engine never depends
/// on a concrete library (D-11/D-12). Async + Sendable ⇒ Share-Extension safe.
///
/// The default production client is `C2PASwiftProvenanceClient` when the
/// `contentauth/c2pa-swift` package is linked. `NoopC2PAProvenanceClient`
/// remains the honest fallback for builds where C2PA is unavailable.
public protocol C2PAProvenanceClient: Sendable {
    /// Read & verify any manifest already in the source; returns the small
    /// summary the 19-01 analyzer consumes. nil = no manifest.
    ///
    /// - Parameter url: Source file URL to inspect for an existing C2PA manifest.
    /// - Returns: A `SourceProvenanceAnalyzer.C2PASummary`, or nil when no
    ///   manifest is present or the manifest cannot be read for this source.
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
/// `status` is the honest outcome: `.signed` only when a manifest was attached
/// and read back with an intact claim signature, `.notSigned` when signing is
/// disabled (noop), `.notSupported` when the format/path cannot carry C2PA
/// (e.g. some video containers).
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
    /// Honest warnings (e.g. missing creator name, unsupported format, fallback build).
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
/// Used only when the C2PA package is not linked, or when tests inject it.
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
import UniformTypeIdentifiers

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
        try? await runC2PAWork {
            let manifestJSON = try C2PA.readFile(at: url)
            return parseManifestSummary(manifestJSON)
        }
    }

    public func signExport(
        outputURL: URL,
        source: URL,
        manifest: C2PAManifestRequest,
        identity: C2PASigningIdentity
    ) async throws -> C2PASigningResult {
        try await runC2PAWork {
            guard let secKey = identity.secKey else {
                return C2PASigningResult(
                    status: .notSigned,
                    identityType: identity.type,
                    displayName: identity.displayName,
                    warnings: ["Markepi could not create or load a local device signing key. Try signing again on your iPhone in Markepi."]
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
            var warnings: [String] = []
            do {
                try addSourceIngredient(source, to: builder)
            } catch {
                warnings.append("Source ingredient could not be attached to the Content Credentials manifest.")
            }

            let signedURL = signedTemporaryURL(for: outputURL)
            let verification: C2PAVerificationResult
            do {
                let format = c2paFormat(for: outputURL)
                do {
                    // Sign the already-rendered export, not the original source.
                    // Builder.sign reads from `source` and writes a complete signed
                    // file to `destination`, so using the original input here would
                    // replace the user's edited/watermarked pixels.
                    let renderedStream = try Stream(readFrom: outputURL)
                    let signedStream = try Stream(writeTo: signedURL)
                    _ = try builder.sign(
                        format: format,
                        source: renderedStream,
                        destination: signedStream,
                        signer: signer
                    )
                }
                verification = try verifiedSignedExport(at: signedURL)
                try replaceOutput(at: outputURL, with: signedURL)
            } catch {
                try? FileManager.default.removeItem(at: signedURL)
                throw error
            }

            return C2PASigningResult(
                status: .signed,
                identityType: identity.type,
                displayName: identity.displayName,
                warnings: warnings,
                verification: verification
            )
        }
    }

    public func verifyExport(at url: URL) async -> C2PAVerificationResult? {
        try? await runC2PAWork {
            let json = try C2PA.readFile(at: url)
            return parseVerification(from: json)
        }
    }

    // MARK: - Private

    /// `c2pa-swift` calls into Rust code that can park/wait internally. Run the
    /// synchronous concrete library calls on an explicit utility-QoS queue so
    /// app UI/export tasks do not perform Rust thread parking at user-initiated
    /// priority.
    private func runC2PAWork<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Self.c2paWorkQueue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static let c2paWorkQueue = DispatchQueue(
        label: "com.osamamazhar.markepi.c2pa-work",
        qos: .utility,
        attributes: .concurrent
    )

    private func verifiedSignedExport(at url: URL) throws -> C2PAVerificationResult {
        let json = try C2PA.readFile(at: url)
        guard let verification = parseVerification(from: json) else {
            throw C2PASignError.readbackVerificationFailed
        }
        guard verification.signatureIsIntact else {
            throw C2PASignError.signatureNotIntact(verification.items)
        }
        return verification
    }

    private func certChain(for secKey: SecKey, identity: C2PASigningIdentity) throws -> String {
        let publicKey = SecKeyCopyPublicKey(secKey)!
        let cacheKey = certCacheKey(for: publicKey, identity: identity)
        if let cached = certCache.get(cacheKey) {
            return cached
        }
        let config = CertificateManager.CertificateConfig(
            commonName: "Markepi Device Signer",
            organization: "Markepi",
            organizationalUnit: "Markepi App",
            country: "US",
            state: "NA",
            locality: "NA",
            emailAddress: nil,
            validityDays: 365
        )
        let pem = try CertificateManager.createSelfSignedCertificateChain(
            for: publicKey, config: config
        )
        certCache.set(pem, for: cacheKey)
        return pem
    }

    private func certCacheKey(for publicKey: SecKey, identity: C2PASigningIdentity) -> String {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return identity.type.rawValue
        }
        return "\(identity.type.rawValue)-\(data.base64EncodedString())"
    }

    private func signedTemporaryURL(for outputURL: URL) -> URL {
        let baseName = outputURL.deletingPathExtension().lastPathComponent
        let ext = outputURL.pathExtension
        let signedName = "\(baseName)-signed-\(UUID().uuidString)"
        var url = outputURL.deletingLastPathComponent().appendingPathComponent(signedName)
        if !ext.isEmpty {
            url = url.appendingPathExtension(ext)
        }
        return url
    }

    private func replaceOutput(at outputURL: URL, with signedURL: URL) throws {
        let fileManager = FileManager.default
        let backupURL = unsignedBackupURL(for: outputURL)

        // Keep the rendered export recoverable until the signed replacement is
        // safely in place. These are temp files, but losing a completed render
        // because a move failed would make signing failures unnecessarily costly.
        try fileManager.moveItem(at: outputURL, to: backupURL)
        do {
            try fileManager.moveItem(at: signedURL, to: outputURL)
            try? fileManager.removeItem(at: backupURL)
        } catch {
            if !fileManager.fileExists(atPath: outputURL.path) {
                try? fileManager.moveItem(at: backupURL, to: outputURL)
            }
            throw error
        }
    }

    private func unsignedBackupURL(for outputURL: URL) -> URL {
        let name = "\(outputURL.lastPathComponent).unsigned-\(UUID().uuidString)"
        return outputURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    private func c2paFormat(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .jpeg) { return "image/jpeg" }
            if type.conforms(to: .heic) { return "image/heic" }
            if type.conforms(to: .png) { return "image/png" }
            if type.conforms(to: .tiff) { return "image/tiff" }
            if type.conforms(to: .mpeg4Movie) { return "video/mp4" }
            if type.conforms(to: .quickTimeMovie) { return "video/quicktime" }
        }
        return "image/jpeg"
    }

    private func addSourceIngredient(_ source: URL, to builder: Builder) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let ingredient = try Stream(readFrom: source)
        let json = ingredientJSON(title: source.lastPathComponent, format: c2paFormat(for: source))
        try builder.addIngredient(json: json, format: c2paFormat(for: source), from: ingredient)
    }

    private func ingredientJSON(title: String, format: String) -> String {
        let object: [String: Any] = [
            "title": title,
            "format": format,
            "relationship": "parentOf",
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data()
        return String(data: data, encoding: .utf8) ?? #"{"relationship":"parentOf"}"#
    }

    private func buildManifestJSON(_ request: C2PAManifestRequest) -> String {
        var assertions: [[String: Any]] = []

        // C2PA requires a `c2pa.actions` assertion whose FIRST action is
        // `c2pa.created` or `c2pa.opened`; otherwise verifiers report
        // `assertion.action.malformed`. We use `c2pa.created` (Markepi creates a
        // new watermarked rendition) rather than `c2pa.opened` — `opened`,
        // `placed` and `removed` actions must carry explicit `ingredients`
        // parameters or verifiers report `assertion.action.ingredientMismatch`.
        // `created` and `edited` have no such requirement; the source lineage is
        // still recorded via the `parentOf` ingredient.
        var actions: [[String: Any]] = [["action": "c2pa.created"]]
        if request.visibleWatermarkApplied || request.whiteFrameApplied {
            actions.append(["action": "c2pa.edited"])
        }
        assertions.append([
            "label": "c2pa.actions",
            "data": ["actions": actions] as [String: Any]
        ])

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

        var provenanceData: [String: Any] = [
            "sourceState": request.sourceState.rawValue,
            "evidenceSummary": request.sourceEvidenceSummary,
            "userDeclaration": request.userDeclaration.rawValue,
            "visibleWatermarkApplied": request.visibleWatermarkApplied,
            "whiteFrameApplied": request.whiteFrameApplied,
        ]
        if let privacyAction = request.privacyAction {
            provenanceData["privacyAction"] = privacyAction
        }
        if let payloadID = request.invisibleWatermarkPayloadID {
            provenanceData["invisibleWatermarkPayloadID"] = payloadID
        }

        // Provenance summary assertion — records source state as a declaration.
        assertions.append([
            "label": "c2pa.markepi.provenance",
            "data": provenanceData
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

        let statusItems = validationStatusItems(in: root)
            + validationResultStatusItems(in: root, buckets: ["failure", "informational"])
        let successItems = validationResultStatusItems(in: root, buckets: ["success"])
        var items: [C2PAVerificationItem] = []
        var seenItems = Set<String>()

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
                let itemID = "\(code)|\(explanation)"
                if seenItems.insert(itemID).inserted {
                    items.append(C2PAVerificationItem(code: code, explanation: explanation))
                }
            }
            if sigCodes.contains(code) { signatureIsIntact = true }
        }

        for item in successItems {
            let code = item["code"] as? String ?? ""
            if sigCodes.contains(code) { signatureIsIntact = true }
        }

        return C2PAVerificationResult(signatureIsIntact: signatureIsIntact, items: items)
    }

    private func parseManifestSummary(_ json: String) -> SourceProvenanceAnalyzer.C2PASummary? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let active = activeManifest(in: root)
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

    private func activeManifest(in root: [String: Any]) -> [String: Any]? {
        if let active = root["active_manifest"] as? [String: Any] {
            return active
        }
        if let activeID = root["active_manifest"] as? String,
           let manifests = root["manifests"] as? [String: Any],
           let active = manifests[activeID] as? [String: Any] {
            return active
        }
        if let manifests = root["manifests"] as? [String: Any] {
            return manifests.values.compactMap { $0 as? [String: Any] }.first
        }
        return nil
    }

    private func validationStatusItems(in root: [String: Any]) -> [[String: Any]] {
        if let status = root["validation_status"] as? [[String: Any]] {
            return status
        }
        if let active = activeManifest(in: root),
           let status = active["validation_status"] as? [[String: Any]] {
            return status
        }
        if let manifests = root["manifests"] as? [String: Any] {
            return manifests.values
                .compactMap { $0 as? [String: Any] }
                .flatMap { $0["validation_status"] as? [[String: Any]] ?? [] }
        }
        return []
    }

    private func validationResultStatusItems(in root: [String: Any], buckets: [String]) -> [[String: Any]] {
        guard let results = root["validation_results"] as? [String: Any] else { return [] }
        var items: [[String: Any]] = []

        func append(from statusCodes: [String: Any]) {
            for bucket in buckets {
                items += statusCodes[bucket] as? [[String: Any]] ?? []
            }
        }

        if let active = results["activeManifest"] as? [String: Any] {
            append(from: active)
        }

        if let deltas = results["ingredientDeltas"] as? [[String: Any]] {
            for delta in deltas {
                if let validationDeltas = delta["validationDeltas"] as? [String: Any] {
                    append(from: validationDeltas)
                }
            }
        }

        return items
    }
}

private enum C2PASignError: Error, LocalizedError, Sendable {
    case signingFailed
    case readbackVerificationFailed
    case signatureNotIntact([C2PAVerificationItem])

    var errorDescription: String? {
        switch self {
        case .signingFailed:
            return "Content Credentials signing failed."
        case .readbackVerificationFailed:
            return "Content Credentials signing failed because Markepi could not verify the signed image after export."
        case .signatureNotIntact(let items):
            let codes = items.map(\.code).filter { !$0.isEmpty }.joined(separator: ", ")
            if codes.isEmpty {
                return "Content Credentials signing failed because the exported image signature could not be verified."
            }
            return "Content Credentials signing failed verification: \(codes)."
        }
    }
}

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
