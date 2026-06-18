# Phase 11: Photos Extension HDR Detection - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase populates `sourceHasHDR` and `sourceFormatLabel` in `PhotosExtensionViewModel` from the `PHContentEditingInput` asset, so the HDR→JPEG format-conversion warning fires correctly in the Photos extension context.

**The bug:** `PhotosExtensionViewModel` declares `sourceHasHDR: Bool = false` (line 79) and `sourceFormatLabel: String? = nil` (line 81) — both protocol requirements from `WatermarkConfigurable`. The `ControlsView` already reads these to show the HDR→JPEG warning (line 65 of ControlsView.swift) and the "Match Source (HEIC)" format label (line 76). But neither property is ever populated from the `PHContentEditingInput` — they stay at their default values, so the warning never fires and the format label never appears.

**Deliverables:**
1. HDR detection from `PHContentEditingInput`'s full-size photo asset (gain map detection or UTI heuristic — consistent with Main App's approach)
2. Format label detection from the input asset's format (HEIC/JPEG/DNG/etc.)
3. The HDR→JPEG warning fires when a Dolby Vision / HLG HDR source is loaded in the extension and the user selects JPEG output

**Out of scope:** New user-facing features (v1.1 is a tech-debt milestone). Changes to WatermarkViewModel or ShareExtensionViewModel (already populate these properties correctly). Changes to ControlsView (already wired). Changes to the rendering pipeline or HDR preservation itself (Phase 11 only adds the warning mechanism, not new preservation logic).
</domain>

<decisions>
## Implementation Decisions

[auto] Selected all 5 gray areas. Recommended options auto-picked for each.

### HDR Detection for Photos
- **D-01:** Use the **CGImageSource UTI heuristic** (public.heic → HDR capable). This is exactly consistent with `WatermarkViewModel.detectHDRSource(from:)` (line 202) and `ShareExtensionViewModel.detectHDRSource(from:)` (line 691) — both check `CGImageSourceGetType(source) == "public.heic"`. For the Photos extension, `PHContentEditingInput.fullSizeImageURL` provides a file URL; read the file header via `CGImageSourceCreateWithURL(_:_:)` or `Data(contentsOf:) → CGImageSourceCreateWithData`.
- **D-02:** Do NOT implement deeper gain map auxiliary data inspection for this phase. The ROADMAP says "gain map presence or transfer function inspection — consistent with the Main App's HDR detection approach." The Main App's approach is the UTI heuristic (both ViewModels say "Heuristic: checks UTI via CGImageSource. Full HDR gain map detection is deferred"). A deeper check would be inconsistent with the other two targets and would increase scope. The UTI heuristic errs on the side of caution (HEIC photos that lack HDR gain maps may show a false-positive warning, but HDR photos will never be silently degraded to JPEG without warning).

### HDR Detection for Videos
- **D-03:** Use `AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)` on the `PHContentEditingInput.audiovisualAsset`. This is consistent with `VideoProcessor` in WatermarkCore (line 119: `formatDescsForHDR.contains { ... }`) which checks `hasMediaCharacteristic` and transfer functions. For the Photos extension's detection purposes, `hasMediaCharacteristic` alone is sufficient — the VideoProcessor handles the more nuanced transfer function inspection during actual export.
- **D-04:** Video format label: derive from the source URL's path extension (`.mov` → "MOV", `.mp4` → "MP4") or from the `AVURLAsset.url` if available. The main app doesn't have a video format label path to replicate (it only detects format for photos), so this is a reasonable extension.

### Format Label Detection
- **D-05:** For photos: **CGImageSource UTI → human-readable label**, using the same mapping as `detectSourceFormatLabel(from:)` in WatermarkViewModel (line 210) and ShareExtensionViewModel (line 699): `public.heic` → "HEIC", `public.jpeg` → "JPEG", `public.png` → "PNG", `public.tiff` → "TIFF", `com.adobe.raw-image` → "DNG" (for ProRAW DNG files). Unknown UTI → nil (format label hidden, "Match Source" shown without suffix).
- **D-06:** For videos: file extension mapping (`.mov` → "MOV", `.mp4` → "MP4"). This is a pragmatic extension — the main app and share extension currently don't detect video format labels either, but adding it here improves consistency.

### Detection Timing
- **D-07:** Detect **eagerly in `startEditing(with:placeholderImage:)`**, after `sourceURL` is determined and `isLoadingMedia` is set to false. This matches the pattern used by WatermarkViewModel (which calls `detectHDRSource`/`detectSourceFormatLabel` during `loadPhoto` / `loadVideo`) and ShareExtensionViewModel (which calls them during `loadSharedItem`). Eager detection ensures `sourceHasHDR` and `sourceFormatLabel` are populated before the user interacts with export options in ControlsView.
- **D-08:** Detection should be lightweight — for photos, `CGImageSourceCreateWithURL` reads only the file header (not the full image data). For videos, `AVAsset.load(.tracks)` then iterate is fast (<10ms for most assets). No background task needed since `startEditing` already runs on @MainActor and the detection is synchronous/trivial.

