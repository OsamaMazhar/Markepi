import Foundation
import ImageIO
import os.log

/// Synchronizes `WatermarkConfiguration` between the main app and extensions
/// via App Group `UserDefaults`.
///
/// Uses Codable JSON serialization to persist the configuration to a shared
/// `UserDefaults` suite so that the main app and share extension always have
/// a consistent watermark configuration (D-08).
///
/// On read failure or missing data, returns `nil` — callers should fall back
/// to their default configuration.
public struct AppGroupConfigSync {

    /// App Group suite name (placeholder — developer must configure in Xcode).
    /// Must match the App Group ID in both the main app and extension entitlements.
    public static let suiteName = "group.com.osamamazhar.markepi"

    /// Key used to store the serialized `WatermarkConfiguration` JSON data.
    private static let configKey = "watermarkConfiguration"
    private static let schemaVersionKey = "watermarkConfigurationSchemaVersion"

    /// Bump when a change to `WatermarkConfiguration`'s defaults should not be
    /// outlived by configs saved under the old defaults. A saved config is
    /// restored on every launch, so without this a test device keeps rendering
    /// last week's sizes no matter what the new defaults are — exactly the
    /// "still small" report that prompted this.
    ///
    /// 2: frame styles — gallery default, millimetre sizing, measured metrics.
    private static let schemaVersion = 2

    // MARK: - Save

    /// Encodes `config` to JSON and writes it to the shared App Group `UserDefaults`.
    ///
    /// Failures (missing suite, encoding error) are silently ignored — config
    /// sync is best-effort, not critical path.
    ///
    /// - Parameter config: The `WatermarkConfiguration` to persist
    public static func save(_ config: WatermarkConfiguration) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #if DEBUG
            os_log(.error, "[AppGroupConfigSync] Failed to open UserDefaults suite '%@'", suiteName)
            #endif
            return
        }

        do {
            let data = try JSONEncoder().encode(config)
            defaults.set(data, forKey: configKey)
            defaults.set(schemaVersion, forKey: schemaVersionKey)
        } catch {
            #if DEBUG
            os_log(.error, "[AppGroupConfigSync] Failed to encode config: %@", error.localizedDescription)
            #endif
        }
    }

    // MARK: - Load

    /// Reads and decodes a `WatermarkConfiguration` from the shared App Group
    /// `UserDefaults`.
    ///
    /// - Returns: The saved configuration, or `nil` if no data exists or decoding fails
    public static func load() -> WatermarkConfiguration? {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #if DEBUG
            os_log(.error, "[AppGroupConfigSync] Failed to open UserDefaults suite '%@'", suiteName)
            #endif
            return nil
        }

        // A config saved by an older schema is dropped rather than restored:
        // it would otherwise pin the render to the old defaults forever.
        guard defaults.integer(forKey: schemaVersionKey) == schemaVersion else {
            defaults.removeObject(forKey: configKey)
            defaults.removeObject(forKey: schemaVersionKey)
            return nil
        }

        guard let data = defaults.data(forKey: configKey) else {
            return nil // No saved config yet — expected on first launch
        }

        do {
            var config = try JSONDecoder().decode(WatermarkConfiguration.self, from: data)
            config = sanitized(config)
            return config
        } catch {
            #if DEBUG
            os_log(.error, "[AppGroupConfigSync] Failed to decode config: %@", error.localizedDescription)
            #endif
            return nil
        }
    }

    /// Removes the persisted configuration from the shared App Group `UserDefaults`.
    ///
    /// Used to recover from a corrupt persisted config, and by tests to avoid
    /// leaking fixture data into the shared suite that the app reads on launch.
    public static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: configKey)
    }

    // MARK: - Sanitization

    /// Drops `.image` watermark layers whose PNG data is empty or cannot be
    /// decoded as an image. A corrupt image layer would
    /// otherwise make every preview/render throw `invalidImageData`
    /// ("The image data is empty or corrupt"), blocking the whole pipeline.
    ///
    /// Returns the config unchanged when all image layers are valid.
    private static func sanitized(_ config: WatermarkConfiguration) -> WatermarkConfiguration {
        var config = config
        let originalCount = config.watermarks.count
        config.watermarks.removeAll { layer in
            guard case .image(let input, _, _, _, _) = layer else { return false }
            return !isDecodableImageData(input.pngData)
        }
        let dropped = originalCount - config.watermarks.count
        if dropped > 0 {
            #if DEBUG
            os_log(.error,
                   "[AppGroupConfigSync] Dropped %d image watermark layer(s) with undecodable PNG data from persisted config",
                   dropped)
            #endif
        }
        return config
    }

    /// Whether `data` decodes as a real, readable image.
    private static func isDecodableImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetType(source) != nil else {
            return false
        }
        return true
    }
}
