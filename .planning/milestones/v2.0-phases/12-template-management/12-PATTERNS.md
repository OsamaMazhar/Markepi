# Phase 12: Template Management - Pattern Map

**Mapped:** 2026-06-19
**Files analyzed:** 16 (7 new, 9 modified)
**Analogs found:** 16 / 16

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Packages/WatermarkCore/Sources/WatermarkCore/Models/Template.swift` (NEW) | model | CRUD | `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` | exact |
| `Packages/WatermarkCore/Sources/WatermarkCore/Storage/TemplateStore.swift` (NEW) | service/store | CRUD | `Packages/WatermarkCore/Sources/WatermarkCore/Storage/AppGroupConfigSync.swift` + `App/ViewModels/WatermarkViewModel.swift` | combined |
| `Packages/WatermarkCore/Sources/WatermarkCore/Storage/MigrationChain.swift` (NEW) | utility | transform | `Packages/WatermarkCore/Sources/WatermarkCore/Engine/PipelineError.swift` | partial |
| `App/Views/Templates/TemplateListView.swift` (NEW) | component/view | request-response | `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` + `Packages/WatermarkCore/Sources/WatermarkCore/UI/LayerListView.swift` | combined |
| `App/Views/Templates/TemplateRowView.swift` (NEW) | component/view | request-response | `Packages/WatermarkCore/Sources/WatermarkCore/UI/LayerListView.swift` (layerRow method) | role-match |
| `App/Views/Templates/TemplatePreviewThumbnail.swift` (NEW) | component/view | file-I/O | `App/Views/Navigation/ThumbnailStripView.swift` (thumbnailCell) | role-match |
| `App/Views/Templates/SaveTemplateAlertModifier.swift` (NEW) | component/view | request-response | `App/Views/Common/ErrorAlertModifier.swift` | exact |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` (MODIFY) | component/view | request-response | (self: existing ControlsView) | exact |
| `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` (MODIFY) | protocol | request-response | (self: existing protocol) | exact |
| `App/Views/ContentView.swift` (MODIFY) | view | request-response | (self: existing `.sheet`/`.alert` on ContentView) | exact |
| `App/ViewModels/WatermarkViewModel.swift` (MODIFY) | viewModel | CRUD + event-driven | (self: existing ViewModel with `didSet` sync) | exact |
| `ShareExtension/ShareExtensionViewModel.swift` (MODIFY) | viewModel | CRUD + event-driven | (self: existing ViewModel with `didSet` sync) | exact |
| `PhotoEditExtension/PhotosExtensionViewModel.swift` (MODIFY) | viewModel | CRUD + event-driven | (self: existing ViewModel with `didSet` sync) | exact |
| `App/Info.plist` (MODIFY) | config | — | `App/Info.plist` (existing `CFBundleDocumentTypes` + `UTExportedTypeDeclarations`) | exact |
| `ShareExtension/Info.plist` (MODIFY) | config | — | `App/Info.plist` (same UTI declarations for import support) | exact |
| `PhotoEditExtension/Info.plist` (MODIFY) | config | — | `App/Info.plist` (same UTI declarations for import support) | exact |

## Pattern Assignments

### `Template.swift` (model, CRUD) — NEW

**Analog:** `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift`

**Struct declaration pattern** (lines 1–9):
```swift
import CoreImage // OR Foundation (Template only needs Foundation)

/// Top-level configuration for a watermark processing operation.
///
/// ...
/// Consumed by `WatermarkEngine.process(url:config:)` to build the filter graph.
public struct WatermarkConfiguration: Sendable, Codable {
```

**Template should replicate:**
```swift
import Foundation

/// A saved watermark template with metadata and schema versioning.
///
/// Wraps a `WatermarkConfiguration` with name, default flag,
/// creation date, and a `schemaVersion` field for forward-compatible
/// migration. Consumed by `TemplateStore` for persistence in
/// App Group UserDefaults.
public struct Template: Sendable, Codable, Identifiable {
```

**CodingKeys pattern** (lines 28–30):
```swift
    enum CodingKeys: String, CodingKey {
        case watermarks, padding, whiteFrame, outputFormat, outputQuality
    }
```

