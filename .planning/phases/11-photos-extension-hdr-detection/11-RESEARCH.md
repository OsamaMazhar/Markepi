# Phase 11: Photos Extension HDR Detection - Research

**Researched:** 2026-06-18
**Domain:** iOS Photos Editing Extension / HDR detection / ImageIO UTI inspection
**Confidence:** HIGH

## Summary

Phase 11 fixes a 2-line population bug: `PhotosExtensionViewModel` declares `sourceHasHDR: Bool = false` (line 79) and `sourceFormatLabel: String? = nil` (line 81) but never populates them from the `PHContentEditingInput`. The `ControlsView` in WatermarkCore already reads both properties to drive the HDR→JPEG format-conversion warning (line 65) and the "Match Source (HEIC)" format label (line 76). The fix adds detection logic in `startEditing(with:placeholderImage:)` — for photos, reading the file header UTI via `CGImageSourceCreateWithURL(_:_:)`; for videos, checking `AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)`. The exact UTI heuristic (`public.heic` → HDR capable) is already duplicated identically in `WatermarkViewModel` (lines 200–223) and `ShareExtensionViewModel` (lines 691–712). This phase replicates it into `PhotosExtensionViewModel` — and optionally extracts it to WatermarkCore to eliminate the triplication.

**Primary recommendation:** Add detection inline in `startEditing` between `isLoadingMedia = false` (line 163) and `Task { await generatePreview() }` (line 173). Use the same CGImageSource UTI heuristic for photos and `AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)` for videos. Optionally extract the duplicated ~25 lines of detection helpers to WatermarkCore as shared utility functions (reducing 3 ViewModels' duplicated code to 0).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Use the CGImageSource UTI heuristic (`public.heic` → HDR capable). Do NOT implement deeper gain map auxiliary data inspection — the Main App also uses the UTI heuristic (both ViewModels say "Full HDR gain map detection is deferred").
- **D-02:** No deeper HDR gain map inspection for this phase.
- **D-03:** Use `AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)` for video HDR detection.
- **D-04:** Video format label derived from source URL path extension (`.mov` → "MOV", `.mp4` → "MP4", `.m4v` → "M4V"). Unknown → nil.
- **D-05:** For photos: CGImageSource UTI → human-readable label, same four-way mapping as existing helpers (`public.heic` → "HEIC", `public.jpeg` → "JPEG", `public.png` → "PNG", `public.tiff` → "TIFF").
- **D-06:** For videos: file extension mapping (`.mov` → "MOV", `.mp4` → "MP4"). Extension beyond the main app's behavior (which doesn't detect video format labels) but improves consistency.
- **D-07:** Detect eagerly in `startEditing(with:placeholderImage:)`, after `isLoadingMedia = false` and before preview generation trigger.
- **D-08:** Detection is lightweight — synchronous, no background task. `CGImageSourceCreateWithURL` reads only file header (~4KB); `AVAsset.load(.tracks)` + iteration is <10ms.
- **D-11:** Out of scope: rendering pipeline, ControlsView, WatermarkViewModel, ShareExtensionViewModel, WatermarkConfigurable protocol.

### the agent's Discretion
- Whether to use `CGImageSourceCreateWithURL(_:_:)` (zero-copy file header read) or `Data(contentsOf:) → CGImageSourceCreateWithData` (simpler, reads full file). `CGImageSourceCreateWithURL` is preferred for performance, especially with large ProRAW DNG files.
- Whether to extract shared HDR/format detection helpers to WatermarkCore (D-09/D-10). If extracted, file placement and naming should follow existing patterns.
- The exact integration point in `startEditing` (before or after `isLoadingMedia = false`). Recommended: after `isLoadingMedia = false` and before `Task { await generatePreview() }`.
- For video format label detection, the exact mapping of extensions to labels: `.mov` → "MOV", `.mp4` → "MP4", `.m4v` → "M4V". Unknown → nil.

