import os

// Markepi's only log destinations. Debug builds log as usual; release builds
// (App Store) use the disabled log, so nothing reaches the console.

extension OSLog {
    /// The log for `os_log` calls. Pass it as `log: .markepi`.
    public static let markepi: OSLog = {
        #if DEBUG
        OSLog(subsystem: "com.osamamazhar.markepi", category: "Markepi")
        #else
        .disabled
        #endif
    }()
}

extension Logger {
    /// A `Logger` for one category, silent in release builds.
    public static func markepi(_ category: String) -> Logger {
        #if DEBUG
        Logger(subsystem: "com.osamamazhar.markepi", category: category)
        #else
        Logger(OSLog.disabled)
        #endif
    }
}