**Custom decode with defaults pattern** (lines 51–58):
```swift
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.watermarks = try container.decode([WatermarkLayer].self, forKey: .watermarks)
        self.padding = try container.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 20
        self.whiteFrame = try container.decodeIfPresent(WhiteFrameConfig.self, forKey: .whiteFrame)
        self.outputFormat = try container.decodeIfPresent(OutputFormat.self, forKey: .outputFormat) ?? .preserveSource
        self.outputQuality = try container.decodeIfPresent(Float.self, forKey: .outputQuality) ?? 1.0
    }
```

**Key pattern: use `decodeIfPresent` + `?? defaultValue` for every field** — this is how future fields get added without breaking old templates. Follow this exact pattern.

**Init with defaults pattern** (lines 39–49):
```swift
    public init(
        watermarks: [WatermarkLayer] = [],
        whiteFrame: WhiteFrameConfig? = nil,
        outputFormat: OutputFormat = .preserveSource,
        outputQuality: Float = 1.0
    ) {
        self.watermarks = watermarks
        self.whiteFrame = whiteFrame
        self.outputFormat = outputFormat
        self.outputQuality = outputQuality
    }
```

**Static constant pattern** (from `AppGroupConfigSync.swift` lines 17–20):
```swift
    public static let suiteName = "group.com.watermark.app"
    private static let configKey = "watermarkConfiguration"
```
→ Template should use: `public static let currentSchemaVersion = 1`

---

### `TemplateStore.swift` (service/store, CRUD) — NEW

**Analog 1 (persistence):** `Packages/WatermarkCore/Sources/WatermarkCore/Storage/AppGroupConfigSync.swift`

**UserDefaults suite pattern** (lines 15–20):
```swift
    /// App Group suite name (placeholder — developer must configure in Xcode).
    /// Must match the App Group ID in both the main app and extension entitlements.
    public static let suiteName = "group.com.watermark.app"

    /// Key used to store the serialized `WatermarkConfiguration` JSON data.
    private static let configKey = "watermarkConfiguration"
```

**Save pattern** (lines 30–42):
```swift
    public static func save(_ config: WatermarkConfiguration) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            os_log(.error, "[AppGroupConfigSync] Failed to open UserDefaults suite '%@'", suiteName)
            return
        }

        do {
            let data = try JSONEncoder().encode(config)
            defaults.set(data, forKey: configKey)
        } catch {
            os_log(.error, "[AppGroupConfigSync] Failed to encode config: %@", error.localizedDescription)
        }
    }
```

**Load pattern** (lines 50–66):
```swift
    public static func load() -> WatermarkConfiguration? {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            os_log(.error, "[AppGroupConfigSync] Failed to open UserDefaults suite '%@'", suiteName)
            return nil
        }

        guard let data = defaults.data(forKey: configKey) else {
            return nil // No saved config yet — expected on first launch
        }

        do {
            return try JSONDecoder().decode(WatermarkConfiguration.self, from: data)
        } catch {
            os_log(.error, "[AppGroupConfigSync] Failed to decode config: %@", error.localizedDescription)
            return nil
        }
    }
```

**Analog 2 (Observable singleton + @MainActor):** `App/ViewModels/WatermarkViewModel.swift`

**Class declaration pattern** (lines 14–15):
```swift
@Observable @MainActor
final class WatermarkViewModel: WatermarkConfigurable {
```

**TemplateStore should replicate:**
```swift
@Observable @MainActor
public final class TemplateStore {
    public static let shared = TemplateStore()
```

**Note:** Unlike `WatermarkViewModel`, `TemplateStore` does NOT conform to `WatermarkConfigurable`. It is a standalone singleton store.

**Private init pattern** (line 52–58 of WatermarkViewModel.swift):
```swift
    init() {
        // Load saved config from App Group if available
        if let saved = AppGroupConfigSync.load() {
            config = saved
        }
```
→ TemplateStore's `private init()` calls `loadTemplates()`.

**Logger pattern** (from AppGroupConfigSync.swift lines 2, 32):
```swift
import os.log

os_log(.error, "[AppGroupConfigSync] Failed to open UserDefaults suite '%@'", suiteName)
```
→ TemplateStore uses `os_log(.error, "[TemplateStore] ...")` for all error paths.

**Error type pattern** (from `PipelineError.swift` lines 8–9):
```swift
public enum PipelineError: Error, LocalizedError, Sendable, Equatable {
    /// The source URL does not contain valid image data
    case invalidSource
```