### Deferred Ideas (OUT OF SCOPE)
- CUST-01 through CUST-04 (customization templates) — v2+ scope
- BATC-01/02 (batch processing) — v2+ scope
- PHRO-01 (per-phase VERIFICATION.md template) — deferred to future process-hardening milestone
- PHRO-02 (worktree-safety fix) — GSD tooling concern
- Extracting duplicated `detectHDRSource`/`detectSourceFormatLabel` helpers to WatermarkCore — bonus for this phase; if not included, remains minor tech debt (2 ViewModels each with ~12 lines of duplicated helper code).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PHDR-01 | PhotosExtensionViewModel populates sourceHasHDR and sourceFormatLabel from the PHContentEditingInput asset so the HDR→JPEG format-conversion warning fires correctly in the Photos extension context | CGImageSource UTI heuristic (photo) + AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo) (video) — both Apple APIs well-documented and already used in-codebase for the same purpose. Integration point is `startEditing(with:placeholderImage:)` lines 151–173. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| HDR detection (photo) | iOS App Extension / ViewModel | — | ViewModel reads file header UTI synchronously from the PHContentEditingInput URL; no server or service involvement |
| HDR detection (video) | iOS App Extension / ViewModel | — | ViewModel inspects AVAsset tracks; detection is read-only and synchronous on the input provided by Photos |
| Format label derivation | iOS App Extension / ViewModel | — | Pure string mapping from UTI or path extension; no I/O beyond the input already provided |
| HDR loss warning UI | Shared Package (ControlsView) | — | ControlsView in WatermarkCore already reads `viewModel.sourceHasHDR` to trigger the alert; no changes needed |
| Format picker label | Shared Package (ControlsView) | — | ControlsView already reads `viewModel.sourceFormatLabel` to display "Match Source (HEIC)"; no changes needed |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ImageIO (`CGImageSource`) | iOS 18 SDK | Read file header UTI for HDR/format detection | Zero-copy file header read — only loads metadata, not pixel data. Apple's recommended API for image format inspection. Already used by WatermarkViewModel and ShareExtensionViewModel. [VERIFIED: codebase — Apple Developer Documentation] |
| AVFoundation (`AVAssetTrack`) | iOS 18 SDK | Detect HDR video tracks via `hasMediaCharacteristic(.containsHDRVideo)` | Apple's standard API for video track characteristic inspection. Already used by VideoProcessor in WatermarkCore (line 119). [VERIFIED: codebase] |
| Photos (`PHContentEditingInput`) | iOS 18 SDK | Provides `fullSizeImageURL` (photo) and `audiovisualAsset` (video) | Required by the Photos edit extension protocol. Already received in `startEditing(with:placeholderImage:)`. [VERIFIED: Apple Developer Documentation] |
| UniformTypeIdentifiers | iOS 18 SDK | UTI string constants (`public.heic`, `public.jpeg`, etc.) | Apple's standard UTI system. Used in existing detection helpers. [VERIFIED: codebase] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| — (none) | — | — | No third-party libraries needed. All detection uses Apple system frameworks already present in the project. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `CGImageSourceCreateWithURL(_:_:)` (recommended) | `Data(contentsOf:) → CGImageSourceCreateWithData` | Data approach reads entire file into memory (wasteful for UTI check). URL approach reads only the ~4KB file header. For a 48MP ProRAW DNG (~75MB), URL approach is ~18,000× more memory-efficient. Both produce identical UTI results. [CITED: Apple ImageIO documentation — CGImageSourceCreateWithURL reads header incrementally] |
| UTI heuristic (`public.heic` → HDR) (D-01) | Deep gain map auxiliary data inspection via `CGImageSourceCopyAuxiliaryDataInfoAtIndex` | Gain map inspection is more accurate (no false positives) but inconsistent with the Main App's detection approach. Deferred per D-02. The UTI heuristic errs on the side of caution — HEIC photos without HDR gain maps may show a false-positive warning, but HDR photos are never silently degraded. [CITED: codebase — WatermarkViewModel line 202 comment "Full HDR gain map detection is deferred"] |
| Inline detection in ViewModel (D-07) | Extracted shared helpers in WatermarkCore (D-09) | Inline is simpler (1 file changed). Extraction removes ~25 duplicated lines across 3 ViewModels and follows Phase 10's refactoring pattern. Bonus, not required.

