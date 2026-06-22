import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Font selector whose collapsed control and expanded list both render each
/// typeface in its OWN font.
///
/// SwiftUI's `Menu`/`Picker` route their item labels through UIKit's menu
/// system, which strips custom fonts and forces the system face — so a font
/// dropdown can never preview the actual typeface. We therefore present a
/// custom sheet (a `List`) where each row is a plain `Text` we fully control,
/// rendered with `Font.custom`, which is exactly how Pages/Keynote do it.
public struct FontPickerView: View {
    @Binding var selectedFontID: String?
    @State private var showPicker = false

    public init(selectedFontID: Binding<String?>) {
        self._selectedFontID = selectedFontID
    }

    private var selectedFont: WatermarkFont? {
        guard let id = selectedFontID else { return nil }
        return FontCatalog.all.first { $0.id == id }
    }

    public var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 6) {
                Text(selectedFont?.displayName ?? "System")
                    // Render the current selection in its own typeface too.
                    .font(Self.resolvedFont(selectedFont?.postScriptName, size: 17))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Font, currently \(selectedFont?.displayName ?? "System")")
        .accessibilityHint("Double tap to choose a different font")
        .sheet(isPresented: $showPicker) {
            FontPickerSheet(selectedFontID: $selectedFontID)
        }
        .task { FontRegistry.registerBundledFonts() }
    }

    /// Returns a `Font.custom` for `postScriptName` when that face is actually
    /// loadable, otherwise the system font. `nil` name → system font.
    static func resolvedFont(_ postScriptName: String?, size: CGFloat) -> Font {
        guard let name = postScriptName else { return .system(size: size) }
        #if canImport(UIKit)
        if UIFont(name: name, size: size) != nil { return .custom(name, size: size) }
        #elseif canImport(AppKit)
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        #endif
        return .system(size: size)
    }
}

// MARK: - Font Picker Sheet

/// The presented list of fonts, grouped by category, each row drawn in its own
/// typeface with a bundled-font badge and a checkmark for the current choice.
struct FontPickerSheet: View {
    @Binding var selectedFontID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var fontsRegistered = false

    private let previewSize: CGFloat = 22

    var body: some View {
        NavigationStack {
            List {
                systemSection
                categorySections
            }
            .navigationTitle("Font")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if !fontsRegistered {
                    FontRegistry.registerBundledFonts()
                    fontsRegistered = true
                }
            }
        }
    }

    private var systemSection: some View {
        Section {
            fontRow(
                title: "System (San Francisco)",
                font: .system(size: previewSize),
                isSelected: selectedFontID == nil,
                isBundled: false
            ) {
                selectedFontID = nil
                dismiss()
            }
        }
    }

    private var categorySections: some View {
        ForEach(FontCategory.allCases, id: \.rawValue) { category in
            Section(category.displayName) {
                ForEach(FontCatalog.fonts(for: category)) { font in
                    fontRow(
                        title: font.displayName,
                        font: FontPickerView.resolvedFont(font.postScriptName, size: previewSize),
                        isSelected: font.id == selectedFontID,
                        isBundled: !font.isSystemFont
                    ) {
                        selectedFontID = font.id
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fontRow(
        title: String,
        font: Font,
        isSelected: Bool,
        isBundled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(font)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if isBundled {
                    Image(systemName: "arrow.down.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Bundled font")
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension FontCategory {
    var displayName: String {
        switch self {
        case .serif: return "Serif"
        case .sansSerif: return "Sans Serif"
        case .script: return "Script"
        case .monospace: return "Monospace"
        }
    }
}
