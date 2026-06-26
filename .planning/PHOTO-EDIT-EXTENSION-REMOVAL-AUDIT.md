# Photo Edit Extension Removal Audit

**Project:** Watermark  
**Audited:** 2026-06-24  
**Status:** Implemented 2026-06-24 — static verification passed; full build/test verification pending

## Decision

Watermark no longer needs the Photos app native editing extension. The main app, PhotosPicker import, Share Extension, Live Photo processing, metadata/HDR preservation, and App Group-backed sharing between the main app and Share Extension must remain.

Removing the extension requires more than deleting `PhotoEditExtension/`. The feature is also wired into the Xcode project, shared WatermarkCore UI/model code, tests and snapshots, user-facing copy, build-gate documentation, and current project documentation.

## Audit Summary

- The dedicated extension contains four files and 679 lines of Swift/configuration.
- The Xcode project embeds `PhotoEditExtension.appex` in `WatermarkApp.app` and links WatermarkCore into the extension target.
- WatermarkCore contains a dedicated root view, rendering protocol, and `PHAdjustmentData` serialization helpers used only by this extension and related tests.
- The test suite contains a dedicated 768-line Photos Extension test file with 21 tests, two extension snapshot tests, two committed snapshot images, and one signature test coupled to the adjustment-data stripping helper.
- A broad textual scan found 485 matches across 68 files. Fifty of those files are planning/history documents. Historical milestone artifacts should generally remain intact; current project documentation must be updated.
- Several removal candidates currently have uncommitted edits. Removal must preserve or consciously discard those edits rather than assuming the files match `HEAD`.

## 1. Delete the Dedicated Extension

Delete the complete `PhotoEditExtension/` directory:

| File | Purpose |
|------|---------|
| `PhotoEditExtension/PhotoEditingViewController.swift` | UIKit entry point implementing `PHContentEditingController` and hosting SwiftUI |
| `PhotoEditExtension/PhotosExtensionViewModel.swift` | Loads `PHContentEditingInput`, renders photo/video output, creates `PHContentEditingOutput`, and encodes/decodes `PHAdjustmentData` |
| `PhotoEditExtension/Info.plist` | Registers `com.apple.photo-editing`, supported Image/Video types, and the principal class |
| `PhotoEditExtension/PhotoEditExtension.entitlements` | Grants access to `group.com.watermark.app` |

The template UTI declaration duplicated in the extension plist can disappear with this target. The declarations in `App/Info.plist` and `ShareExtension/Info.plist` must remain.

## 2. Remove Xcode Project Wiring

Edit `Watermark.xcodeproj/project.pbxproj` and remove all objects belonging to the Photo Edit Extension.

### Build files

- `017` — `PhotoEditingViewController.swift in Sources`
- `018` — `PhotosExtensionViewModel.swift in Sources`
- `01B` — `PhotoEditExtension.appex in Embed App Extensions`
- `4AF4A26D2FE9816900C77DCC` — WatermarkCore framework link used by the Photo Edit target

### File and group references

- `610` — `PhotoEditingViewController.swift`
- `611` — `PhotosExtensionViewModel.swift`
- `613` — target `Info.plist`
- `614` — `PhotoEditExtension.entitlements`
- `621` — `PhotoEditExtension.appex` product
- `305` — `PhotoEditExtension` group

Remove group `305` from the main group and product `621` from the Products group.

### Target and build phases

- `411` — `PhotoEditExtension` native target
- `404` — Sources phase
- `406` — Frameworks phase
- `408` — Resources phase

Also remove target `411` from:

- `PBXProject.TargetAttributes`
- The project `targets` array

The main app's `Embed App Extensions` phase (`409`) must remain because it still embeds `ShareExtension.appex`; remove only entry `01B`.

### Build configurations

- `63D` — Photo Edit Debug configuration
- `63E` — Photo Edit Release configuration
- `71E` — Photo Edit target configuration list

These configurations contain:

