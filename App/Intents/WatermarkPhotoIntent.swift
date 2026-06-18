import AppIntents
import WatermarkCore

@AssistantIntent(schema: .photos.edit)
struct WatermarkPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Watermark Photo"
    static var description = IntentDescription("Adds a watermark overlay to a photo.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Photo", description: "The photo to watermark.", supportedTypeIdentifiers: ["public.image"])
    var photo: IntentFile

    @Parameter(title: "Configuration", description: "Optional watermark configuration as JSON.", default: nil)
    var configJSON: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        if let data = photo.data {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("intent_photo_\(UUID().uuidString)")
            try data.write(to: tempURL)
            UserDefaults(suiteName: AppGroupConfigSync.suiteName)?
                .set(tempURL.absoluteString, forKey: "pendingIntentMediaURL")
        }

        if let json = configJSON {
            UserDefaults(suiteName: AppGroupConfigSync.suiteName)?
                .set(json, forKey: "pendingIntentConfigJSON")
        }

        UserDefaults(suiteName: AppGroupConfigSync.suiteName)?
            .set("photo", forKey: "pendingIntentMediaType")

        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Watermark \(\.$photo)")
    }
}
