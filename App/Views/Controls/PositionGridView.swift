import SwiftUI
import WatermarkCore

struct PositionGridView: View {
    @Bindable var viewModel: WatermarkViewModel

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private let positions: [(WatermarkPosition, String, String)] = [
        (.topLeft, "TL", "Top Left"),
        (.topCenter, "TC", "Top Center"),
        (.topRight, "TR", "Top Right"),
        (.middleLeft, "ML", "Middle Left"),
        (.center, "C", "Center"),
        (.middleRight, "MR", "Middle Right"),
        (.bottomLeft, "BL", "Bottom Left"),
        (.bottomCenter, "BC", "Bottom Center"),
        (.bottomRight, "BR", "Bottom Right")
    ]

    private var layerIndex: Int {
        let idx = viewModel.activeLayerIndex
        guard idx >= 0, idx < viewModel.config.watermarks.count else { return 0 }
        return idx
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position")
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(positions, id: \.0.rawValue) { position, label, fullName in
                    Button {
                        viewModel.updateLayerPosition(at: layerIndex, position: position)
                    } label: {
                        ZStack {
                            if currentPosition == position {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor)
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separator))
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Position: \(fullName)")
                    .accessibilityHint("Double tap to place watermark at \(fullName.lowercased())")
                }
            }
        }
        .opacity(viewModel.currentPhoto == nil ? 0.4 : 1.0)
        .disabled(viewModel.currentPhoto == nil)
    }

    private var currentPosition: WatermarkPosition? {
        guard let layer = viewModel.config.watermarks[safe: layerIndex] else { return nil }
        return layer.position
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
