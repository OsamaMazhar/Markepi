import CoreImage

/// A single metadata field that can be toggled on/off in the white-frame caption.
///
/// Each case maps to an `EXIFTokenParser` token so the caption is assembled by
/// substituting the selected fields against the source image's metadata. The
/// declaration order is the canonical render order: enabled fields are always
/// shown in this order regardless of the order the user ticked them.
public enum CaptionField: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Who made the camera. First, because a caption that names both reads
    /// maker-then-model, and this order is the render order.
    case maker
    case cameraModel
    case lens
    case focalLength
    case aperture
    case shutterSpeed
    case iso
    case date
    case time
    case dimensions
    case format
    case gps

    public var id: String { rawValue }

    /// The `EXIFTokenParser` token this field resolves to.
    public var token: String {
        switch self {
        case .maker:        return "{make}"
        case .cameraModel:  return "{camera_model}"
        case .lens:         return "{lens}"
        case .focalLength:  return "{focal_length}"
        case .aperture:     return "{aperture}"
        case .shutterSpeed: return "{shutter_speed}"
        case .iso:          return "{iso}"
        case .date:         return "{date}"
        case .time:         return "{time}"
        case .dimensions:   return "{dimensions}"
        case .format:       return "{format}"
        case .gps:          return "{gps}"
        }
    }

    /// Human-readable label shown next to the field's checkbox.
    public var displayName: String {
        switch self {
        case .maker:        return "Brand"
        case .cameraModel:  return "Camera / Device"
        case .lens:         return "Lens"
        case .focalLength:  return "Focal length"
        case .aperture:     return "Aperture"
        case .shutterSpeed: return "Shutter speed"
        case .iso:          return "ISO"
        case .date:         return "Date"
        case .time:         return "Time"
        case .dimensions:   return "Dimensions"
        case .format:       return "Format"
        case .gps:          return "Location"
        }
    }
}

/// The visual style of the frame: what shape the mat takes and how the caption
/// is laid out on it.
///
/// `classic` is the original look — a uniform border with one centred caption
/// line. `gallery` is the two-column caption bar: device and date on the left,
/// a brand mark and the photographer's details on the right. `print` lifts the
/// photo off a plain mat with a drop shadow and credits the device above the
/// shooting details. `banner` drops the mat entirely and sets a full-bleed
/// photo over a caption bar.
///
/// Deliberately a closed enum rather than a registry: every style-dependent
/// `switch` in the renderer is exhaustive, so the compiler is what stops a new
/// style from being half-wired. That check is worth more than open-ended
/// extensibility nobody has asked for.
public enum FrameStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case classic
    case gallery
    case `print`
    case banner

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .gallery: return "Gallery"
        case .print: return "Print"
        case .banner: return "Banner"
        }
    }

    public var summary: String {
        switch self {
        case .classic: return "An even border with one centred line of text"
        case .gallery: return "A gallery mat with device details and a brand mark"
        case .print: return "The photo lifted off the mat by a soft shadow"
        case .banner: return "A full-width photo over a caption bar"
        }
    }

    /// Whether this style lays its caption out as `gallery` does — two columns
    /// with a brand mark between them.
    ///
    /// Asked rather than compared against a style name, so the caption,
    /// geometry and mark decisions keep working if another style ever adopts
    /// the same bar.
    var usesGalleryCaption: Bool { self == .gallery }

    /// Whether this style offers the graduated-mat choice.
    ///
    /// Only `gallery`. It began as two styles — one graduated, one flat — but
    /// they differed in nothing else, so the flat one is a switch on this one
    /// rather than a second entry in the picker saying the same thing twice.
    var offersGradient: Bool { self == .gallery }

    /// Whether this style casts a drop shadow behind the photo.
    var castsShadow: Bool { self == .print }

    /// Whether this style lets the user write their own text around the
    /// device credit.
    ///
    /// `print` does. Its credit line is fixed wording — "Shot on" plus the
    /// model — so the way to sign a print is to wrap that line rather than to
    /// replace it; the other styles either have one line only or already give
    /// the user slots of their own to type into.
    var offersCreditText: Bool { self == .print }

    /// Whether this style draws the maker's brand mark in its caption.
    ///
    /// `gallery` sets it between its two columns; `banner` sets it at the far
    /// left of the bar. Asked here rather than at each mark decision so the two
    /// cannot drift.
    var drawsBrandMark: Bool { self == .gallery || self == .banner }

    /// Whether this style surrounds the photo with a mat at all.
    ///
    /// `banner` does not: the photo runs to three edges and the caption sits in
    /// a bar beneath it, which is the whole point of the look.
    var hasSideMat: Bool { self != .banner }

    /// Whether this style offers the keyline.
    ///
    /// `print` does not. The keyline's job is to separate a pale photo edge
    /// from a pale mat, and the shadow already does that — drawn together they
    /// fight, and a heavy black rule around a lifted print looks like a
    /// mistake rather than a choice.
    ///
    /// `banner` does not either, for a plainer reason: it has no mat on three
    /// sides, so there is nowhere to stroke a rule that would not either fall
    /// off the canvas or sit on the photograph.
    var offersKeyline: Bool { self != .print && self != .banner }

    /// Decodes leniently: a style written by a newer build falls back to
    /// `classic` rather than failing the whole config, so a template can move
    /// backwards between versions.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FrameStyle(rawValue: raw) ?? .classic
    }
}

