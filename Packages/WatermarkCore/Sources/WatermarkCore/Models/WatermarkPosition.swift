import CoreImage

/// Watermark placement: nine presets plus free-form `.custom` placement.
///
/// Uses CIImage bottom-left origin coordinate system:
/// - Origin (0,0) is bottom-left corner
/// - +X extends right, +Y extends up
/// - This is the OPPOSITE of UIKit (0,0 top-left, +Y down)
///
/// Always normalize EXIF orientation to `.up` before using this enum's
/// translation values — working on non-normalized images causes watermark
/// misplacement (the "double-rotation" bug).
public enum WatermarkPosition: Sendable, Hashable {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case center
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    /// Free placement, set by dragging the element on the preview.
    ///
    /// `x`/`y` are fractions (0…1) of the space the element can travel in —
    /// 0 = flush against the left/top edge, 1 = flush against the right/bottom
    /// edge — so a custom position can never push the element off the image,
    /// whatever its size. `y` runs DOWN (0 = top) to match the UI; the presets'
    /// CIImage y-up convention is applied in `translation`.
    case custom(x: CGFloat, y: CGFloat)

    /// Calculates the CGAffineTransform translation for placing a watermark at
    /// this position, using CIImage bottom-left origin coordinate math.
    ///
    /// - Parameters:
    ///   - watermarkExtent: The extent rect of the watermark `CIImage`
    ///   - baseExtent: The extent rect of the base image `CIImage`
    ///   - padding: Padding in points from edges of base image
    /// - Returns: A `CGAffineTransform` with translationX and translationY set
    ///
    /// After normalization to `.up`, top-left maps to visual top-left:
    ///   topLeft  → y = baseExtent.height - watermarkExtent.height - padding
    ///   bottomLeft → y = padding
    public func translation(
        watermarkExtent: CGRect,
        baseExtent: CGRect,
        padding: CGFloat
    ) -> CGAffineTransform {
        // CIImage coordinate system: origin is BOTTOM-LEFT
        //   +X extends right, +Y extends up
        //   topLeft  → visual top-left    (y near height)
        //   bottomLeft → visual bottom-left (y near 0)
        let x: CGFloat
        let y: CGFloat

        switch self {
        case .topLeft:
            x = padding
            y = baseExtent.height - watermarkExtent.height - padding
        case .topCenter:
            x = (baseExtent.width - watermarkExtent.width) / 2
            y = baseExtent.height - watermarkExtent.height - padding
        case .topRight:
            x = baseExtent.width - watermarkExtent.width - padding
            y = baseExtent.height - watermarkExtent.height - padding
        case .middleLeft:
            x = padding
            y = (baseExtent.height - watermarkExtent.height) / 2
        case .center:
            x = (baseExtent.width - watermarkExtent.width) / 2
            y = (baseExtent.height - watermarkExtent.height) / 2
        case .middleRight:
            x = baseExtent.width - watermarkExtent.width - padding
            y = (baseExtent.height - watermarkExtent.height) / 2
        case .bottomLeft:
            x = padding
            y = padding
        case .bottomCenter:
            x = (baseExtent.width - watermarkExtent.width) / 2
            y = padding
        case .bottomRight:
            x = baseExtent.width - watermarkExtent.width - padding
            y = padding
        case .custom(let fx, let fy):
            // Fractions of the free travel space, so the element is always
            // fully inside the image — this is the single guard that keeps a
            // dragged element in bounds, for photo, video and batch alike.
            // Custom placement ignores `padding` on purpose: the user picked
            // the spot, including flush against an edge.
            let travelX = max(0, baseExtent.width - watermarkExtent.width)
            let travelY = max(0, baseExtent.height - watermarkExtent.height)
            x = min(max(fx, 0), 1) * travelX
            y = (1 - min(max(fy, 0), 1)) * travelY
        }

        return CGAffineTransform(translationX: x, y: y)
    }
}

// MARK: - Raw value & Codable

extension WatermarkPosition: RawRepresentable {
    /// Stable string key. Presets keep the raw values they had when this was a
    /// `String`-backed enum, so saved configs and templates still decode.
    public var rawValue: String {
        switch self {
        case .topLeft: return "topLeft"
        case .topCenter: return "topCenter"
        case .topRight: return "topRight"
        case .middleLeft: return "middleLeft"
        case .center: return "center"
        case .middleRight: return "middleRight"
        case .bottomLeft: return "bottomLeft"
        case .bottomCenter: return "bottomCenter"
        case .bottomRight: return "bottomRight"
        case .custom(let x, let y):
            return "custom:\(String(format: "%.4f", x)),\(String(format: "%.4f", y))"
        }
    }

    public init?(rawValue: String) {
        if let preset = Self.allCases.first(where: { $0.rawValue == rawValue }) {
            self = preset
            return
        }
        guard rawValue.hasPrefix("custom:") else { return nil }
        let parts = rawValue.dropFirst("custom:".count).split(separator: ",")
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
        self = .custom(x: CGFloat(x), y: CGFloat(y))
    }
}

extension WatermarkPosition: CaseIterable {
    /// The nine presets. `.custom` is deliberately absent — it carries
    /// coordinates, so it is offered by the pickers as a separate entry
    /// derived from wherever the element currently sits.
    public static let allCases: [WatermarkPosition] = [
        .topLeft, .topCenter, .topRight,
        .middleLeft, .center, .middleRight,
        .bottomLeft, .bottomCenter, .bottomRight
    ]
}

extension WatermarkPosition: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognized watermark position '\(raw)'"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Custom placement

extension WatermarkPosition {
    /// Where this position sits in travel-fraction space (x right, y DOWN),
    /// ignoring the presets' edge padding.
    public var fraction: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .topCenter: return CGPoint(x: 0.5, y: 0)
        case .topRight: return CGPoint(x: 1, y: 0)
        case .middleLeft: return CGPoint(x: 0, y: 0.5)
        case .center: return CGPoint(x: 0.5, y: 0.5)
        case .middleRight: return CGPoint(x: 1, y: 0.5)
        case .bottomLeft: return CGPoint(x: 0, y: 1)
        case .bottomCenter: return CGPoint(x: 0.5, y: 1)
        case .bottomRight: return CGPoint(x: 1, y: 1)
        case .custom(let x, let y): return CGPoint(x: x, y: y)
        }
    }

    /// True for a dragged (free) placement.
    public var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    /// Converts to `.custom` without moving the element.
    ///
    /// `layout` is the last rendered preview geometry; when it knows where this
    /// layer landed, the conversion is exact. Without it (no preview yet) the
    /// preset's nominal corner is used, which lands within the edge padding of
    /// where the element sits.
    public func asCustom(in layout: RenderLayout?, layerIndex: Int) -> WatermarkPosition {
        if isCustom { return self }
        guard let f = layout?.travelFraction(ofLayer: layerIndex) else {
            let nominal = fraction
            return .custom(x: nominal.x, y: nominal.y)
        }
        return .custom(x: f.x, y: f.y)
    }

    /// Human-readable display name for the position picker Menu.
    public var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .center: return "Center"
        case .middleRight: return "Middle Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        case .custom: return "Custom"
        }
    }
}

extension Array {
    /// Safe subscript that returns `nil` when index is out of bounds,
    /// instead of crashing. Used by scale stepper and other UI views
    /// that query layer properties at the active layer index.
    public subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
