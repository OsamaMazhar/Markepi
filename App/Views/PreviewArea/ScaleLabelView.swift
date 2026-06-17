import SwiftUI

struct ScaleLabelView: View {
    let scale: CGFloat

    var body: some View {
        Text("\(Int(scale * 100))%")
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .shadow(radius: 4)
    }
}
