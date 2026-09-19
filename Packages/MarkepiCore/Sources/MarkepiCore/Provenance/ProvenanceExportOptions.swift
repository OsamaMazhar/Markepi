import Foundation

/// Options a caller passes to opt INTO provenance work during export
/// (Plan 19-02 Task 6). nil ⇒ today's behavior — no provenance analysis,
/// no IPTC merge, no C2PA signing, no receipt.
///
/// The `c2paClient` is injected so tests and fallback builds can supply
/// `NoopC2PAProvenanceClient`; when c2pa-swift is linked, the default client is
/// the concrete `C2PASwiftProvenanceClient`.
public struct ProvenanceExportOptions: Sendable {
    /// IPTC rights metadata to merge into the output (AUTH-03).
    public var rights: RightsMetadata
    /// Privacy profile controlling metadata stripping (D-10).
    public var privacyProfile: MetadataPrivacyProfile
    /// True to attempt C2PA manifest signing (no-op when the client is Noop).
    public var includeC2PA: Bool
    /// User-supplied source declaration (recorded as a declaration, not verified).
    public var userDeclaration: UserSourceDeclaration
    /// App version string for the manifest claim generator.
    public var appVersion: String
    /// Injected C2PA client. Defaults to the real `C2PASwiftProvenanceClient`
    /// when c2pa-swift is available, otherwise `NoopC2PAProvenanceClient`.
    public var c2paClient: any C2PAProvenanceClient

    public init(
        rights: RightsMetadata,
        privacyProfile: MetadataPrivacyProfile,
        includeC2PA: Bool,
        userDeclaration: UserSourceDeclaration,
        appVersion: String,
        c2paClient: (any C2PAProvenanceClient)? = nil
    ) {
        self.rights = rights
        self.privacyProfile = privacyProfile
        self.includeC2PA = includeC2PA
        self.userDeclaration = userDeclaration
        self.appVersion = appVersion
        self.c2paClient = c2paClient ?? Self.defaultClient()
    }

    /// The production C2PA client for this build: the real
    /// `C2PASwiftProvenanceClient` when c2pa-swift is linked, otherwise the
    /// honest `NoopC2PAProvenanceClient`. Also used by the engine's
    /// source-credential preservation path, which must be able to sign even
    /// when the caller supplied no provenance options at all.
    public static func defaultClient() -> any C2PAProvenanceClient {
        #if canImport(C2PA)
        C2PASwiftProvenanceClient()
        #else
        NoopC2PAProvenanceClient()
        #endif
    }
}
