import SwiftUI
import WatermarkCore

/// Root SwiftUI view for the Photo Editing extension's watermarking UI.
///
/// Composes a 60/40 split layout: preview area (top 60%) and controls area
/// (bottom 40%). Mirrors the `ShareExtensionRootView` layout but adapted
/// for the Photos extension context: "Done" button instead of share sheet,
/// single-item processing, and no multi-item progress bar.
struct PhotosExtensionRootView: View {
    @State var viewModel: PhotosExtensionViewModel

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                previewArea
                    .frame(height: geometry.size.height * 0.60)

                Color(.separator)
                    .frame(height: 1)

                // HDR fallback warning
                if viewModel.showHDRWarning && viewModel.renderingState == .done {
                    hdrWarningBanner
                }

                // Video preview indicator overlay
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    viewModel.finishEditing(completionHandler: { _ in })
                } label: {
                    if viewModel.renderingState == .rendering {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Done")
                    }
                }
                .disabled(viewModel.renderingState == .rendering)
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .task(id: viewModel.previewIdentifier) {
            guard viewModel.sourceURL != nil else { return }
            await viewModel.generatePreview()
        }
    }

    // MARK: - Preview Area

    /// Displays the current preview state: loading spinner, watermarked
    /// preview image, error message, or idle placeholder.
    private var previewArea: some View {
        ZStack {
            if viewModel.isLoadingMedia {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading from Photos...")
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

    /// Hosts the shared `ControlsView` generic over `WatermarkConfigurable`.
    /// Identical to the main app and share extension — full UI parity (D-01, D-03).
    private var controlsArea: some View {
        ControlsView(viewModel: viewModel)
    }

    // MARK: - HDR Warning Banner

    /// Inline warning shown when HDR could not be preserved in the output.
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
}
