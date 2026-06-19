import Foundation

/// A saved watermark template with metadata and schema versioning.
///
/// Wraps a `WatermarkConfiguration` with name, default flag,
/// creation date, and a `schemaVersion` field for forward-compatible
/// migration. Consumed by `TemplateStore` for persistence in
/// App Group UserDefaults.
///
/// Schema versioning: `currentSchemaVersion` is the version of the
/// latest Template schema. When templates are loaded from disk with
/// an older `schemaVersion`, `TemplateStore` runs the migration chain
/// to upgrade them to the current version.
public struct Template: Sendable, Codable, Identifiable {

    /// Unique identifier for this template
    public let id: UUID

    /// User-visible name (must be unique across all templates)
    public var name: String

    /// The watermark configuration this template applies
    public var config: WatermarkConfiguration

    /// Whether this template auto-applies on media import
    public var isDefault: Bool

    /// When this template was created
    public let createdAt: Date

    /// Schema version of this template's encoded data.
    /// Bumped by `MigrationChain` when new fields are added.
    public var schemaVersion: Int

    // MARK: CodingKeys

    enum CodingKeys: String, CodingKey {
        case id, name, config, isDefault, createdAt, schemaVersion
    }

    /// Current schema version. Bump when adding new fields to Template.
    /// The `MigrationChain` registry in `TemplateStore` registers a
    /// migration function for each version bump.
    public static let currentSchemaVersion = 1

    // MARK: Init

    /// Creates a template with the given configuration and metadata.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (default: new UUID)
    ///   - name: User-visible template name
    ///   - config: The watermark configuration to save
    ///   - isDefault: Whether this template auto-applies on import (default: false)
    ///   - createdAt: Creation timestamp (default: now)
    ///   - schemaVersion: Schema version (default: `currentSchemaVersion`)
    public init(
        id: UUID = UUID(),
        name: String,
        config: WatermarkConfiguration,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        schemaVersion: Int = Template.currentSchemaVersion
    ) {
        self.id = id
        self.name = name
        self.config = config
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.schemaVersion = schemaVersion
    }

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.config = try container.decode(WatermarkConfiguration.self, forKey: .config)
        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}
