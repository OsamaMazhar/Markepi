import SwiftUI
import WatermarkCore

/// Composite view combining all watermarking controls: text input, position
/// grid, scale stepper, logo picker, white frame toggle, and layer list.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel so both
/// the main app and share extension can reuse it with their own ViewModels.
///
/// Includes the Share/Render button which adapts to the ViewModel's
/// `renderingState` (idle/rendering/done/error).
public struct ControlsView<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Export Options state
    @State private var showHDRLossWarning = false
    @State private var pendingFormatSelection: OutputFormat = .preserveSource

    /// Computed property for source format label shown when .preserveSource is selected.
    /// Defaults to nil — the ViewModel provides the label after media loading.
    private var sourceFormatLabel: String? {
        viewModel.sourceFormatLabel
    }

    /// True when the ViewModel has multiple photos loaded — gates batch-mode UI.
    private var isBatchMode: Bool { viewModel.hasMultiplePhotos }

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                TextWatermarkInputView(viewModel: viewModel)
                PositionGridView(viewModel: viewModel)
                ScaleStepperView(viewModel: viewModel)
                LogoPickerView(viewModel: viewModel)
                SignatureCaptureView(viewModel: viewModel)
                WhiteFrameToggleView(viewModel: viewModel)
                LayerListView(viewModel: viewModel)

                Divider()
                    .padding(.horizontal, -16)

                saveTemplateButton

                Divider()
                    .padding(.horizontal, -16)

                exportOptionsDisclosure

                Divider()
                    .padding(.vertical, 4)

                shareButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var exportOptionsDisclosure: some View {
        DisclosureGroup("Export Options") {
            VStack(alignment: .leading, spacing: 12) {
                // Format Picker row
                HStack {
                    Text("Format")
                    Spacer()
                    Picker("Format", selection: Binding(
                        get: { viewModel.config.outputFormat },
                        set: { newValue in
                            // D-01: HDR→JPEG warning
                            if newValue == .jpeg && viewModel.sourceHasHDR {
                                pendingFormatSelection = .jpeg
                                showHDRLossWarning = true
                            }
                            viewModel.config.outputFormat = newValue
                        }
                    )) {
                        Text("HEIC").tag(OutputFormat.heic)
                        Text("JPEG").tag(OutputFormat.jpeg)
                        Text("PNG").tag(OutputFormat.png)
                        Text("TIFF").tag(OutputFormat.tiff)
                        Text("Match Source\(sourceFormatLabel.map { " (\($0))" } ?? "")").tag(OutputFormat.preserveSource)
                    }
                    .pickerStyle(.menu)
                }

                // Quality Slider row
                HStack {
                    Text("Quality")
                    Spacer()
                    Text("\(Int(viewModel.config.outputQuality * 100))%")
                        .foregroundStyle(viewModel.config.outputFormat.isLossless ? .secondary : .primary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { viewModel.config.outputQuality },
                    set: { newValue in
                        // Snap to 1.0 when >= 0.98
                        if newValue >= 0.98 && newValue < 1.0 {
                            viewModel.config.outputQuality = 1.0
                        } else {
                            viewModel.config.outputQuality = newValue
                        }
                    }
                ), in: 0.6...1.0, step: 0.01)
                .disabled(viewModel.config.outputFormat.isLossless)
            }
            .padding(.top, 4)
        }
        .alert("HDR Will Be Lost", isPresented: $showHDRLossWarning) {
            Button("Convert to JPEG") {
                // Keep JPEG selection — config already changed
                pendingFormatSelection = .preserveSource
            }
            Button("Cancel", role: .cancel) {
                viewModel.config.outputFormat = .preserveSource
            }
        } message: {
            Text("JPEG does not support HDR. The image will be converted to standard dynamic range.")
        }
    }

    private var shareButton: some View {
        Group {
            switch viewModel.renderingState {
            case .idle:
                Button {
                    Task { await viewModel.renderAndPrepareShare() }
                } label: {
                    HStack(spacing: 8) {
                        if isBatchMode {
                            Image(systemName: "square.and.arrow.up.on.square.fill")
                            Text("Watermark All")
                        } else {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)

            case .rendering:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Rendering...")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .disabled(true)
                .transition(.opacity.combined(with: .scale))

            case .renderingVideo(let progress, let eta):
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                        Text("\(Int(progress * 100))%")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                    if let eta = eta {
                        Text("~\(Int(eta))s remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("--")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        viewModel.cancelProcessing()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            case .batchProcessing(let current, let total, let eta):
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        ProgressView(value: total > 0 ? Double(current) / Double(total) : 0, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                        Text("\(current)/\(total)")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                    if let eta = eta, eta > 0 {
                        Text("ETA: \(Int(eta / 60)) min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("--")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        viewModel.cancelProcessing()
                    } label: {
                        Text("Stop Processing")
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            case .done:
                Button {
                    if !reduceMotion {
                        withAnimation(.easeOut(duration: 0.3)) {}
                    }
                    viewModel.presentShareSheet()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        if isBatchMode {
                            Text("Ready to Share All")
                        } else {
                            Text("Ready to Share")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

            case .error:
                Button {
                    Task { await viewModel.renderAndPrepareShare() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.renderingState)
    }

    private var saveTemplateButton: some View {
        Button {
            viewModel.showSaveTemplateAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down.on.square")
                Text("Save as Template")
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
    }
}
