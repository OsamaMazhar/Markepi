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
    var viewModel: ViewModel

    @Environment(\.dismiss) private var dismiss

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
        templateList
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
            .alert("Rename Template", isPresented: $showRenameAlert) {
                TextField("Template name", text: $renameText)
                Button("Save") {
                    if let id = renameTemplateID {
                        try? TemplateStore.shared.rename(id: id, to: renameText)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
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
            .sheet(isPresented: $showExportSheet) {
                if let url = exportShareURL {
                    ShareSheetView(activityItems: [url]) {
                        try? FileManager.default.removeItem(at: url)
                        exportShareURL = nil
                    }
                }
            }
    }

    // MARK: - Subviews

    private var templateList: some View {
        List {
            ForEach(TemplateStore.shared.templates) { template in
                templateRow(for: template)
            }
        }
        .overlay {
            if TemplateStore.shared.templates.isEmpty {
                ContentUnavailableView(
                    "No Templates Saved",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Configure your watermark then tap **Save Template** to create your first reusable template. Templates work across the app and share extension.")
                )
            }
        }
    }

    @ViewBuilder
    private func templateRow(for template: Template) -> some View {
        TemplateRowView(
            template: template,
            sourceURL: sourceURL
        )
        .onTapGesture {
            viewModel.applyTemplate(template)
            dismiss()
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
            contextMenuContent(for: template)
        }
    }

    @ViewBuilder
    private func contextMenuContent(for template: Template) -> some View {
        Button {
            viewModel.applyTemplate(template)
            dismiss()
        } label: {
            Label("Apply", systemImage: "checkmark")
        }

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

        Button {
            exportTemplate(template)
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }

        Button(role: .destructive) {
            deleteTemplateID = template.id
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
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
