import SwiftUI
import WatermarkCore

/// Persistent bottom tool dock for the main editor.
///
/// Renders one glass capsule containing every `EditorTool`. Tapping a tool
/// selects it (revealing its panel); tapping the active tool again collapses
/// the panel. The active tool is highlighted with an accent-tinted glass pill.
struct EditorToolDock: View {
    @Binding var activeTool: EditorTool?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditorTool.allCases) { tool in
                toolButton(tool)
            }
        }
        .padding(6)
        .markepiGlass(
            shape: Capsule(),
            fallbackMaterial: .bar,
            isEnabled: !reduceTransparency
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editing tools")
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        let isActive = activeTool == tool
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                activeTool = isActive ? nil : tool
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tool.icon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 20)
                Text(tool.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tool.panelTitle) tool")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isActive ? "Double tap to hide controls" : "Double tap to show controls")
    }
}
