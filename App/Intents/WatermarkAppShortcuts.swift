import AppIntents

struct WatermarkAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatermarkPhotoIntent(),
            phrases: [
                "Watermark a photo in \(.applicationName)",
                "Add watermark to photo with \(.applicationName)",
                "Watermark my photo using \(.applicationName)"
            ],
            shortTitle: "Watermark Photo",
            systemImageName: "photo.badge.plus"
        )
        AppShortcut(
            intent: WatermarkVideoIntent(),
            phrases: [
                "Watermark a video in \(.applicationName)",
                "Add watermark to video with \(.applicationName)"
            ],
            shortTitle: "Watermark Video",
            systemImageName: "video.badge.plus"
        )
    }
}