/// What one line of the `gallery` caption says.
///
/// A slot is either a metadata field picked from `CaptionField`, free text the
/// user typed, or nothing. Free text goes through `EXIFTokenParser`, so
/// `"{lens} {focal_length}"` works there too — which is how a single line can
/// carry several metadata values, as the reference layout's lens line does.
public enum CaptionSlot: Sendable, Codable, Equatable {
    case field(CaptionField)
    case text(String)
    case empty

    /// True when this slot can never produce text, regardless of metadata.
    public var isEmpty: Bool {
        switch self {
        case .empty: return true
        case .text(let t): return t.trimmingCharacters(in: .whitespaces).isEmpty
        case .field: return false
        }
    }

    // MARK: Codable

    // Encoded as one tagged string rather than a nested object, so a slot
    // round-trips through a single value and stays readable in a saved template.
    private static let fieldPrefix = "field:"
    private static let textPrefix = "text:"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw.isEmpty {
            self = .empty
        } else if raw.hasPrefix(Self.fieldPrefix) {
            let name = String(raw.dropFirst(Self.fieldPrefix.count))
            // An unknown field name means a newer build wrote it; drop the slot
            // rather than failing the whole config.
            self = CaptionField(rawValue: name).map { .field($0) } ?? .empty
        } else if raw.hasPrefix(Self.textPrefix) {
            self = .text(String(raw.dropFirst(Self.textPrefix.count)))
        } else {
            // Untagged legacy value: treat it as what the user typed.
            self = .text(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .empty: try container.encode("")
        case .field(let f): try container.encode(Self.fieldPrefix + f.rawValue)
        case .text(let t): try container.encode(Self.textPrefix + t)
        }
    }
}

/// Where `print` casts its shadow.
///
/// Two looks from one drawing step: a shadow offset downwards reads as a print
/// resting on a surface and lit from above, while an unoffset shadow on every
/// side reads as one floating parallel to it. Only `print` uses this.
public enum FrameShadow: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Offset downwards, so the photo sits on the mat.
    case bottom
    /// Even on all four sides, so the photo floats above it.
    case all

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bottom: return "Bottom"
        case .all: return "All sides"
        }
    }

    /// Decodes leniently, like `FrameStyle`: a value written by a newer build
    /// falls back rather than failing the whole config.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FrameShadow(rawValue: raw) ?? .bottom
    }
}

/// Whether the brand mark is drawn in colour or as a single tone.
///
/// Which single tone — the dark or the light rendition — is not a user choice:
/// the renderer picks whichever contrasts with the mat.
public enum LogoVariant: String, Codable, CaseIterable, Sendable, Identifiable {
    case color
    case monochrome

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .color: return "Colour"
        case .monochrome: return "Monochrome"
        }
    }
}

