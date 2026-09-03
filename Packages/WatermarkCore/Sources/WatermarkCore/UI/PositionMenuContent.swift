// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import SwiftUI

/// The body of every "Position" menu: free placement first, then the nine
/// presets. Shared so the editor panel, layer list, batch sheet and share
/// extension all offer the same choices.
///
/// Choosing "Custom" never moves the element — it converts wherever it
/// currently sits into draggable coordinates, using the last rendered preview
/// geometry when there is one.
public struct PositionMenuContent: View {
    let current: WatermarkPosition
    let layerIndex: Int
    let layout: RenderLayout?
    let onSelect: (WatermarkPosition) -> Void

    public init(
        current: WatermarkPosition,
        layerIndex: Int,
        layout: RenderLayout?,
        onSelect: @escaping (WatermarkPosition) -> Void
    ) {
        self.current = current
        self.layerIndex = layerIndex
        self.layout = layout
        self.onSelect = onSelect
    }

    public var body: some View {
        Button {
            onSelect(current.asCustom(in: layout, layerIndex: layerIndex))
        } label: {
            Label(
                "Custom — drag on the photo",
                systemImage: current.isCustom ? "checkmark" : "hand.draw"
            )
        }
        Divider()
        ForEach(WatermarkPosition.allCases, id: \.rawValue) { position in
            Button {
                onSelect(position)
            } label: {
                if position == current {
                    Label(position.displayName, systemImage: "checkmark")
                } else {
                    Text(position.displayName)
                }
            }
        }
    }
}
#endif
