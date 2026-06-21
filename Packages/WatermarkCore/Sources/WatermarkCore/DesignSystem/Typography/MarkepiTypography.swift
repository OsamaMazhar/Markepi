import SwiftUI

/// Semantic typography styles for the Markepi design system.
///
/// Each case maps to a system font style + weight combination,
/// ensuring automatic uncapped Dynamic Type scaling without any
/// truncation or scale factor constraints.
///
/// Conforms to `CaseIterable` for PreviewCatalog iteration.
///
/// D-14: System default font (San Francisco) — no rounded or custom variant.
/// D-15: Dynamic Type is uncapped — system font styles inherit the user's
///       preferred content size category automatically.
public enum MarkepiTypography: CaseIterable {
    /// Grouped section titles (e.g., "Watermark Text", "Style")
    case sectionHeader

    /// Individual control labels (e.g., "Text", "Position", "Scale")
    case controlLabel

    /// Live readout values (e.g., "85%", "0.25x")
    case value

    /// Secondary hints and captions (e.g., "Drag to adjust", format info)
    case metadata

    /// Pill bar segment labels (e.g., "Watermark", "Style", "Output")
    case pillLabel

    // MARK: - Font

    /// Returns the system font for this typography style.
    ///
    /// All styles use San Francisco (system default) per D-14.
    /// Dynamic Type scaling is automatic — system font styles inherit
    /// the user's preferred content size category without any extra code.
    public var font: Font {
        switch self {
        case .sectionHeader:
            return .title3.weight(.semibold)
        case .controlLabel:
            return .body
        case .value:
            return .body.monospacedDigit()
        case .metadata:
            return .caption
        case .pillLabel:
            return .headline.weight(.medium)
        }
    }

    // MARK: - Foreground Color

    /// Returns the foreground color for this typography style.
    ///
    /// Section headers, control labels, and pill labels use `.primary`.
    /// Values and metadata use `.secondary` for visual hierarchy.
    public var foreground: Color {
        switch self {
        case .sectionHeader:
            return .primary
        case .controlLabel:
            return .primary
        case .value:
            return .secondary
        case .metadata:
            return .secondary
        case .pillLabel:
            return .primary
        }
    }
}

// MARK: - ViewModifier

/// Applies Markepi typography to a view using a semantic style label.
///
/// Usage:
/// ```swift
/// Text("Watermark Text")
///     .markepiTypography(.sectionHeader)
/// Text("85%")
///     .markepiTypography(.value)
/// ```
///
/// D-14: System default font (San Francisco) — no rounded or custom variant.
/// D-15: Uncapped Dynamic Type — system font styles scale automatically.
public struct MarkepiTypographyModifier: ViewModifier {
    let style: MarkepiTypography

    public func body(content: Content) -> some View {
        content
            .font(style.font)
            .foregroundStyle(style.foreground)
    }
}

// MARK: - View Extension

public extension View {
    /// Applies the given Markepi typography style to the view.
    ///
    /// - Parameter style: The semantic typography style to apply.
    /// - Returns: A view with the typography style applied.
    func markepiTypography(_ style: MarkepiTypography) -> some View {
        modifier(MarkepiTypographyModifier(style: style))
    }
}
