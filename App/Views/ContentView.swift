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

    // Editor tool-dock state. Starts on Text so controls are visible on launch.
    @State private var activeTool: EditorTool? = .text

    /// Measured height of the active tool panel, used to lift the photo above it.
    @State private var panelHeight: CGFloat = 0

    /// Approximate vertical space the dock occupies — used to keep the batch
    /// thumbnail strip clear of it.
    private let dockClearance: CGFloat = 96

    /// Space the dock + spacings + bottom safe area occupy below the panel.
    /// Added to the measured panel height to compute how far to lift the photo.
    private let dockReserve: CGFloat = 124

    /// True when a tool panel is on screen (and not replaced by a render banner).
    private var isPanelVisible: Bool { activeTool != nil && !isBusy }

    /// How far to inset the photo's bottom so it sits fully above the tool panel.
    private var imageBottomInset: CGFloat {
        isPanelVisible ? panelHeight + dockReserve : 0
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                mainLayout(geometry)
                    .toolbar { toolbarContent }
                    .toolbarBackground(.hidden, for: .navigationBar)
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

    // MARK: - Main Layout (editor canvas + tool dock)

    private func mainLayout(_ geometry: GeometryProxy) -> some View {
        // Empty state when no photo loaded AND not rendering — prevents flashing
        // the empty state during batch processing while photo data reloads.
        return Group {
            if viewModel.currentPhoto == nil && viewModel.renderingState != .rendering {
                EmptyStateView(onChoosePhoto: { viewModel.showPicker = true })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(canvasBackground.ignoresSafeArea())
            } else {
                ZStack(alignment: .bottom) {
                    // z=0: Full-bleed preview on a neutral editing canvas.
                    previewArea
                        .ignoresSafeArea()

                    // z=1: Batch overlays (thumbnail strip + batch progress).
                    batchOverlays
                        .zIndex(1)

                    // z=2: Tool panel + persistent dock + render progress.
                    bottomControls(geometry)
                        .zIndex(2)
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
        .onChange(of: viewModel.renderingState) { _, newState in
            if case .done = newState, viewModel.batchResults != nil {
                showBatchResultAlert = true
            }
        }
    }

    /// Neutral dark canvas behind the photo so letterboxing reads as an
    /// intentional editing surface rather than empty white space.
    private var canvasBackground: some View {
        Color.black
    }

    /// True while a render/export/batch operation is in progress.
    private var isBusy: Bool {
        switch viewModel.renderingState {
        case .idle, .done, .error: return false
        default: return true
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.hasMultiplePhotos {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    viewModel.requestCancel()
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                viewModel.showPicker = true
            } label: {
                Image(systemName: "photo.badge.plus")
            }
            .accessibilityLabel("Add photos")

            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .accessibilityLabel("Import from Files")

            if viewModel.hasBatchOverrides {
                Button {
                    showResetOverridesConfirmation = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset all overrides")
            }

            ExportToolbarButton(viewModel: viewModel)
        }
    }

    // MARK: - Preview Area (z=0)

    private var previewArea: some View {
        ZStack {
            canvasBackground
            // Lift the photo above the tool panel so it stays fully visible,
            // animating smoothly as panels open/close or swap.
            PreviewView(viewModel: viewModel)
                .padding(.bottom, imageBottomInset)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
                    value: imageBottomInset
                )
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.renderingState)
    }

    // MARK: - Batch Overlays (z=1)

    @ViewBuilder
    private var batchOverlays: some View {
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
            .padding(.bottom, dockClearance)
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
            .transition(reduceMotion ? .identity : .opacity)
        }
    }

    // MARK: - Bottom Controls (z=2)

    private func bottomControls(_ geometry: GeometryProxy) -> some View {
        // Panel grows taller at large Dynamic Type so controls stay reachable.
        let panelMaxHeight: CGFloat = dynamicTypeSize >= .xxLarge
            ? geometry.size.height * 0.62
            : geometry.size.height * 0.50

        return VStack(spacing: 12) {
            RenderProgressBanner(viewModel: viewModel)

            if let tool = activeTool, !isBusy {
                ToolPanelView(
                    tool: tool,
                    viewModel: viewModel,
                    onClose: {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                            activeTool = nil
                        }
                    }
                )
                .frame(maxHeight: panelMaxHeight)
                .padding(.horizontal, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            EditorToolDock(activeTool: $activeTool)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: activeTool)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isBusy)
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