**TemplateStoreError should replicate** (in same file, bottom):
```swift
public enum TemplateStoreError: LocalizedError {
    case emptyName
    case duplicateName(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Template name cannot be empty."
        case .duplicateName(let name):
            return "A template named \"\(name)\" already exists. Please choose a different name."
        case .notFound:
            return "Template not found."
        }
    }
}
```

**Caches directory pattern** (from `TempFileManager.swift` lines 17–25):
```swift
        let cachesDir = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let filename = "watermark_\(UUID().uuidString).\(FormatDetector.fileExtension(for: uti))"
        return cachesDir.appendingPathComponent(filename)
```

**Thumbnail cache dir should replicate:**
```swift
    private var thumbnailCacheDir: URL? {
        try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("template_thumbnails")
    }
```

---

### `MigrationChain.swift` (utility, transform) — NEW

**Analog:** `PipelineError.swift` (registry-style enum + dictionary mapping pattern)

**Registry pattern** (dict mapping version → migration closure):
```swift
    private let migrationChain: [Int: (inout Template) -> Void] = [
        // Example for future use:
        // 1: { template in /* v1→v2 migration */ }
    ]
```

This file is a thin registry — 20 lines max. It can live inside `TemplateStore.swift` rather than being a separate file. Pattern identical to RESEARCH.md code example.

---

### `TemplateListView.swift` (component/view, request-response) — NEW

**Analog 1 (generic ViewModel + init pattern):** `ControlsView.swift` (lines 1–28)

```swift
import SwiftUI
import WatermarkCore

/// Composite view combining all watermarking controls...
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel...
public struct ControlsView<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }
```

**TemplateListView should replicate the generic pattern:**
```swift
import SwiftUI
import WatermarkCore

public struct TemplateListView<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel

    // Local state for alerts
    @State private var showRenameAlert = false
    @State private var renameTemplateID: UUID?
    @State private var renameText = ""

    public init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }
```

**Analog 2 (List/ForEach with rows):** `LayerListView.swift` (lines 20–35)

```swift
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.config.watermarks.enumerated()), id: \.offset) { index, layer in
                        layerRow(index: index, layer: layer)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))

                        if index < viewModel.config.watermarks.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
```

**Template list should replicate:**
```swift
    public var body: some View {
        List {
            ForEach(TemplateStore.shared.templates) { template in
                TemplateRowView(
                    template: template,
                    sourceURL: viewModel.currentPhoto?.sourceURL
                )
                .onTapGesture {
                    viewModel.applyTemplate(template)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        TemplateStore.shared.delete(id: template.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        renameTemplateID = template.id
                        renameText = template.name
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        try? TemplateStore.shared.duplicate(template)
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    if template.isDefault {
                        Button(role: .destructive) {
                            try? TemplateStore.shared.removeDefault(id: template.id)
                        } label: {
                            Label("Unset as Default", systemImage: "star.slash")
                        }
                    } else {
                        Button {
                            try? TemplateStore.shared.setDefault(id: template.id)
                        } label: {
                            Label("Set as Default", systemImage: "star")
                        }
                    }
                }
            }
        }
        .alert("Rename Template", isPresented: $showRenameAlert) {
            TextField("Template name", text: $renameText)
            Button("Save") {
                if let id = renameTemplateID {
                    try? TemplateStore.shared.rename(id: id, to: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .overlay {
            if TemplateStore.shared.templates.isEmpty {
                ContentUnavailableView(
                    "No Templates",
                    systemImage: "doc.text",
                    description: Text("Save your current watermark configuration as a template to reuse it anytime.")
                )
            }
        }
    }
```

---

### `TemplateRowView.swift` (component/view, request-response) — NEW

**Analog:** `LayerListView.swift` `layerRow` method (lines 38–69)

```swift
    @ViewBuilder
    private func layerRow(index: Int, layer: WatermarkLayer) -> some View {
        Button {
            viewModel.activeLayerIndex = index
        } label: {
            HStack(spacing: 12) {
                Image(systemName: layerIcon(for: layer))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(layerDescription(for: layer))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        viewModel.removeLayer(at: index)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Remove layer: \(layerDescription(for: layer))")
                .accessibilityHint("Double tap to remove this watermark layer")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
```

**TemplateRowView should replicate the HStack row pattern:**
```swift
import SwiftUI
import WatermarkCore

struct TemplateRowView: View {
    let template: Template
    let sourceURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            TemplatePreviewThumbnail(template: template, sourceURL: sourceURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(template.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if template.isDefault {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .accessibilityLabel("Default template")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
```

