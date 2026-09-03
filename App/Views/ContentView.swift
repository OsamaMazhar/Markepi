import PhotosUI
import StoreKit
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

    /// Photo pending removal confirmation from the thumbnail strip's Edit Batch
    /// mode. Drives a `.confirmationDialog(item:)` — set when a red ✕ is tapped.
    @State private var photoPendingRemoval: PhotoItem? = nil

    // Editor tool-dock state. Starts on Text so controls are visible on launch.
    // Frame is the landing tool: the frame is applied the moment a photo is
    // imported, so the controls that shape it are what the user should meet.
    @State private var activeTool: EditorTool? = .frame

    /// Settings pane (gear icon) presentation state.
    @State private var showSettings = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// StoreKit entitlement, injected from `WatermarkApp`. Drives the toolbar
    /// crown's treatment (shiny "upgrade" prompt vs. entitled state).
    @Environment(StoreManager.self) private var store

    // Landscape Share↔dock alignment needs no measurement: in landscape the
    // Share button lives in the same vertical rail stack as the tool dock (see
    // `landscapeRightRail`), so they share one horizontal center by construction.

    /// Side-rail (landscape, iPhone + iPad) vs. bottom-dock (portrait) split.
    /// In landscape the tool dock runs vertically down the right edge so the
    /// photo keeps the full height; in portrait it stays a bottom dock. The
    /// split is driven by the window's *aspect ratio*, not device identity:
    /// iPad reports `.regular` width in both orientations, so size class alone
    /// can't tell portrait from landscape. A minimum height keeps the vertical
    /// dock usable in very short windows — below it the portrait bottom-dock
    /// layout is used instead.
    ///
    /// Computed from a *live* size (the `GeometryReader`'s `geometry.size`),
    /// never from lagged `@State`: deciding the branch from async state made the
    /// layout flip-flop on rotation (it would briefly render the portrait
    /// bottom-dock inside a landscape window, or get stuck there when a sheet
    /// swallowed the geometry update).
    private func isLandscape(width: CGFloat, height: CGFloat) -> Bool {
        width > height && height >= 320
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // The on-screen keyboard is delivered as a bottom safe-area inset:
                // as it rises, `size.height` shrinks and `safeAreaInsets.bottom`
                // grows by the same amount, so their sum is keyboard-invariant.
                // Branching on the raw height flipped the editor into the landscape
                // rails the instant a text field (e.g. the Content Credentials
                // "Name") pushed the available height below the width — destroying
                // the field's identity, resigning the keyboard, and looping (the
                // "can't type my name" bug). The stable height pins the decision
                // while the keyboard is up.
                let stableHeight = geometry.size.height + geometry.safeAreaInsets.bottom
                let landscape = isLandscape(width: geometry.size.width, height: stableHeight)
                // In PORTRAIT the system toolbar drives the chrome (real Liquid
                // Glass). In LANDSCAPE-while-editing the chrome moves into two
                // custom rails — Back + Settings/Add/Files on the left, Share +
                // tool dock on the right — so the system nav bar is emptied AND
                // hidden. Hiding it also reclaims the top safe-area inset it
                // reserved, which had pushed the photo up (no top gap, a gap at
                // the bottom); with it gone the photo centers symmetrically.
                let landscapeEditing = landscape && viewModel.currentPhoto != nil
                mainLayout(geometry, landscape: landscape)
                    .toolbar { toolbarContent(landscapeEditing: landscapeEditing) }
                    .toolbar(landscapeEditing ? .hidden : .automatic, for: .navigationBar)
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
                    // On large displays (iPad) the system photo picker defaults to
                    // a small centered sheet; force it to the large detent so it
                    // fills the available height. (On iPhone this is a no-op.)
                    .presentationDetents([.large])
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
                showBatchResultAlert: $showBatchResultAlert,
                photoPendingRemoval: $photoPendingRemoval
            ))
            .modifier(SheetModifiers(
                viewModel: viewModel,
                selectedItemForOverride: $selectedItemForOverride
            ))
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showPaywall) {
                PaywallView()
            }
            .overlay {
                if viewModel.isImportingMedia {
                    LoadingOverlay(message: "Loading your media…")
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.isImportingMedia)
            // The base layer INSIDE the NavigationStack. The nav stack carries its
            // own opaque container background (system white in light mode) that sits
            // BETWEEN the content and anything painted outside the stack — so a
            // `.background` on the NavigationStack, or painting the window/hosting
            // UIView layers, could not reach it. During a device rotation the
            // content's black canvas lags one layout frame; for that frame the
            // container's white showed as a flash "on the right and under" the
            // photo. Painting the base black here covers the container through that
            // lag frame. (Steady state is unaffected — the branches' own black
            // canvases sit on top of this.)
            .background(
                (viewModel.currentPhoto != nil ? Color.black : MarkepiColors.canvasBackground)
                    .ignoresSafeArea()
            )
        }
        // Window + hosting-view UIView layers, for the triangular corner gaps
        // exposed during rotation (a separate white source from the container
        // above). See WindowBackgroundColor.
        .background(
            WindowBackgroundColor(color: viewModel.currentPhoto != nil ? .black : .systemBackground)
        )
    }

    // MARK: - Main Layout (editor canvas + tool dock)

    private func mainLayout(_ geometry: GeometryProxy, landscape: Bool) -> some View {
        Group {
            if viewModel.currentPhoto == nil && viewModel.renderingState != .rendering {
                firstPage
            } else if landscape {
                landscapeLayout(geometry)
            } else {
                PreviewView(viewModel: viewModel)
                    .background(MarkepiColors.photoCanvasBackground.ignoresSafeArea())
                    .simultaneousGesture(
                        TapGesture().onEnded { closeActiveTool() },
                        including: dismissesToolOnTap
                    )
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 0) {
                            mediaControls(includeStrip: true)
                                // Mirror the top breathing room BELOW the batch
                                // strip so its gaps are symmetric. The outer
                                // `.padding(.top, md)` sets the gap above; without
                                // this the strip sat flush against the dock/panel
                                // (RenderProgressBanner collapses to EmptyView when
                                // idle, so it adds no spacing). Scoped to when the
                                // media controls actually have content so a single
                                // photo (no strip) doesn't get a phantom gap.
                                .padding(.bottom, mediaControlsHasContent ? MarkepiSpacing.md : 0)
                            editorControls(geometry)
                        }
                        // Breathing room so the photo never sits flush against
                        // the panel's top edge.
                        .padding(.top, MarkepiSpacing.md)
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

    /// Backdrop behind the photo so the letterboxing reads as an intentional
    /// editing surface — white in light mode, black in dark mode (shares the
    /// canvas token so onboarding and editor stay in sync).
    private var canvasBackground: Color {
        MarkepiColors.canvasBackground
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

    /// "Version X.Y" string from the bundle.
    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(short)"
    }

    /// True while a render/export/batch operation is in progress.
    private var isBusy: Bool {
        switch viewModel.renderingState {
        case .idle, .done, .error: return false
        default: return true
        }
    }

    // MARK: - Toolbar

    /// The system navigation toolbar. Used as-is in portrait and on the first
    /// page. In landscape-while-editing every item moves to the custom rails
    /// (see `landscapeLeftChrome` and `landscapeRightRail`), so the whole bar is
    /// emptied here and hidden by the caller.
    @ToolbarContentBuilder
    private func toolbarContent(landscapeEditing: Bool) -> some ToolbarContent {
        if !landscapeEditing {
            ToolbarItem(placement: .topBarLeading) {
                if viewModel.currentPhoto != nil {
                    // Editing: back to the start screen. Routes through the discard
                    // confirmation so in-progress edits aren't lost by accident.
                    Button {
                        viewModel.requestCancel()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityIdentifier("chrome.back")
                    .accessibilityLabel("Back to start")
                } else {
                    // First page: upgrade to Premium. A metallic-gold crown with
                    // a sheen that sweeps right→left draws the eye to it; once the
                    // user is entitled the sweep stops and it reads as a calm badge.
                    Button {
                        viewModel.showPaywall = true
                    } label: {
                        PremiumCrownIcon(isPremium: store.isPremium, reduceMotion: reduceMotion)
                    }
                    .accessibilityLabel(store.isPremium ? "Markepi Pro" : "Upgrade to Premium")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityIdentifier("chrome.settings")
                .accessibilityLabel("Settings")

                // Add / import / reset / export only matter once media is loaded;
                // on the first page the empty-state CTAs handle adding media.
                if viewModel.currentPhoto != nil {
                    Button {
                        viewModel.showPicker = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                    }
                    .accessibilityIdentifier("chrome.addPhotos")
                    .accessibilityLabel("Add photos")

                    Button {
                        showFileImporter = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("chrome.importFiles")
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

    // MARK: - Landscape Layout: Canvas Column

    private func canvasColumn(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            PreviewView(viewModel: viewModel)
                .background(MarkepiColors.photoCanvasBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(
                    TapGesture().onEnded { closeActiveTool() },
                    including: dismissesToolOnTap
                )

            // Landscape moves the batch strip into the right rail (vertical), so
            // only the video scrub bar remains under the photo here.
            mediaControls(includeStrip: false)
        }
    }

    // MARK: - Landscape Layout: Canvas + Vertical Tool Dock

    /// Landscape editor. The chrome (Back / Settings / Add / Files / Share) is
    /// the *same system navigation toolbar* used in portrait — see
    /// `toolbarContent` — so the buttons are identical across orientations (real
    /// Liquid Glass, the grouped pill, the prominent blue Export). The only
    /// orientation-specific change is the tool dock: it runs vertically down the
    /// right edge here, instead of as a bottom dock, so the photo keeps the full
    /// height. Opening a tool slides its panel in as a real column to the left of
    /// the dock, flexing the photo narrower; the split animates on `activeTool`.
    private func landscapeLayout(_ geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Left chrome as a real column (not an overlay) so the photo sits to
            // its RIGHT instead of underneath it. Top-aligned — Back on top, then
            // the Settings/Add/Files pill — with its own leading padding to clear
            // the rounded corner, mirroring the right rail's trailing inset.
            landscapeLeftChrome
                .padding(.leading, MarkepiSpacing.md)
                .padding(.top, MarkepiSpacing.sm)
                // Fixed-width column (leading-aligned) so the left rail reserves
                // the SAME width as the right dock column — that symmetry is what
                // centers the photo column between them when the panel is closed.
                .frame(width: Self.sideRailColumnWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)

            canvasColumn(geometry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            landscapeRightRail(geometry)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Extend the whole split into the top/bottom safe areas (applied to the
        // container, NOT a single child — doing it per-child distorted the HStack
        // width distribution and made the photo bleed up but not down). Both
        // columns now span the full height and center their content, so the photo
        // and the open panel share one vertical center (aligned + symmetric) and
        // the photo uses the full height under the floating toolbar.
        //
        // Extend into the TRAILING safe area so the tool rail hugs the right edge,
        // but DELIBERATELY respect the LEADING inset: in landscape the Dynamic
        // Island / notch lives on the leading side, and the left chrome column
        // (Back + Settings/Add/Files) must clear it rather than render underneath.
        // The black canvas background below ignores all safe areas, so the area
        // behind the leading inset is still filled — no gap shows.
        .ignoresSafeArea(.container, edges: [.vertical, .trailing])
        // Cover the whole screen, safe areas included, with the black canvas so
        // no system background is exposed — a light "white box" used to flash on
        // the right during the portrait→landscape rotation because the canvas
        // didn't extend into the safe area.
        .background(MarkepiColors.photoCanvasBackground.ignoresSafeArea())
        .overlay {
            batchOverlays
        }
        // Animate the split so the photo slides left and resizes when a tool
        // panel opens or closes, rather than snapping.
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: activeTool)
    }

    /// Landscape-only left chrome: the Back button stacked above the
    /// Settings/Add/Files (+ reset) group, mirroring the right rail. Uses the
    /// project's `markepiGlass` (same pill as the tool dock). In portrait these
    /// live in the system toolbar instead (see `toolbarContent`).
    private var landscapeLeftChrome: some View {
        VStack(spacing: MarkepiSpacing.md) {
            // Back: framed to the same width as the group pill below so the round
            // glass button isn't narrower than the pill (they read as one rail).
            chromeButton(systemImage: "chevron.backward", label: "Back to start") {
                viewModel.requestCancel()
            }
            .frame(width: Self.chromeRailWidth, height: Self.chromeRailWidth)
            .chromeGlass(in: Circle(), isEnabled: !reduceTransparency)

            VStack(spacing: 2) {
                chromeButton(systemImage: "gearshape", label: "Settings") {
                    showSettings = true
                }
                chromeButton(systemImage: "photo.badge.plus", label: "Add photos") {
                    viewModel.showPicker = true
                }
                chromeButton(systemImage: "folder.badge.plus", label: "Import from Files") {
                    showFileImporter = true
                }
                if viewModel.hasBatchOverrides {
                    chromeButton(systemImage: "arrow.counterclockwise", label: "Reset all overrides") {
                        showResetOverridesConfirmation = true
                    }
                }
            }
            .padding(.vertical, 6)
            .frame(width: Self.chromeRailWidth)
            .chromeGlass(in: Capsule(), isEnabled: !reduceTransparency)
        }
    }

    /// SF Symbol point size for the landscape chrome glyphs (Back, Settings,
    /// Add, Files, Share). Sized to match the portrait system toolbar's glyphs,
    /// which render larger than a plain 17pt symbol.
    private static let chromeIconSize: CGFloat = 20

    /// Outer width of the left-rail chrome (Back circle + the Settings/Add/Files
    /// pill). One value so the round Back button and the pill are the same width.
    private static let chromeRailWidth: CGFloat = 56

    /// Reserved width for each side-rail column (left chrome, right tool dock)
    /// when the panel is closed. Both columns share this width, so the photo
    /// column between them is screen-centered — symmetric between the left
    /// buttons and the right dock. Holds the widest rail content (the ~60pt
    /// vertical dock) plus the `md` edge inset that clears the rounded corner.
    private static let sideRailColumnWidth: CGFloat = 80

    /// A single glass-rail chrome icon button, sized to match the tool dock's
    /// touch targets so the left rail and the dock align visually.
    private func chromeButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Self.chromeIconSize, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .accessibilityLabel(label)
    }

    /// Right-edge rail: the active tool's panel (a real column, so opening it
    /// widens the rail and shrinks the photo) plus the vertical tool dock pinned
    /// to the trailing edge and vertically centered. All chrome lives in the
    /// shared top toolbar, not here.
    private func landscapeRightRail(_ geometry: GeometryProxy) -> some View {
        // One consistent gap between the rail's columns (panel · batch strip ·
        // dock). With the vertical batch strip now sitting between the panel and
        // the dock, the previous `xl` gutter was applied twice — doubling the
        // whitespace — so `md` keeps the gaps tight and symmetric on both sides
        // of the strip. (The dock column drops its fixed width when the strip is
        // present, below, so its trailing-alignment slack can't inflate the
        // strip→dock gap and re-break the symmetry.)
        HStack(spacing: MarkepiSpacing.md) {
            if let tool = activeTool, !isBusy {
                ToolPanelView(
                    tool: tool,
                    viewModel: viewModel,
                    onClose: closeActiveTool,
                    maxHeight: max(200, geometry.size.height - 32)
                )
                .frame(width: landscapePanelWidth(geometry, for: tool))
                // Breathing room from the photo's edge — applied to the panel
                // (only present when open) rather than the whole rail, so the
                // closed-state dock column stays exactly `sideRailColumnWidth`
                // and the photo stays centered.
                .padding(.leading, MarkepiSpacing.md)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Batch strip as a vertical column, sitting between the (optional)
            // open panel and the tool dock — the landscape home for what is the
            // horizontal strip under the photo in portrait.
            if viewModel.hasMultiplePhotos {
                landscapeVerticalStrip(geometry)
            }

            // Share sits directly above the vertical dock in one centered stack,
            // so the dock and the Share button share a single horizontal center
            // by construction — no measurement, no offset.
            VStack(spacing: MarkepiSpacing.md) {
                // Round prominent-glass Share button (circular by construction in
                // glassCircle mode), sized by its square label so it isn't oversized
                // and the glyph stays centered. The icon font matches the left-rail
                // chrome glyphs.
                ExportToolbarButton(viewModel: viewModel, glassCircle: true)
                    .font(.system(size: Self.chromeIconSize, weight: .regular))

                EditorToolDock(activeTool: $activeTool, axis: .vertical)
            }
            // Trailing inset clears the rounded corner (mirrors the left chrome's
            // leading inset). The fixed-width, trailing-aligned column matches the
            // left chrome's width, so the photo column between the two rails is
            // screen-centered when the panel is closed — but only when there's NO
            // batch strip. With the strip present that centering is moot (the
            // strip sits between), and the column's trailing-alignment slack would
            // otherwise widen the strip→dock gap asymmetrically, so the dock hugs
            // its content instead.
            .padding(.trailing, MarkepiSpacing.md)
            .frame(width: viewModel.hasMultiplePhotos ? nil : Self.sideRailColumnWidth, alignment: .trailing)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(.vertical, MarkepiSpacing.sm)
    }

    /// Panel column width for the landscape rail. A content-rich panel (text,
    /// signature controls, export) gets a comfortable width; a *sparse* panel —
    /// one showing nothing but an "Add …" button (logo/signature before anything
    /// is configured) — shrinks so it doesn't stretch a single button across the
    /// full width. Capped on iPad so the photo is never squeezed out, floored so
    /// rows don't collapse on the narrowest landscape windows.
    private func landscapePanelWidth(_ geometry: GeometryProxy, for tool: EditorTool) -> CGFloat {
        let full = min(420, max(320, geometry.size.width * 0.42))
        return isLandscapePanelSparse(tool) ? min(full, 280) : full
    }

    /// True when the tool's panel currently shows only its empty-state "Add …"
    /// button (no layer configured yet), so the panel can render compact.
    private func isLandscapePanelSparse(_ tool: EditorTool) -> Bool {
        switch tool {
        case .logo:
            return !viewModel.config.watermarks.contains { if case .image = $0 { return true }; return false }
        case .signature:
            return !viewModel.config.watermarks.contains { if case .signature = $0 { return true }; return false }
        default:
            return false
        }
    }

    // MARK: - Shared Media Controls

    /// True when `mediaControls` renders something (the batch strip and/or the
    /// video scrub bar). Drives the symmetric gap below the strip in portrait —
    /// applied only when there's content, so a lone photo doesn't get an empty
    /// band before the tool dock.
    private var mediaControlsHasContent: Bool {
        viewModel.hasMultiplePhotos || (viewModel.isCurrentVideo && !isBusy)
    }

    /// Media controls that sit below the photo. In portrait this holds the
    /// horizontal batch strip and the video scrub bar; in landscape the batch
    /// strip moves to the right rail (vertical — see `landscapeVerticalStrip`),
    /// so `includeStrip` is false there and only the scrub bar remains.
    @ViewBuilder
    private func mediaControls(includeStrip: Bool) -> some View {
        VStack(spacing: MarkepiSpacing.md) {
            if includeStrip && viewModel.hasMultiplePhotos {
                ThumbnailStripView(
                    photos: viewModel.photos,
                    currentIndex: $viewModel.currentIndex,
                    perItemOverrides: viewModel.perItemOverrides,
                    onItemTapped: { index in
                        selectedItemForOverride = IdentifiableIndex(value: index)
                    },
                    onReorder: { reordered in
                        viewModel.photos = reordered
                    },
                    allowsRemoval: !isBusy,
                    onRequestRemoval: { photo in
                        photoPendingRemoval = photo
                    }
                )
                .padding(.horizontal, MarkepiSpacing.md)
            }

            if viewModel.isCurrentVideo && !isBusy {
                VideoScrubBar(fraction: $viewModel.videoPreviewFraction)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isBusy)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.hasMultiplePhotos)
    }

    /// Landscape batch strip: a slim vertical column of thumbnails that lives in
    /// the right rail, between the open tool panel and the tool dock. Vertically
    /// centered and height-capped so a short batch hugs its content and a long
    /// one scrolls.
    private func landscapeVerticalStrip(_ geometry: GeometryProxy) -> some View {
        ThumbnailStripView(
            photos: viewModel.photos,
            currentIndex: $viewModel.currentIndex,
            perItemOverrides: viewModel.perItemOverrides,
            onItemTapped: { index in
                selectedItemForOverride = IdentifiableIndex(value: index)
            },
            onReorder: { reordered in
                viewModel.photos = reordered
            },
            allowsRemoval: !isBusy,
            onRequestRemoval: { photo in
                photoPendingRemoval = photo
            },
            axis: .vertical,
            // Reserve room for the Edit toggle + the rail's vertical padding.
            verticalMaxLength: max(160, geometry.size.height - 140)
        )
        .frame(maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Narrow Layout: Editor Controls

    /// Aspect ratio (width ÷ height) of the photo currently being previewed;
    /// falls back to 1 when no preview is loaded yet. Drives the display-aware
    /// panel cap so the layout adapts to the actual photo, not a fixed fraction.
    private var previewAspectRatio: CGFloat {
        guard let size = viewModel.previewImage?.size, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    /// Collapses the active tool's panel (shared by the portrait bottom dock and
    /// the landscape side rail).
    private func closeActiveTool() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
            activeTool = nil
        }
    }

    /// Tapping the photo closes an open tool panel — the replacement for the
    /// old swipe-down-to-dismiss gesture. Active only while a tool is open and
    /// nothing is rendering; the panel and dock sit above the photo, so taps on
    /// them are never intercepted.
    ///
    /// This has to be a SIMULTANEOUS gesture rather than an overlay. An overlay
    /// hit-tests the whole preview, so with a panel open it swallowed every
    /// touch on the photo — including the drag that places a watermark, which
    /// then only worked with all the panels closed. A simultaneous tap coexists
    /// with the drag: movement makes the tap fail, and a still tap dismisses.
    private var dismissesToolOnTap: GestureMask {
        activeTool != nil && !isBusy ? .all : .none
    }

    private func editorControls(_ geometry: GeometryProxy) -> some View {
        // The panel sizes to its own content (capped) via ToolPanelView. The cap
        // isn't a magic fraction of the screen — it's whatever height is left
        // after the photo and the dock. The photo is width-constrained in the
        // tall portrait region, so its drawn height is (display width ÷ aspect):
        // a tall portrait photo therefore reserves more height and gets a short
        // panel, while a wide landscape photo leaves the panel room to grow. A
        // floor keeps the panel usable (and a touch taller at large Dynamic Type)
        // when an extreme-aspect photo would otherwise crowd it out.
        let photoHeight = geometry.size.width / max(previewAspectRatio, 0.1)
        let dockReserve: CGFloat = 96   // tool dock + surrounding spacing
        let minPanelHeight: CGFloat = dynamicTypeSize >= .xxLarge ? 260 : 200
        let panelCap = max(minPanelHeight, geometry.size.height - photoHeight - dockReserve)

        return VStack(spacing: MarkepiSpacing.sm) {
            RenderProgressBanner(viewModel: viewModel)

            if let tool = activeTool, !isBusy {
                ToolPanelView(
                    tool: tool,
                    viewModel: viewModel,
                    onClose: closeActiveTool,
                    maxHeight: panelCap
                )
                // On wide bottom-dock containers (iPad portrait), pad the panel
                // toward a ~560pt centered column instead of stretching it
                // edge-to-edge; on iPhone the math clamps to the normal inset.
                .padding(.horizontal, max(MarkepiSpacing.md, (geometry.size.width - 560) / 2))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            EditorToolDock(activeTool: $activeTool)
                .padding(.horizontal, MarkepiSpacing.lg)
        }
        // Sit the dock right above the home-indicator safe area with no extra
        // gutter — the previous bottom padding left a visible empty band between
        // the dock and the display's bottom edge.
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: activeTool)
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
    @Binding var photoPendingRemoval: PhotoItem?

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
            .confirmationDialog(
                "Remove from Batch?",
                isPresented: Binding(
                    get: { photoPendingRemoval != nil },
                    set: { if !$0 { photoPendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let photo = photoPendingRemoval {
                        viewModel.removePhoto(id: photo.id)
                    }
                    photoPendingRemoval = nil
                }
                Button("Cancel", role: .cancel) {
                    photoPendingRemoval = nil
                }
            } message: {
                Text(removalMessage)
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
            .alert("Content Credentials in Batch", isPresented: Binding(
                get: { viewModel.showBatchC2PASigningNotice },
                set: { viewModel.showBatchC2PASigningNotice = $0 }
            )) {
                Button(batchC2PAContinueButtonTitle) {
                    Task { await viewModel.continueBatchAfterC2PASigningNotice() }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.showBatchC2PASigningNotice = false
                }
            } message: {
                Text(batchC2PAMessage)
            }
    }

    private var batchC2PAContinueButtonTitle: String {
        batchC2PADisclosure.alertContinueButtonTitle
    }

    private var batchC2PAMessage: String {
        batchC2PADisclosure.alertMessage
    }

    private var batchC2PADisclosure: BatchC2PASigningDisclosure {
        BatchC2PASigningDisclosure(
            signableImageCount: viewModel.batchSignableImageCount,
            videoCount: viewModel.batchVideoCount
        )
    }

    /// Media-type-aware body for the "Remove from Batch?" confirmation.
    private var removalMessage: String {
        guard let photo = photoPendingRemoval else {
            return "This item will be removed from the batch. This can't be undone."
        }
        let noun: String
        switch photo.mediaType {
        case .video: noun = "video"
        case .livePhoto: noun = "Live Photo"
        default: noun = "photo"
        }
        return "This \(noun) will be removed from the batch. This can't be undone."
    }
}

/// Sheet presentations (share, template list, per-item detail).
private struct SheetModifiers: ViewModifier {
    let viewModel: WatermarkViewModel
    @Binding var selectedItemForOverride: IdentifiableIndex?

    /// StoreKit's official review prompt (iOS 16+). The system presents the
    /// prompt and enforces its own 3-per-year cap; we only invoke it at a good
    /// moment. Requires `import StoreKit`.
    @Environment(\.requestReview) private var requestReview

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
                    ExportReceiptView(receipt: receipt) {
                        viewModel.showExportReceipt = false
                        viewModel.presentShareSheet()
                    }
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
        // The system "Save Image" (.saveToCameraRoll) re-encodes through
        // UIImage and strips the C2PA Content Credentials manifest from signed
        // exports. It's excluded and replaced by SaveToPhotosActivity, which
        // stores the ORIGINAL bytes via PHAssetCreationRequest so credentials
        // and all metadata survive into the photo library.
        if let batchResults = viewModel.batchResults, !batchResults.successes.isEmpty {
            ShareSheetView(
                activityItems: batchResults.successes,
                applicationActivities: [SaveToPhotosActivity(onFinished: handleSaveToPhotosResult)],
                excludedActivityTypes: [.saveToCameraRoll],
                onComplete: { completed in
                    // A completed batch share counts as one delight moment.
                    if completed { requestReviewAfterSuccessfulExport() }
                }
            ) {
                viewModel.cleanupTempFile()
            }
        } else if viewModel.fullResResult?.url != nil {
            ShareSheetView(
                activityItems: viewModel.singleShareItems,
                applicationActivities: [SaveToPhotosActivity(onFinished: handleSaveToPhotosResult)],
                excludedActivityTypes: [.saveToCameraRoll],
                onComplete: { completed in
                    if completed { requestReviewAfterSuccessfulExport() }
                }
            ) {
                viewModel.cleanupTempFile()
            }
        }
    }

    /// Surfaces Save-to-Photos failures (most commonly a denied add-photos
    /// permission) — a UIActivity has no view controller to alert from.
    private func handleSaveToPhotosResult(_ result: Result<Int, Error>) {
        if case .failure(let error) = result {
            viewModel.errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            viewModel.showError = true
        }
    }

    /// Records a successful export and, when the moment is right (enough prior
    /// successes, not already asked on this version), asks the system to show
    /// the App Store review prompt. Fired only when the user actually saved or
    /// shared a result — never on cancel — which is the natural point of
    /// accomplishment Apple recommends. A short delay lets the share sheet
    /// finish dismissing so the system prompt doesn't fight it for the screen.
    private func requestReviewAfterSuccessfulExport() {
        let manager = ReviewRequestManager.shared
        manager.recordSuccessfulExport()
        guard manager.shouldRequestReview() else { return }
        manager.markReviewRequested()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            requestReview()
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
    @Environment(StoreManager.self) private var store
    @AppStorage("appearancePreference") private var appearancePreference: String = AppearancePreference.system.rawValue

    #if DEBUG
    @AppStorage("debugAlwaysShowOnboarding") private var debugAlwaysShowOnboarding = false
    #endif

    var body: some View {
        @Bindable var store = store
        return NavigationStack {
            Form {
                #if DEBUG
                Section {
                    Toggle("Force Premium", isOn: $store.debugForcePremium)
                    Toggle("Always Show Onboarding", isOn: $debugAlwaysShowOnboarding)
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug builds only. Force Premium unlocks every premium feature without a purchase. Always Show Onboarding replays the welcome flow on every launch for testing. This section does not exist in App Store builds.")
                }
                #endif

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
                    Picker("Appearance", selection: $appearancePreference) {
                        ForEach(AppearancePreference.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                } footer: {
                    Text("Choose a light, dark, or system-following appearance for the editor.")
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

                Section {
                    NavigationLink {
                        ContentCredentialsInfoView()
                    } label: {
                        Label("About Content Credentials", systemImage: "checkmark.seal")
                    }
                } header: {
                    Text("Content Credentials")
                } footer: {
                    Text("Learn what C2PA Content Credentials prove, and when they're kept or removed as you share your image.")
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
            .frame(maxWidth: 640)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// "X.Y" from the bundle.
    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        return short
    }

    private static let termsURL = URL(string: "https://www.orbitaar.com/markepi/terms-of-use.html")!
    private static let privacyURL = URL(string: "https://www.orbitaar.com/markepi/privacy-policy.html")!
}

// MARK: - Window Background

/// Paints EVERY host UIKit layer behind the SwiftUI content with the backdrop
/// color, so no system-white shows during a device rotation. A SwiftUI
/// `.background` can't fix this and neither does setting one UIView: during
/// rotation UIKit snapshots the whole UIView stack *beneath* SwiftUI's drawing,
/// and the white flash is whichever opaque layer is exposed — the window (corner
/// gaps), `rootViewController.view`, or the `_UIHostingView` sitting on top of
/// it. `AncestorPaintingView` walks the full chain up to the window and paints
/// each, so none can flash its default `systemBackground` (white in light mode).
private struct WindowBackgroundColor: UIViewRepresentable {
    let color: UIColor

    func makeUIView(context: Context) -> AncestorPaintingView {
        let view = AncestorPaintingView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.paintColor = color
        return view
    }

    func updateUIView(_ uiView: AncestorPaintingView, context: Context) {
        uiView.paintColor = color
        uiView.paintAncestors()
    }
}

/// Walks every UIKit layer from this view up to the `UIWindow` and paints each
/// one's `backgroundColor`. One layer isn't enough: during a device rotation
/// UIKit snapshots the UIView stack *beneath* SwiftUI's drawing, and the white
/// flash is whichever opaque layer is exposed — `rootViewController.view`, the
/// `_UIHostingView` on top of it, or the window itself. Setting just the window
/// (gaps) or just the root view (covered by `_UIHostingView`) left the white
/// shape; a SwiftUI `.background` can't touch any of them. Re-applied from
/// `layoutSubviews` because rotation re-lays-out without changing the
/// representable's inputs (so `updateUIView` may not fire).
private final class AncestorPaintingView: UIView {
    var paintColor: UIColor = .clear

    override func didMoveToWindow() {
        super.didMoveToWindow()
        paintAncestors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        paintAncestors()
    }

    func paintAncestors() {
        guard let window = self.window else { return }
        window.backgroundColor = paintColor
        var ancestor = self.superview
        while let current = ancestor, current !== window {
            current.backgroundColor = paintColor
            ancestor = current.superview
        }
    }
}

// MARK: - Chrome Glass (device-live Liquid Glass)

private extension View {
    /// Real iOS-26 Liquid Glass on a physical device, material fallback on the
    /// simulator — used by the landscape custom chrome rails so they match the
    /// system toolbar's real glass on device.
    ///
    /// SwiftUI's `glassEffect` crashes (`EXC_BAD_ACCESS` in
    /// `swift_getOpaqueTypeMetadata`) on simulator runtimes whose Swift ABI
    /// doesn't match the build SDK — and we have no simulator matching the 26.2
    /// SDK, so it crashes on all of them. Because *merely compiling the call*
    /// into the render path triggers it, `#if targetEnvironment(simulator)` keeps
    /// the call OUT of simulator builds entirely (not just an unused runtime
    /// branch). On device the call is safe and renders the same glass the OS
    /// gives the toolbar. This is intentionally separate from the app-wide
    /// `markepiGlass` (compile-flag-gated, off everywhere) so the chrome can be
    /// device-live without changing the dock or panels. Pure SwiftUI, no UIKit.
    @ViewBuilder
    func chromeGlass<S: Shape>(in shape: S, isEnabled: Bool) -> some View {
        if isEnabled {
            #if targetEnvironment(simulator)
            background(.bar, in: shape)
            #else
            if #available(iOS 26, macOS 26, *) {
                glassEffect(.regular, in: shape)
            } else {
                background(.bar, in: shape)
            }
            #endif
        } else {
            self
        }
    }
}

// MARK: - Premium Crown Icon

/// The toolbar "upgrade" crown. It rests **grey** (a muted, non-shouty upsell);
/// for free users a warm **golden** glow sweeps across it right→left on a slow
/// loop, momentarily lighting the crown gold to draw the eye. Entitled users get
/// a calm, static gold crown (earned, no animation); Reduce Motion drops the
/// sweep and leaves the grey resting state.
private struct PremiumCrownIcon: View {
    let isPremium: Bool
    let reduceMotion: Bool

    /// Only free users get the attention-drawing sweep; Pro users have nothing
    /// to upsell, and Reduce Motion suppresses it.
    private var animate: Bool { !isPremium && !reduceMotion }

    /// Metallic gold: a light top edge falling to a deeper amber. Used as the
    /// static fill for Pro and as the colour the sweep paints for free users.
    private static let gold = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.91, blue: 0.60),
            Color(red: 0.99, green: 0.78, blue: 0.28),
            Color(red: 0.86, green: 0.58, blue: 0.12)
        ],
        startPoint: .top, endPoint: .bottom
    )

    /// The warm highlight band that travels across the grey crown.
    private static let goldGlow = LinearGradient(
        colors: [
            .clear,
            Color(red: 1.00, green: 0.82, blue: 0.34).opacity(0.85),
            Color(red: 1.00, green: 0.94, blue: 0.66),
            Color(red: 1.00, green: 0.82, blue: 0.34).opacity(0.85),
            .clear
        ],
        startPoint: .leading, endPoint: .trailing
    )

    @State private var sweep = false

    var body: some View {
        Image(systemName: "crown.fill")
            .symbolRenderingMode(.monochrome)
            // Rest state: gold when entitled, otherwise a muted grey.
            .foregroundStyle(isPremium ? AnyShapeStyle(Self.gold)
                                       : AnyShapeStyle(Color.secondary))
            .overlay {
                if animate {
                    GeometryReader { geo in
                        // A golden band, masked to the crown, sliding from
                        // off-right (+w) to off-left (−w): a right→left sweep that
                        // lights the grey crown gold as it passes.
                        Self.goldGlow
                            .frame(width: geo.size.width * 0.85)
                            .offset(x: sweep ? -geo.size.width * 1.15 : geo.size.width * 1.15)
                            .animation(
                                .easeInOut(duration: 1.1)
                                    .delay(1.4)
                                    .repeatForever(autoreverses: false),
                                value: sweep
                            )
                    }
                    .mask {
                        Image(systemName: "crown.fill")
                            .symbolRenderingMode(.monochrome)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear { sweep = animate }
            .onChange(of: animate) { _, active in sweep = active }
    }
}

// MARK: - Loading Overlay

/// A branded, animated full-screen loading overlay — a rotating accent arc
/// around a pulsing app glyph, on a dimmed glass card. Used wherever the app
/// would otherwise appear frozen (media import, share preparation).
struct LoadingOverlay: View {
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive = false

    var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(isActive ? 360 : 0))
                        .animation(
                            reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false),
                            value: isActive
                        )
                    Image(systemName: "photo.on.rectangle.angled")
                        .markepiTypography(.glyph)
                        .foregroundStyle(.white)
                        .scaleEffect(isActive ? 1.08 : 0.92)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                            value: isActive
                        )
                }
                .frame(width: MarkepiSizing.loadingGlyphSize, height: MarkepiSizing.loadingGlyphSize)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: MarkepiRadius.xxxl, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .onAppear { isActive = true }
        .onDisappear { isActive = false }
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
                .frame(width: MarkepiSizing.videoScrubBarPercentWidth, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: MarkepiRadius.xxl, style: .continuous)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: MarkepiRadius.xxl, style: .continuous))
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