- `CODE_SIGN_ENTITLEMENTS = PhotoEditExtension/PhotoEditExtension.entitlements`
- `INFOPLIST_FILE = PhotoEditExtension/Info.plist`
- `PRODUCT_BUNDLE_IDENTIFIER = com.watermark.app.photoedit`

### Schemes

`Watermark.xcodeproj/xcshareddata/xcschemes/WatermarkApp.xcscheme` does not explicitly list the Photo Edit target. It builds the app with implicit dependencies, and the embedded `.appex` causes the target to build. No shared-scheme edit should be necessary after removing the target and embed entry.

Remove the `PhotoEditExtension.xcscheme_^#shared#^_` state entry from:

`Watermark.xcodeproj/xcuserdata/osama.xcuserdatad/xcschemes/xcschememanagement.plist`

## 3. Remove Extension-Only WatermarkCore Code

### Delete the root view

Delete:

`Packages/WatermarkCore/Sources/WatermarkCore/UI/PhotosExtensionRootView.swift`

`Package.swift` discovers source files by directory and contains no explicit reference to this file, so no package-manifest edit is required.

### Remove the rendering protocol

In `Packages/WatermarkCore/Sources/WatermarkCore/UI/ExtensionRendering.swift`:

- Delete the complete `PhotosExtensionRendering` protocol.
- Keep `ShareExtensionRendering`.
- Change its `sourceURL` documentation so it refers only to `NSItemProvider`, not `PHContentEditingInput`.

### Remove PHAdjustmentData helpers

In `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift`, remove the extension under:

`// MARK: - PHAdjustmentData Image Stripping`

This removes:

- `strippedPlaceholderPNG`
- `strippingImageData()`
- `rehydrateImageData()`

Production search shows these helpers are called only by `PhotosExtensionViewModel`. Remaining calls are tests specifically covering this extension behavior. Planning research discussed possible template reuse, but the current `TemplateStore` does not use these methods.

Keep `AppGroupConfigSync`: it is still used by the main app and Share Extension. Update its comment about an “un-rehydrated image layer” because rehydration will no longer be part of the production model.

## 4. Tests and Snapshots

### PhotosExtensionTests

`Packages/WatermarkCore/Tests/WatermarkCoreTests/PhotosExtensionTests.swift` contains 21 tests. Do not delete it without deciding what to do with its generic engine coverage.

Extension-specific tests that can be removed include:

- `adjustmentDataFormatConstantsMatch`
- `adjustmentDataRejectsUnknownIdentifier`
- `adjustmentDataStripsImagePNGData`
- `rehydrateImageDataRestoresPNG`
- `textOnlyConfigUnder10KB`
- `utiToFormatLabelMapping`
- `hdrDetectionHeuristic`
- `cgImageSourceGetTypeReturnsNilForTextFile`
- `videoFormatLabelMapping`

The latter four test local helper logic copied from `PhotosExtensionViewModel`, rather than shared production utilities.

The remaining tests cover generic behavior such as engine photo/video processing, metadata and HDR preservation, media-type detection, configuration JSON round-tripping, orientation handling, and ImageIO URL detection. Much of this overlaps other suites, but unique regression coverage should be moved into appropriately named engine, format, metadata, or video test files before deleting `PhotosExtensionTests.swift`.

### Snapshot tests

In `Packages/WatermarkCore/Tests/WatermarkCoreTests/ExtensionSnapshotTests.swift`:

- Remove `photosExtensionIdle()`.
- Remove `photosExtensionPreview()`.
- Keep all Share Extension snapshots.
- Remove navigation-controller-only snapshot infrastructure if it becomes unused after the Photos tests are gone.

Delete the committed references:

- `Packages/WatermarkCore/Tests/WatermarkCoreTests/__Snapshots__/photos-ext-idle.png`
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/__Snapshots__/photos-ext-preview.png`

### Snapshot test ViewModel

In `Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/SnapshotTestViewModel.swift`:

- Remove the `PhotosExtensionRendering` conformance.
- Remove `FinishOutput`.
- Remove the `finishEditing` stub.
- Update comments to describe only `ShareExtensionRootView` and `ShareExtensionViewModel`.

### Signature test coupling

Remove the `strippingImageData() passes .signature layers through unchanged` test from:

`Packages/WatermarkCore/Tests/WatermarkCoreTests/SignatureInputTests.swift`

Signature model and rendering tests unrelated to adjustment-data stripping must remain.

## 5. User-Facing Copy and Shared Comments

Update the empty-template message in:

`App/Views/Templates/TemplateListView.swift`

Current copy says templates work across the app, Share Extension, and Photos Extension. It should mention only the remaining surfaces.

Update stale comments in:

- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/EmptyStateView.swift`
- `Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ShareActionButton.swift`
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/TextWatermarkInputView.swift`
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift`
- `Packages/WatermarkCore/Sources/WatermarkCore/Storage/AppGroupConfigSync.swift`

The `Menu`-based font and color controls in `TextWatermarkInputView` should remain unless there is a separate UI decision to change them. Only their comments currently attribute the design to Photos Extension crashes.

## 6. Live Photo and Photos Framework Boundaries

Do not treat every Photos-related symbol as part of the removed extension.

### Keep

- `PhotosPicker` and `PhotosUI` imports used by the main app and logo picker
- Main-app `Photos` usage in `WatermarkViewModel`, including `PHPhotoLibrary`, `PHAsset`, `PHFetchOptions`, and `PHImageManager`
- `LivePhotoProcessor` implementation and `LivePhotoProcessorTests`
- Main app and Share Extension App Group entitlements
- `AppGroupConfigSync` and `TemplateStore`
- The Share Extension target, ViewModel, root view, tests, and snapshots

### Clean up in LivePhotoProcessor

`Packages/WatermarkCore/Sources/WatermarkCore/Processing/LivePhotoProcessor.swift` contains an obsolete comment saying `PHLivePhotoEditingContext` will be used in a future Photo Edit Extension. Remove that comment.

Its `import Photos` currently has no code-level `PH*` use in the file and can be removed if the compiler confirms it is unnecessary. The Live Photo processing implementation itself must stay.

`LivePhotoProcessorTests.swift` matched the broad audit because its documentation uses the phrase “Live Photo extension” to mean a Swift type extension. It is not testing the Photos Edit Extension and should remain.

## 7. Build and Workflow Updates

Update comments in `scripts/build-gate.sh` from “all 3 targets” to the two remaining targets:

- `WatermarkApp`
- `ShareExtension`

The command builds the `WatermarkApp` scheme, so its behavior should automatically follow the Xcode project after the embedded target is removed.

`scripts/test-build-gate.sh` does not contain Photo Edit-specific target logic and should remain unchanged unless verification reveals otherwise.

## 8. Documentation and Planning References

The audit found 50 planning/history files containing Photo Edit Extension references.

### Current sources that must be updated

- `.planning/PROJECT.md` — product scope, shipped features, constraints, architecture, target count, and current decisions
- `.planning/STATE.md` — current cross-target risk and target-count statements
- `.planning/research/STACK.md` — currently feeds the stack section in `AGENTS.md`
- `AGENTS.md` — active repository instructions must no longer require Photos Edit Extension support

If `AGENTS.md` is generated from planning sources, update the source documents and regenerate it rather than allowing generated content to drift.

### Historical sources that should normally remain

- Completed phase plans, summaries, and verification reports
- Archived milestone requirements and roadmaps
- `.planning/MILESTONES.md`
- `.planning/RETROSPECTIVE.md`

These describe what was built and verified at the time. Erasing those references would make the development record inaccurate. Record the removal as a new decision/task instead.

Historical requirements affected include:

- `MEDI-03` — receive media through the Photos native edit extension
- `PHDR-01` — Photos Extension HDR/source-format detection
- `XTG-02` — Photos Edit Extension ControlsView parity

They should remain completed in their archived milestone records, while current scope documentation should state that the capability was later retired.

## 9. External Cleanup After Code Removal