/// Configuration for the white frame border overlay.
///
/// The white frame is a uniform 4-sided border with proportional width
/// (3-5% of shorter image dimension per D-05) and an optional caption rendered
/// on the bottom portion of the frame.
///
/// The caption is assembled from `captionPrefix` (free text the user types)
/// followed by the metadata fields the user has ticked in `captionFields`
/// (in canonical `CaptionField.allCases` order). `customAttributionText`
/// remains as a legacy/advanced override: when non-nil it takes precedence and
/// is rendered verbatim (after `{token}` substitution).
///
/// Consumed by `WhiteFrameRenderer` for Core Graphics → Core Image rendering
/// and by `WatermarkEngine.buildFilterGraph` to composite the frame below
/// all watermark layers.
public struct WhiteFrameConfig: Sendable, Codable {
    /// Whether the white frame overlay is enabled
    public var isEnabled: Bool

    /// Master switch for the bottom-frame caption. When false, no text is
    /// rendered regardless of `captionPrefix`/`captionFields`.
    /// Default: true
    public var metadataTextEnabled: Bool

    /// Free-text prefix shown before the selected metadata fields, e.g.
    /// "Shot on". May be empty. `{token}` patterns are substituted.
    /// Default: "" (no prefix)
    public var captionPrefix: String

    /// Metadata fields to include in the caption, after `captionPrefix`.
    /// Rendered in canonical `CaptionField.allCases` order joined by " · ".
    /// Default: camera + shooting details.
    public var captionFields: [CaptionField]

    /// Legacy/advanced override. When non-nil, this text is rendered verbatim
    /// (after `{token}` substitution) instead of the prefix + fields caption.
    /// The current UI never sets this; it exists for backward compatibility
    /// with older saved templates.
    /// Default: nil
    public var customAttributionText: String?

    /// Text color for the metadata text rendered on the white frame.
    /// Default: dark gray (CGColor(gray: 0.333, alpha: 1.0))
    public var textColor: CGColor

    /// Which frame look to render. Default: `.gallery` — the mat with the
    /// device, date, brand mark and shooting details.
    ///
    /// A template saved before styles existed still decodes to `.classic`: it
    /// was authored against that look, so changing it would silently restyle
    /// someone's saved work. Only new frames get the gallery default.
    public var style: FrameStyle

    /// Whether the maker's brand mark is drawn in the caption band.
    ///
    /// The mark is chosen from the photo's own metadata, never picked by the
    /// user — but not everyone wants a manufacturer's logo on their picture,
    /// so it can be turned off. Off, the caption keeps its two columns and
    /// the divider goes with the mark.
    public var logoEnabled: Bool

    /// Resolution the millimetre sizes are converted against, in pixels per
    /// inch. `nil` means automatic: believe the photo's own resolution when it
    /// looks like a real print measurement, else 300.
    ///
    /// Set it and every physical size follows — the mat, the caption, the mark
    /// and the print size shown in More all key off this one number, so
    /// raising it makes the same millimetres land on more pixels.
    public var outputDPI: CGFloat?

    /// Mat thickness in millimetres — every style measures its border this way.
    ///
    /// A physical size rather than a proportion: 8mm is 8mm on paper whatever
    /// the photo's pixel dimensions, so the same settings print the same frame
    /// from a 12MP phone shot and a 60MP raw. Classic used to size its border
    /// as a percentage of the photo instead, which meant the printed border
    /// changed with the camera.
    ///
    /// Converted to pixels against the photo's own resolution; see
    /// `FrameGeometry.resolveDPI`.
    ///
    /// Changing it carries the caption and the mark with it. A size the user
    /// set is scaled by the same factor rather than left alone: they asked for
    /// the text to grow with the frame, and a number chosen for a narrow mat
    /// is a number for *that* mat. Setting a size again afterwards is what
    /// re-fixes the proportion.
    public var borderMillimetres: CGFloat {
        get { storedBorderMillimetres }
        set {
            let clamped = Self.clamped(newValue, to: 50)
            let previous = storedBorderMillimetres
            storedBorderMillimetres = clamped
            guard previous > 0, clamped != previous else { return }
            let factor = clamped / previous
            captionMillimetresOverride = captionMillimetresOverride
                .map { Self.clamped($0 * factor, to: 20) }
            logoMillimetresOverride = logoMillimetresOverride
                .map { Self.clamped($0 * factor, to: 30) }
        }
    }

