import SwiftUI
import WatermarkCore

/// Root SwiftUI view for the share extension's watermarking UI.
///
/// Composes a 60/40 split layout: preview area (top 60%) and controls area
/// (bottom 40%). Does NOT use NavigationStack — the extension has no
/// navigation bar. Mirrors the main app's `ContentView` layout but adapted
/// for the extension context.
struct ShareExtensionRootView: View {
    @State var viewModel: ShareExtensionViewModel

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
        ControlsView(viewModel: viewModel)
    }

    // MARK: - Multi-Item Progress (D-14)
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