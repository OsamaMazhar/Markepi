// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import SwiftUI

/// A single-file catalog rendering every Markepi design system primitive
/// side-by-side in a scrollable view for Xcode Preview design iteration
/// without building to a device (D-23).
///
/// Sections: Glass Effects, Typography, Buttons, Pill Bar, Scroll Edge Protection.
///
/// Renders on iOS 18 (material fallbacks) and iOS 26 (Liquid Glass effects).
/// No `@available(iOS 26, *)` on the catalog — individual modifiers handle
/// availability internally.
public struct PreviewCatalog: View {
    @State private var catalogSection: ControlsSection = .watermark

    public init() {}

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                glassEffectsSection
                typographySection
                buttonsSection
                pillBarSection
                scrollEdgeProtectionSection
            }
            .padding()
        }
    }

    // MARK: - Section 1: Glass Effects

    @ViewBuilder
    private var glassEffectsSection: some View {
        Text("Glass Effects")
            .markepiTypography(.sectionHeader)

        // Regular Glass — Sheet Surface
        RoundedRectangle(cornerRadius: 12)
            .fill(.clear)
            .frame(height: 60)
            .markepiGlass(
                shape: RoundedRectangle(cornerRadius: 12),
                fallbackMaterial: .regularMaterial
            )
            .overlay {
                Text("Regular Glass — Sheet Surface")
                    .markepiTypography(.controlLabel)
            }

        // Thin Glass — Toolbar/Button
        Capsule()
            .fill(.clear)
            .frame(height: 44)
            .markepiGlass(
                shape: Capsule(),
                fallbackMaterial: .ultraThinMaterial
            )
            .overlay {
                Text("Thin Glass — Toolbar/Button")
                    .markepiTypography(.controlLabel)
            }
    }

    // MARK: - Section 2: Typography

    @ViewBuilder
    private var typographySection: some View {
        Text("Typography")
            .markepiTypography(.sectionHeader)

        VStack(alignment: .leading, spacing: 4) {
            ForEach(MarkepiTypography.allCases, id: \.self) { style in
                Text(String(describing: style))
                    .markepiTypography(style)
            }
        }
    }

    // MARK: - Section 3: Buttons

    @ViewBuilder
    private var buttonsSection: some View {
        Text("Buttons")
            .markepiTypography(.sectionHeader)

        ForEach([MarkepiButtonRole.primary,
                 MarkepiButtonRole.secondary,
                 MarkepiButtonRole.destructive],
                id: \.self) { role in
            Button {} label: {
                Label("\(String(describing: role)) Button", systemImage: "star.fill")
            }
            .buttonStyle(MarkepiButtonStyle(role: role))
        }

        Button {} label: {
            Label("Primary (extension)", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.markepiPrimary())
    }

    // MARK: - Section 4: Pill Bar

    @ViewBuilder
    private var pillBarSection: some View {
        Text("Pill Bar")
            .markepiTypography(.sectionHeader)

        MarkepiPillBar(selection: $catalogSection)
            .frame(height: 60)

        Text("Selected: \(catalogSection.rawValue)")
            .markepiTypography(.metadata)
    }

    // MARK: - Section 5: Scroll Edge Protection

    @ViewBuilder
    private var scrollEdgeProtectionSection: some View {
        Text("Scroll Edge Protection")
            .markepiTypography(.sectionHeader)

        VStack {
            ForEach(0..<20, id: \.self) { i in
                Text("Scrolling content line \(i)")
                    .markepiTypography(.controlLabel)
            }
        }
        .markepiScrollEdgeProtection {
            Text("Glass Header")
                .markepiTypography(.pillLabel)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("Design System Catalog") {
    PreviewCatalog()
}
#endif
