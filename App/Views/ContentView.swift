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
    @Bindable var viewModel: WatermarkViewModel
    @State private var showFileImporter = false

    // Batch processing UI state (Phase 13)
    @State private var selectedItemForOverride: IdentifiableIndex? = nil
    @State private var showBatchCancelConfirmation: Bool = false
    @State private var showResetOverridesConfirmation: Bool = false
    @State private var showBatchResultAlert: Bool = false

    // Editor tool-dock state. Starts on Text so controls are visible on launch.
    @State private var activeTool: EditorTool? = .text

    /// Settings pane (gear icon) presentation state.
    @State private var showSettings = false

    /// Premium upgrade (paywall) presentation state.
    @State private var showPaywall = false

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
                        // Don't pop the launch picker when a Share Extension
                        // handoff is pending — importPendingShares will load it.
                        if viewModel.photos.isEmpty
                            && viewModel.openPickerOnLaunch
                            && !SharedInboxStore.hasPending {
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
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .overlay {
                if viewModel.isImportingMedia {
                    LoadingOverlay(message: "Loading your media…")
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.isImportingMedia)
        }
    }

    // MARK: - Main Layout (editor canvas + tool dock)

    private func mainLayout(_ geometry: GeometryProxy) -> some View {
        // Empty state when no photo loaded AND not rendering — prevents flashing
        // the empty state during batch processing while photo data reloads.
        return Group {
            if viewModel.currentPhoto == nil && viewModel.renderingState != .rendering {
                firstPage
            } else {
                // The preview is the main content; it respects the safe area on
                // top (so it stays below the status bar / toolbar) and SwiftUI's
                // `safeAreaInset` automatically keeps it clear of the bottom
                // chrome (batch strip, scrubber, panel, dock) — no manual height
                // math, and the content rises into the free space above.
                PreviewView(viewModel: viewModel)
                    .background(canvasBackground.ignoresSafeArea())
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        bottomControls(geometry)
                    }
                    .overlay {
                        batchOverlays
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

    // MARK: - First Page (no media loaded)

    /// The app's launch / empty screen: a branded hero with the photo and
    /// Files entry points, and the app name + version pinned to the bottom.
    private var firstPage: some View {
        ZStack(alignment: .bottom) {
            EmptyStateView(
                onChoosePhoto: { viewModel.showPicker = true },
                onImportFiles: { showFileImporter = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            appVersionFooter
                .padding(.bottom, 16)
        }
        .background(canvasBackground.ignoresSafeArea())
    }

    /// App name + version, shown only on the first page.
    private var appVersionFooter: some View {
        VStack(spacing: 3) {
            Text(Self.appDisplayName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Self.appVersionString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.appDisplayName), \(Self.appVersionString)")
    }

    /// Display name from the bundle (falls back to "Markepi").
    private static var appDisplayName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "Markepi"
    }

    /// "Version X.Y (build)" string from the bundle.
    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
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
        ToolbarItem(placement: .topBarLeading) {
            if viewModel.currentPhoto != nil {
                // Editing: back to the start screen. Routes through the discard
                // confirmation so in-progress edits aren't lost by accident.
                Button {
                    viewModel.requestCancel()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel("Back to start")
            } else {
                // First page: upgrade to Premium.
                Button {
                    showPaywall = true
                } label: {
                    Image(systemName: "crown.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .tint(.yellow)
                .accessibilityLabel("Upgrade to Premium")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")

            // Add / import / reset / export only matter once media is loaded;
            // on the first page the empty-state CTAs handle adding media.
            if viewModel.currentPhoto != nil {
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
    }

    // MARK: - Batch Overlays

    /// Full-screen batch progress overlay shown during processing. The thumbnail
    /// strip now lives in the bottom chrome stack (see `bottomControls`) so it
    /// stacks with — rather than hides behind — the tool panel.
    @ViewBuilder
    private var batchOverlays: some View {
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
            // Batch thumbnail strip sits at the TOP of the chrome stack so it is
            // always visible alongside (never hidden behind) the tool panel.
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 12)
            }

            // Frame scrubber: drag through the video timeline to preview the
            // watermarked output at any frame (AVAssetImageGenerator-backed).
            if viewModel.isCurrentVideo && !isBusy {
                VideoScrubBar(fraction: $viewModel.videoPreviewFraction)
            }

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
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            EditorToolDock(activeTool: $activeTool)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: activeTool)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isBusy)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.hasMultiplePhotos)
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
                Text("Your loaded photos and any unsaved watermark adjustments will be discarded, returning you to the start.")
            }
            .confirmationDialog("Add These Photos?", isPresented: Binding(
                get: { viewModel.showImportChoice },
                set: { newValue in
                    // Treat a swipe-to-dismiss as cancel so the pending temp
                    // files don't leak.
                    if !newValue && viewModel.showImportChoice {
                        viewModel.cancelImport()
                    }
                    viewModel.showImportChoice = newValue
                }
            )) {
                Button("Add to Batch") { viewModel.confirmImportAppend() }
                Button("Replace Current", role: .destructive) { viewModel.confirmImportReplace() }
                Button("Cancel", role: .cancel) { viewModel.cancelImport() }
            } message: {
                Text("You already have \(viewModel.photos.count) photo\(viewModel.photos.count == 1 ? "" : "s") loaded. Add the new \(viewModel.pendingImport.count == 1 ? "photo" : "photos") to the batch, or replace what's loaded?")
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
                get: { viewModel.showExportReceipt },
                set: { viewModel.showExportReceipt = $0 }
            )) {
                if let receipt = viewModel.lastExportReceipt {
                    ExportReceiptView(receipt: receipt)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.showTemplateList },
                set: { viewModel.showTemplateList = $0 }
            )) {
                NavigationStack {
                    TemplateListView(
                        viewModel: viewModel,
                        sourceURL: viewModel.currentPhoto?.sourceURL
                    )
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
        } else if viewModel.fullResResult?.url != nil {
            ShareSheetView(activityItems: viewModel.singleShareItems) {
                viewModel.cleanupTempFile()
            }
        }
    }

    @ViewBuilder
    private func perItemDetailSheet(for index: Int) -> some View {
        let photo = viewModel.photos[index]
        // BatchItemDetailSheet supplies its own NavigationStack; wrapping it in
        // another here produced two stacked navigation bars that overlapped on
        // presentation until the sheet was dismissed and reopened.
        BatchItemDetailSheet(
            itemIndex: index,
            thumbnail: photo.thumbnail,
            perItemConfig: Binding(
                get: { viewModel.overrideConfig(for: photo.id) },
                set: { viewModel.setOverride($0, for: photo.id) }
            ),
            sharedConfig: viewModel.config,
            onReset: { viewModel.resetOverride(for: photo.id) },
            onDismiss: { selectedItemForOverride = nil }
        )
    }
}

// MARK: - Settings

/// App settings pane, presented from the gear icon. Holds the opt-in for
/// restoring the previous session's watermark and a "start fresh" reset.
struct SettingsView: View {
    @Bindable var viewModel: WatermarkViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Remember Last Settings", isOn: $viewModel.rememberLastSettings)
                } footer: {
                    Text("When on, the app reopens with the watermark you used last time. When off, each launch starts from a clean slate.")
                }

                Section {
                    Toggle("Open Photo Picker on Launch", isOn: $viewModel.openPickerOnLaunch)
                } footer: {
                    Text("When on, the photo picker opens automatically each time you launch the app. When off, you start on the home screen.")
                }

                Section {
                    Button(role: .destructive) {
                        viewModel.resetToDefaults()
                        dismiss()
                    } label: {
                        Label("Start From Scratch", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Clears the current text, logo, signature, and frame so you can begin fresh.")
                }

                Section("About") {
                    LabeledContent("Developer", value: "Orbitaar")
                    LabeledContent("Version", value: Self.appVersionString)
                    Link(destination: Self.termsURL) {
                        Label("Terms of Use", systemImage: "doc.text")
                    }
                    Link(destination: Self.privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// "X.Y (build)" from the bundle.
    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // Placeholder destinations — point these at the real hosted documents.
    private static let termsURL = URL(string: "https://orbitaar.com/markepi/terms")!
    private static let privacyURL = URL(string: "https://orbitaar.com/markepi/privacy")!
}

// MARK: - Loading Overlay

/// A branded, animated full-screen loading overlay — a rotating accent arc
/// around a pulsing app glyph, on a dimmed glass card. Used wherever the app
/// would otherwise appear frozen (media import, share preparation).
struct LoadingOverlay: View {
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(spin ? 360 : 0))
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .scaleEffect(pulse ? 1.08 : 0.9)
                }
                .frame(width: 64, height: 64)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Video Scrub Bar

/// A compact timeline scrubber for videos. Dragging updates the previewed
/// frame fraction (0...1); the preview pipeline re-extracts and re-watermarks
/// that frame via `AVAssetImageGenerator`, so the user sees exactly how the
/// rendered video will look at any point. Lives inside the measured bottom
/// chrome stack, so it never overlaps the photo content.
private struct VideoScrubBar: View {
    @Binding var fraction: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Slider(value: $fraction, in: 0...1)
                .tint(.accentColor)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview frame position")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent through the video")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: fraction = min(1, fraction + 0.05)
            case .decrement: fraction = max(0, fraction - 0.05)
            @unknown default: break
            }
        }
    }
}
