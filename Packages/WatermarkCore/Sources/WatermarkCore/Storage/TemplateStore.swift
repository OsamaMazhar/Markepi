import Foundation
import os.log

/// Manages template persistence in App Group UserDefaults with schema migration.
///
/// Templates are stored as a `[Template]` JSON array in the shared App Group
/// `UserDefaults` suite `group.com.watermark.app`. The store provides full CRUD
/// operations, a migration chain for forward-compatible schema upgrades, and
/// thumbnail caching in the app's caches directory.
///
/// - Important: All mutations to `templates` go through TemplateStore methods
///   to ensure persistence and validation. Never mutate the array directly.
/// - Note: `@Observable` makes `templates` automatically observable by SwiftUI
///   views — no `@Published` needed.
@Observable @MainActor
public final class TemplateStore {

    /// Shared singleton instance.
    public static let shared = TemplateStore()

    // MARK: - Constants

    /// App Group suite — same as AppGroupConfigSync.suiteName
    private let suiteName = "group.com.watermark.app"

    /// Key for the serialized `[Template]` JSON array in UserDefaults
    private let templatesKey = "com.watermark.app.templates"

    /// Key for the current template schema version in UserDefaults
    private let versionKey = "com.watermark.app.templateSchemaVersion"

    /// Maximum allowed encoded size for the entire template array (500 KB).
    /// Templates exceeding this limit are rejected to avoid UserDefaults
    /// throttling (T-12-03).
    private let maxEncodedSize = 500_000

    // MARK: - Migration Chain

    /// Registry: version → migration function that mutates a Template in-place.
    ///
    /// When `Template.currentSchemaVersion` is bumped, register a migration
    /// function here keyed by the *from* version. Example for future use:
    /// ```swift
    /// 1: { template in
    ///     // v1 → v2: add tags field
    ///     template.tags = template.tags ?? []
    /// }
    /// ```
    private let migrationChain: [Int: (inout Template) -> Void] = [:]

    // MARK: - Published State

    /// The current array of templates. Automatically observed by SwiftUI via `@Observable`.
    var templates: [Template] = []

    // MARK: - Init

    private init() {
        loadTemplates()
    }

    // MARK: - Load with Migration

    /// Loads templates from App Group UserDefaults, runs the migration chain
    /// to upgrade any templates with an older `schemaVersion`, and persists
    /// the migrated data.
    private func loadTemplates() {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            os_log(.error, "[TemplateStore] Failed to open App Group suite '%@'", suiteName)
            return
        }

        guard let data = defaults.data(forKey: templatesKey) else {
            templates = []
            return
        }

        guard var decoded = try? JSONDecoder().decode([Template].self, from: data) else {
            os_log(.error, "[TemplateStore] Failed to decode templates from UserDefaults")
            templates = []
            return
        }

        // Run migration chain for each template
        var migrated = false
        for i in decoded.indices {
            let current = decoded[i].schemaVersion
            for version in current..<Template.currentSchemaVersion {
                if let migration = migrationChain[version] {
                    migration(&decoded[i])
                    decoded[i].schemaVersion = version + 1
                    migrated = true
                }
            }
        }

        templates = decoded

        // Persist migrated data so we don't re-run migrations on next load
        if migrated {
            saveToDefaults(decoded)
        }