    private var storedBorderMillimetres: CGFloat = FrameMetrics.defaultBorderMillimetres

    /// The caption size a new frame of this style starts at.
    public static func defaultCaptionMillimetres(for style: FrameStyle) -> CGFloat {
        switch style {
        case .classic: return FrameMetrics.defaultClassicCaptionMillimetres
        case .print: return FrameMetrics.defaultPrintCaptionMillimetres
        // Banner's bar is proportioned like gallery's, so its text is too.
        case .gallery, .banner: return FrameMetrics.defaultCaptionMillimetres
        }
    }

    /// Caption text size in millimetres — every style measures its text this
    /// way.
    ///
    /// Physical like the border it sits in. Sized as a proportion of the photo
    /// instead, a large photo would grow text that a millimetre border could
    /// not hold — the two units would fight.
    ///
    /// Follows the mat until the user sets it. Every default size here is
    /// already stated as a ratio of the default border (`captionToBorder`,
    /// `markToBorder`), so widening the mat simply keeps that ratio: text that
    /// stayed put while the frame around it grew read as a frame with the
    /// wrong caption in it. Once the user picks a size it is theirs, and it
    /// stops following.
    public var captionTextMillimetres: CGFloat {
        get { captionMillimetresOverride ?? Self.clamped(
            Self.defaultCaptionMillimetres(for: style) * borderScale, to: 20) }
        set { captionMillimetresOverride = Self.clamped(newValue, to: 20) }
    }

    /// The caption size the user set, or nil while it follows the mat.
    public private(set) var captionMillimetresOverride: CGFloat?

    /// How far the mat has been taken from the thickness every default size
    /// was measured against.
    private var borderScale: CGFloat { borderMillimetres / FrameMetrics.defaultBorderMillimetres }

    private static func clamped(_ millimetres: CGFloat, to limit: CGFloat) -> CGFloat {
        min(limit, max(0.5, millimetres))
    }

    /// Brand mark height in millimetres, used by `gallery` and `banner`.
    ///
    /// Height, not width: these marks are mostly wordmarks whose aspect ratios
    /// run from about 10:1 to taller-than-wide, so a width-based size would
    /// make a wordmark microscopic and a square glyph enormous.
    ///
    /// Follows the mat on the same terms as `captionTextMillimetres`: it
    /// shares the caption's band, and a mark left at its old height beside
    /// grown text is the misalignment that rule exists to prevent.
    public var logoHeightMillimetres: CGFloat {
        get { logoMillimetresOverride ?? Self.clamped(
            FrameMetrics.defaultMarkMillimetres * borderScale, to: 30) }
        set { logoMillimetresOverride = Self.clamped(newValue, to: 30) }
    }

    /// The mark height the user set, or nil while it follows the mat.
    public private(set) var logoMillimetresOverride: CGFloat?

    /// Thin black stroke between the photo and the mat. Applies to every
    /// style, not just `gallery`. Default: true — the reference layout has
    /// one, and it is what separates a light photo edge from a light mat.
    public var keylineEnabled: Bool

    /// Colour or monochrome for the brand mark. The brand itself is never
    /// configured — it is resolved from the photo's metadata.
    /// Default: `.color`
    public var logoVariant: LogoVariant

    /// Whether `gallery`'s mat grades from light at the top to darker at the
    /// bottom, or is one flat white. Unread by every other style.
    ///
    /// On, the shading stops a wide pale border reading as dead space and
    /// seats the caption on a firmer ground. Off, the mat is the same plain
    /// white every other style uses.
    ///
    /// Default: false. The reference layout this style was measured from is
    /// graduated, but a white mat is what a frame is expected to be, and the
    /// gradient reads as a choice rather than as the starting point.
    public var gradientEnabled: Bool

