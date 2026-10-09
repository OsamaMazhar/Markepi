// iOS-only UI. Guarded so MarkepiCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
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
    case more = "More"

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
public struct MarkepiPillBar<Option: Hashable & Identifiable>: View {
    @Binding var selection: Option
    private let options: [Option]
    private let title: (Option) -> String
    private let icon: (Option) -> String?
    private let groupLabel: String
    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Any set of options, each with a title and an optional SF Symbol.
    public init(
        selection: Binding<Option>,
        options: [Option],
        groupLabel: String,
        title: @escaping (Option) -> String,
        icon: @escaping (Option) -> String? = { _ in nil }
    ) {
        self._selection = selection
        self.options = options
        self.groupLabel = groupLabel
        self.title = title
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = option
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let symbol = icon(option) {
                            Image(systemName: symbol).imageScale(.small)
                        }
                        Text(title(option))
                    }
                    .markepiTypography(.pillLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .contentShape(Capsule())
                }
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(selection == option ? [.isButton, .isSelected] : .isButton)
                .foregroundStyle(selection == option ? .primary : .secondary)
                .background {
                    if selection == option {
                        Capsule()
                            .fill(.selection) // system-adaptive selection fill
                            .matchedGeometryEffect(id: "activePill", in: pillNamespace)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(groupLabel)
        .padding(4) // inner breathing room for the pill indicator
        .markepiGlass(
            shape: Capsule(),
            fallbackMaterial: .ultraThinMaterial,
            isEnabled: !reduceTransparency
        )
        // D-16: Glass backing provides the blur when content scrolls beneath
    }
}

extension MarkepiPillBar where Option == ControlsSection {
    /// The controls-section bar (D-04).
    public init(selection: Binding<ControlsSection>) {
        self.init(selection: selection, options: ControlsSection.allCases,
                  groupLabel: "Controls section selector", title: { $0.rawValue })
    }
}
#endif
