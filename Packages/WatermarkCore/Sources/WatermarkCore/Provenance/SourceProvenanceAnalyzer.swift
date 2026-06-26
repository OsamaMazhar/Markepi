import ImageIO
import Foundation

public struct SourceProvenanceAnalyzer: Sendable {

    public struct C2PASummary: Sendable, Equatable {
        public let isValidlySigned: Bool
        public let indicatesAIGeneration: Bool
        public let indicatesTrustedCapture: Bool

        public init(isValidlySigned: Bool, indicatesAIGeneration: Bool, indicatesTrustedCapture: Bool) {
            self.isValidlySigned = isValidlySigned
            self.indicatesAIGeneration = indicatesAIGeneration
            self.indicatesTrustedCapture = indicatesTrustedCapture
        }
    }

    public init() {}

    private static let aiDigitalSourceTypes: Set<String> = [
        "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia",
        "http://cv.iptc.org/newscodes/digitalsourcetype/compositeWithTrainedAlgorithmicMedia",
        "http://cv.iptc.org/newscodes/digitalsourcetype/algorithmicMedia",
    ]

    private static let aiSoftwareHints: [String] = [
        "midjourney", "stable diffusion", "dall-e", "dall\u{00b7}e", "firefly"
    ]

    public func analyze(
        metadata: [String: Any],
        userDeclaration: UserSourceDeclaration = .none,
        c2paSummary: C2PASummary? = nil
    ) -> SourceProvenanceReport {
        var evidence: [ProvenanceEvidence] = []
        var warnings: [String] = []

        if let c2pa = c2paSummary, c2pa.isValidlySigned {
            evidence.append(.init(kind: .c2paManifest, source: "C2PA", strength: .strong,
                                  summary: "Signed Content Credentials present"))
            if c2pa.indicatesAIGeneration { return report(.markedAI, evidence, warnings, userDeclaration) }
            if c2pa.indicatesTrustedCapture { return report(.verifiedCameraCapture, evidence, warnings, userDeclaration) }
        }

        if let dst = digitalSourceType(in: metadata) {
            evidence.append(.init(kind: .iptcDigitalSourceType, source: "IPTC", strength: .moderate,
                                  summary: "Digital Source Type: \(dst)", rawValue: dst))
            if Self.aiDigitalSourceTypes.contains(dst) {
                return report(.markedAI, evidence, warnings, userDeclaration)
            }
        }

        if let (make, model) = cameraMakeModel(in: metadata) {
            evidence.append(.init(kind: .exifCameraMakeModel, source: "EXIF", strength: .weak,
                                  summary: "Camera: \(make) \(model)".trimmingCharacters(in: .whitespaces)))
        }

        if let sw = software(in: metadata),
           Self.aiSoftwareHints.contains(where: { sw.lowercased().contains($0) }) {
            evidence.append(.init(kind: .softwareTag, source: "Software", strength: .weak,
                                  summary: "AI-tool software marker: \(sw)", rawValue: sw))
            warnings.append("Software marker suggests AI tooling; not conclusive.")
            return report(.suspectedAI, evidence, warnings, userDeclaration)
        }

        if userDeclaration != .none {
            evidence.append(.init(kind: .userDeclaration, source: "User", strength: .weak,
                                  summary: "User declared source: \(userDeclaration.rawValue)",
                                  rawValue: userDeclaration.rawValue, isUserSupplied: true))
            return report(.userDeclared, evidence, warnings, userDeclaration)
        }

        return report(.unknown, evidence, warnings, userDeclaration)
    }

    private func report(_ s: ProvenanceState, _ e: [ProvenanceEvidence],
                        _ w: [String], _ d: UserSourceDeclaration) -> SourceProvenanceReport {
        SourceProvenanceReport(state: s, evidence: e, warnings: w, userDeclaration: d)
    }

    private func digitalSourceType(in m: [String: Any]) -> String? {
        let iptc = m[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
        return iptc?[kCGImagePropertyIPTCExtDigitalSourceType as String] as? String
            ?? iptc?["DigitalSourceType"] as? String
    }

    private func cameraMakeModel(in m: [String: Any]) -> (String, String)? {
        let tiff = m[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let make = tiff?[kCGImagePropertyTIFFMake as String] as? String
        let model = tiff?[kCGImagePropertyTIFFModel as String] as? String
        guard make != nil || model != nil else { return nil }
        return (make ?? "", model ?? "")
    }

    private func software(in m: [String: Any]) -> String? {
        let tiff = m[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        return tiff?[kCGImagePropertyTIFFSoftware as String] as? String
    }
}
