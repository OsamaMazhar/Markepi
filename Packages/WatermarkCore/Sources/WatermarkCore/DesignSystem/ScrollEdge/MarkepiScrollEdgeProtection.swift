import SwiftUI

// MARK: - MarkepiScrollEdgeProtection

/// Protects the top edge of a scroll view from content collision
/// by overlaying a glass/material header bar. Content scrolls beneath
/// the header via `.scrollClipDisabled()` and is blurred naturally
/// by the glass backing (D-16, D-17).
///
/// **Architecture:**
/// - **Layer 1 (back):** A vertical `ScrollView` containing the content,
///   padded to clear the header area. `.scrollClipDisabled()` allows
///   content to render beneath the header.
/// - **Layer 2 (front):** The `headerContent` (typically `MarkepiPillBar`),
///   with glass/material treatment that naturally blurs scrolling content.
///
/// **Glass treatment (D-16, D-17):**
/// - iOS 26 + Reduce Transparency off: `.glassEffect(.regular, in: RoundedRectangle)`
/// - iOS 18 / Reduce Transparency: `.background(.ultraThinMaterial, in: RoundedRectangle)`
/// The material itself provides the obscuring effect — no separate `.blur()` modifier.
///
/// **Hit-testing (Pitfall 2 mitigation):**
/// The header is placed second in the `ZStack` (alignment `.top`) so it sits
/// above the scroll content. Its glass material background intercepts touches
/// before any content in the overlap zone. No explicit `.allowsHitTesting(false)`
/// needed on the content.
///
/// **Top edge only (D-18):** Only the top edge needs protection since the pill bar
/// is the colliding element. No bottom-edge effect.
///
/// Usage:
/// ```swift
/// @State private var section: ControlsSection = .watermark
/// 
/// ScrollViewReader { proxy in
///     LazyVStack { ... }
/// }
/// .markepiScrollEdgeProtection {
///     MarkepiPillBar(selection: $section)
/// }
/// ```
public struct MarkepiScrollEdgeProtection<Header: View>: ViewModifier {
    @ViewBuilder let headerContent: () -> Header
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Creates a scroll-edge protection modifier with a glass/material header.
    ///
    /// - Parameter headerContent: A `@ViewBuilder` closure that returns the header
    ///   view (typically `MarkepiPillBar`).
    public init(@ViewBuilder headerContent: @escaping () -> Header) {
        self.headerContent = headerContent
    }

    public func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            // Layer 1: Scrollable content
            ScrollView(.vertical) {
                content
                    .padding(.top, headerHeight + 16) // offset for header + breathing room
            }
            .scrollClipDisabled() // D-16: content renders beneath header

            // Layer 2: Glass/material header bar
            glassHeader
                .padding(.top, 4) // safe-area clearance
        }
    }

    /// The header content with its glass/material backing. `glassEffect` is
    /// gated behind the MARKEPI_LIQUID_GLASS compile flag (see
    /// `MarkepiGlassModifier` for why): the iOS-26 opaque-type descriptor it
    /// emits crashes on mismatched simulator runtimes, so by default we use the
    /// material backing, which provides the same obscuring effect (D-17).
    @ViewBuilder
    private var glassHeader: some View {
        let padded = headerContent()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        #if MARKEPI_LIQUID_GLASS
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
            padded.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        } else {
            padded.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        #else
        padded.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        #endif
    }

    /// Approximate header height. The pill bar with `.padding(4)` outer +
    /// segment padding `.padding(.vertical, 8)` ≈ 44pt.
    private var headerHeight: CGFloat { 44 }
}

// MARK: - View Extension

public extension View {
    /// Applies top-edge scroll protection with a glass/material header bar.
    ///
    /// The header overlays the scroll view and blurs content that scrolls beneath it
    /// via its glass backing. On iOS 26 this uses `.glassEffect(...)` and on iOS 18
    /// falls back to `.ultraThinMaterial` (D-17, D-19).
    ///
    /// Only the top edge is protected (D-18) — this is designed for the pill bar
    /// collision case at the top of `ControlsView`.
    ///
    /// - Parameter headerContent: A `@ViewBuilder` closure returning the header view.
    /// - Returns: A view with the scroll-edge protection modifier applied.
    func markepiScrollEdgeProtection<Header: View>(
        @ViewBuilder headerContent: @escaping () -> Header
    ) -> some View {
        modifier(MarkepiScrollEdgeProtection(headerContent: headerContent))
    }
}