---

### `TemplatePreviewThumbnail.swift` (component/view, file-I/O) — NEW

**Analog:** `ThumbnailStripView.swift` `thumbnailCell` method (lines 37–50)

```swift
    @ViewBuilder
    private func thumbnailCell(for photo: PhotoItem, index: Int) -> some View {
        let isCurrent = index == currentIndex

        Group {
            if let thumbnail = photo.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                placeholderCell
            }
        }
        .frame(width: 60, height: 60)
```

**TemplatePreviewThumbnail should replicate the async thumbnail loading pattern:**
```swift
import SwiftUI
import WatermarkCore
import CoreImage

/// Renders a 48×48pt watermark preview for a template applied to current media.
struct TemplatePreviewThumbnail: View {
    let template: Template
    let sourceURL: URL?
    @State private var thumbnail: UIImage?
    @State private var isLoading = false

    private let engine = WatermarkEngine.shared
    private let store = TemplateStore.shared

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if isLoading {
                ProgressView()
                    .frame(width: 48, height: 48)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .task {
            await generateThumbnail()
        }
    }
```

The `generateThumbnail()` method follows the existing `createThumbnail()` static function pattern in `WatermarkViewModel.swift` (lines 703–714):
```swift
private func createThumbnail(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}
```

---

### `SaveTemplateAlertModifier.swift` (component/view, request-response) — NEW

**Analog:** `App/Views/Common/ErrorAlertModifier.swift` (lines 1–17)

```swift
import SwiftUI

struct ErrorAlertModifier: ViewModifier {
    @Binding var errorMessage: String?
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .alert("Rendering Error", isPresented: $isPresented) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
    }
}
```

**SaveTemplateAlertModifier should replicate the ViewModifier pattern:**
```swift
import SwiftUI
import WatermarkCore

/// A reusable alert modifier for saving the current watermark configuration as a named template.
struct SaveTemplateAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onSave: (String) -> Void

    @State private var templateName = ""

    func body(content: Content) -> some View {
        content
            .alert("Save Template", isPresented: $isPresented) {
                TextField("Template name", text: $templateName)
                Button("Save") {
                    let trimmed = templateName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onSave(trimmed)
                        templateName = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    templateName = ""
                }
            } message: {
                Text("Enter a name for your saved watermark template.")
            }
    }
}

extension View {
    func saveTemplateAlert(isPresented: Binding<Bool>, onSave: @escaping (String) -> Void) -> some View {
        modifier(SaveTemplateAlertModifier(isPresented: isPresented, onSave: onSave))
    }
}
```

---

### `ControlsView.swift` (MODIFY — add Save Template button)

**Analog:** (self — existing ControlsView VStack pattern)

**Existing VStack layout pattern** (lines 31–51):
```swift
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                TextWatermarkInputView(viewModel: viewModel)
                PositionGridView(viewModel: viewModel)
                ScaleStepperView(viewModel: viewModel)
                LogoPickerView(viewModel: viewModel)
                SignatureCaptureView(viewModel: viewModel)
                WhiteFrameToggleView(viewModel: viewModel)
                LayerListView(viewModel: viewModel)

                exportOptionsDisclosure

                Divider()
                    .padding(.vertical, 4)

                shareButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
```

**Insert after `LayerListView` and before `exportOptionsDisclosure`:**

```swift
                // NEW: Save Template button (Phase 12)
                Divider()
                    .padding(.horizontal, -16)

                saveTemplateButton

                Divider()
                    .padding(.horizontal, -16)
```

**Button pattern** (from existing shareButton in ControlsView, lines 117–131):
```swift
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
```

**Save Template button (new private var):**
```swift
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
```

---

### `WatermarkConfigurable.swift` (MODIFY — add protocol requirements)

**Analog:** (self — existing protocol property and method pattern)

**Existing property pattern** (lines 17–28):
```swift
@MainActor
public protocol WatermarkConfigurable: AnyObject {
    var config: WatermarkConfiguration { get set }
    var activeLayerIndex: Int { get set }
    var renderingState: RenderingState { get }
    var whiteFrameEnabled: Bool { get }
    var outputFormat: OutputFormat { get set }
    var outputQuality: Float { get set }
    var sourceHasHDR: Bool { get }
    var sourceFormatLabel: String? { get }
    var errorMessage: String? { get set }
    var showError: Bool { get set }
```

