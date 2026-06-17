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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position")
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(positions, id: \.0.rawValue) { position, label, fullName in
                    Button {
                        setPosition(position)
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
                    .accessibilityLabel(fullName)
                }
            }
        }
        .opacity(viewModel.currentPhoto == nil ? 0.4 : 1.0)
        .disabled(viewModel.currentPhoto == nil)
    }

    private var currentPosition: WatermarkPosition? {
        guard let layer = viewModel.config.watermarks.first else { return nil }
        switch layer {
        case .text(_, let position, _): return position
        case .image(_, let position, _): return position
        }
    }

    private func setPosition(_ position: WatermarkPosition) {
        guard var layer = viewModel.config.watermarks.first else { return }
        switch layer {
        case .text(let input, _, let scale):
            viewModel.config.watermarks[0] = .text(input, position: position, scale: scale)
        case .image(let input, _, let scale):
            viewModel.config.watermarks[0] = .image(input, position: position, scale: scale)
        }
    }
}