These items are outside the repository and should be reviewed after a successful archive:

- Remove or retire the App ID for `com.watermark.app.photoedit` in the Apple Developer portal if it is no longer needed.
- Remove unused development/distribution provisioning profiles for that extension identifier.
- Confirm App Store Connect signing configuration no longer expects the extension.
- Clean DerivedData and reinstall the app during device verification so an older installed extension is not mistaken for a current build artifact.

## 10. Dirty Worktree Warning

At audit time, the repository already had broad uncommitted work. The following removal-related files were among the modified files:

- `PhotoEditExtension/PhotoEditingViewController.swift`
- `PhotoEditExtension/PhotosExtensionViewModel.swift`
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/PhotosExtensionRootView.swift`
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift`
- `App/Views/Templates/TemplateListView.swift`
- `Watermark.xcodeproj/project.pbxproj`
- `Watermark.xcodeproj/xcuserdata/osama.xcuserdatad/xcschemes/xcschememanagement.plist`

Before deleting these files or sections, inspect their current diffs. Preserve unrelated work and avoid destructive checkout/reset commands.

## 11. Recommended Removal Order

1. Review uncommitted diffs for every overlapping file.
2. Remove the Photo Edit target objects and embed entry from `project.pbxproj`.
3. Delete `PhotoEditExtension/`.
4. Delete the shared Photos extension root view and protocol.
5. Remove `PHAdjustmentData` stripping/rehydration helpers.
6. Prune or migrate tests, then delete Photos extension snapshots.
7. Update copy, comments, build-gate wording, and current planning documentation.
8. Run residual-reference scans.
9. Run package tests and the iOS build gate.
10. Inspect the built/archive app bundle to confirm `PhotoEditExtension.appex` is absent and `ShareExtension.appex` remains.

## 12. Verification Checklist

### Residual reference scan

The active code/config scan should return no Photo Edit Extension references:

```bash
rg -n -i \
  'PhotoEditExtension|PhotosExtension|PHContentEditing|PHAdjustmentData|com\.apple\.photo-editing|com\.watermark\.app\.photoedit' \
  App Packages ShareExtension Watermark.xcodeproj scripts AGENTS.md
```

Historical `.planning/` matches are acceptable when they are clearly archived records.

Check removed helper symbols separately:

```bash
rg -n 'strippingImageData|rehydrateImageData|PhotosExtensionRendering|PhotosExtensionRootView' .
```

Expected result: no active production/test references. Historical Markdown references may remain.

### Project structure

```bash
xcodebuild -project Watermark.xcodeproj -list
```

Expected targets:

- `WatermarkApp`
- `ShareExtension`

`PhotoEditExtension` must not appear.

### Tests and build

```bash
swift test --package-path Packages/WatermarkCore
bash scripts/build-gate.sh
```

The build gate must exit zero and report `BUILD GATE: PASSED`.

### Built-product inspection

After building or archiving, inspect `WatermarkApp.app/PlugIns/`:

- `ShareExtension.appex` must exist.
- `PhotoEditExtension.appex` must not exist.

### Manual smoke checks

- Import a photo and a video through the main app PhotosPicker.
- Share a photo/video into Watermark through the Share Extension.
- Apply a text/logo/signature/frame watermark and share without saving.
- Exercise template save/load/default behavior across the main app and Share Extension.
- Exercise Live Photo processing.
- Confirm HDR/metadata behavior remains unchanged in the supported main-app/share workflows.

## Definition of Done

The Photos native edit extension is successfully removed when:

- The Photo Edit target, product, source directory, shared UI/protocol, adjustment-data model helpers, and extension-only tests/snapshots are gone.
- No active product copy promises Photos Extension support.
- `WatermarkApp` embeds only `ShareExtension.appex`.
- Main app PhotosPicker, Share Extension, Live Photo processing, App Group sync, templates, metadata, HDR, and original-quality behavior still build and pass their tests.
- Current project documentation records the capability as retired while historical milestone evidence remains intact.
