import Foundation

public struct ProvenanceEvidence: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case c2paManifest
        case iptcDigitalSourceType
        case exifCameraMakeModel
        case softwareTag
        case userDeclaration
        case detectorHint
    }

    public enum Strength: Int, Codable, Sendable, Comparable {
        case weak = 0
        case moderate = 1
        case strong = 2

        public static func < (a: Strength, b: Strength) -> Bool { a.rawValue < b.rawValue }
    }

    public let id: UUID
    public let kind: Kind
    public let source: String
    public let strength: Strength
    public let summary: String
    public let rawValue: String?
    public let isUserSupplied: Bool

    public init(id: UUID = UUID(), kind: Kind, source: String, strength: Strength,
                summary: String, rawValue: String? = nil, isUserSupplied: Bool = false) {
        self.id = id; self.kind = kind; self.source = source; self.strength = strength
        self.summary = summary; self.rawValue = rawValue; self.isUserSupplied = isUserSupplied
    }
}

public enum UserSourceDeclaration: String, Codable, Equatable, Sendable {
    case none, camera, ai, aiEdited, composite
}

public struct SourceProvenanceReport: Codable, Equatable, Sendable {
    public let state: ProvenanceState
    public let evidence: [ProvenanceEvidence]
    public let warnings: [String]
    public let userDeclaration: UserSourceDeclaration
    public let analyzedAt: Date

    public init(state: ProvenanceState, evidence: [ProvenanceEvidence],
                warnings: [String] = [], userDeclaration: UserSourceDeclaration = .none,
                analyzedAt: Date = Date()) {
        self.state = state; self.evidence = evidence; self.warnings = warnings
        self.userDeclaration = userDeclaration; self.analyzedAt = analyzedAt
    }

    public var allowsVerifiedCameraClaim: Bool { state.allowsVerifiedCameraClaim }
    public var allowsNoAIClaim: Bool { state.allowsNoAIClaim }
    public var allowsRightsProtection: Bool { state.allowsRightsProtection }
}
