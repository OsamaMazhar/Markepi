import AppIntents
import WatermarkCore

@AssistantIntent(schema: .photos.edit)
struct WatermarkVideoIntent: AppIntent {
    static var title: LocalizedStringResource = "Watermark Video"
    static var description = IntentDescription("Adds a watermark overlay to a video.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Video", description: "The video to watermark.", supportedTypeIdentifiers: ["public.movie"])
    var video: IntentFile

    @Parameter(title: "Configuration", description: "Optional watermark configuration as JSON.", default: nil)
    var configJSON: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        if let data = video.data {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("intent_video_\(UUID().uuidString)")
            try data.write(to: tempURL)
            UserDefaults(suiteName: AppGroupConfigSync.suiteName)?
                .set(tempURL.absoluteString, forKey: "pendingIntentMediaURL")
        }

        if let json = configJSON {
            UserDefaults(suiteName: AppGroupConfigSync.suiteName)?
                .set(json, forKey: "pendingIntentConfigJSON")
        }

        UserDefaults(suiteName: AppGroupConfigSync.suiteName)?
            .set("video", forKey: "pendingIntentMediaType")

        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Watermark \(\.$video)")
    }
}