**Add these properties to the protocol:**
```swift
    // Template Management (Phase 12)
    var showSaveTemplateAlert: Bool { get set }
    var showTemplateList: Bool { get set }
```

**Existing method requirement pattern** (lines 29–38):
```swift
    func addLogoLayer(pngData: Data)
    func addSignatureLayer(strokeData: Data, inkColor: CGColor, strokeWidth: CGFloat)
    func removeLayer(at index: Int)
    func updateLayerPosition(at index: Int, position: WatermarkPosition)
    func updateLayerScale(at index: Int, scale: CGFloat)
    func toggleWhiteFrame()
```

**Add these method requirements:**
```swift
    /// Applies a template's configuration to the current state.
    /// Called from TemplateListView when a row is tapped.
    func applyTemplate(_ template: Template)
```

**Add default implementation in the extension** (watermarkConfigurable extension, lines 51-134):
```swift
    public func applyTemplate(_ template: Template) {
        config = template.config
        // config.didSet triggers AppGroupConfigSync.save(config) automatically
    }
```

---

### `ContentView.swift` (MODIFY — add template sheet + save alert)

**Analog:** (self — existing `.sheet` and `.alert` modifier patterns)

**Existing `.sheet` pattern** (lines 79–85):
```swift
                .sheet(isPresented: $viewModel.showShareSheet) {
                    if let url = viewModel.fullResResult?.url {
                        ShareSheetView(activityItems: [url]) {
                            viewModel.cleanupTempFile()
                        }
                    }
                }
```

**Existing `.alert` pattern** (lines 64–70):
```swift
                .alert("Rendering Error", isPresented: $viewModel.showError) {
                    Button("OK") {
                        viewModel.errorMessage = nil
                    }
                } message: {
                    Text(viewModel.errorMessage ?? "Unknown error")
                }
```

**Add these modifiers after existing `.alert` chain (before `.task`):**
```swift
                // Phase 12: Template list sheet
                .sheet(isPresented: $viewModel.showTemplateList) {
                    NavigationStack {
                        TemplateListView(viewModel: viewModel)
                            .navigationTitle("Templates")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                // Phase 12: Save template alert
                .saveTemplateAlert(isPresented: $viewModel.showSaveTemplateAlert) { name in
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
```

---

### `WatermarkViewModel.swift` (MODIFY — add template properties + methods)

**Analog:** (self — existing property declaration + method patterns)

**Existing property pattern** (lines 36–41):
```swift
    var renderingState: RenderingState = .idle
    var fullResResult: ProcessingResult?
    var showPicker: Bool = false
    var showShareSheet: Bool = false
    var showCancelAlert: Bool = false
    var errorMessage: String?
    var showError: Bool = false
```

**Add these properties:**
```swift
    // Phase 12: Template Management
    var showSaveTemplateAlert: Bool = false
    var showTemplateList: Bool = false
```

**Existing config didSet pattern** (lines 19–29):
```swift
    var config = WatermarkConfiguration(watermarks: [
        .text(
            TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
            position: .bottomRight,
            scale: 0.15,
            opacity: 1.0,
            isVisible: true
        )
    ]) {
        didSet { AppGroupConfigSync.save(config) }
    }
```

**Add template auto-apply method** (after `handleSelection`, at end of media-import section):
```swift
    /// Auto-applies the default template config on new media import (Phase 12).
    func applyDefaultTemplateIfNeeded() {
        guard let defaultTemplate = TemplateStore.shared.defaultTemplate else { return }
        config = defaultTemplate.config
        // config.didSet triggers AppGroupConfigSync.save(config) automatically
    }
```

**Call this method INSIDE the `handleSelection` Task, after the media load completes:**

At line 194 (after `photos = loaded` and `currentIndex = 0`), add:
```swift
            // Phase 12: Auto-apply default template on import
            if let defaultTemplate = TemplateStore.shared.defaultTemplate {
                config = defaultTemplate.config
            }
```

**Note:** The `applyTemplate(_:)` method is provided as a default implementation in `WatermarkConfigurable` extension — no need to override in `WatermarkViewModel` unless customization is required.

---

### `ShareExtensionViewModel.swift` (MODIFY — add default template auto-apply)

**Analog:** (self — existing media-load + config init patterns)

**Existing config init pattern** (lines 143–155):
```swift
    init() {
        let defaultConfig = WatermarkConfiguration(watermarks: [
            .text(
                TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                position: .bottomRight,
                scale: 0.15,
                opacity: 1.0,
                isVisible: true
            )
        ])
        self.config = AppGroupConfigSync.load() ?? defaultConfig
    }
```