### Code Organization
- **D-09:** Add the detection logic **inline in `PhotosExtensionViewModel`** for this phase. The `detectHDRSource(from:)` and `detectSourceFormatLabel(from:)` private helpers are currently duplicated identically in both `WatermarkViewModel` (lines 200–223) and `ShareExtensionViewModel` (lines 691–712). The researcher SHOULD evaluate extracting these to WatermarkCore as shared static/file-level functions with overloads for both `Data` and `URL` inputs — this would de-duplicate ~25 lines across 3 ViewModels and is a natural extension of Phase 10's refactoring pattern. However, this is a bonus — not required to meet Phase 11's success criteria.
- **D-10:** If the planner chooses to extract shared helpers to WatermarkCore, the approach is: add `public static func detectHDRSource(from url: URL) -> Bool` and `public static func detectSourceFormatLabel(from url: URL) -> String?` (or equivalent Data-based variants) to a new or existing utility file in WatermarkCore. Then call from all 3 ViewModels, removing the private duplicates. This follows the Phase 10 pattern of collapsing duplicated code into the shared package.

### Scope Boundary — What This Phase Does NOT Touch
- **D-11:** The following are explicitly out of scope:
  - **Rendering pipeline** — HDR preservation during export is already handled by `ImageWriter` (gain map re-attachment) and `VideoProcessor` (HDR transfer function preservation). Phase 11 only adds the UI warning.
  - **ControlsView** — already reads `sourceHasHDR` (line 65) and `sourceFormatLabel` (line 23) from the ViewModel. No changes needed.
  - **WatermarkViewModel / ShareExtensionViewModel** — already populate these properties. No changes needed unless D-09/D-10's shared-helper extraction is included.
  - **WatermarkConfigurable protocol** — already declares `sourceHasHDR: Bool { get }` and `sourceFormatLabel: String? { get }`. No protocol changes needed.

