import SwiftUI

// MARK: - ControlsSection

/// The three sections of the redesigned controls (D-04).
///
/// Control allocation per D-06:
/// - **Watermark:** text input + position picker + scale stepper
/// - **Style:** logo picker + signature capture + white frame toggle + layer list
/// - **Output:** export options + save-as-template
///
/// Conforms to `CaseIterable` for `ForEach` iteration in `MarkepiPillBar`.
public enum ControlsSection: String, CaseIterable, Identifiable {
    case watermark = "Watermark"
    case style = "Style"
    case output = "Output"

    public var id: String { rawValue }
}

// MARK: - MarkepiPillBar

/// A pill-shaped segmented control bar with glass backing and a sliding
/// selection indicator (D-04, D-16).
///
/// Uses a custom `HStack` + `matchedGeometryEffect` approach instead of
/// `PickerStyle.segmented` because native segmented pickers do not support
/// per-segment glass-effect styling (RESEARCH.md § Pattern 4).
///
/// **Per-instance namespace (Pitfall 3 mitigation):**
/// `pillNamespace` is scoped to each `MarkepiPillBar` instance. Two pill bars
/// in the same view hierarchy each get their own namespace — no ID collision.
///
/// **Glass backing (D-16):**
/// The `.markepiGlass(shape: Capsule())` modifier provides Liquid Glass on
/// iOS 26 and `.ultraThinMaterial` fallback on iOS 18. The glass backing blurs
/// content that scrolls beneath the pill bar.
///
/// Usage:
/// ```swift
/// @State private var section: ControlsSection = .watermark
/// MarkepiPillBar(selection: $section)
///     .padding(.horizontal, 16)
/// ```
public struct MarkepiPillBar: View {
    @Binding var selection: ControlsSection
    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<ControlsSection>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(ControlsSection.allCases) { section in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = section
                    }
                } label: {
                    Text(section.rawValue)
                        .markepiTypography(.pillLabel)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("\(section.rawValue) controls")
                .accessibilityHint("Shows \(section.rawValue.lowercased()) settings")
                .accessibilityAddTraits(selection == section ? [.isButton, .isSelected] : .isButton)
                .foregroundStyle(selection == section ? .primary : .secondary)
                .background {
                    if selection == section {
                        Capsule()
                            .fill(.selection) // system-adaptive selection fill
                            .matchedGeometryEffect(id: "activePill", in: pillNamespace)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Controls section selector")
        .padding(4) // inner breathing room for the pill indicator
        .markepiGlass(
            shape: Capsule(),
            fallbackMaterial: .ultraThinMaterial,
            isEnabled: !reduceTransparency
        )
        // D-16: Glass backing provides the blur when content scrolls beneath
    }
}
