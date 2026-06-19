import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import WatermarkCore

/// Lightweight Identifiable wrapper for Int to support `.sheet(item:)` modifier.
struct IdentifiableIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

struct ContentView: View {
    @State var viewModel: WatermarkViewModel
    @State private var showFileImporter = false

    // Batch processing UI state (Phase 13)
    @State private var selectedItemForOverride: IdentifiableIndex? = nil
    @State private var showBatchCancelConfirmation: Bool = false
    @State private var showResetOverridesConfirmation: Bool = false
    @State private var showBatchResultAlert: Bool = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                mainLayout(geometry)
                    .toolbar { toolbarContent }
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
                        matching: .any(of: [.images, .videos])
                    )
                    .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .movie, .audiovisualContent]) { result in
                        switch result {
                        case .success(let url):
                            viewModel.handleIncomingFile(url: url)
                        case .failure:
                            break
                        }
                    }
                    .onAppear {
                        if viewModel.photos.isEmpty {
                            viewModel.showPicker = true
                        }
                    }
            }
            .modifier(AlertModifiers(viewModel: viewModel))
            .modifier(BatchAlertModifiers(
                viewModel: viewModel,
                showBatchCancelConfirmation: $showBatchCancelConfirmation,
                showResetOverridesConfirmation: $showResetOverridesConfirmation,
                showBatchResultAlert: $showBatchResultAlert
            ))
            .modifier(SheetModifiers(
                viewModel: viewModel,
                selectedItemForOverride: $selectedItemForOverride
            ))
        }
    }

    // MARK: - Main Layout

    private func mainLayout(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            previewArea
                .frame(height: geometry.size.height * 0.60)

            Color(.separator)
                .frame(height: 1)

            controlsArea
                .frame(height: geometry.size.height * 0.40)
        }
        .task(id: viewModel.previewIdentifier) {
            guard viewModel.currentPhoto != nil else { return }
            await viewModel.generatePreview()
        }
        .onChange(of: viewModel.currentIndex) {
            viewModel.fullResResult = nil
            viewModel.renderingState = .idle
        }
        .onChange(of: viewModel.renderingState) { _, newState in
            if case .done = newState, viewModel.batchResults != nil {
                showBatchResultAlert = true
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
        }
        if viewModel.hasMultiplePhotos {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    viewModel.requestCancel()
                }
            }
        }
        if viewModel.hasBatchOverrides {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showResetOverridesConfirmation = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset all overrides")
            }
        }
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        ZStack(alignment: .bottom) {
            PreviewView(viewModel: viewModel)

            if viewModel.hasMultiplePhotos {
                ThumbnailStripView(
                    photos: viewModel.photos,
                    currentIndex: $viewModel.currentIndex,
                    perItemOverrides: viewModel.perItemOverrides,
                    onItemTapped: { index in
                        selectedItemForOverride = IdentifiableIndex(value: index)
                    },
                    onReorder: { reordered in
                        viewModel.photos = reordered
                    }
                )
            }

            if case .batchProcessing(let current, let total, let eta) = viewModel.renderingState {
                BatchProgressOverlay(
                    current: current,
                    total: total,
                    eta: eta,
                    onCancel: {
                        showBatchCancelConfirmation = true
                    }
                )
                .transition(.opacity)
            }

            if viewModel.currentPhoto != nil {
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
        .animation(.easeInOut(duration: 0.2), value: viewModel.renderingState)
    }

    // MARK: - Controls Area

    private var controlsArea: some View {
        ControlsView(viewModel: viewModel)
    }
}

// MARK: - Modifier Groups

/// Error alert and discard confirmation (pre-existing modifiers).
private struct AlertModifiers: ViewModifier {
    let viewModel: WatermarkViewModel