    /// The user's own text before `print`'s device credit — a photographer's
    /// name, usually. Empty means nothing is added, like every other caption
    /// part. Unread by the other styles.
    ///
    /// On the credit line rather than a line of its own: a third centred line
    /// made the block read as three rows of equipment data, where a signature
    /// belongs beside the credit it signs.
    ///
    /// Distinct from `customAttributionText`, which replaces `classic`'s whole
    /// caption; this is added to `print`'s rather than replacing anything.
    /// `{token}` patterns are substituted, so "© {date}" works here too.
    public var creditPrefixText: String

    /// The user's own text after `print`'s device credit. Same rules as
    /// `creditPrefixText`; both may be set, either alone, or neither.
    public var creditSuffixText: String

    /// Where `print` casts its shadow. Unread by every other style.
    ///
    /// Its depth is not configured: like the keyline, it is derived from the
    /// mat so it stays in proportion at any border setting or resolution.
    /// Default: `.bottom`
    public var shadow: FrameShadow

    // The four `gallery` caption lines. Unused by `classic`, which renders the
    // single centred caption built from `captionPrefix` + `captionFields`.

    /// Upper-left caption line, drawn bold and dark. Default: camera model.
    public var leftPrimary: CaptionSlot

    /// Lower-left caption line, drawn lighter. Default: capture date.
    public var leftSecondary: CaptionSlot

    /// Upper-right caption line, drawn bold and dark. Default: empty free
    /// text — this is where the photographer types their handle.
    public var rightPrimary: CaptionSlot

    /// Lower-right caption line, drawn lighter. Default: the lens, whose EXIF
    /// string already carries focal length and aperture — composing it with
    /// those fields as well would print both twice.
    public var rightSecondary: CaptionSlot

    /// The default set of caption fields: camera, the common shooting details,
    /// and where the photo was taken.
    ///
    /// Location is included because it is the one field nobody thinks to go
    /// looking for — it resolves to a country name and its flag, and a caption
    /// that shows it reads as a record of a trip rather than a readout from a
    /// camera. A photo with no GPS simply drops it, like any other field.
    /// The date is here and the pixel dimensions are not: when a photo was
    /// taken is part of what a caption is for, and how many pixels wide it is
    /// is a fact about the file. The date costs nothing on a photo that has
    /// its exposure — it stands in for the readings only when there are none.
    public static let defaultCaptionFields: [CaptionField] = [
        .maker, .cameraModel, .focalLength, .aperture, .shutterSpeed, .iso, .date, .time, .format, .gps,
    ]

    /// The `gallery` caption defaults: the device heads the left column, and
    /// every other line is left for the Include list to fill.
    ///
    /// Pinning entries here fought the list. A date pinned to a line showed
    /// even when the exposure it was meant to stand in for was present, and a
    /// place pinned to the right sat away from the device it belongs beside.
    /// Unpinned, each entry lands in its own column by subject and obeys every
    /// rule the other styles obey — and the four pickers become what they read
    /// as: a way to override that, not the only way to say anything.
    public static let defaultLeftPrimary: CaptionSlot = .field(.cameraModel)
    public static let defaultLeftSecondary: CaptionSlot = .empty
    public static let defaultRightPrimary: CaptionSlot = .empty
    public static let defaultRightSecondary: CaptionSlot = .empty

    /// Creates a white frame configuration.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether to apply the white frame (default: false)
    ///   - metadataTextEnabled: Whether to render the caption (default: true)
    ///   - captionPrefix: Free text shown before the fields (default: "")
    ///   - captionFields: Metadata fields to include (default: camera + shooting details)
    ///   - customAttributionText: Legacy verbatim override, nil = use prefix+fields (default: nil)
    ///   - textColor: CGColor for the metadata text (nil = per-style default:
    ///     black on a gallery mat, dark grey on a classic one)

