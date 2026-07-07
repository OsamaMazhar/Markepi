import SwiftUI
import WatermarkCore

/// Persistent bottom tool dock for the main editor.
///
/// Renders one glass capsule containing every `EditorTool`. Tapping a tool
/// selects it (revealing its panel); tapping the active tool again collapses
/// the panel. The active tool is highlighted with an accent-tinted glass pill.
struct EditorToolDock: View {
    @Binding var activeTool: EditorTool?
    /// `.horizontal` for the portrait bottom dock, `.vertical` for the
    /// landscape right-edge rail.
    var axis: Axis = .horizontal

    /// Inner content width of the vertical side rail. The outer glass capsule is
    /// this plus the 6pt dock padding on each side, so its corner radius is
    /// `(railWidth + 12) / 2` and its *inner* radius (at the content edge) is
    /// `railWidth / 2` — the value the active highlight's end caps use to match.
    ///
    /// Sized to *hug* the icon + label content (the longest label, "Layers", is
    /// ~36pt at the fixed 10pt label font) with a few points of symmetric
    /// breathing room, rather than an oversized fixed width that left visible
    /// dead space on the pill's edges. Still pinned (not `maxWidth: .infinity`)
    /// so the rail doesn't fight the photo column for horizontal space.
    private let railWidth: CGFloat = 48

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        dockStack
            .padding(6)
            .markepiGlass(
                shape: Capsule(),
                fallbackMaterial: .bar,
                isEnabled: !reduceTransparency
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Editing tools")
    }

    @ViewBuilder
    private var dockStack: some View {
        let buttons = ForEach(EditorTool.allCases) { tool in
            toolButton(tool)
        }
        if axis == .horizontal {
            HStack(spacing: 2) { buttons }
        } else {
            // Fixed width so the side-rail capsule stays a slim vertical pill.
            // The buttons use `maxWidth: .infinity` so they fill the capsule
            // evenly; without a pinned dock width that greediness makes the
            // dock fight the photo column (also `maxWidth: .infinity`) for
            // horizontal space and swell to ~20% of the canvas. Locking it
            // keeps the photo dominant.
            VStack(spacing: 2) { buttons }
                .frame(width: railWidth)
        }
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        let isActive = activeTool == tool
        let tools = EditorTool.allCases
        let isFirst = tool == tools.first
        let isLast = tool == tools.last
        // Slightly tighter vertical padding in the side rail so all six tools
        // fit even on the shortest landscape windows (iPhone SE).
        let verticalPadding: CGFloat = axis == .vertical ? 6 : 8
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
            .padding(.vertical, verticalPadding)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .background {
                if isActive {
                    activeHighlight(isFirst: isFirst, isLast: isLast)
                        .fill(MarkepiColors.activePillBackground)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tool.panelTitle) tool")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isActive ? "Double tap to hide controls" : "Double tap to show controls")
    }

    /// Shape for the selected-tool highlight.
    ///
    /// Horizontal dock: a `Capsule`, matching the outer pill's rounded ends.
    ///
    /// Vertical rail: the cells are wide-and-short, so a capsule reads as a
    /// lozenge. Instead the highlight spans the full content width and its END
    /// CAPS use the pill's *inner* radius (`railWidth / 2`) on the first/last
    /// tools — so they follow the dock pill's rounded top/bottom — while the
    /// other corners use a subtle uniform radius. This makes the highlight's
    /// curvature match the feature pill's radius, the user's request.
    private func activeHighlight(isFirst: Bool, isLast: Bool) -> AnyShape {
        guard axis == .vertical else { return AnyShape(Capsule()) }
        let cap = railWidth / 2
        let inner: CGFloat = 12
        return AnyShape(UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? cap : inner,
            bottomLeadingRadius: isLast ? cap : inner,
            bottomTrailingRadius: isLast ? cap : inner,
            topTrailingRadius: isFirst ? cap : inner,
            style: .continuous
        ))
    }
}
