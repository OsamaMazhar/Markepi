import CoreImage
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import WatermarkCore

/// Logo/image watermark picker with Photos library and Files app support.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel.
public struct LogoPickerView<ViewModel: WatermarkConfigurable & Observable>: View {
    @Bindable var viewModel: ViewModel
    @State private var showConfirmationDialog = false
    @State private var showPhotosPicker = false
    @State private var showFileImporter = false
    @State private var logoPickerItems: [PhotosPickerItem] = []

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logo Watermark")
                .font(.title3.weight(.semibold))

            if hasLogoLayer {
                logoSelectedView
            } else {
                addLogoButton
            }
        }
        .confirmationDialog("Add Logo Watermark", isPresented: $showConfirmationDialog) {
            Button("From Photos") {
                showPhotosPicker = true
            }
            Button("From Files") {
                showFileImporter = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $logoPickerItems,
            maxSelectionCount: 1,
            matching: .images
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.png]
        ) { result in
            switch result {
            case .success(let url):
                guard let data = try? Data(contentsOf: url) else { return }
                viewModel.addLogoLayer(pngData: data)
            case .failure:
                break
            }
        }
        .onChange(of: logoPickerItems) { _, items in
            guard let item = items.first else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    viewModel.addLogoLayer(pngData: data)
                }
                logoPickerItems = []
            }
        }
    }

    private var hasLogoLayer: Bool {
        viewModel.config.watermarks.contains { layer in
            if case .image = layer { return true }
            return false
        }
    }

    private var logoLayerIndex: Int? {
        viewModel.config.watermarks.firstIndex { layer in
            if case .image = layer { return true }
            return false
        }
    }

    private var addLogoButton: some View {
        Button {
            showConfirmationDialog = true
        } label: {
            HStack {
                Image(systemName: "photo.badge.plus")
                Text("Add Logo")
            }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Add logo watermark")
        .accessibilityHint("Choose a logo image from your photo library or files")
    }

    private var logoSelectedView: some View {
        HStack {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)

            Text("Logo")
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            Button {
                if let index = logoLayerIndex {
                    viewModel.removeLayer(at: index)
                }
            } label: {
                Text("Remove")
                    .font(.body)
                    .foregroundStyle(.red)
            }
        }
    }
}