### Verification Strategy
- **D-12:** Verification is four-fold:
  1. **Build gate:** `bash scripts/build-gate.sh` must pass for all 3 targets (success criteria #4).
  2. **Existing tests:** All 227 automated tests must still pass. The change adds detection logic in `startEditing` — no existing test paths are altered.
  3. **Manual / test verification:** A test or manual QA should verify that when a Dolby Vision / HLG HDR source is loaded in the Photos extension and the user selects JPEG output, the HDR→JPEG warning fires (success criteria #3). The `ControlsView` already has the `showHDRLossWarning` alert wired to `viewModel.sourceHasHDR` — populating the source data is the missing piece.
  4. **Format label verification:** After loading a HEIC/JPEG/PNG/TIFF photo in the Photos extension, the ControlsView's "Match Source" format picker option should show the format label (e.g., "Match Source (HEIC)").

### the agent's Discretion
- Whether to use `CGImageSourceCreateWithURL(_:_:)` directly (zero-copy file header read) or `Data(contentsOf:) → CGImageSourceCreateWithData` (simpler, reads full file) is left to the planner. `CGImageSourceCreateWithURL` is preferred for performance but either works for detection.
- Whether to extract shared HDR/format detection helpers to WatermarkCore (D-09/D-10) is left to the researcher and planner. If extracted, the WatermarkCore file placement (new utility file vs. existing file) and naming convention should follow existing patterns.
- For video format label detection (D-06), the exact mapping of extensions to labels is left to the planner. Suggested mapping: `.mov` → "MOV", `.mp4` → "MP4", `.m4v` → "M4V". Unknown → nil.
- The exact integration point in `startEditing` (before or after `isLoadingMedia = false`, before or after preview generation trigger) is left to the planner. Constraint: detection must complete before the user opens ControlsView's export options. Recommended: after `isLoadingMedia = false` and before `Task { await generatePreview() }`.

### Folded Todos
None — no pending todos matched Phase 11's scope.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope + success criteria
- `.planning/ROADMAP.md` §"Phase 11: Photos Extension HDR Detection" — phase goal, depends-on (Phase 10), requirements (PHDR-01), and the 4 success criteria (verbatim source of truth for what "done" means).
- `.planning/REQUIREMENTS.md` §"Photos HDR (PHDR)" — defines PHDR-01: "PhotosExtensionViewModel populates sourceHasHDR and sourceFormatLabel from the PHContentEditingInput asset so the HDR→JPEG format-conversion warning fires correctly."
- `.planning/PROJECT.md` §"Current Milestone" and §"Key Decisions" — v1.1 tech-debt framing; confirms the bug: "PhotosExtensionViewModel doesn't populate sourceHasHDR/sourceFormatLabel (minor — HDR preserved by default)."

### PhotosExtensionViewModel (the edit target)
- `PhotoEditExtension/PhotosExtensionViewModel.swift` — the file to modify. Lines 79–81 declare the properties; lines 147–173 implement `startEditing(with:placeholderImage:)` where detection must be added. Lines 102 stores `private var input: PHContentEditingInput?` which provides `fullSizeImageURL` (line 152) and `audiovisualAsset` (line 155).

### Existing HDR detection patterns (to replicate)
- `App/ViewModels/WatermarkViewModel.swift` lines 200–223 — `detectHDRSource(from:)` and `detectSourceFormatLabel(from:)` private helpers. HEIC UTI → HDR. Four-UTI mapping for format label.
- `ShareExtension/ShareExtensionViewModel.swift` lines 691–712 — identical duplicated helpers.
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift` lines 119–134 — video HDR detection via `AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)` + transfer function inspection.

### Consumer of sourceHasHDR/sourceFormatLabel
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` lines 22–24, 65–76 — `sourceFormatLabel` drives the "Match Source (HEIC)" picker label; `sourceHasHDR` triggers the HDR→JPEG `showHDRLossWarning` alert.
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift` lines 24–25 — protocol declares `sourceHasHDR: Bool { get }` and `sourceFormatLabel: String? { get }`.

### Build gate (protects the change)
- `scripts/build-gate.sh` — Phase 9's xcodebuild gate. Must pass for all 3 targets after the change (success criteria #4).
- `.planning/phases/09-wave-level-build-gate/09-CONTEXT.md` §"Implementation Decisions" — D-01 through D-14 document the build gate's invocation, exit codes, and wave-boundary wiring.

### Prior phase patterns
- `.planning/phases/10-watermarkconfigurable-protocol-defaults/10-CONTEXT.md` §"Implementation Decisions" — Phase 10 refactored PhotosExtensionViewModel (removed duplicated layer-management code, added protocol defaults). Phase 11 works on the refactored ViewModel. D-09 explores whether Phase 11 should also extract HDR/format helpers to WatermarkCore following the same pattern.
- `.planning/phases/08-traceability-reconciliation-recurrence-guard/08-CONTEXT.md` §"Implementation Decisions" — established repo conventions: atomic commits, AGENTS.md documentation, exit-code contracts.

### WatermarkCore (shared package context)
- `Packages/WatermarkCore/Sources/WatermarkCore/Input/ImageLoader.swift` lines 81, 124 — HDR gain map extraction from `CGImageSource` via `CGImageSourceCopyAuxiliaryDataInfoAtIndex` and `expandToHDR: true` CIImage option. The `ImageLoader` provides the full HDR pipeline context but Phase 11 only needs UTI-level detection.
- `Packages/WatermarkCore/Sources/WatermarkCore/Output/ImageWriter.swift` lines 56–70 — re-attaches HDR gain map aux data during export. Relevant for understanding the full HDR flow but not directly modified by Phase 11.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`CGImageSourceCreateWithURL(_:_:)`** — Apple ImageIO API. Reads file header without loading full pixel data. Used to inspect UTI for HDR/format detection from `PHContentEditingInput.fullSizeImageURL`. Zero-copy alternative to `Data(contentsOf:) → CGImageSourceCreateWithData`.
- **`AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo)`** — Apple AVFoundation API. Already used by `VideoProcessor` for video HDR detection. Directly applicable to `PHContentEditingInput.audiovisualAsset` tracks.
- **Existing detection helpers** — `detectHDRSource(from:)` and `detectSourceFormatLabel(from:)` are duplicated in WatermarkViewModel (lines 200–223) and ShareExtensionViewModel (lines 691–712). Identical logic (CGImageSource UTI check). The researcher should evaluate extracting these to WatermarkCore.

### Established Patterns
- **Eager detection during media loading** — Both ViewModels set `sourceHasHDR` and `sourceFormatLabel` in their media-loading methods (`loadPhoto`/`loadVideo` in WatermarkViewModel, `loadSharedItem` in ShareExtensionViewModel). Phase 11 follows the same pattern in `startEditing`.
- **CGImageSource UTI heuristic** — All existing HDR detection uses the same approach: create CGImageSource from data, get type UTI, check `== "public.heic"`. Comment says "Full HDR gain map detection is deferred." Phase 11 preserves this consistency.
- **@MainActor protocol conformance** — PhotosExtensionViewModel is `@MainActor final class` conforming to `WatermarkConfigurable`. Detection logic added to `startEditing` inherits @MainActor isolation automatically.

### Integration Points
- **`startEditing(with:placeholderImage:)`** (line 147) — the integration point. After `isLoadingMedia = false` and before `Task { await generatePreview() }`, add HDR and format detection. The method already has `self.input` (stores the `PHContentEditingInput`), `self.sourceURL` (derived from input), and `self.isVideo` (determined during URL resolution).
- **`ControlsView`** (WatermarkCore) — reads `viewModel.sourceHasHDR` and `viewModel.sourceFormatLabel` at render time. No changes needed. Once populated, the HDR→JPEG warning and format label automatically work.
- **`WatermarkConfigurable` protocol** (WatermarkCore) — declares `sourceHasHDR: Bool { get }` and `sourceFormatLabel: String? { get }`. PhotosExtensionViewModel already conforms. No protocol changes needed.

### Creative Options
- **`CGImageSourceCreateWithURL` vs `Data(contentsOf:)`:** The URL API reads only the image header (fast, low memory). The Data API reads the entire file into memory (simpler code, but wastefully reads full-resolution pixel data for a UTI check). `CGImageSourceCreateWithURL` is preferred for the Photos extension where the source file could be a 48MP ProRAW DNG (~75MB).
- **Shared helper extraction:** The researcher may recommend adding `HDRDetector` or static methods to WatermarkCore (e.g., `enum SourceDetector { static func isHDR(url: URL) -> Bool; static func formatLabel(url: URL) -> String? }`). This would eliminate the duplicated ~25 lines across WatermarkViewModel and ShareExtensionViewModel while solving Phase 11's requirement. If the planner includes this, the file count increases from 1 (PhotosExtensionViewModel) to 2–4 (new WatermarkCore file + remove duplicates from 2 ViewModels).
- **Video format label:** The main app and share extension currently don't populate `sourceFormatLabel` for videos. Phase 11 could either skip video format labeling (consistent with existing behavior) or add it (more complete). D-06 recommends adding it since the detection is trivial (path extension mapping) and improves the Photos extension's UX.

</code_context>

<specifics>
## Specific Ideas

- The two properties to populate: `sourceHasHDR: Bool` (line 79) and `sourceFormatLabel: String?` (line 81). Both are already declared and default to `false`/`nil`.
- The single method to modify: `startEditing(with:placeholderImage:)` (line 147). Detection goes after the sourceURL/isVideo resolution (lines 151–161) and `isLoadingMedia = false` (line 163), before the preview generation trigger (line 173).
- For photos: `fullSizeImageURL` is already available as `imageURL` in the `if let imageURL = input.fullSizeImageURL` block (line 152). The `sourceURL` is set to `imageURL` (line 153). Detection can use `sourceURL` after the block.
- For videos: `audiovisualAsset` is cast to `AVURLAsset` to get `urlAsset.url` (lines 157–158). `isVideo = true` is set. Detection uses `input.audiovisualAsset` directly for `.containsHDRVideo` check.
- The detection is lightweight: for photos, CGImageSourceCreateWithURL reads ~4KB header. For videos, `AVAsset.load(.tracks)` followed by `hasMediaCharacteristic` iteration is ~5–10ms. No async overhead concerns.
- The change touches exactly 1 file: `PhotoEditExtension/PhotosExtensionViewModel.swift`. If the planner includes shared helper extraction (D-09), 2–4 additional files: new WatermarkCore utility + removal of duplicates from WatermarkViewModel.swift and ShareExtensionViewModel.swift.
- The HDR→JPEG warning is already wired in ControlsView lines 64–68: `if newValue == .jpeg && viewModel.sourceHasHDR { pendingFormatSelection = .jpeg; showHDRLossWarning = true }`. The `showHDRLossWarning` alert is defined in ControlsView lines 107–129. Populating `sourceHasHDR` is the only missing piece.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. The following are already deferred at milestone level:
- **CUST-01 through CUST-04** (customization templates) — v2+ scope
- **BATC-01/02** (batch processing) — v2+ scope
- **PHRO-01** (per-phase VERIFICATION.md template) — deferred to future process-hardening milestone
- **PHRO-02** (worktree-safety fix) — GSD tooling concern

A possible follow-up noted during analysis: extracting the duplicated `detectHDRSource`/`detectSourceFormatLabel` helpers from WatermarkViewModel and ShareExtensionViewModel to WatermarkCore. This was evaluated as a bonus for Phase 11 (D-09/D-10) — if the planner doesn't include it, it remains a minor tech debt item (2 ViewModels each with ~12 lines of duplicated helper code that could live in the shared package).

</deferred>

---

*Phase: 11-Photos Extension HDR Detection*
*Context gathered: 2026-06-18*
