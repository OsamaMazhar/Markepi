import CoreImage

/// Top-level configuration for a watermark processing operation.
///
/// Specifies which watermarks to apply, in what order (D-01: ordered layer stack),
/// optional white frame settings, and output format preferences.
///
/// Consumed by `WatermarkEngine.process(url:config:)` to build the filter graph.
public struct WatermarkConfiguration: Sendable, Codable {
    /// Default scale for a newly-added text layer — the font height as a fraction
    /// of the image height (see `WatermarkEngine`). ~4.5% reads as a tasteful
    /// signature; 10% rendered far too large.
    public static let defaultTextScale: CGFloat = 0.045

    /// PostScript name of the font new text layers start with. Pacifico is a
    /// friendly script face that suits a personal signature watermark.
    public static let defaultFontPostScriptName: String = "Pacifico-Regular"

    /// Ordered array of watermark layers composited from bottom to top (per D-01)
    public var watermarks: [WatermarkLayer]

    /// Padding between watermark and image edges, in points (default: 20)
    public var padding: CGFloat = 20

    /// Optional white frame configuration (full implementation in Plan 03)
    public var whiteFrame: WhiteFrameConfig?

    /// Optional retro date-stamp overlay (orange film-camera databack look).
    public var dateStamp: DateStampConfig?

    /// Output format preference
    public var outputFormat: OutputFormat

    /// Output quality for lossy formats (0.0–1.0). Default 1.0 (maximum quality).
    /// Maps to kCGImageDestinationLossyCompressionQuality. Ignored by lossless formats (PNG, TIFF).
    public var outputQuality: Float = 1.0

    // MARK: - Provenance & Authorship Protection (Plan 19-03)

    /// IPTC rights metadata the user wants sealed into exports (creator,
    /// copyright, credit, usage terms). Persisted so the Share Extension
    /// inherits it via App Group sync (D-16, AUTH-03).
    public var rightsMetadata: RightsMetadata = RightsMetadata()

    /// Privacy profile controlling metadata stripping on export (D-10, CTRL-04).
    /// Defaults to `.preserveAll` (today's behavior) — old configs decode to this.
    public var metadataPrivacyProfile: MetadataPrivacyProfile = .preserveAll

    /// Master switch for the Content Credentials / provenance feature. When
    /// false (default), exports are shared directly with no provenance receipt,
    /// signing, rights, or metadata changes — and the More panel hides all the
    /// detailed controls. When true, the full controls are shown and every
    /// export produces a provenance receipt.
    public var provenanceEnabled: Bool = false

    /// True to attach a C2PA Content Credentials manifest on export. Defaults
    /// to false — signing is user-initiated from the More section (D-25), never
    /// automatic. The actual Sign button sets this to true after the explainer
    /// popup is confirmed (D-27).
    public var includeC2PAManifest: Bool = false

    /// User-supplied source declaration (camera / AI / AI-edited / composite).
    /// Recorded as a declaration, NEVER as a verified claim (D-18).
    public var sourceDeclaration: UserSourceDeclaration = .none

    /// Invisible creator protection toggle (placeholder for Plan 19-04). The
    /// provider is not yet shipped, so the control is disabled in the UI.
    public var invisibleProtectionEnabled: Bool = false

    // MARK: CodingKeys

    enum CodingKeys: String, CodingKey {
        case watermarks, padding, whiteFrame, dateStamp, outputFormat, outputQuality
        case rightsMetadata, metadataPrivacyProfile, provenanceEnabled, includeC2PAManifest
        case sourceDeclaration, invisibleProtectionEnabled
    }

