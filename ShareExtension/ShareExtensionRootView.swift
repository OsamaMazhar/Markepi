import SwiftUI
import PhotosUI
import WatermarkCore

/// Root SwiftUI view for the share extension's watermarking UI.
///
/// Composes a 60/40 split layout: preview area (top 60%) and controls area
/// (bottom 40%). Does NOT use NavigationStack — the extension has no
/// navigation bar. Mirrors the main app's `ContentView` layout but adapted
/// for the extension context.
struct ShareExtensionRootView: View {
    @State var viewModel: ShareExtensionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                previewArea
                    .frame(height: geometry.size.height * 0.60)

                Color(.separator)
                    .frame(height: 1)

                // Multi-item progress (D-14)
                if viewModel.isMultiItem {
                    multiItemProgressBar
                }

                // HDR fallback warning (D-10)
                if viewModel.showHDRWarning && viewModel.renderingState == .done {
                    hdrWarningBanner
                }

                // Audio track mismatch warning (informational)
                if viewModel.showAudioWarning && viewModel.renderingState == .done {
                    audioWarningBanner
                }

                // Video preview "▶" indicator overlay
                if viewModel.isVideo && !viewModel.isLoadingMedia {
                    Color(.separator)
                        .frame(height: 1)
                        .overlay(alignment: .center) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Video")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                }

                controlsArea
                    .frame(height: geometry.size.height * 0.40)
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.errorMessage = nil
                // Multi-item: proceed to next item after error dismissal
                if viewModel.isMultiItem {
                    Task { await viewModel.processNextItem() }
                }
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .alert("Unsupported File Type", isPresented: $viewModel.unsupportedType) {
            Button("Open in App") {
                viewModel.openInMainApp()
            }
            Button("Cancel", role: .cancel) {
                viewModel.completeRequest?()
            }
        } message: {
            Text("This file type isn't supported yet. Open it in the Watermark app instead?")
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let url = viewModel.fullResResult?.url {
                ShareSheetView(activityItems: [url]) {
                    viewModel.handleShareDismiss()
                }
            }
        }
        .task(id: viewModel.previewIdentifier) {
            guard viewModel.sourceURL != nil else { return }
            await viewModel.generatePreview()
        }
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        ZStack {
            if viewModel.isLoadingMedia {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let previewImage = viewModel.previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .overlay(alignment: .center) {
                        if viewModel.isVideo {
                            Image(systemName: "play.rectangle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.7))
                                .shadow(radius: 2)
                        }
                    }
            } else if let errorMessage = viewModel.errorMessage, viewModel.previewImage == nil {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            } else {
                // No media loaded yet — idle state
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Preparing photo...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Controls Area

    private var controlsArea: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                // Active layer controls (text input, position, scale)
                if !viewModel.config.watermarks.isEmpty {
                    activeLayerControls
                }

                // Logo picker (add image watermark layer)
                logoPickerSection

                Divider()

                // White frame toggle
                whiteFrameToggleSection

                // Layer list (show all layers with remove ability)
                if viewModel.config.watermarks.count > 1 {
                    Divider()
                    layerListSection
                }

                Divider()
                    .padding(.vertical, 4)

                // Share button
                shareButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Active Layer Controls

    private var activeLayerControls: some View {
        let index = min(viewModel.activeLayerIndex, viewModel.config.watermarks.count - 1)
        let binding = Binding<WatermarkLayer>(
            get: { viewModel.config.watermarks[index] },
            set: { viewModel.config.watermarks[index] = $0 }
        )

        return Group {
            // Text input for text watermark layers
            if case .text = viewModel.config.watermarks[safe: index] ?? .text(
                TextWatermarkInput(text: ""), position: .bottomRight, scale: 0.15
            ) {
                textInputSection(index: index)
            }

            // Position picker (works for all layer types)
            positionPickerSection(index: index)

            // Scale stepper
            scaleStepperSection(index: index)
        }
    }

    // MARK: - Text Input

    private func textInputSection(index: Int) -> some View {
        guard case .text(let input, let position, let scale) = viewModel.config.watermarks[safe: index] else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Watermark Text")
                    .font(.headline)

                TextField("Enter watermark text", text: Binding(
                    get: { input.text },
                    set: { newText in
                        let newInput = TextWatermarkInput(
                            text: newText,
                            fontSize: input.fontSize,
                            color: input.color,
                            opacity: input.opacity
                        )
                        viewModel.config.watermarks[index] = .text(newInput, position: position, scale: scale)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
        )
    }

    // MARK: - Position Picker

    private func positionPickerSection(index: Int) -> some View {
        let layer = viewModel.config.watermarks[safe: index]
        let currentPosition = layer?.position ?? .bottomRight

        return VStack(alignment: .leading, spacing: 8) {
            Text("Position")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(WatermarkPosition.allCases, id: \.rawValue) { position in
                    Button {
                        viewModel.updateLayerPosition(at: index, position: position)
                    } label: {
                        Text(positionLabel(for: position))
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(currentPosition == position ? .blue : .secondary)
                }
            }
        }
    }

    private func positionLabel(for position: WatermarkPosition) -> String {
        switch position {
        case .topLeft: return "↖ TL"
        case .topCenter: return "↑ TC"
        case .topRight: return "↗ TR"
        case .middleLeft: return "← ML"
        case .center: return "⊙ C"
        case .middleRight: return "→ MR"
        case .bottomLeft: return "↙ BL"
        case .bottomCenter: return "↓ BC"
        case .bottomRight: return "↘ BR"
        }
    }

    // MARK: - Scale Stepper

    private func scaleStepperSection(index: Int) -> some View {
        let layer = viewModel.config.watermarks[safe: index]
        let currentScale = layer?.scale ?? 0.15

        return VStack(alignment: .leading, spacing: 8) {
            Text("Scale: \(String(format: "%.0f", currentScale * 100))%")
                .font(.headline)

            Slider(value: Binding(
                get: { Double(currentScale) },
                set: { viewModel.updateLayerScale(at: index, scale: CGFloat($0)) }
            ), in: 0.01...0.90, step: 0.01)
        }
    }

    // MARK: - Logo Picker

    private var logoPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Logo / Image")
                .font(.headline)

            Button {
                viewModel.showLogoPicker = true
            } label: {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text("Choose Logo Image...")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .photosPicker(
            isPresented: $viewModel.showLogoPicker,
            selection: Binding<[PhotosPickerItem]>(
                get: { [] },
                set: { viewModel.handleLogoSelection($0) }
            ),
            maxSelectionCount: 1,
            matching: .images
        )
    }

    // MARK: - White Frame Toggle

    private var whiteFrameToggleSection: some View {
        Toggle(isOn: Binding(
            get: { viewModel.whiteFrameEnabled },
            set: { _ in viewModel.toggleWhiteFrame() }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("White Frame Border")
                    .font(.headline)
                Text("Adds a white frame with device attribution text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Layer List

    private var layerListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layers (\(viewModel.config.watermarks.count))")
                .font(.headline)

            ForEach(Array(viewModel.config.watermarks.enumerated()), id: \.offset) { index, layer in
                HStack {
                    Button {
                        viewModel.activeLayerIndex = index
                    } label: {
                        HStack {
                            Image(systemName: layerIcon(for: layer))
                                .foregroundStyle(index == viewModel.activeLayerIndex ? .blue : .secondary)
                            Text(layerLabel(for: layer))
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if viewModel.config.watermarks.count > 1 {
                        Button {
                            viewModel.removeLayer(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)

                if index < viewModel.config.watermarks.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func layerIcon(for layer: WatermarkLayer) -> String {
        switch layer {
        case .text: return "textformat"
        case .image: return "photo"
        }
    }

    private func layerLabel(for layer: WatermarkLayer) -> String {
        switch layer {
        case .text(let input, _, _):
            return input.text.isEmpty ? "Text (empty)" : "Text: \"\(input.text)\""
        case .image:
            return "Logo Image"
        }
    }

    // MARK: - Share Button

    private var shareButton: some View {
        Group {
            switch viewModel.renderingState {
            case .idle:
                Button {
                    Task { await viewModel.renderAndPrepareShare() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.sourceURL == nil)
                .opacity(viewModel.sourceURL == nil ? 0.4 : 1.0)

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

            case .done:
                Button {
                    if !reduceMotion {
                        withAnimation(.easeOut(duration: 0.3)) {}
                    }
                    viewModel.presentShareSheet()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Ready to Share")
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
}

    // MARK: - Multi-Item Progress (D-14)

    private var multiItemProgressBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text(viewModel.multiItemProgress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ProgressView(value: Double(viewModel.currentItemIndex + 1), total: Double(viewModel.totalItemCount))
                .tint(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - HDR Warning (D-10)

    private var hdrWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(viewModel.hdrWarningMessage ?? "HDR could not be preserved. Video was exported in standard dynamic range.")
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                viewModel.showHDRWarning = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
    }

    // MARK: - Audio Warning

    private var audioWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.slash")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("Audio track count changed during export.")
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                viewModel.showAudioWarning = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
    }

    // MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}