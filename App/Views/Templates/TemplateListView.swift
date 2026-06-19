import SwiftUI
import UniformTypeIdentifiers
import WatermarkCore

/// Full template library sheet with scrollable list, context menus,
/// swipe-to-delete, and .watermarktemplate import.
///
/// Generic over any `WatermarkConfigurable & Observable` ViewModel
/// matching the `ControlsView` pattern.
///
/// Presented as a sheet from `ContentView` (wired in Plan 04).
public struct TemplateListView<ViewModel: WatermarkConfigurable & Observable>: View {
    @State var viewModel: ViewModel

    /// The current media source URL used for rendering preview thumbnails.
    /// Wired by ContentView in Plan 04 from `viewModel.currentPhoto?.sourceURL`.
    private let sourceURL: URL?

    // MARK: - Alert State

    @State private var showRenameAlert = false
    @State private var renameTemplateID: UUID?
    @State private var renameText = ""

    @State private var showDeleteConfirmation = false
    @State private var deleteTemplateID: UUID?

    // MARK: - Import State

    @State private var showFileImporter = false
    @State private var importError: String?

    // MARK: - Export State

    @State private var showExportSheet = false
    @State private var exportShareURL: URL?

    // MARK: - Init

    public init(viewModel: ViewModel, sourceURL: URL? = nil) {
        self.viewModel = viewModel
        self.sourceURL = sourceURL
    }

    // MARK: - Body

    public var body: some View {
        List {
            ForEach(TemplateStore.shared.templates) { template in
                TemplateRowView(
                    template: template,
                    sourceURL: sourceURL
                )
                .onTapGesture {
                    viewModel.applyTemplate(template)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteTemplateID = template.id
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    // Apply
                    Button {
                        viewModel.applyTemplate(template)
                    } label: {
                        Label("Apply", systemImage: "checkmark")
                    }

                    // Rename
                    Button {
                        renameTemplateID = template.id
                        renameText = template.name
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    // Duplicate
                    Button {
                        try? TemplateStore.shared.duplicate(template)
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }

                    // Set / Remove Default
                    if template.isDefault {
                        Button {
                            try? TemplateStore.shared.removeDefault(id: template.id)
                        } label: {
                            Label("Remove Default", systemImage: "star.slash")
                        }
                    } else {
                        Button {
                            try? TemplateStore.shared.setDefault(id: template.id)
                        } label: {
                            Label("Set as Default", systemImage: "star")
                        }
                    }

                    // Export
                    Button {
                        exportTemplate(template)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }

                    // Delete
                    Button(role: .destructive) {
                        deleteTemplateID = template.id
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showFileImporter = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                }
            }
        }
        // Rename alert
        .alert("Rename Template", isPresented: $showRenameAlert) {
            TextField("Template name", text: $renameText)
            Button("Save") {
                if let id = renameTemplateID {
                    try? TemplateStore.shared.rename(id: id, to: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        // Delete confirmation alert
        .alert("Delete Template?", isPresented: $showDeleteConfirmation) {
            Button("Delete Template", role: .destructive) {
                if let id = deleteTemplateID {
                    TemplateStore.shared.delete(id: id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let id = deleteTemplateID,
               let template = TemplateStore.shared.templates.first(where: { $0.id == id }) {
                Text("Template \"\(template.name)\" will be permanently deleted.")
            }
        }
        // Import error alert
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            if let error = importError {
                Text(error)
            }
        }
        // Empty state overlay
        .overlay {
            if TemplateStore.shared.templates.isEmpty {
                ContentUnavailableView(
                    "No Templates Saved",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Configure your watermark then tap **Save Template** to create your first reusable template. Templates work across the app, share extension, and Photos extension.")
                )
            }
        }
        // File importer for .watermarktemplate
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "watermarktemplate")].compactMap { $0 }
        ) { result in
            switch result {
            case .success(let url):
                guard let data = try? Data(contentsOf: url) else {
                    importError = TemplateStoreError.importInvalid.localizedDescription
                    return
                }
                do {
                    _ = try TemplateStore.shared.import(from: data)
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        // Export share sheet
        .sheet(isPresented: $showExportSheet) {
            if let url = exportShareURL {
                ShareSheetView(activityItems: [url]) {
                    try? FileManager.default.removeItem(at: url)
                    exportShareURL = nil
                }
            }
        }
    }

    // MARK: - Helpers

    /// Serializes a template to .watermarktemplate data, writes to a temp
    /// file, and presents the share sheet.
    private func exportTemplate(_ template: Template) {
        guard let data = try? TemplateStore.shared.exportData(for: template) else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(template.name).watermarktemplate"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            exportShareURL = fileURL
            showExportSheet = true
        } catch {
            importError = "Could not export template. Please try again."
        }
    }
}
