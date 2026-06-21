import SwiftUI

/// Applies Liquid Glass on iOS 26 or material fallback on iOS 18.
///
/// Uses a generic constraint `<S: Shape>` (not an existential type) to
/// avoid compiler rejection in the glass effect API where the API may require
/// a concrete Shape type (per Pitfall 4 mitigation).
///
/// Callers should wire `isEnabled` to `@Environment(\.accessibilityReduceTransparency)`:
/// ```swift
/// @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
/// SomeView()
///     .markepiGlass(shape: Capsule(), isEnabled: !reduceTransparency)
/// ```
///
/// - Parameters:
///   - shape: The clipping shape for the glass effect. Default: `Capsule()`.
///   - fallbackMaterial: The material used on iOS < 26. Default: `.ultraThinMaterial`.
///   - isEnabled: Whether glass is active (respects Reduce Transparency). When `false`,
///                renders the content unmodified with no background.
public struct MarkepiGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let fallbackMaterial: Material
    let isEnabled: Bool

    public init(
        shape: S = Capsule(),
        fallbackMaterial: Material = .ultraThinMaterial,
        isEnabled: Bool = true
    ) {
        self.shape = shape
        self.fallbackMaterial = fallbackMaterial
        self.isEnabled = isEnabled
    }

    public func body(content: Content) -> some View {
        content
            .modify { view in
                // D-02: iOS 26 Liquid Glass with material fallback on iOS 18
                if #available(iOS 26, *), isEnabled {
                    // D-03: system-adaptive tint (cool light, warm dark) —
                    // the .regular variant handles this automatically (no custom tint)
                    view.glassEffect(.regular, in: shape)
                } else if isEnabled {
                    view.background(fallbackMaterial, in: shape)
                }
                // When isEnabled is false (e.g., Reduce Transparency),
                // render view unmodified with no background
            }
    }
}

public extension View {
    /// Applies Liquid Glass (iOS 26) or material fallback (iOS 18) to the view.
    ///
    /// - Parameters:
    ///   - shape: The clipping shape for the glass effect. Default: `Capsule()`.
    ///   - fallbackMaterial: The material used on iOS < 26. Default: `.ultraThinMaterial`.
    ///   - isEnabled: Whether glass is active. Callers should pass
    ///                `!reduceTransparency` from `@Environment(\.accessibilityReduceTransparency)`.
    ///                Default: `true`.
    /// - Returns: A view with the glass effect applied.
    ///
    /// D-03: No custom tint — system-adaptive by default (cool light, warm dark).
    public func markepiGlass<S: Shape>(
        shape: S = Capsule(),
        fallbackMaterial: Material = .ultraThinMaterial,
        isEnabled: Bool = true
    ) -> some View {
        modifier(MarkepiGlassModifier(
            shape: shape,
            fallbackMaterial: fallbackMaterial,
            isEnabled: isEnabled
        ))
    }
}
