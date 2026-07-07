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

    @ViewBuilder
    public func body(content: Content) -> some View {
        if isEnabled {
            #if MARKEPI_LIQUID_GLASS
            // D-02: iOS/macOS 26 Liquid Glass with material fallback on earlier OS.
            // Gated behind the MARKEPI_LIQUID_GLASS compile flag: the iOS-26
            // `glassEffect` opaque-type descriptor crashes (`EXC_BAD_ACCESS` in
            // `swift_getOpaqueTypeMetadata`) on simulator runtimes whose Swift
            // ABI predates the SDK the app is built with — and merely *compiling*
            // the call into the render path is enough to trigger it, even when
            // the branch isn't taken. Define MARKEPI_LIQUID_GLASS in build
            // settings only when the run destination's runtime matches the SDK.
            if #available(iOS 26, macOS 26, *) {
                // D-03: system-adaptive tint (cool light, warm dark) — the
                // .regular variant handles this automatically (no custom tint).
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(fallbackMaterial, in: shape)
            }
            #else
            content.background(fallbackMaterial, in: shape)
            #endif
        } else {
            // Reduce Transparency: render content unmodified (no background).
            // Previously this branch returned EmptyView via `.modify`, which
            // dropped the content entirely.
            content
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
    func markepiGlass<S: Shape>(
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