    public init(
        isEnabled: Bool = false,
        metadataTextEnabled: Bool = true,
        captionPrefix: String = "",
        captionFields: [CaptionField] = WhiteFrameConfig.defaultCaptionFields,
        customAttributionText: String? = nil,
        textColor: CGColor? = nil,
        style: FrameStyle = .gallery,
        borderMillimetres: CGFloat = FrameMetrics.defaultBorderMillimetres,
        captionTextMillimetres: CGFloat? = nil,
        logoHeightMillimetres: CGFloat? = nil,
        keylineEnabled: Bool = true,
        logoEnabled: Bool = true,
        outputDPI: CGFloat? = nil,
        logoVariant: LogoVariant = .color,
        gradientEnabled: Bool = false,
        shadow: FrameShadow = .bottom,
        creditPrefixText: String = "",
        creditSuffixText: String = "",
        leftPrimary: CaptionSlot = WhiteFrameConfig.defaultLeftPrimary,
        leftSecondary: CaptionSlot = WhiteFrameConfig.defaultLeftSecondary,
        rightPrimary: CaptionSlot = WhiteFrameConfig.defaultRightPrimary,
        rightSecondary: CaptionSlot = WhiteFrameConfig.defaultRightSecondary
    ) {
        self.isEnabled = isEnabled
        // Clamp to 0.03–0.05 per D-05 (warning-level tolerance, not a throw)
        self.metadataTextEnabled = metadataTextEnabled
        self.captionPrefix = captionPrefix
        self.captionFields = captionFields
        self.customAttributionText = customAttributionText
        // A caption that sits in a band of its own is black in both
        // references, and its secondary line is derived from it — a grey
        // primary made the whole block read washed out and, at a glance,
        // unbold. A caption tucked into a border takes the softer grey, where
        // black would shout.
        self.textColor = textColor ?? (style == .gallery || style == .banner
            ? CGColor(gray: 0.0, alpha: 1.0)
            : CGColor(gray: 0.333, alpha: 1.0))
        self.style = style
        // A hairline mat is a rendering bug waiting to happen, and nobody
        // frames a print with a 10cm border; clamp rather than throw.
        self.storedBorderMillimetres = Self.clamped(borderMillimetres, to: 50)
        // Nil means "follow the mat"; an explicit size is always taken as
        // given, and stops following.
        self.captionMillimetresOverride = captionTextMillimetres.map { Self.clamped($0, to: 20) }
        self.logoMillimetresOverride = logoHeightMillimetres.map { Self.clamped($0, to: 30) }
        self.keylineEnabled = keylineEnabled
        self.logoEnabled = logoEnabled
        // A print is not made below ~36 DPI and no consumer pipeline needs
        // above 2400; clamp rather than let a stray value blow up the canvas.
        self.outputDPI = outputDPI.map { min(2400, max(36, $0)) }
        self.logoVariant = logoVariant
        self.gradientEnabled = gradientEnabled
        self.shadow = shadow
        self.creditPrefixText = creditPrefixText
        self.creditSuffixText = creditSuffixText
        self.leftPrimary = leftPrimary
        self.leftSecondary = leftSecondary
        self.rightPrimary = rightPrimary
        self.rightSecondary = rightSecondary
    }

    // MARK: - Codable (CGColor)