    /// Creates a watermark configuration.
    ///
    /// - Parameters:
    ///   - watermarks: Ordered watermark layers (bottom → top)
    ///   - whiteFrame: Optional white frame config (default: nil)
    ///   - outputFormat: Output format preference (default: .preserveSource)
    ///   - outputQuality: Output quality 0.0–1.0 (default: 1.0, max quality)
    public init(
        watermarks: [WatermarkLayer] = [],
        whiteFrame: WhiteFrameConfig? = nil,
        dateStamp: DateStampConfig? = nil,
        outputFormat: OutputFormat = .preserveSource,
        outputQuality: Float = 1.0
    ) {
        self.watermarks = watermarks
        self.whiteFrame = whiteFrame
        self.dateStamp = dateStamp
        self.outputFormat = outputFormat
        self.outputQuality = outputQuality
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.watermarks = try container.decode([WatermarkLayer].self, forKey: .watermarks)
        self.padding = try container.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 20
        self.whiteFrame = try container.decodeIfPresent(WhiteFrameConfig.self, forKey: .whiteFrame)
        self.dateStamp = try container.decodeIfPresent(DateStampConfig.self, forKey: .dateStamp)
        self.outputFormat = try container.decodeIfPresent(OutputFormat.self, forKey: .outputFormat) ?? .preserveSource
        self.outputQuality = try container.decodeIfPresent(Float.self, forKey: .outputQuality) ?? 1.0
        self.rightsMetadata = try container.decodeIfPresent(RightsMetadata.self, forKey: .rightsMetadata) ?? RightsMetadata()
        self.metadataPrivacyProfile = try container.decodeIfPresent(MetadataPrivacyProfile.self, forKey: .metadataPrivacyProfile) ?? .preserveAll
        self.provenanceEnabled = try container.decodeIfPresent(Bool.self, forKey: .provenanceEnabled) ?? false
        self.includeC2PAManifest = try container.decodeIfPresent(Bool.self, forKey: .includeC2PAManifest) ?? false
        self.sourceDeclaration = try container.decodeIfPresent(UserSourceDeclaration.self, forKey: .sourceDeclaration) ?? .none
        self.invisibleProtectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .invisibleProtectionEnabled) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(watermarks, forKey: .watermarks)
        try container.encode(padding, forKey: .padding)
        try container.encodeIfPresent(whiteFrame, forKey: .whiteFrame)
        try container.encodeIfPresent(dateStamp, forKey: .dateStamp)
        try container.encode(outputFormat, forKey: .outputFormat)
        try container.encode(outputQuality, forKey: .outputQuality)
        try container.encode(rightsMetadata, forKey: .rightsMetadata)
        try container.encode(metadataPrivacyProfile, forKey: .metadataPrivacyProfile)
        try container.encode(provenanceEnabled, forKey: .provenanceEnabled)
        try container.encode(includeC2PAManifest, forKey: .includeC2PAManifest)
        try container.encode(sourceDeclaration, forKey: .sourceDeclaration)
        try container.encode(invisibleProtectionEnabled, forKey: .invisibleProtectionEnabled)
    }
}

// MARK: - WatermarkLayer

/// Discriminated union representing a single watermark layer in the layer stack.
///
/// Each layer has a type (.text or .image), a position preset, a scale factor,
/// per-layer compositing opacity (0.0–1.0), and a visibility toggle.
/// Layers are composited in array order (index 0 = bottom, last index = top) per D-01.
public enum WatermarkLayer: Sendable {
    /// Text watermark with SF system font rendering
    case text(TextWatermarkInput, position: WatermarkPosition, scale: CGFloat, opacity: CGFloat, isVisible: Bool)

    /// Image/logo watermark (full implementation in Plan 02)
    case image(ImageWatermarkInput, position: WatermarkPosition, scale: CGFloat, opacity: CGFloat, isVisible: Bool)

    /// Signature watermark with PencilKit stroke data
    case signature(SignatureInput, position: WatermarkPosition, scale: CGFloat, opacity: CGFloat, isVisible: Bool)

    /// The position preset for this watermark layer
    public var position: WatermarkPosition {
        switch self {
        case .text(_, let position, _, _, _): return position
        case .image(_, let position, _, _, _): return position
        case .signature(_, let position, _, _, _): return position
        }
    }

    /// The scale factor relative to base image shorter dimension (0.01–0.90)
    public var scale: CGFloat {
        switch self {
        case .text(_, _, let scale, _, _): return scale
        case .image(_, _, let scale, _, _): return scale
        case .signature(_, _, let scale, _, _): return scale
        }
    }

    /// Per-layer compositing opacity (0.0–1.0). Default 1.0.
    /// Applied via CIFilter.colorMatrix alpha modulation at compositing time.
    /// Distinct from per-element opacity (TextWatermarkInput.opacity for text rendering,
    /// ImageWatermarkInput.opacity for PNG alpha).
    public var opacity: CGFloat {
        switch self {
        case .text(_, _, _, let opacity, _): return opacity
        case .image(_, _, _, let opacity, _): return opacity
        case .signature(_, _, _, let opacity, _): return opacity
        }
    }

    /// Per-layer visibility. False → layer is skipped in compositing.
    public var isVisible: Bool {
        switch self {
        case .text(_, _, _, _, let isVisible): return isVisible
        case .image(_, _, _, _, let isVisible): return isVisible
        case .signature(_, _, _, _, let isVisible): return isVisible
        }
    }
}

// MARK: - WatermarkLayer Parametric Copies

extension WatermarkLayer {
    /// Returns a copy of this layer with a new position, preserving every other
    /// parameter. Centralizes the otherwise-repeated case switch so callers
    /// (and the `WatermarkConfigurable` setters) cannot accidentally drop a field.
    public func withPosition(_ position: WatermarkPosition) -> WatermarkLayer {
        switch self {
        case .text(let i, _, let s, let o, let v): return .text(i, position: position, scale: s, opacity: o, isVisible: v)
        case .image(let i, _, let s, let o, let v): return .image(i, position: position, scale: s, opacity: o, isVisible: v)
        case .signature(let i, _, let s, let o, let v): return .signature(i, position: position, scale: s, opacity: o, isVisible: v)
        }
    }

    /// Returns a copy with a new scale (clamped 0.01–0.90), preserving all else.
    public func withScale(_ scale: CGFloat) -> WatermarkLayer {
        let clamped = min(max(scale, 0.01), 0.90)
        switch self {
        case .text(let i, let p, _, let o, let v): return .text(i, position: p, scale: clamped, opacity: o, isVisible: v)
        case .image(let i, let p, _, let o, let v): return .image(i, position: p, scale: clamped, opacity: o, isVisible: v)
        case .signature(let i, let p, _, let o, let v): return .signature(i, position: p, scale: clamped, opacity: o, isVisible: v)
        }
    }

