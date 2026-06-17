import Foundation
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
    public static let suiteName = "group.com.watermark.app"

    /// Key used to store the serialized `WatermarkConfiguration` JSON data.
    private static let configKey = "watermarkConfiguration"

    // MARK: - Save

    /// Encodes `config` to JSON and writes it to the shared App Group `UserDefaults`.
    ///
    /// Failures (missing suite, encoding error) are logged via `os_log` but
    /// silently ignored — config sync is best-effort, not critical path.
    ///
    /// - Parameter config: The `WatermarkConfiguration` to persist
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

    // MARK: - Load

    /// Reads and decodes a `WatermarkConfiguration` from the shared App Group
    /// `UserDefaults`.
    ///
    /// - Returns: The saved configuration, or `nil` if no data exists or decoding fails
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
}