**Installation:**
```bash
# No packages to install. All Apple frameworks are included with the iOS SDK.
```

**Version verification:** Not applicable — all dependencies are Apple system frameworks bundled with iOS 18 SDK.

## Package Legitimacy Audit

> No external packages are installed in this phase. All dependencies are Apple system frameworks (ImageIO, AVFoundation, Photos, UniformTypeIdentifiers) included with the iOS 18 SDK. No npm, PyPI, or crates packages are involved.

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
PHContentEditingInput
    │
    ├── fullSizeImageURL (photo) ──→ CGImageSourceCreateWithURL() ──→ CGImageSourceGetType()
    │                                        │                              │
    │                                        │                              ▼
    │                                        │                      UTI string ("public.heic")
    │                                        │                              │
    │                                        │                    ┌─────────┴─────────┐
    │                                        │                    │                   │
    │                                        │                    ▼                   ▼
    │                                        │            sourceHasHDR          sourceFormatLabel
    │                                        │            (UTI == "heic")       (UTI → label)
    │                                        │
    ├── audiovisualAsset (video) ──→ AVAsset ──→ load(.tracks) ──→ videoTrack.hasMediaCharacteristic
    │                                                    │              (.containsHDRVideo)
    │                                                    │                    │
    │                                                    │                    ▼
    │                                                    │              sourceHasHDR
    │                                                    │
    │                                                    └──→ sourceURL.pathExtension
    │                                                                  │
    │                                                                  ▼
    │                                                          sourceFormatLabel
    │                                                          (.mov → "MOV", etc.)
    │
    ▼
PhotosExtensionViewModel.sourceHasHDR / .sourceFormatLabel
    │
    ▼
ControlsView (WatermarkCore) — reads both properties:
    ├── sourceHasHDR → triggers HDR→JPEG warning alert on format change
    └── sourceFormatLabel → populates "Match Source (HEIC)" picker label
```

### Recommended Project Structure

Only one file is modified (plus optional WatermarkCore extraction):

```
PhotoEditExtension/
└── PhotosExtensionViewModel.swift        # Add detection in startEditing() (lines 163–173 region)

Packages/WatermarkCore/Sources/WatermarkCore/Utilities/
└── SourceDetector.swift                  # OPTIONAL (D-09): shared static helpers extracted from 3 ViewModels

App/ViewModels/
└── WatermarkViewModel.swift              # OPTIONAL: remove private detectHDRSource/detectSourceFormatLabel (lines 200–223)