    func body(content: Content) -> some View {
        content
            .alert("Rendering Error", isPresented: Binding(
                get: { viewModel.showError },
                set: { viewModel.showError = $0 }
            )) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .confirmationDialog("Discard Changes?", isPresented: Binding(
                get: { viewModel.showCancelAlert },
                set: { viewModel.showCancelAlert = $0 }
            )) {
                Button("Discard", role: .destructive) {
                    viewModel.confirmCancel()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("All unsaved watermark configurations for the remaining photos will be lost.")
            }
    }
}

/// Batch-related alerts and confirmation dialogs (Phase 13).
private struct BatchAlertModifiers: ViewModifier {
    let viewModel: WatermarkViewModel
    @Binding var showBatchCancelConfirmation: Bool
    @Binding var showResetOverridesConfirmation: Bool
    @Binding var showBatchResultAlert: Bool

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Cancel batch processing?", isPresented: $showBatchCancelConfirmation) {
                Button("Cancel Batch", role: .destructive) {
                    viewModel.cancelProcessing()
                }
                Button("Continue Processing", role: .cancel) {}
            } message: {
                Text("Progress on completed items is saved. Remaining items will not be processed. Temp files for cancelled items will be cleaned up.")
            }
            .confirmationDialog("Reset All Overrides?", isPresented: $showResetOverridesConfirmation) {
                Button("Reset All", role: .destructive) {
                    viewModel.resetAllOverrides()
                }
                Button("Keep Adjustments", role: .cancel) {}
            } message: {
                Text("All per-item adjustments will be lost. Items will use the shared watermark configuration.")
            }
            .alert("Batch Complete", isPresented: $showBatchResultAlert) {
                Button("OK") {
                    viewModel.presentShareSheet()
                }
                if let failures = viewModel.batchResults?.failures, !failures.isEmpty {
                    Button("Show Details") {
                        let details = failures.map { "Item \($0.key): \($0.value.localizedDescription)" }.joined(separator: "\n")
                        viewModel.errorMessage = details
                        viewModel.showError = true
                    }
                }
            } message: {
                if let results = viewModel.batchResults {
                    if results.failureCount == 0 {
                        Text("\(results.successCount) of \(results.totalCount) processed successfully.")
                    } else {
                        Text("\(results.successCount) of \(results.totalCount) processed. \(results.failureCount) failed.")
                    }
                }
            }
    }
}

/// Sheet presentations (share, template list, per-item detail).
private struct SheetModifiers: ViewModifier {
    let viewModel: WatermarkViewModel
    @Binding var selectedItemForOverride: IdentifiableIndex?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { viewModel.showShareSheet },
                set: { viewModel.showShareSheet = $0 }
            )) {
                shareSheetContent
            }
            .sheet(isPresented: Binding(
                get: { viewModel.showTemplateList },
                set: { viewModel.showTemplateList = $0 }
            )) {
                NavigationStack {
                    TemplateListView(viewModel: viewModel)
                        .navigationTitle("Templates")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(item: $selectedItemForOverride) { (wrapper: IdentifiableIndex) in
                perItemDetailSheet(for: wrapper.value)
            }
            .saveTemplateAlert(isPresented: Binding(
                get: { viewModel.showSaveTemplateAlert },
                set: { viewModel.showSaveTemplateAlert = $0 }
            )) { name in
                do {
                    let template = Template(
                        name: name,
                        config: viewModel.config,
                        isDefault: false
                    )
                    try TemplateStore.shared.save(template)
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.showError = true
                }
            }
    }

    @ViewBuilder
    private var shareSheetContent: some View {
        if let batchResults = viewModel.batchResults, !batchResults.successes.isEmpty {
            ShareSheetView(activityItems: batchResults.successes) {
                viewModel.cleanupTempFile()
            }
        } else if let url = viewModel.fullResResult?.url {
            ShareSheetView(activityItems: [url]) {
                viewModel.cleanupTempFile()
            }
        }
    }

    @ViewBuilder
    private func perItemDetailSheet(for index: Int) -> some View {
        let photo = viewModel.photos[index]
        NavigationStack {
            BatchItemDetailSheet(
                itemIndex: index,
                perItemConfig: Binding(
                    get: { viewModel.overrideConfig(for: photo.id) },
                    set: { viewModel.setOverride($0, for: photo.id) }
                ),
                sharedConfig: viewModel.config,
                onDismiss: { selectedItemForOverride = nil }
            )
        }
    }
}
