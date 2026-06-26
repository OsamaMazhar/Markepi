import Foundation

public enum ProvenanceState: String, Codable, Equatable, Sendable, CaseIterable {
    case verifiedCameraCapture
    case markedAI
    case userDeclared
    case unknown
    case suspectedAI

    public var displayLabel: String {
        switch self {
        case .verifiedCameraCapture: return "Verified source"
        case .markedAI:              return "AI-marked source"
        case .userDeclared:          return "User-declared"
        case .unknown:               return "Unknown source"
        case .suspectedAI:           return "Suspected AI"
        }
    }

    public var allowsVerifiedCameraClaim: Bool { self == .verifiedCameraCapture }

    public var allowsNoAIClaim: Bool { false }

    public var allowsRightsProtection: Bool { true }
}
