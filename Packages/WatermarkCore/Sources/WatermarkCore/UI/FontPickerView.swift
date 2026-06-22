import SwiftUI

public struct FontPickerView: View {
    @Binding var selectedFontID: String?
    @State private var fontsRegistered = false

    public init(selectedFontID: Binding<String?>) {
        self._selectedFontID = selectedFontID
    }

    private var selectedFont: WatermarkFont? {
        guard let id = selectedFontID else { return nil }
        return FontCatalog.all.first { $0.id == id }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Menu {
                Button {
                    selectedFontID = nil
                } label: {
                    HStack {
                        Text("System (San Francisco)")
                            .font(.body.weight(.semibold))
                        Spacer()
                        if selectedFontID == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Divider()
                ForEach(FontCategory.allCases, id: \.rawValue) { category in
                    Section(category.displayName) {
                        ForEach(FontCatalog.fonts(for: category)) { font in
                            Button {
                                selectedFontID = font.id
                            } label: {
                                HStack {
                                    Text(font.displayName)
                                        .font(fontPreviewFont(for: font))
                                    Spacer()
                                    if font.id == selectedFontID {
                                        Image(systemName: "checkmark")
                                    }
                                    if !font.isSystemFont {
                                        Image(systemName: "arrow.down.doc")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedFont?.displayName ?? "System")
                        .markepiTypography(.value)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Font, currently \(selectedFont?.displayName ?? "System")")
            .accessibilityHint("Double tap to choose a different font")

            if let font = selectedFont, !font.isSystemFont {
                Text("Bundled font")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .task {
            if !fontsRegistered {
                FontRegistry.registerBundledFonts()
                fontsRegistered = true
            }
        }
    }

    private func fontPreviewFont(for font: WatermarkFont) -> Font {
        let size: CGFloat = 16
        let name = font.postScriptName

        #if canImport(UIKit)
        if UIFont(name: name, size: size) != nil {
            return Font.custom(name, size: size)
        }
        #elseif canImport(AppKit)
        if NSFont(name: name, size: size) != nil {
            return Font.custom(name, size: size)
        }
        #endif

        return .body
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