        // T-12-04: Clean up orphaned thumbnail cache files
        cleanOrphanedThumbnails()
    }

    // MARK: - CRUD

    /// Saves a template (upsert by id). Validates name is non-empty and unique.
    ///
    /// - Parameter template: The template to save
    /// - Throws: `TemplateStoreError.emptyName` if name is empty,
    ///           `TemplateStoreError.duplicateName` if another template has the same name,
    ///           `TemplateStoreError.tooLarge` if the encoded array exceeds 500 KB
    public func save(_ template: Template) throws {
        guard !template.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw TemplateStoreError.emptyName
        }
        guard !templates.contains(where: { $0.name == template.name && $0.id != template.id }) else {
            throw TemplateStoreError.duplicateName(template.name)
        }

        if let existingIndex = templates.firstIndex(where: { $0.id == template.id }) {
            templates[existingIndex] = template
        } else {
            templates.append(template)
        }

        if template.isDefault {
            clearOtherDefaults(except: template.id)
        }

        try persist()
    }

    /// Deletes a template by id and cleans up its thumbnail cache.
    ///
    /// - Parameter id: The template's UUID
    public func delete(id: UUID) {
        templates.removeAll(where: { $0.id == id })

        // T-12-04: Clean up associated thumbnail cache file
        if let dir = thumbnailCacheDir {
            let thumbURL = dir.appendingPathComponent("thumb_\(id.uuidString).png")
            try? FileManager.default.removeItem(at: thumbURL)
        }

        try? persist()
    }

    /// Duplicates a template (new UUID, " (copy)" suffix, isDefault = false).
    ///
    /// - Parameter template: The template to duplicate
    /// - Throws: TemplateStoreError on save failure
    public func duplicate(_ template: Template) throws {
        var copy = template
        copy.id = UUID()
        copy.name = uniqueName(from: template.name + " (copy)")
        copy.isDefault = false
        copy.createdAt = Date()
        try save(copy)
    }

    /// Renames a template.
    ///
    /// - Parameters:
    ///   - id: The template's UUID
    ///   - newName: The new name (must be non-empty and unique)
    /// - Throws: `TemplateStoreError.notFound`, `.emptyName`, or `.duplicateName`
    public func rename(id: UUID, to newName: String) throws {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            throw TemplateStoreError.notFound
        }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw TemplateStoreError.emptyName
        }
        guard !templates.contains(where: { $0.name == trimmed && $0.id != id }) else {
            throw TemplateStoreError.duplicateName(trimmed)
        }
        templates[index].name = trimmed
        try persist()
    }

    /// Sets a template as the default (clears previous default).
    ///
    /// - Parameter id: The template's UUID
    /// - Throws: `TemplateStoreError.notFound`
    public func setDefault(id: UUID) throws {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            throw TemplateStoreError.notFound
        }
        clearOtherDefaults(except: id)
        templates[index].isDefault = true
        try persist()
    }

    /// Removes default status from a template.
    ///
    /// - Parameter id: The template's UUID
    /// - Throws: `TemplateStoreError.notFound`
    public func removeDefault(id: UUID) throws {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            throw TemplateStoreError.notFound
        }
        templates[index].isDefault = false
        try persist()
    }

    /// Returns the default template, or nil if none is set.
    public var defaultTemplate: Template? {
        templates.first(where: { $0.isDefault })
    }

    // MARK: - Preview Thumbnail Caching

    /// Caches directory for template preview thumbnails.
    /// Follows TempFileManager cachesDirectory URL pattern.
    private var thumbnailCacheDir: URL? {
        try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("template_thumbnails")
    }

    /// Saves a PNG thumbnail for a template ID.
    ///
    /// - Parameters:
    ///   - pngData: The PNG image data
    ///   - templateID: The template's UUID
    public func saveThumbnail(_ pngData: Data, for templateID: UUID) {
        guard let dir = thumbnailCacheDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("thumb_\(templateID.uuidString).png")
        try? pngData.write(to: url)
    }

    /// Loads a cached thumbnail for a template ID.
    ///
    /// - Parameter templateID: The template's UUID
    /// - Returns: PNG data, or nil if not cached
    public func loadThumbnail(for templateID: UUID) -> Data? {
        guard let dir = thumbnailCacheDir else { return nil }
        let url = dir.appendingPathComponent("thumb_\(templateID.uuidString).png")
        return try? Data(contentsOf: url)
    }

    // MARK: - Export/Import

    /// Serializes a template for export as a `.watermarktemplate` file.
    ///
    /// The exported template has `isDefault` forced to `false` so imported
    /// templates never auto-become default (T-12-02).
    ///
    /// - Parameter template: The template to export
    /// - Returns: JSON-encoded template data
    /// - Throws: Encoding errors
    public func exportData(for template: Template) throws -> Data {
        var exportTemplate = template
        exportTemplate.isDefault = false
        return try JSONEncoder().encode(exportTemplate)
    }

    /// Imports a template from `.watermarktemplate` file data.
    ///
    /// Validates the imported template (T-12-01), runs the migration chain,
    /// regenerates the UUID, forces `isDefault = false`, and handles
    /// duplicate names.
    ///
    /// - Parameter data: JSON-encoded Template data from a file
    /// - Returns: The saved template
    /// - Throws: `TemplateStoreError.importInvalid` if validation fails,
    ///           `TemplateStoreError.importFormatUnsupported` if schema is too new
    public func `import`(from data: Data) throws -> Template {
        // T-12-01: Wrap decode in try? with format validation
        guard let imported = try? JSONDecoder().decode(Template.self, from: data) else {
            throw TemplateStoreError.importInvalid
        }

        // T-12-01: Reject if schema version is newer than what we understand
        guard imported.schemaVersion <= Template.currentSchemaVersion else {
            throw TemplateStoreError.importFormatUnsupported
        }

        // T-12-01: Validate name length
        guard imported.name.count <= 50 else {
            throw TemplateStoreError.importInvalid
        }

        // T-12-01: Validate watermark layer count
        guard imported.config.watermarks.count <= 20 else {
            throw TemplateStoreError.importInvalid
        }

        var result = imported

        // Run migration chain on imported template
        let current = result.schemaVersion
        for version in current..<Template.currentSchemaVersion {
            if let migration = migrationChain[version] {
                migration(&result)
                result.schemaVersion = version + 1
            }
        }

        // T-12-02: Regenerate ID and force isDefault = false
        result.id = UUID()
        result.createdAt = Date()
        result.isDefault = false

        // Handle duplicate name
        if templates.contains(where: { $0.name == result.name }) {
            result.name = uniqueName(from: result.name + " (imported)")
        }

        try save(result)
        return result
    }

    // MARK: - Private Helpers

    /// Encodes templates to JSON and writes to App Group UserDefaults.
    ///
    /// - Throws: `TemplateStoreError.tooLarge` if the encoded array exceeds 500 KB
    private func persist() throws {
        guard let data = try? JSONEncoder().encode(templates) else {
            os_log(.error, "[TemplateStore] Failed to encode templates")
            return
        }

        // T-12-03: Reject if blob exceeds UserDefaults practical limit
        guard data.count <= maxEncodedSize else {
            throw TemplateStoreError.tooLarge
        }

        guard let defaults = UserDefaults(suiteName: suiteName) else {
            os_log(.error, "[TemplateStore] Failed to open App Group suite '%@'", suiteName)
            return
        }
        defaults.set(data, forKey: templatesKey)
        defaults.set(Template.currentSchemaVersion, forKey: versionKey)
    }

    /// Writes the given templates array to UserDefaults (used after migrations).
    private func saveToDefaults(_ templates: [Template]) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(templates) else {
            os_log(.error, "[TemplateStore] Failed to save templates to defaults")
            return
        }
        defaults.set(data, forKey: templatesKey)
    }

    /// Sets `isDefault = false` on all templates except the one with the given id.
    private func clearOtherDefaults(except templateID: UUID) {
        for i in templates.indices where templates[i].id != templateID {
            templates[i].isDefault = false
        }
    }

    /// Returns a unique template name by appending incrementing counter until no collision.
    private func uniqueName(from base: String) -> String {
        var candidate = base
        var counter = 2
        while templates.contains(where: { $0.name == candidate }) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }

    /// T-12-04: Removes thumbnail cache files whose UUID doesn't match any existing template.
    private func cleanOrphanedThumbnails() {
        guard let dir = thumbnailCacheDir else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        let existingIDs = Set(templates.map { $0.id.uuidString })
        for url in contents {
            let filename = url.lastPathComponent
            // Filename format: thumb_{UUID}.png
            guard filename.hasPrefix("thumb_"), filename.hasSuffix(".png") else { continue }
            let uuidString = String(filename.dropFirst(6).dropLast(4))
            if !existingIDs.contains(uuidString) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

// MARK: - TemplateStoreError

public enum TemplateStoreError: LocalizedError {
    case emptyName
    case duplicateName(String)
    case notFound
    case tooLarge
    case importInvalid
    case importFormatUnsupported

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Template name cannot be empty."
        case .duplicateName(let name):
            return "A template named \"\(name)\" already exists."
        case .notFound:
            return "Template not found."
        case .tooLarge:
            return "Template data is too large to save."
        case .importInvalid:
            return "Could not import template. The file is invalid or uses an incompatible format."
        case .importFormatUnsupported:
            return "Could not import template. The file was created by a newer version of the app."
        }
    }
}