**Add `showSaveTemplateAlert` and `showTemplateList` to satisfy protocol conformance** (at the end of property declarations):
```swift
    // Phase 12: Template Management (protocol conformance — extension doesn't show UI)
    var showSaveTemplateAlert: Bool = false
    var showTemplateList: Bool = false
```

**Add auto-apply at the end of `loadPhotoFromProvider`** (after line 261 `await generatePreview()`):
```swift
            // Phase 12: Auto-apply default template on import
            if let defaultTemplate = TemplateStore.shared.defaultTemplate {
                config = defaultTemplate.config
            }
```

**Add auto-apply at the end of `loadVideoFromProvider`** (after line 306 `await generateVideoPreview()`):
```swift
            // Phase 12: Auto-apply default template on import
            if let defaultTemplate = TemplateStore.shared.defaultTemplate {
                config = defaultTemplate.config
            }
```

---

### `PhotosExtensionViewModel.swift` (MODIFY — add default template auto-apply)

**Analog:** (self — existing `startEditing` lifecycle pattern)

**Existing config init pattern** (lines 110–122):
```swift
    init() {
        let defaultConfig = WatermarkConfiguration(watermarks: [
            .text(
                TextWatermarkInput(text: "", fontSize: 48, color: CGColor(gray: 1, alpha: 1), opacity: 1.0),
                position: .bottomRight,
                scale: 0.15,
                opacity: 1.0,
                isVisible: true
            )
        ])
        self.config = AppGroupConfigSync.load() ?? defaultConfig
    }
```

**Add protocol conformance properties** (same as ShareExtension):
```swift
    // Phase 12: Template Management (protocol conformance — extension doesn't show UI)
    var showSaveTemplateAlert: Bool = false
    var showTemplateList: Bool = false
```

**Add auto-apply at the end of `startEditing()`** (after line 177, before the closing `}`):
```swift
        // Phase 12: Auto-apply default template on import
        if let defaultTemplate = TemplateStore.shared.defaultTemplate {
            self.config = defaultTemplate.config
        }
```

**IMPORTANT — ordering:** Auto-apply AFTER `decodeAdjustmentData` (re-edit scenario should restore previous config, not default template). The existing code at lines 169–173 already loads saved config from adjustment data:
```swift
        if let adjustmentData = input.adjustmentData,
           canHandle(adjustmentData),
           let savedConfig = decodeAdjustmentData(adjustmentData) {
            self.config = savedConfig
        }
```
So the auto-apply should be conditional — only apply default template when NO adjustment data exists (fresh edit, not re-edit):
```swift
        // Phase 12: Auto-apply default template on fresh edit only (not re-edit)
        if input.adjustmentData == nil,
           let defaultTemplate = TemplateStore.shared.defaultTemplate {
            self.config = defaultTemplate.config
        }
```

---

### Info.plist files (MODIFY — add `.watermarktemplate` UTI)

**Analog:** `App/Info.plist` existing `CFBundleDocumentTypes` array (lines 5–34)

**Pattern for adding declarations:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
```

**Add to ALL THREE Info.plist files** (App, ShareExtension, PhotoEditExtension):

Add a new top-level key `UTExportedTypeDeclarations` (after existing `CFBundleDocumentTypes` in App/Info.plist; after `CFBundleDisplayName` in extension plists):

```xml
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.watermark.app.template</string>
            <key>UTTypeDescription</key>
            <string>Watermark Template</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>watermarktemplate</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>application/json</string>
                </array>
            </dict>
        </dict>
    </array>
```

**App/Info.plist** — Add `UTImportedTypeDeclarations` and `LSItemContentTypes` entry for template file support in `CFBundleDocumentTypes`:

```xml
        <dict>
            <key>CFBundleTypeName</key>
            <string>Watermark Template</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.watermark.app.template</string>
            </array>
        </dict>
