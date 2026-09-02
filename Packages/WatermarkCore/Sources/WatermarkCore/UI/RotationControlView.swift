// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import SwiftUI

/// Rotation control for the active logo (image) layer.
///
/// Two ways to rotate, matching common image editors:
/// - a **90°** button that steps the angle in 90° increments, and
/// - an editable **degrees** field for an exact angle.
///
/// Only meaningful for image/logo layers; the host shows it inside the logo
/// tool where an image layer is active. Generic over any
/// `WatermarkConfigurable & Observable` ViewModel.
public struct RotationControlView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel

    /// Local text mirror of the degree field. Kept in sync with the model's
    /// rotation but editable independently while the field is focused.
    @State private var degreeText: String = ""
    @FocusState private var fieldFocused: Bool

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    private var layerIndex: Int {
        let idx = viewModel.activeLayerIndex
        guard idx >= 0, idx < viewModel.config.watermarks.count else { return 0 }
        return idx
    }

    /// Current rotation of the active image layer, or 0 if the active layer is
    /// not an image (in which case this control is a no-op).
    private var currentRotation: CGFloat {
        guard let layer = viewModel.config.watermarks[safe: layerIndex],
              case let .image(input, _, _, _, _) = layer else { return 0 }
        return input.rotationDegrees
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text("Rotation")
                .markepiTypography(.controlLabel)

            Spacer()

            HStack(spacing: 2) {
                TextField("0", text: $degreeText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .focused($fieldFocused)
                    .submitLabel(.done)
                    .onSubmit(commitFieldValue)
                    .accessibilityLabel("Rotation angle in degrees")
                Text("°")
                    .markepiTypography(.value)
                    .foregroundStyle(.secondary)
            }

            Button {
                stepBy90()
            } label: {
                Label("90°", systemImage: "rotate.right")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.markepiSecondary())
            .accessibilityLabel("Rotate 90 degrees")
            .accessibilityHint("Rotates the logo clockwise in 90 degree steps")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { syncFieldFromModel() }
        // Keep the field in sync when the angle changes elsewhere (the 90°
        // button, switching to another logo) — but never yank text out from
        // under the user while they are typing.
        .onChange(of: currentRotation) { _, _ in
            if !fieldFocused { syncFieldFromModel() }
        }
        .onChange(of: fieldFocused) { _, focused in
            if !focused { commitFieldValue() }
        }
        .onChange(of: layerIndex) { _, _ in syncFieldFromModel() }
    }

    /// Applies the typed value (if it parses) to the model, then re-syncs the
    /// field to the normalized result so "370" shows as "10", "" reverts, etc.
    private func commitFieldValue() {
        let trimmed = degreeText.trimmingCharacters(in: .whitespaces)
        if let value = Double(trimmed) {
            viewModel.updateLayerRotation(at: layerIndex, degrees: CGFloat(value))
        }
        syncFieldFromModel()
    }

    private func stepBy90() {
        viewModel.updateLayerRotation(at: layerIndex, degrees: currentRotation + 90)
        syncFieldFromModel()
    }

    private func syncFieldFromModel() {
        degreeText = String(Int(currentRotation.rounded()))
    }
}
#endif