    enum CodingKeys: String, CodingKey {
        case isEnabled, metadataTextEnabled
        case captionPrefix, captionFields
        case customAttributionText, textColorRGBA
        case style, borderMillimetres, captionTextMillimetres, logoHeightMillimetres
        case keylineEnabled, logoVariant, outputDPI, logoEnabled, shadow, gradientEnabled
        case captionMillimetresManual, logoMillimetresManual
        case creditPrefixText, creditSuffixText
        case leftPrimary, leftSecondary, rightPrimary, rightSecondary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        metadataTextEnabled = try container.decode(Bool.self, forKey: .metadataTextEnabled)
        // New fields are optional so older saved configs keep decoding: absent
        // captionFields fall back to the default shooting-details set, matching
        // the prior auto-caption behavior.
        captionPrefix = try container.decodeIfPresent(String.self, forKey: .captionPrefix) ?? ""
        captionFields = try container.decodeIfPresent([CaptionField].self, forKey: .captionFields)
            ?? WhiteFrameConfig.defaultCaptionFields
        customAttributionText = try container.decodeIfPresent(String.self, forKey: .customAttributionText)
        let rgba = try container.decode([CGFloat].self, forKey: .textColorRGBA)
        guard rgba.count == 4,
              let cgColor = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    components: rgba) else {
            throw DecodingError.dataCorruptedError(forKey: .textColorRGBA, in: container,
                debugDescription: "Invalid RGBA components for CGColor")
        }
        textColor = cgColor
        // All new as of frame styles. Absent means a template written before
        // styles existed: it gets the classic border, no keyline, and the
        // reference gallery defaults it will only use if switched to gallery.
        style = try container.decodeIfPresent(FrameStyle.self, forKey: .style) ?? .classic
        storedBorderMillimetres = Self.clamped(
            try container.decodeIfPresent(CGFloat.self, forKey: .borderMillimetres)
                ?? FrameMetrics.defaultBorderMillimetres, to: 50)
        // A template written before these followed the mat always names a
        // size, so reading every one as hand-set would freeze it there. When
        // the flag is absent, a size still equal to the style's default means
        // nobody ever touched it — which is exactly what it says.
        func size(_ key: CodingKeys, manual manualKey: CodingKeys,
                  default fallback: CGFloat, limit: CGFloat) throws -> CGFloat? {
            guard let stored = try container.decodeIfPresent(CGFloat.self, forKey: key) else { return nil }
            let manual = try container.decodeIfPresent(Bool.self, forKey: manualKey)
                ?? (abs(stored - fallback) > 0.005)
            return manual ? Self.clamped(stored, to: limit) : nil
        }
        captionMillimetresOverride = try size(
            .captionTextMillimetres, manual: .captionMillimetresManual,
            default: Self.defaultCaptionMillimetres(for: style), limit: 20)
        logoMillimetresOverride = try size(
            .logoHeightMillimetres, manual: .logoMillimetresManual,
            default: FrameMetrics.defaultMarkMillimetres, limit: 30)
        keylineEnabled = try container.decodeIfPresent(Bool.self, forKey: .keylineEnabled) ?? false
        logoVariant = try container.decodeIfPresent(LogoVariant.self, forKey: .logoVariant) ?? .color
        shadow = try container.decodeIfPresent(FrameShadow.self, forKey: .shadow) ?? .bottom
        gradientEnabled = try container.decodeIfPresent(Bool.self, forKey: .gradientEnabled) ?? true
        creditPrefixText = try container.decodeIfPresent(String.self, forKey: .creditPrefixText) ?? ""
        creditSuffixText = try container.decodeIfPresent(String.self, forKey: .creditSuffixText) ?? ""
        outputDPI = try container.decodeIfPresent(CGFloat.self, forKey: .outputDPI)
            .map { min(2400, max(36, $0)) }
        logoEnabled = try container.decodeIfPresent(Bool.self, forKey: .logoEnabled) ?? true
        leftPrimary = try container.decodeIfPresent(CaptionSlot.self, forKey: .leftPrimary)
            ?? WhiteFrameConfig.defaultLeftPrimary
        leftSecondary = try container.decodeIfPresent(CaptionSlot.self, forKey: .leftSecondary)
            ?? WhiteFrameConfig.defaultLeftSecondary
        rightPrimary = try container.decodeIfPresent(CaptionSlot.self, forKey: .rightPrimary)
            ?? WhiteFrameConfig.defaultRightPrimary
        rightSecondary = try container.decodeIfPresent(CaptionSlot.self, forKey: .rightSecondary)
            ?? WhiteFrameConfig.defaultRightSecondary
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(metadataTextEnabled, forKey: .metadataTextEnabled)
        try container.encode(captionPrefix, forKey: .captionPrefix)
        try container.encode(captionFields, forKey: .captionFields)
        try container.encodeIfPresent(customAttributionText, forKey: .customAttributionText)
        // Convert first: `CGColor(gray:alpha:)` has two components, so reading
        // `.components` straight off a grey colour fell through to the 0.333
        // fallback and silently rewrote the caption tone on every save.
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let components = textColor.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components
            ?? textColor.components
            ?? [0.333, 0.333, 0.333, 1.0]
        let rgba: [CGFloat] = components.count >= 4
            ? [components[0], components[1], components[2], components[3]]
            : [0.333, 0.333, 0.333, 1.0]
        try container.encode(rgba, forKey: .textColorRGBA)
        try container.encodeIfPresent(outputDPI, forKey: .outputDPI)
        try container.encode(logoEnabled, forKey: .logoEnabled)
        try container.encode(style, forKey: .style)
        try container.encode(borderMillimetres, forKey: .borderMillimetres)
        // The effective size under the old key, so a build that predates this
        // renders the same frame, plus the flag that says whose number it is.
        try container.encode(captionTextMillimetres, forKey: .captionTextMillimetres)
        try container.encode(captionMillimetresOverride != nil, forKey: .captionMillimetresManual)
        try container.encode(logoMillimetresOverride != nil, forKey: .logoMillimetresManual)
        try container.encode(logoHeightMillimetres, forKey: .logoHeightMillimetres)
        try container.encode(keylineEnabled, forKey: .keylineEnabled)
        try container.encode(logoVariant, forKey: .logoVariant)
        try container.encode(shadow, forKey: .shadow)
        try container.encode(gradientEnabled, forKey: .gradientEnabled)
        try container.encode(creditPrefixText, forKey: .creditPrefixText)
        try container.encode(creditSuffixText, forKey: .creditSuffixText)
        try container.encode(leftPrimary, forKey: .leftPrimary)
        try container.encode(leftSecondary, forKey: .leftSecondary)
        try container.encode(rightPrimary, forKey: .rightPrimary)
        try container.encode(rightSecondary, forKey: .rightSecondary)
    }
}

