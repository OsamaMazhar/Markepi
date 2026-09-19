import Foundation

/// Receipt describing the provenance outcome of an export (AUTH-02, VERIFY-03).
///
/// Carries the analyzed source provenance report and, when C2PA signing was
/// requested, the signing result. Built by `WatermarkEngine.process` when the
/// caller passes `ProvenanceExportOptions`; nil when no provenance work was
/// requested (today's default behavior).
///
/// `SourceProvenanceReport` is `Codable`, and `C2PASigningResult` is `Codable`,
/// so the receipt is serializable for the export-receipt UI (Plan 19-03).
public struct ExportReceipt: Codable, Equatable, Sendable {
    /// Analyzed source provenance (single source of truth from 19-01).
    public let report: SourceProvenanceReport
    /// C2PA signing result, nil when signing was not requested or not supported.
    public var signingResult: C2PASigningResult?
    /// Rights metadata written or requested for this export.
    public var rightsMetadata: RightsMetadata
    /// Privacy profile applied to this export.
    public var privacyProfile: MetadataPrivacyProfile
    /// Human-readable privacy actions taken during export.
    public var privacyActions: [String]
    /// Whether an invisible watermark payload was applied.
    public var invisibleWatermarkApplied: Bool

    public init(
        report: SourceProvenanceReport,
        signingResult: C2PASigningResult? = nil,
        rightsMetadata: RightsMetadata = RightsMetadata(),
        privacyProfile: MetadataPrivacyProfile = .preserveAll,
        privacyActions: [String] = [],
        invisibleWatermarkApplied: Bool = false
    ) {
        self.report = report
        self.signingResult = signingResult
        self.rightsMetadata = rightsMetadata
        self.privacyProfile = privacyProfile
        self.privacyActions = privacyActions
        self.invisibleWatermarkApplied = invisibleWatermarkApplied
    }
}