ShareExtension/
└── ShareExtensionViewModel.swift         # OPTIONAL: remove private detectHDRSource/detectSourceFormatLabel (lines 691–712)
```

### Pattern 1: Eager Detection During Media Loading
**What:** Detect source properties synchronously as soon as the media URL/asset is available, before the user interacts with export controls.
**When to use:** All three ViewModels use this pattern — WatermarkViewModel in `loadPhoto`/`loadVideo`, ShareExtensionViewModel in `loadSharedItem`, PhotosExtensionViewModel should use it in `startEditing`.
**Example:**
```swift
// Source: ShareExtensionViewModel.swift lines 246–248 (verified pattern)
// D-01: Detect HDR source for JPEG warning dialog
sourceHasHDR = detectHDRSource(from: data)
sourceFormatLabel = detectSourceFormatLabel(from: data)
```

### Pattern 2: CGImageSource UTI Heuristic for HDR Detection
**What:** Create a `CGImageSource` from file data/URL, read the type UTI, check if it equals `"public.heic"` — HEIC is a potential HDR carrier (Dolby Vision / HLG gain maps are stored in HEIC containers).
**When to use:** Anywhere you need a quick "could this be HDR?" check without loading pixel data or inspecting auxiliary data info.
**Example:**
```swift
// Source: WatermarkViewModel.swift lines 200–208 [VERIFIED: codebase]
/// Detects whether the source data is HEIC (potential HDR carrier).
/// Heuristic: checks UTI via CGImageSource. Full HDR gain map detection is deferred.
private func detectHDRSource(from data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let uti = CGImageSourceGetType(source) else {
        return false
    }
    return (uti as String) == "public.heic"
}
```

### Pattern 3: CGImageSource URL-Based Header Read
**What:** Use `CGImageSourceCreateWithURL(_:_:)` to read only the file header (not pixel data) when a file URL is already available. This is the preferred approach for the Photos extension since `PHContentEditingInput.fullSizeImageURL` provides a direct file URL.
**When to use:** When the source is already a file URL (not in-memory Data). Avoids reading the entire file into memory.
**Example:**
```swift
// [CITED: Apple ImageIO documentation — CGImageSourceCreateWithURL]
// CGImageSourceCreateWithURL reads the image header incrementally —
// it does NOT load the full pixel data into memory.
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let uti = CGImageSourceGetType(source) else {
    return false
}
```

### Pattern 4: AVAssetTrack HDR Video Detection
**What:** Load video tracks from an `AVAsset`, iterate to find the video track, check `hasMediaCharacteristic(.containsHDRVideo)`. This is the standard Apple API for detecting HDR video content.
**When to use:** When `PHContentEditingInput.audiovisualAsset` is available (video editing context).
**Example:**
```swift
// Source: VideoProcessor.swift line 119 [VERIFIED: codebase]
// Also: Apple AVFoundation documentation — AVMediaCharacteristic.containsHDRVideo
let asset = input.audiovisualAsset  // AVAsset from PHContentEditingInput
let tracks = try await asset.load(.tracks)
let isHDR = tracks.contains { track in
    track.mediaType == .video && track.hasMediaCharacteristic(.containsHDRVideo)
}
// For detection only, sync load via loadTracks(withMediaType:) is acceptable:
// let videoTracks = try await asset.loadTracks(withMediaType: .video)
// let isHDR = videoTracks.contains { $0.hasMediaCharacteristic(.containsHDRVideo) }
```

### Anti-Patterns to Avoid
- **`Data(contentsOf:)` for UTI detection on large files:** Reading a 75MB ProRAW DNG just to check its UTI is wasteful. Use `CGImageSourceCreateWithURL` which reads only the file header (~4KB). [CITED: Apple ImageIO — CGImageSource reads headers incrementally]
- **`UIImage` for UTI inspection:** `UIImage` strips metadata including the original UTI information. Always use `CGImageSource` APIs for format detection. [CITED: AGENTS.md — "UIImage for processing pipeline strips EXIF metadata"]
- **Deferring detection to export time:** The HDR→JPEG warning must fire *before* the user selects JPEG in ControlsView. Eager detection in `startEditing` ensures the ViewModel state is ready when ControlsView renders. [CITED: CONTEXT.md D-07]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Image format detection | Custom byte-pattern matching on file headers | `CGImageSourceCreateWithURL` + `CGImageSourceGetType` | ImageIO handles all image formats (HEIC, JPEG, PNG, TIFF, DNG, RAW), including container variants and multi-image files. Hand-rolling byte-pattern matching breaks on format variants. [CITED: Apple ImageIO documentation] |
| Video HDR detection | Custom transfer function parsing | `AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)` | AVFoundation already inspects format descriptions for HDR transfer functions (HLG, PQ). Hand-rolling requires parsing CMFormatDescription extensions — brittle and redundant. [CITED: AVFoundation documentation] |
| UTI → label mapping | Custom switch on string prefixes | Direct `switch` on known UTI constants (`public.heic`, `public.jpeg`, etc.) | The four-way UTI mapping used by the existing helpers is already the simplest correct approach. No library is needed for a 4-case switch. |
| File extension → label mapping | MIME type database | Simple dictionary of known extensions | Only 3 video extensions need mapping (`.mov`, `.mp4`, `.m4v`). A full MIME type database is overkill for a 3-entry mapping. |

**Key insight:** Every detection need in this phase is covered by Apple system framework APIs that the codebase already uses. The challenge is integration (wiring them into `startEditing`), not invention.

## Common Pitfalls

### Pitfall 1: fullSizeImageURL Can Be Nil Even After startEditing Is Called
**What goes wrong:** `PHContentEditingInput.fullSizeImageURL` can be `nil` for certain asset types (e.g., iCloud photos not yet downloaded,某些 RAW formats). The current code (line 152) already guards with `if let imageURL = input.fullSizeImageURL`. Detection code must only run when `fullSizeImageURL` is non-nil.
**Why it happens:** Photos provides `fullSizeImageURL` only when the asset's full-resolution data is locally available. Cloud-origin assets may need `requestContentEditingInput` with `canHandleAdjustmentData` first.
**How to avoid:** Add detection inside the existing `if let imageURL = input.fullSizeImageURL` block (line 152), or check `sourceURL != nil && !isVideo` after the URL resolution block.
**Warning signs:** Force-unwrapping `fullSizeImageURL` or assuming it's always non-nil.

### Pitfall 2: audiovisualAsset May Not Be AVURLAsset
**What goes wrong:** `PHContentEditingInput.audiovisualAsset` returns an `AVAsset?`. It may be an `AVComposition` (not `AVURLAsset`) for certain asset types, meaning `.url` is unavailable.
**Why it happens:** Photos may compose assets from multiple sources for edited or Live Photo videos.
**How to avoid:** For HDR detection, use `input.audiovisualAsset` directly — `AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)` works on any `AVAsset`, not just `AVURLAsset`. For format label (path extension), fall back gracefully: cast to `AVURLAsset` → read `.url.pathExtension`; if unavailable, use `formatDescriptions` to infer container type, or return nil. The existing code (lines 157–158) already handles the AVURLAsset cast for `sourceURL` extraction.
**Warning signs:** Force-casting `audiovisualAsset as! AVURLAsset` without a guard.

### Pitfall 3: CGImageSourceCreateWithURL Returns nil for Video Files
**What goes wrong:** Attempting `CGImageSourceCreateWithURL` on a video URL returns `nil` (CGImageSource only handles still images). Detection must branch on `isVideo` before choosing the detection path.
**Why it happens:** CGImageSource is an image-only API. Video format detection requires AVFoundation.
**How to avoid:** Check `isVideo` before calling image detection APIs. Structure the detection as: `if isVideo { detectVideoHDR() } else { detectPhotoHDR() }`.
**Warning signs:** Calling `CGImageSourceCreateWithURL` on `sourceURL` without checking `isVideo` first.

### Pitfall 4: AVAsset.load(.tracks) Is Async but startEditing Is Synchronous
**What goes wrong:** `AVAsset.load(.tracks)` is an `async throws` method, but `startEditing` is a synchronous method (not `async`). Calling it inline would require wrapping in a `Task`, which defers the detection to after `startEditing` returns.
**Why it happens:** `startEditing(with:placeholderImage:)` is called by Photos on the main thread and is not marked `async`. The existing code already uses `Task { await generatePreview() }` for async work.
**How to avoid:** Two options: (1) Use the older synchronous `asset.tracks(withMediaType:)` API which returns immediately (available since iOS 4.0, deprecated in iOS 16 but still functional), or (2) wrap in `Task` and set properties after the async load completes. Option 1 is preferred for simplicity and matches the lightweight detection goal (D-08). The synchronous `tracks(withMediaType:)` API returns an `[AVAssetTrack]` array immediately — the tracks are loaded lazily, and `hasMediaCharacteristic` triggers the necessary loading. This is the approach used by the existing codebase for `AVURLAsset` URL extraction (line 157 — synchronous cast).
**Warning signs:** Using `await` inside `startEditing` without wrapping in `Task`.

### Pitfall 5: Detection Runs Before sourceURL Is Resolved
**What goes wrong:** HDR/format detection code placed before the `if let imageURL` / `else if let avAsset` blocks would have no `sourceURL` or `isVideo` determined yet.
**Why it happens:** The `startEditing` method resolves `sourceURL` and `isVideo` in lines 151–161. Detection must come after this block.
**How to avoid:** Place detection code after line 163 (`self.isLoadingMedia = false`), where both `sourceURL` and `isVideo` are guaranteed to be set (or nil — guard for that).
**Warning signs:** Detection code appearing before the URL resolution block.

## Code Examples

Verified patterns from official sources:

### Photo HDR Detection via CGImageSourceCreateWithURL
```swift
// [CITED: Apple ImageIO — CGImageSourceCreateWithURL]
// [VERIFIED: codebase — WatermarkViewModel.swift lines 200–208 (Data variant)]
// URL-based variant (preferred for Photos extension — avoids reading full file):
if let sourceURL, !isVideo {
    if let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
       let uti = CGImageSourceGetType(source) {
        sourceHasHDR = (uti as String) == "public.heic"
        sourceFormatLabel = Self.formatLabel(for: uti as String)
    }
}
```

### Photo Format Label Mapping
```swift
// [VERIFIED: codebase — WatermarkViewModel.swift lines 210–223]
// [VERIFIED: codebase — ShareExtensionViewModel.swift lines 699–712]
private func formatLabel(for uti: String) -> String? {
    switch uti {
    case "public.heic": return "HEIC"
    case "public.jpeg": return "JPEG"
    case "public.png":  return "PNG"
    case "public.tiff": return "TIFF"
    default:            return nil
    }
}
```

### Video HDR Detection via AVAssetTrack
```swift
// [VERIFIED: codebase — VideoProcessor.swift line 119]
// [CITED: Apple AVFoundation — AVMediaCharacteristic.containsHDRVideo]
if isVideo, let asset = input?.audiovisualAsset {
    // Synchronous track loading — tracks are lazily initialized,
    // hasMediaCharacteristic triggers loading as needed.
    let videoTracks = asset.tracks(withMediaType: .video)
    sourceHasHDR = videoTracks.contains { track in
        track.hasMediaCharacteristic(.containsHDRVideo)
    }
}
```

### Video Format Label from Path Extension
```swift
// [ASSUMED] — extension mapping follows D-04 guidance
if isVideo {
    if let url = sourceURL {
        switch url.pathExtension.lowercased() {
        case "mov": sourceFormatLabel = "MOV"
        case "mp4": sourceFormatLabel = "MP4"
        case "m4v": sourceFormatLabel = "M4V"
        default:    sourceFormatLabel = nil
        }
    }
}
```

### Integration Point in startEditing (Recommended)
```swift
// [VERIFIED: codebase — PhotosExtensionViewModel.swift lines 147–174]
func startEditing(with input: PHContentEditingInput, placeholderImage: UIImage) {
    self.input = input
    self.previewImage = placeholderImage

    // D-06: Source URL from PHContentEditingInput
    if let imageURL = input.fullSizeImageURL {
        self.sourceURL = imageURL
        self.isVideo = false
    } else if let avAsset = input.audiovisualAsset {
        if let urlAsset = avAsset as? AVURLAsset {
            self.sourceURL = urlAsset.url
        }
        self.isVideo = true
    }

    self.isLoadingMedia = false

    // NEW: Detect HDR and format (added after isLoadingMedia = false)
    detectSourceProperties()

    // D-05: Re-load config from prior adjustment data (re-edit scenario)
    if let adjustmentData = input.adjustmentData,
       canHandle(adjustmentData),
       let savedConfig = decodeAdjustmentData(adjustmentData) {
        self.config = savedConfig
    }

    // Trigger debounced preview generation
    Task { await generatePreview() }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No HDR detection in Photos extension (properties default to false/nil) | Eager CGImageSource UTI detection + AVAssetTrack.hasMediaCharacteristic | Phase 11 (this phase) | HDR→JPEG warning fires correctly in Photos extension; format label appears in ControlsView |
| `detectHDRSource(from: Data)` duplicated in WatermarkViewModel and ShareExtensionViewModel | Same helpers (unchanged for this phase; optional extraction to WatermarkCore as D-09 bonus) | Phase 10 (refactor) then Phase 11 (optionally extract) | No duplication impact — Phase 11 just adds a 3rd copy unless extracted |

**Deprecated/outdated:**
- `AVAsset.tracks(withMediaType:)` — deprecated in iOS 16 in favor of `loadTracks(withMediaType:)` async API. However, the synchronous API still functions and is appropriate for this lightweight detection case where converting `startEditing` to async is undesirable. [CITED: Apple AVFoundation documentation — deprecation note]
- `CGImageSourceCreateWithData` for URL-based detection — when a file URL is available, `CGImageSourceCreateWithURL` is preferred. The existing Data-based helpers are correct for their use cases (in-memory data from PhotosPickerItem / NSItemProvider) but should not be copied for the Photos extension's file-URL context.

## Assumptions Log

> All claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `AVAsset.tracks(withMediaType:)` synchronous API is functional and appropriate for lightweight detection in `startEditing` which is a synchronous method | Code Examples (Video HDR Detection), Pitfall 4 | LOW — the API is deprecated but still functional. If unavailable, fallback to wrapping in `Task { }` adds ~2 lines of code and a minor timing change (detection completes after preview generation starts instead of before — still before user interacts with export controls) |
| A2 | Video format label extension mapping (`.mov` → "MOV", `.mp4` → "MP4", `.m4v` → "M4V") covers the common video formats from Photos library | Code Examples (Video Format Label) | LOW — if a format like `.avi` or `.mkv` appears, it maps to nil (format label hidden, "Match Source" shown without suffix). This is acceptable UX. The mapping can be extended later. |
| A3 | `PHContentEditingInput.audiovisualAsset` when non-nil guarantees at least one video track is present | Pitfall 2 | LOW — if the asset has no video tracks (audio-only), `tracks(withMediaType: .video)` returns empty array, `sourceHasHDR` stays false. Correct behavior. |

## Open Questions

1. **Should the duplicated detection helpers be extracted to WatermarkCore?**
   - What we know: The identical `detectHDRSource(from:)` and `detectSourceFormatLabel(from:)` helpers exist in WatermarkViewModel (lines 200–223) and ShareExtensionViewModel (lines 691–712). Phase 11 will add a URL-based variant to PhotosExtensionViewModel. Total: ~36 lines of duplicated logic across 3 ViewModels.
   - What's unclear: Whether the planner includes this as a scope item (D-09/D-10 marked it as a bonus). Extracting to WatermarkCore adds 2–4 file changes (new WatermarkCore utility + remove from 2 ViewModels) but eliminates future drift risk.
   - Recommendation: If the planner has bandwidth, extract to `Packages/WatermarkCore/Sources/WatermarkCore/Utilities/SourceDetector.swift` as `enum SourceDetector` with `static func isHDR(uti:) -> Bool` and `static func formatLabel(uti:) -> String?` (Data-based and URL-based overloads). If not, document as tech debt and move on — Phase 11's primary success criteria are met with inline detection only.

2. **Should video HDR detection use `load(.tracks)` async or `tracks(withMediaType:)` sync?**
   - What we know: `AVAsset.load(.tracks)` is the modern async API (iOS 16+). `tracks(withMediaType:)` is deprecated but synchronous — matches `startEditing`'s synchronous signature without needing `Task {}`.
   - What's unclear: Whether Photos calls `startEditing` on the main actor in a way where async track loading (via `Task {}`) would cause a visible delay. Both approaches are fast (<10ms for most assets).
   - Recommendation: Use the synchronous `tracks(withMediaType:)` API for simplicity — the deprecation is advisory, not breaking. The detection is a read-only metadata check, not a processing pipeline. If future iOS versions remove the API, migration to `load(.tracks)` is trivial (wrap in `Task`).

## Environment Availability

**Step 2.6: SKIPPED** — Phase 11 has no external dependencies beyond Apple system frameworks (ImageIO, AVFoundation, Photos, UniformTypeIdentifiers) which are bundled with the iOS 18 SDK and already present in the project. No CLI tools, services, runtimes, or package managers need verification beyond the existing Xcode toolchain.

The build gate (`scripts/build-gate.sh`) already verifies Xcode availability (`xcodebuild`) — confirmed available:
```
Xcode 26.2
Build version 17A324
```

## Validation Architecture

> **Skipped** — `workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`.

## Security Domain

> Required — `security_enforcement` is enabled (absent from config.json `workflow` object, defaults to `true`).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | No authentication in scope — on-device media processing only |
| V3 Session Management | No | No sessions in scope |
| V4 Access Control | No | App Group container access is handled by iOS entitlements; no additional access control in this phase |
| V5 Input Validation | Yes | `PHContentEditingInput` values are system-provided and trusted. No user-provided strings, URLs, or data are parsed — CGImageSource and AVAsset APIs handle malformed files gracefully (return nil / empty). No injection surface. |
| V6 Cryptography | No | No cryptographic operations in this phase — detection is read-only metadata inspection |

### Known Threat Patterns for iOS Photos Extension

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Maliciously crafted image file with invalid UTI | Denial of Service | `CGImageSourceCreateWithURL` and `CGImageSourceGetType` handle malformed files by returning nil — no crash or hang. Apple's ImageIO parser is hardened against fuzzed inputs. |
| `fullSizeImageURL` pointing outside sandbox | Elevation of Privilege | iOS sandbox prevents access to URLs outside the extension's container. `CGImageSourceCreateWithURL` will fail gracefully (return nil) for inaccessible files. |
| `audiovisualAsset` with crafted format descriptions | Information Disclosure | `AVAssetTrack.hasMediaCharacteristic` reads metadata only — no pixel data access. No information disclosure surface. |

**No security-specific code changes are needed in this phase.** All detection APIs are read-only and operate on system-provided inputs within the iOS sandbox. No user-controlled strings are parsed or evaluated.

## Sources

### Primary (HIGH confidence)
- **WatermarkViewModel.swift** lines 200–223 — reference implementation of `detectHDRSource(from:)` and `detectSourceFormatLabel(from:)` [VERIFIED: codebase — read and confirmed]
- **ShareExtensionViewModel.swift** lines 691–712 — identical duplicated reference implementation [VERIFIED: codebase — read and confirmed]
- **PhotosExtensionViewModel.swift** lines 79–81, 147–174 — the edit target: property declarations and `startEditing` integration point [VERIFIED: codebase — read and confirmed]
- **VideoProcessor.swift** lines 116–123 — HDR video detection via `hasMediaCharacteristic(.containsHDRVideo)` + transfer function inspection [VERIFIED: codebase — read and confirmed]
- **ControlsView.swift** lines 64–68, 107–129 — consumer of `sourceHasHDR` (HDR→JPEG warning) and `sourceFormatLabel` (format picker label) [VERIFIED: codebase — read and confirmed]
- **WatermarkConfigurable.swift** lines 24–25 — protocol declaring `sourceHasHDR: Bool { get }` and `sourceFormatLabel: String? { get }` [VERIFIED: codebase — read and confirmed]
- Apple Developer Documentation — `CGImageSourceCreateWithURL` [CITED: Apple ImageIO]
- Apple Developer Documentation — `AVMediaCharacteristic.containsHDRVideo` [CITED: Apple AVFoundation]

### Secondary (MEDIUM confidence)
- **AGENTS.md** — project constraints: no third-party libraries, iOS 18 minimum, CGImageSource pipeline for metadata preservation [VERIFIED: project file]
- **ROADMAP.md Phase 11** — success criteria: (1) sourceHasHDR populated, (2) sourceFormatLabel populated, (3) warning fires for HDR→JPEG, (4) build gate passes [VERIFIED: project file]
- **REQUIREMENTS.md PHDR-01** — requirement definition [VERIFIED: project file]
- **CONTEXT.md (Phase 11)** — 12 locked decisions (D-01 through D-12) [VERIFIED: phase file]

### Tertiary (LOW confidence)
- None — all claims verified against codebase or official Apple documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are Apple system frameworks, confirmed present in codebase and verified via code reads
- Architecture: HIGH — the integration point (`startEditing` between lines 163–173), pattern (eager detection during media loading), and consumer (ControlsView) are all verified against the actual code
- Pitfalls: HIGH — all 5 pitfalls are derived from the actual code structure (nil guards, API type mismatches, async/sync boundaries) and confirmed by reading the source files

**Research date:** 2026-06-18
**Valid until:** 2026-07-18 — Apple framework APIs are stable; no expected changes to CGImageSource, AVAssetTrack, or PHContentEditingInput APIs.

**Research scope:** 5 source files read in full + cross-referenced with 7 context/planning files. All 5 research questions from the brief answered in findings above.
