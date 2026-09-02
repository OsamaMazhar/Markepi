// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import SwiftUI

extension View {
    /// Applies a conditional transform to the view. Used to inject
    /// `if #available(iOS 26, *)` gates into modifier chains without
    /// duplicating the full view hierarchy.
    ///
    /// Usage:
    /// ```swift
    /// SomeView()
    ///     .modify { view in
    ///         if #available(iOS 26, *) {
    ///             view.glassEffect(.regular, in: Capsule())
    ///         } else {
    ///             view.background(.ultraThinMaterial, in: Capsule())
    ///         }
    ///     }
    /// ```
    @ViewBuilder
    public func modify<Content: View>(
        @ViewBuilder transform: (Self) -> Content
    ) -> some View {
        transform(self)
    }
}
#endif