// MARK: - Preview freshness

extension WhiteFrameConfig {

    /// Every render-affecting field of this frame, as one compact string.
    ///
    /// The live preview's `.task(id:)` re-runs only when its identifier
    /// changes, so a field missing from here renders a stale preview — the
    /// known failure mode for this feature. It lives on the config rather than
    /// in a view model because there are two view models (the app's and the
    /// share extension's) and only one of them used to spell the frame out:
    /// the extension keyed on `isEnabled` alone, so every frame control in it
    /// left the preview untouched. One key, both callers, no drift.
    public var previewKey: String {
        "wf:\(isEnabled ? 1 : 0)"
        + "|mt:\(metadataTextEnabled ? 1 : 0)|at:\(customAttributionText ?? "auto")"
        + "|cpfx:\(captionPrefix)|cf:\(captionFields.map(\.rawValue).joined(separator: ","))"
        + "|tc:\(Self.colorKey(textColor))"
        + "|st:\(style.rawValue)|kl:\(keylineEnabled ? 1 : 0)|lv:\(logoVariant.rawValue)"
        + "|sh:\(shadow.rawValue)|gr:\(gradientEnabled ? 1 : 0)"
        + "|cpre:\(creditPrefixText)|csuf:\(creditSuffixText)"
        + "|bmm:\(String(format: "%.2f", borderMillimetres))"
        + "|cmm:\(String(format: "%.2f", captionTextMillimetres))"
        + "|lmm:\(String(format: "%.2f", logoHeightMillimetres))"
        + "|dpi:\(outputDPI.map { String(format: "%.0f", $0) } ?? "auto")"
        + "|le:\(logoEnabled ? 1 : 0)"
        + "|lp:\(Self.slotKey(leftPrimary))|ls:\(Self.slotKey(leftSecondary))"
        + "|rp:\(Self.slotKey(rightPrimary))|rs:\(Self.slotKey(rightSecondary))"
    }

    /// Compact, stable key for a caption slot.
    static func slotKey(_ slot: CaptionSlot) -> String {
        switch slot {
        case .empty: return "none"
        case .field(let field): return "f:\(field.rawValue)"
        case .text(let text): return "t:\(text)"
        }
    }

    /// Compact, stable key for a colour's components.
    static func colorKey(_ color: CGColor) -> String {
        (color.components ?? []).map { String(format: "%.3f", $0) }.joined(separator: ",")
    }
}
