// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import SwiftUI

// MARK: - MarkepiButtonRole

/// Semantic roles for buttons in the Markepi design system.
///
/// Three roles map to standard iOS tint conventions (D-10):
/// - `.primary` → accentColor (main call-to-action)
/// - `.secondary` → gray (supplementary actions)
/// - `.destructive` → red (delete, cancel, destructive operations)
public enum MarkepiButtonRole {
    case primary
    case secondary
    case destructive
}

// MARK: - MarkepiButtonStyle

/// A capsule-shaped button style with three semantic roles and glass treatment.
///
/// Uses the configuration-driven pattern (SwiftUI standard): the style renders
/// `configuration.label` and applies glass/capsule treatment around whatever
/// label content the caller provides via the standard `Button { } label: { }` pattern.
///
/// **Label convention (D-12):**
/// Callers are responsible for label content — `icon+text` for primary actions,
/// `icon-only` for the overlay Share button, `text-only` for destructive/inline buttons.
///
/// **Glass treatment:**
/// Uses `.markepiGlass(shape: Capsule())` from the GlassEffect foundation (Plan 01).
/// Respects Reduce Transparency by disabling the glass background entirely.
///
/// **Pressed-state feedback:**
/// Opacity drops to 0.7 and scale to 0.97 on press with a 0.15s ease-out animation.
///
/// Usage:
/// ```swift
/// Button { action() } label: {
///     Label("Share", systemImage: "square.and.arrow.up")
/// }
/// .buttonStyle(.markepiPrimary())
/// ```
public struct MarkepiButtonStyle: ButtonStyle {
    let role: MarkepiButtonRole

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Creates a Markepi button style with the given semantic role.
    ///
    /// - Parameter role: The semantic role determining tint color.
    public init(role: MarkepiButtonRole) {
        self.role = role
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .foregroundStyle(tintColor)
            .markepiGlass(
                shape: Capsule(),
                fallbackMaterial: .ultraThinMaterial,
                isEnabled: !reduceTransparency
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    // MARK: - Tint Colors (D-10)

    /// Tint color per semantic role.
    ///
    /// - `.primary` → `.accentColor` (system adaptive — cool blue light, warm blue dark)
    /// - `.secondary` → `.secondary` (gray, lower visual priority)
    /// - `.destructive` → `.red` (standard iOS destructive)
    private var tintColor: Color {
        switch role {
        case .primary:
            return .accentColor
        case .secondary:
            return .secondary
        case .destructive:
            return .red
        }
    }
}

// MARK: - Convenience Extensions

public extension ButtonStyle where Self == MarkepiButtonStyle {
    /// Primary action button style with accentColor tint.
    ///
    /// Usage:
    /// ```swift
    /// Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
    ///     .buttonStyle(.markepiPrimary())
    /// ```
    static func markepiPrimary() -> MarkepiButtonStyle {
        MarkepiButtonStyle(role: .primary)
    }

    /// Secondary action button style with gray tint.
    ///
    /// Usage:
    /// ```swift
    /// Button { cancel() } label: { Text("Cancel") }
    ///     .buttonStyle(.markepiSecondary())
    /// ```
    static func markepiSecondary() -> MarkepiButtonStyle {
        MarkepiButtonStyle(role: .secondary)
    }

    /// Destructive action button style with red tint.
    ///
    /// Usage:
    /// ```swift
    /// Button(role: .destructive) { delete() } label: {
    ///     Label("Delete", systemImage: "trash")
    /// }
    /// .buttonStyle(.markepiDestructive())
    /// ```
    static func markepiDestructive() -> MarkepiButtonStyle {
        MarkepiButtonStyle(role: .destructive)
    }
}
#endif
