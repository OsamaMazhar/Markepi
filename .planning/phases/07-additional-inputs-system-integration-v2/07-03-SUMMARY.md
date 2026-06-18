# Plan 07-03 Summary: App Intents & System Integration

**Phase:** 07 — additional-inputs-system-integration-v2
**Status:** Complete
**Duration:** ~5 min

## What was built

**IMPS-01, IMPS-02, SYSI-01, SYSI-02** — Four system integration features converging on the existing configure→preview→share flow.

### Task 1: Files Import
- Added `CFBundleDocumentTypes` to `Info.plist` — Image (public.image, jpeg, heic, png, tiff, raw-image) and Video (public.movie, quicktime-movie, mpeg-4) UTIs registered for "Open In" support
- Upgraded `WatermarkApp.swift` with `.onOpenURL` modifier calling `viewModel.handleIncomingFile(url:)`
- Added "Browse Files" toolbar button (SF Symbol `folder.badge.plus`) to `ContentView.swift` with `.fileImporter` accepting `.image`, `.movie`, `.audiovisualContent`
- Implemented `handleIncomingFile(url:)` in `WatermarkViewModel` — security-scoped resource access, UTI validation, sandbox copy, thumbnail generation, comparison source trigger

### Task 2: Quick Actions
- Added `UIApplicationShortcutItems` to `Info.plist` with two entries:
  - "Watermark Last Photo" (`photo.on.rectangle.angled`)
  - "Watermark from Clipboard" (`doc.on.clipboard`)
- Consolidated `AppDelegate` + `SceneDelegate` into `WatermarkApp.swift` — `UIApplicationDelegateAdaptor`, scene configuration routing, shortcut interception via `NotificationCenter`
- Implemented `handleQuickAction(_:)` dispatching to `fetchMostRecentPhoto()` and `loadFromClipboard()`
- `fetchMostRecentPhoto()` — PhotoKit integration with all authorization states handled, most recent image asset fetch
- `loadFromClipboard()` — UIPasteboard image detection, PNG/JPEG conversion, sandbox copy

### Task 3: App Intents
- Created `WatermarkPhotoIntent` — `@AssistantIntent(schema: .photos.edit)`, `AppIntent`, `openAppWhenRun: true`, `IntentFile` parameter
- Created `WatermarkVideoIntent` — same pattern for video with `public.movie` type identifier
- Created `WatermarkAppShortcuts` — `AppShortcutsProvider` with 2 shortcuts and natural language Siri phrases
- Implemented `checkPendingIntent()` — reads pending media URL, config JSON, media type from App Group UserDefaults on app launch, clears after consumption

## Files changed
- `App/Info.plist` — CFBundleDocumentTypes + UIApplicationShortcutItems
- `App/WatermarkApp.swift` — .onOpenURL, AppDelegate, SceneDelegate, .onReceive for quick actions
- `App/Views/ContentView.swift` — Browse Files button + .fileImporter
- `App/ViewModels/WatermarkViewModel.swift` — handleIncomingFile, handleQuickAction, fetchMostRecentPhoto, loadFromClipboard, checkPendingIntent
- `App/Intents/WatermarkPhotoIntent.swift` — created
- `App/Intents/WatermarkVideoIntent.swift` — created
- `App/Intents/WatermarkAppShortcuts.swift` — created

## Deviations
- AppDelegate and SceneDelegate consolidated into WatermarkApp.swift (avoided pbxproj complexity for new target files)
- `uniformTypeIdentifiers` not available on PHAsset — used hardcoded "heic" extension fallback

## Tests
- 227 tests in 23 suites pass
- 14 pre-existing failures (EXIF orientation) unchanged