```

Add inside the existing `CFBundleDocumentTypes` array.

---

## Shared Patterns

### Observable + @MainActor Singleton

**Source:** `App/ViewModels/WatermarkViewModel.swift` (lines 14–15)
```swift
@Observable @MainActor
final class WatermarkViewModel: WatermarkConfigurable {
```
**Apply to:** `TemplateStore.swift` — use `@Observable @MainActor public final class TemplateStore` with `public static let shared = TemplateStore()` and `private init()`.

### App Group UserDefaults Persistence

**Source:** `AppGroupConfigSync.swift` (entire file, 67 lines)
```swift
public static let suiteName = "group.com.watermark.app"
private static let configKey = "watermarkConfiguration"

public static func save(_ config: WatermarkConfiguration) {
    guard let defaults = UserDefaults(suiteName: suiteName) else { ... return }
    let data = try JSONEncoder().encode(config)
    defaults.set(data, forKey: configKey)
}
```
**Apply to:** `TemplateStore.swift` — same suite name, new key `"com.watermark.app.templates"`. Load/save via `JSONEncoder`/`JSONDecoder`.

### Codable with decodeIfPresent defaults

**Source:** `WatermarkConfiguration.swift` (lines 51–58)
```swift
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.watermarks = try container.decode([WatermarkLayer].self, forKey: .watermarks)
    self.padding = try container.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 20
    self.outputFormat = try container.decodeIfPresent(OutputFormat.self, forKey: .outputFormat) ?? .preserveSource
}
```
**Apply to:** `Template.swift` — every field uses `decodeIfPresent` with a sensible default. This is the foundation for schema migration compatibility.

### Logging via os_log

**Source:** `AppGroupConfigSync.swift` (lines 2, 32, 40, 52, 63)
```swift
import os.log

os_log(.error, "[AppGroupConfigSync] Failed to open UserDefaults suite '%@'", suiteName)
os_log(.error, "[AppGroupConfigSync] Failed to encode config: %@", error.localizedDescription)
os_log(.error, "[AppGroupConfigSync] Failed to decode config: %@", error.localizedDescription)
```
**Apply to:** All new Storage files — use `os_log(.error, "[TemplateStore] ...")` for persistence failures.

### LocalizedError enum

**Source:** `PipelineError.swift` (lines 8–9, 92–145)
```swift
public enum PipelineError: Error, LocalizedError, Sendable, Equatable {
    case invalidSource
    // ...
    public var errorDescription: String? { ... }
}
```
**Apply to:** `TemplateStoreError` in `TemplateStore.swift` — use `LocalizedError` conformance with `errorDescription` computed property. Inherit `Sendable` but no need for `Equatable` on error enums with associated `String` values.

### ViewModifier + extension on View

**Source:** `ErrorAlertModifier.swift` (lines 1–17)
```swift
struct ErrorAlertModifier: ViewModifier {
    @Binding var errorMessage: String?
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert(...)
    }
}

// No extension on View used, but it's the standard pattern
```
**Apply to:** `SaveTemplateAlertModifier.swift` — same structure plus a `View` extension for the `.saveTemplateAlert(isPresented:onSave:)` convenience modifier.

### Generic View with ViewModel Constraint

**Source:** `ControlsView.swift` (lines 12–13)
```swift
public struct ControlsView<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel
```
**Apply to:** `TemplateListView.swift` — same generic constraint pattern with `@State var viewModel: ViewModel`.

### config.didSet → AppGroupConfigSync.save

**Source:** `WatermarkViewModel.swift` (line 29)
```swift
    didSet { AppGroupConfigSync.save(config) }
```
**Apply to:** All ViewModels and Template auto-apply — setting `config` triggers the existing sync mechanism. No new sync code needed.

### Image Task-Based Async Load with Task.sleep debounce

**Source:** `WatermarkViewModel.swift` (lines 235–251), `ShareExtensionViewModel.swift` (lines 477–504)
```swift
    func generatePreview() async {
        isGeneratingPreview = true
        defer { isGeneratingPreview = false }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        // ... process ...
    }
```
**Apply to:** `TemplatePreviewThumbnail` — use `.task { await generateThumbnail() }` for lazy loading, with cache-first then engine render.

---

## No Analog Found

No files lack an analog. All 16 files have close matches in the existing codebase. The closest match for `MigrationChain.swift` is `PipelineError` (both are registry structures), but since `MigrationChain` is a thin dictionary registry, the RESEARCH.md recommends inlining it into `TemplateStore.swift` rather than a standalone file.

## Metadata

**Analog search scope:** `App/`, `Packages/WatermarkCore/`, `ShareExtension/`, `PhotoEditExtension/`
**Files scanned:** 17 analog source files + 3 Info.plist files
**Pattern extraction date:** 2026-06-19
