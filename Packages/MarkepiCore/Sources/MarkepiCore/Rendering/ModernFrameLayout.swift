import CoreGraphics

/// The proportions of a modern frame style, measured from the approved mockups
/// (`openspec/changes/add-modern-frame-styles/reference`).
///
/// Edges are multiples of the mat — the `borderMillimetres` setting in pixels —
/// so they follow the border control and stay proportional to the photo the
/// same way every other style does. At the default 8mm the mat is about 3.15%
/// of the photo's short edge, which is what the mockup percentages were divided
/// by. Effect sizes (radius, shadow) are fractions of the photo's short edge.
struct ModernFrameLayout {
    /// Left, top and right edge, in mats. For `spine`, top/bottom/left.
    var side: CGFloat
    /// The caption band, in mats: the bottom edge — or the right rail for `spine`.
    var band: CGFloat
    /// Corner radius of the photo, as a share of its short edge.
    var cornerRadius: CGFloat = 0

    /// How the caption block's height relates to its primary font size: the
    /// model line is 42% of the block, the details line sits at 56% of it.
    static let blockToFont: CGFloat = 1 / 0.42

    init(side: CGFloat, band: CGFloat, cornerRadius: CGFloat = 0) {
        self.side = side
        self.band = band
        self.cornerRadius = cornerRadius
    }

    /// The layout for a modern style, or nil for the four mat styles.
    static func of(_ style: FrameStyle) -> ModernFrameLayout? {
        switch style {
        case .classic, .gallery, .print, .banner: return nil
        case .float: return .init(side: 2.2, band: 6.0, cornerRadius: 0.028)
        case .tone: return .init(side: 1.4, band: 4.8)
        case .swatch: return .init(side: 1.4, band: 4.8)
        case .spine: return .init(side: 1.3, band: 3.5)
        case .noir: return .init(side: 1.1, band: 4.1, cornerRadius: 0.012)
        case .readout: return .init(side: 1.1, band: 3.5)
        case .ambient: return .init(side: 2.5, band: 7.0, cornerRadius: 0.026)
        case .aura: return .init(side: 2.5, band: 7.0, cornerRadius: 0.026)
        case .glow: return .init(side: 2.5, band: 7.0, cornerRadius: 0.026)
        case .emboss: return .init(side: 2.5, band: 7.0, cornerRadius: 0.035)
        case .sunlight: return .init(side: 2.5, band: 7.0)
        case .blend: return .init(side: 1.6, band: 5.1, cornerRadius: 0.02)
        }
    }
}