    /// Returns a copy with a new per-layer opacity (clamped 0–1), preserving all else.
    public func withOpacity(_ opacity: CGFloat) -> WatermarkLayer {
        let clamped = min(max(opacity, 0), 1)
        switch self {
        case .text(let i, let p, let s, _, let v): return .text(i, position: p, scale: s, opacity: clamped, isVisible: v)
        case .image(let i, let p, let s, _, let v): return .image(i, position: p, scale: s, opacity: clamped, isVisible: v)
        case .signature(let i, let p, let s, _, let v): return .signature(i, position: p, scale: s, opacity: clamped, isVisible: v)
        }
    }

    /// Returns a copy with a new visibility flag, preserving all else.
    public func withVisibility(_ isVisible: Bool) -> WatermarkLayer {
        switch self {
        case .text(let i, let p, let s, let o, _): return .text(i, position: p, scale: s, opacity: o, isVisible: isVisible)
        case .image(let i, let p, let s, let o, _): return .image(i, position: p, scale: s, opacity: o, isVisible: isVisible)
        case .signature(let i, let p, let s, let o, _): return .signature(i, position: p, scale: s, opacity: o, isVisible: isVisible)
        }
    }
}

// MARK: - WatermarkLayer Codable

extension WatermarkLayer: Codable {
    enum CodingKeys: String, CodingKey {
        case type, textConfig, imageConfig, signatureConfig, position, scale, opacity, isVisible
    }

    enum LayerType: String, Codable {
        case text, image, signature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(LayerType.self, forKey: .type)
        let position = try container.decode(WatermarkPosition.self, forKey: .position)
        let scale = try container.decode(CGFloat.self, forKey: .scale)
        let opacity = try container.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1.0
        let isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true

        switch type {
        case .text:
            let config = try container.decode(TextWatermarkInput.self, forKey: .textConfig)
            self = .text(config, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        case .image:
            let config = try container.decode(ImageWatermarkInput.self, forKey: .imageConfig)
            self = .image(config, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        case .signature:
            let config = try container.decode(SignatureInput.self, forKey: .signatureConfig)
            self = .signature(config, position: position, scale: scale, opacity: opacity, isVisible: isVisible)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position, forKey: .position)
        try container.encode(scale, forKey: .scale)

        switch self {
        case .text(let config, _, _, let opacity, let isVisible):
            try container.encode(LayerType.text, forKey: .type)
            try container.encode(config, forKey: .textConfig)
            try container.encode(opacity, forKey: .opacity)
            try container.encode(isVisible, forKey: .isVisible)
        case .image(let config, _, _, let opacity, let isVisible):
            try container.encode(LayerType.image, forKey: .type)
            try container.encode(config, forKey: .imageConfig)
            try container.encode(opacity, forKey: .opacity)
            try container.encode(isVisible, forKey: .isVisible)
        case .signature(let config, _, _, let opacity, let isVisible):
            try container.encode(LayerType.signature, forKey: .type)
            try container.encode(config, forKey: .signatureConfig)
            try container.encode(opacity, forKey: .opacity)
            try container.encode(isVisible, forKey: .isVisible)
        }
    }
}

// MARK: - OutputFormat

/// Output image format preference.
///
/// `.preserveSource` (default per D-09) keeps the source format (HEIC→HEIC, JPEG→JPEG).
/// Explicit overrides allow forcing a specific format when needed.
public enum OutputFormat: Sendable, Codable {
    /// Match the source image format (default per D-09)
    case preserveSource

    /// Force HEIC output
    case heic

    /// Force JPEG output
    case jpeg

    /// Force PNG output
    case png

    /// Force TIFF output
    case tiff

    /// Returns the Core Graphics / UTType UTI string for this format,
    /// or nil for `.preserveSource` (which means "use the source UTI").
    public var uti: String? {
        switch self {
        case .preserveSource: return nil
        case .heic: return "public.heic"
        case .jpeg: return "public.jpeg"
        case .png: return "public.png"
        case .tiff: return "public.tiff"
        }
    }

    /// Returns true for lossless formats (PNG, TIFF) where quality slider should be disabled.
    public var isLossless: Bool {
        switch self {
        case .png, .tiff: return true
        default: return false
        }
    }

    // MARK: Codable (String raw value)

    enum RawValue: String, Codable {
        case preserveSource, heic, jpeg, png, tiff
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(RawValue.self)
        switch raw {
        case .preserveSource: self = .preserveSource
        case .heic: self = .heic
        case .jpeg: self = .jpeg
        case .png: self = .png
        case .tiff: self = .tiff
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .preserveSource: try container.encode(RawValue.preserveSource)
        case .heic: try container.encode(RawValue.heic)
        case .jpeg: try container.encode(RawValue.jpeg)
        case .png: try container.encode(RawValue.png)
        case .tiff: try container.encode(RawValue.tiff)
        }
    }
}
