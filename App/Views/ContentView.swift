import PhotosUI
import SwiftUI

struct ContentView: View {
    @State var viewModel: WatermarkViewModel

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    previewArea
                        .frame(height: geometry.size.height * 0.60)

                    Color(.separator)
                        .frame(height: 1)

                    controlsArea
                        .frame(height: geometry.size.height * 0.40)
                }
                .toolbar {
                    if viewModel.hasMultiplePhotos {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                viewModel.requestCancel()
                            }
                        }
                    }
                }
                .photosPicker(
                    isPresented: Binding(
                        get: { viewModel.showPicker },
                        set: { viewModel.showPicker = $0 }
                    ),
                    selection: Binding(
                        get: { viewModel.selectedItems },
                        set: { viewModel.handleSelection($0) }
                    ),
                    maxSelectionCount: 20,
                    matching: .images
                )
                .onAppear {
                    if viewModel.photos.isEmpty {
                        viewModel.showPicker = true
                    }
                }
                .alert("Rendering Error", isPresented: $viewModel.showError) {
                    Button("OK") {
                        viewModel.errorMessage = nil
                    }
                } message: {
                    Text(viewModel.errorMessage ?? "Unknown error")
                }
                .confirmationDialog("Discard Changes?", isPresented: $viewModel.showCancelAlert) {
                    Button("Discard", role: .destructive) {
                        viewModel.confirmCancel()
                    }
                    Button("Keep Editing", role: .cancel) {}
                } message: {
                    Text("All unsaved watermark configurations for the remaining photos will be lost.")
                }
                .sheet(isPresented: $viewModel.showShareSheet) {
                    if let url = viewModel.fullResResult?.url {
                        ShareSheetView(activityItems: [url]) {
                            viewModel.cleanupTempFile()
                        }
                    }
                }
                .task(id: viewModel.previewIdentifier) {
                    guard viewModel.currentPhoto != nil else { return }
                    await viewModel.generatePreview()
                }
                .onChange(of: viewModel.currentIndex) {
                    viewModel.fullResResult = nil
                    viewModel.renderingState = .idle
                }
            }
        }
    }

    private var previewArea: some View {
        ZStack(alignment: .bottom) {
            PreviewView(viewModel: viewModel)

            if let _ = viewModel.currentPhoto {
                Button {
                    viewModel.showPicker = true
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 22, weight: .regular))
                }
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
            }
        }
    }

    private var controlsArea: some View {
        ControlsView(viewModel: viewModel)
    }
}
