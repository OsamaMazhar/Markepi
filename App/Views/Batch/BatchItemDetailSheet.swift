import SwiftUI
import WatermarkCore

/// Per-item watermark override modal sheet.
///
/// Presents text input, position grid, scale stepper, and white frame toggle
/// sub-views scoped to a single item's per-item configuration. A "Reset to
/// Batch Config" button restores the shared batch configuration. A "Done"
/// toolbar button dismisses the sheet.
///
/// Only text, position, scale, and white frame sub-views are shown — not
/// LogoPickerView, SignatureCaptureView, or LayerListView. Per-item overrides
/// adjust text/position/scale/frame on individual items; logo/signature layers
/// are inherited from the shared config.
///
/// Per UI-SPEC Interaction Contract #2.
public struct BatchItemDetailSheet: View {
    /// 0-based index for display label ("Item X — Watermark Adjustment").
    let itemIndex: Int

    /// The per-item configuration (writes back on change).
    @Binding var perItemConfig: WatermarkConfiguration

    /// The shared batch configuration for "Reset to Batch Config".
    let sharedConfig: WatermarkConfiguration

    /// Dismiss callback.
    let onDismiss: () -> Void

    /// Internal proxy that conforms to WatermarkConfigurable for sub-view binding.
    @State private var proxy: BatchItemConfigProxy

    public init(
        itemIndex: Int,
        perItemConfig: Binding<WatermarkConfiguration>,
        sharedConfig: WatermarkConfiguration,
        onDismiss: @escaping () -> Void
    ) {
        self.itemIndex = itemIndex
        self._perItemConfig = perItemConfig
        self.sharedConfig = sharedConfig
        self.onDismiss = onDismiss
        self._proxy = State(initialValue: BatchItemConfigProxy(config: perItemConfig.wrappedValue))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header: "Item X — Watermark Adjustment" (title3, semibold)
                Text("Item \(itemIndex + 1) — Watermark Adjustment")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 8)

                // Reused sub-views from WatermarkCore/UI/, each scoped to proxy
                TextWatermarkInputView(viewModel: proxy)
                PositionGridView(viewModel: proxy)
                ScaleStepperView(viewModel: proxy)
                WhiteFrameToggleView(viewModel: proxy)

                Divider()

                // "Reset to Batch Config" button — bordered, accentColor
                Button {
                    proxy.config = sharedConfig
                } label: {
                    Label("Reset to Batch Config", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .disabled(proxy.config == sharedConfig)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
            .navigationTitle("Adjust Item \(itemIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .onAppear {
            // Sync proxy with current perItemConfig on appear
            proxy.config = perItemConfig
        }
        .onChange(of: proxy.config) { _, newConfig in
            // Write back to the perItemConfig binding on change
            perItemConfig = newConfig
        }
    }
}
