# Feature Research: Batch Processing & Template Management

**Domain:** iOS media watermarking app (v2.0 expansion)
**Researched:** 2026-06-19
**Confidence:** HIGH (verified against Apple docs, competitor analysis, existing WatermarkCore engine)

## Executive Summary

This research maps the feature landscape for three new capabilities: **batch processing** (multi-item watermarking with config sharing), **template management** (save/load/delete watermark presets with auto-default), and **process hardening** (VERIFICATION.md templating and worktree-safety guard). The findings are grounded in competitor analysis (eZy Watermark, Watermarkly, Add Watermark, Photomator), UX best-practice research, and the existing WatermarkCore engine architecture (WatermarkEngine actor, Codable WatermarkConfiguration, AppGroupConfigSync, PhotosPicker multi-select already built).

**Key insight:** Batch processing is inherently HIGH complexity due to memory management constraints (autoreleasepool per-item, sequential async), per-item error isolation (one failure must not abort the entire batch), and UX that straddles between "apply the same thing everywhere" and "but let me tweak this one." Template management is MEDIUM complexity — WatermarkConfiguration is already fully Codable, making it trivially wrappable in SwiftData `@Model` for CRUD, but cross-target template sharing (app → extensions) requires App Group container storage, not just local SwiftData. Process hardening is LOW complexity — templating VERIFICATION.md and fixing worktree directory conflicts are scoped, mechanical changes.

## Feature Landscape

### A. Batch Processing

#### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Multi-select in PhotosPicker** | Any batch app must let users pick multiple items at once. Users expect a "Select" affordance or grid checkmarks. | LOW | Already partially built: `WatermarkViewModel.selectedItems` is `[PhotosPickerItem]`, `maxSelectionCount` configurable. Need to ensure PhotosPicker UI clearly shows multi-select mode with count badge. PhotosPicker natively supports multi-select since iOS 16 — no custom grid needed. |
| **Shared config applied to all items** | Users watermarking a batch expect one set of settings (layers, position, frame, format) applied uniformly. This is the core batch promise. | LOW | Trivial extension of existing `WatermarkConfiguration`. The single config is already shared across the app — batch just means looping `engine.process(sourceURL:config:)` with the same config. |
| **Per-item progress indicator** | Users need to know "Processing 3 of 15" with a determinate progress bar. Leaving the UI unresponsive during batch is a crash magnet (memory + frustration). | MEDIUM | Requires extending `RenderingState` with a `renderingBatch(current: Int, total: Int, itemProgress: Double)` case. The existing `renderingVideo(progress:eta:)` pattern is the model to follow. Progress must update on `MainActor`. |
| **Sequential processing with autoreleasepool** | iOS will kill your app if you hold multiple full-resolution CIImage/CGImage buffers in RAM simultaneously. Competitor apps that crash during batch get 1-star reviews. | HIGH (execution risk) | The engine's `process(sourceURL:config:)` creates CIImage → CIContext → CGImage → CGImageDestination pipeline per call. In a batch loop, each iteration's temporary objects (CIImage, CGImage) must be released before the next iteration. Wrapping each iteration in `autoreleasepool { ... }` is non-negotiable. The existing `WatermarkEngine` actor is already Sendable-isolated — batch loop runs sequentially within its actor context. |
| **Error isolation (one failure ≠ batch abort)** | If photo 7 of 20 fails (e.g., corrupted file, incompatible format), the batch should continue processing 8–20 and report the failure afterward. Silent failures or full aborts are UX failures. | MEDIUM | Requires a `BatchResult` type collecting per-item outcomes: `success(ProcessingResult)` vs `failure(Error, itemIndex)`. The loop must catch-and-continue, not throw-and-abort. The existing `ProcessingResult` model can be extended with a batch wrapper. |
| **Share all results at end** | After watermarking 15 photos, users want to share all 15 at once via the system share sheet. They do not want to share one at a time. | LOW | `UIActivityViewController` already supports `[URL]` for multi-item sharing. The existing `showShareSheet` pattern just needs to pass an array of temp file URLs instead of a single URL. TempFileManager already handles per-file temp URLs. |
| **Cancel batch mid-processing** | Long batch (50+ items) must be cancelable. Users who accidentally started a batch with wrong settings need an escape. | LOW | Reuse the existing `videoExportTask?.cancel()` pattern. A batch-level `Task<Void, Never>?` that can be cancelled. On cancel, clean up already-processed temp files via `TempFileManager.cleanup(url:)`. |

#### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Per-item config override within batch** | The #1 complaint about batch watermarking in competitor apps (eZy, Add Watermark): a watermark perfectly positioned on a portrait photo covers the subject's face on a landscape photo. Users need to "detach" one item, adjust its position/scale, re-merge. | HIGH | This is a structural change: each batch item needs its own `WatermarkConfiguration` (initially cloned from the shared config), with the ability to diverge. The batch grid shows which items have overrides (badge icon). Requires `[BatchItem]` model with `var config: WatermarkConfiguration`, `var hasOverride: Bool`. The preview screen for a per-item adjustment reuses the existing single-item `ControlsView` but scoped to that item only. |
| **Smart proportional scaling across mixed orientations** | A batch of 10 portrait + 5 landscape photos should have the watermark proportionally scaled to each image's shorter dimension. Competitors like Watermarkly do this automatically; apps that don't produce watermarks that are huge on small images and tiny on large ones. | LOW | Already handled by the engine: `WatermarkLayer.scale` is relative to the base image's shorter dimension. No change needed — WatermarkEngine's `buildFilterGraph` already does this. The differentiator is that it "just works" in batch without user intervention. |
| **Background batch processing with notification** | For large batches (20+ items), users shouldn't have to stare at a progress bar. Allow them to background the app and get a notification when done. | MEDIUM | Extend the existing `scheduleCompletionNotification(success:)` pattern from video export. Use `UIApplication.beginBackgroundTask` with time-extension requests. iOS limits background time to ~30 seconds per block — for large batches, request extensions periodically. |
| **Batch preview — "spot check" one item** | Before committing to a 50-photo batch, users need to see how the watermark will look on at least one representative photo. A "Preview on selected" button applies config to the first item and shows the result without processing the whole batch. | LOW | Reuse `generatePreview()` — just call it with the first batch item's sourceURL. The existing before/after comparison toggle works for the preview item. |
| **Mixed photo+video batch** | Many users have photo+video mixed in their library. Allowing them to watermark everything in one go (rather than doing photos first, then videos) is a strong productivity feature. | MEDIUM | The engine already has `process()` for photos and `processVideo()` for videos. The batch loop branches by `WatermarkEngine.mediaType(for:)` per item. Video processing takes longer and uses a different progress model — the batch progress bar must account for this (weighted progress, not just item count). |

#### Anti-Features (Do NOT Build)

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Parallel/concurrent batch processing** | Processing multiple full-resolution images simultaneously will spike memory to 2-4 GB and trigger immediate iOS jetsam (app kill). This is the #1 cause of batch-related 1-star reviews in watermark apps. iOS has a hard memory limit (~2-4 GB on Pro devices, less on non-Pro). | Process sequentially in a single async loop with `autoreleasepool` per iteration. The engine actor is already serial — leverage that guarantee. |
| **Auto-save batch results to camera roll** | Violates the core value proposition: "watermark and share without cluttering camera roll." Batch output of 50 photos = 50 new camera roll items = user frustration. | Write all batch output to temp directory via `TempFileManager`. Present share sheet with all temp URLs. Clean up temps after share completes or on next launch. |
| **Batch-wide "smart auto-position"** | Sounds appealing (AI detects subject, places watermark to avoid faces), but: (a) requires on-device Vision framework integration with significant latency per photo, (b) unpredictable results confuse users who expect consistent positioning, (c) dramatically slows batch processing. | Stick with the existing 8-position preset system. Users can use per-item override for edge cases. |
| **Template marketplace / sharing** | Template sharing requires a backend, authentication, content moderation — all anti-patterns for a privacy-first, on-device-only app. Adds ongoing operational cost and liability. | Export template as `.watermarktemplate` JSON file (WatermarkConfiguration is already Codable), share via standard share sheet. Import by opening the file in-app. One-time, no backend. |
| **Batch video format conversion** | Re-encoding 20 videos from HEVC to H.264 in a batch would take hours and drain battery. Users would blame the app, not the physics. | Keep video export format as source-preserving (HDR passthrough). Offer format choice only for photos where it's fast. |

### B. Template Management

#### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Save current config as named template** | Any app with configurable settings that users reuse expects a "Save as Template" affordance. Without it, users must manually reconfigure for every session — frustration. | LOW | `WatermarkConfiguration` is fully Codable. Saving = encode to JSON, store in SwiftData `@Model`. Name can be auto-generated ("Watermark 1", "Watermark 2") with rename option. A toolbar "Save" button or "Save as Template" action sheet item is the affordance. |
| **Load template from list** | Users need to browse saved templates and apply one with a single tap. A modal sheet with template list is the standard iOS pattern. | LOW | SwiftData `@Query` drives a `List` of templates. Tapping a template sets `WatermarkViewModel.config = template.config` and dismisses the sheet. |
| **Template auto-name with rename** | Forcing users to name every template before saving adds friction. Auto-generate "Watermark 1" and allow rename later. | LOW | SwiftData model has `var name: String` with default "Template N". Inline rename via `.onSubmit` or context menu "Rename" action. |
| **Delete template (swipe-to-delete)** | Standard iOS list interaction. Users expect swipe-to-delete on any managed list. | LOW | SwiftData `@Model` supports `.onDelete` via `modelContext.delete(template)`. Standard SwiftUI List modifier. |
| **Template list with empty state** | A blank "No Templates" screen is broken. Users need a friendly empty state with a "Save Current Settings as Template" CTA. | LOW | `ContentUnavailableView` (iOS 17+), standard iOS pattern. |

#### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Auto-apply default template on import** | When a user who always uses the same watermark imports new media, they shouldn't have to manually load their template every time. Marking one template as "Default" auto-applies it on `handleSelection()`. | MEDIUM | Requires `AppGroupConfigSync` to store the default template ID (or the full config) in App Group UserDefaults so it works across app + extensions. On import, check for default → load template config → set `viewModel.config`. Add a "Set as Default" action with a star/checkmark indicator on the template list. |
| **Template preview on current media** | When browsing templates, users want to see how each template looks on their current photo before committing. A preview thumbnail in the template list shows the template applied to the current item. | MEDIUM | When the template sheet is open and `currentPhoto` exists, call `engine.process(sourceURL:config:template.config)` (low-res, thumbnail scale) for each visible template in the list. Cache results. Use the existing thumbnail generation path (200px max). |
| **Export/import template as .watermarktemplate file** | Power users want to share templates with teammates or back them up. Exporting as a JSON file (WatermarkConfiguration is Codable) and importing via "Open In" or Files picker provides this without a cloud backend. | LOW | Export: encode config to JSON, write to temp `.watermarktemplate` file, present share sheet. Import: register `.watermarktemplate` UTI, decode on open, add to SwiftData. |
| **Duplicate template** | Users who want to create a variant of an existing template (e.g., "Instagram" vs "Twitter" with different positions but same logo) expect a "Duplicate" action. | LOW | Copy the `WatermarkConfiguration`, create new SwiftData model with "(Copy)" suffix. |

#### Anti-Features (Do NOT Build)

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Template cloud sync (iCloud, custom backend)** | Violates privacy constraint (no network calls). Adds sync conflict resolution complexity. User data (templates) is tiny — exporting manually is sufficient. | Keep templates local. Optional manual export/import via share sheet for backup/transfer. |
| **Template folders / categories** | Premature organizational complexity. Most users will have 3-8 templates max. Folders add navigation depth without proportional value. | Flat template list with search/filter if it grows beyond ~15 items. Revisit folders if user feedback demands it. |
| **Template version history / undo** | Over-engineering for a utility app. If a user overwrites a template, they can re-save from the current config. | Simple overwrite-on-save. No versioning. |
| **Auto-detect and suggest templates** | ML-based template suggestion is creepy, requires on-device model, and solves a non-problem (users know their templates). | Manual template selection — fast and predictable. |

### C. Process Hardening

These features improve the development process, not the user-facing app.

| Feature | Why Needed | Complexity | Notes |
|---------|------------|------------|-------|
| **Per-phase VERIFICATION.md template populated during execution** | v1.0 shipped without systematic per-phase verification — UAT checkboxes, manual QA steps, and Nyquist validation were ad-hoc. A template ensures every phase ships with a populated VERIFICATION.md covering UAT criteria, automated test coverage, and manual edge-case checks. | LOW | Template stored in `.planning/templates/VERIFICATION.md`. GSD executor populates it during phase execution with: requirement IDs covered, UAT Yes/No/Partial results, test counts, manual QA checklist. Structured enough to enforce completeness, flexible enough for phase-specific content. |
| **Worktree-safety fix for task-tool branching** | The GSD task-tool creates git worktrees for parallel task execution. If a prior worktree wasn't cleaned up or if a directory already exists, the `git worktree add` command fails with "Working tree exists" error, blocking task parallelization. | LOW | Pre-check: before `git worktree add`, verify target directory doesn't exist or is empty. If stale worktree metadata exists but directory is gone, run `git worktree prune` first. If directory exists with content, use a timestamp-suffixed directory name as fallback. Centralize this logic in a `scripts/worktree-safe-add.sh` helper. |

## Feature Dependencies

```
Batch Processing
    ├──requires──> WatermarkEngine.process() [exists v1.0]
    ├──requires──> WatermarkEngine.processVideo() [exists v1.0]
    ├──requires──> WatermarkConfiguration [exists v1.0]
    ├──requires──> PhotosPicker multi-select [exists v1.0]
    ├──requires──> TempFileManager [exists v1.0]
    ├──requires──> RenderingState extension (batch case) [NEW]
    └──enhances──> Template Management (auto-apply default to batch)

Per-Item Config Override (Batch Differentiator)
    ├──requires──> BatchItem model [NEW]
    ├──requires──> ControlsView (reused per-item) [exists v1.0]
    └──requires──> WatermarkConfigurable protocol [exists v1.0]

Template Management
    ├──requires──> WatermarkConfiguration (Codable) [exists v1.0]
    ├──requires──> SwiftData @Model wrapper [NEW]
    ├──requires──> AppGroupConfigSync (for cross-target default) [exists v1.0]
    ├──requires──> TemplateStore (CRUD) [NEW]
    └──enhances──> Batch Processing (template drives batch config)

Auto-Apply Default Template
    ├──requires──> Template Management (template exists to apply)
    └──requires──> WatermarkViewModel.handleSelection() (hook point) [exists v1.0]

Process Hardening
    ├──requires──> GSD executor integration (VERIFICATION.md population) [exists v1.1]
    └──requires──> scripts/ infrastructure (worktree helper) [exists v1.1]
```

### Dependency Notes

- **Batch Processing requires WatermarkEngine.process()**: The existing actor-based engine is the only processing path. Batch is a loop around it, not a separate engine. No engine changes are needed — the engine's Sendable actor isolation already guarantees serial execution safety.
- **Per-item override depends on ControlsView**: The existing `ControlsView` (with text/image/signature/frame controls) already works for single-item editing. Reusing it for batch-item override means the UI is consistent and no duplicate view code is needed.
- **Template auto-apply depends on Template Management**: Can't auto-apply a default template until templates can be saved and marked as default. Template CRUD must ship first, then auto-apply can be added as a layer on top.
- **Process hardening is independent**: Neither templating VERIFICATION.md nor fixing worktree safety depends on batch or template features. They can ship in parallel or even before.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Multi-select batch import | HIGH | LOW (already built) | P1 |
| Shared config across batch | HIGH | LOW | P1 |
| Per-item progress indicator | HIGH | MEDIUM | P1 |
| Sequential autoreleasepool processing | HIGH (must-have for stability) | HIGH (correctness risk) | P1 |
| Error isolation per item | HIGH | MEDIUM | P1 |
| Share all batch results | HIGH | LOW | P1 |
| Cancel batch mid-processing | MEDIUM | LOW | P2 |
| Save/Load template CRUD | HIGH | LOW | P1 |
| Template auto-name with rename | HIGH | LOW | P1 |
| Delete template (swipe) | HIGH | LOW | P1 |
| Auto-apply default template | HIGH | MEDIUM | P1 |
| Per-item config override in batch | HIGH (differentiator) | HIGH | P2 |
| Background batch notification | MEDIUM | MEDIUM | P2 |
| Template preview on current media | MEDIUM | MEDIUM | P2 |
| Export/import template file | LOW | LOW | P3 |
| Smart proportional scaling (auto) | HIGH | LOW (built-in) | P1 (already works) |
| Mixed photo+video batch | MEDIUM | MEDIUM | P2 |
| VERIFICATION.md templating | DEV-ONLY | LOW | P1 |
| Worktree-safety fix | DEV-ONLY | LOW | P1 |

**Priority key:**
- P1: Ship in v2.0 launch
- P2: Ship in v2.0 if time permits, otherwise v2.1
- P3: Defer to future milestone

## Competitor Feature Analysis

| Feature | eZy Watermark | Watermarkly | Add Watermark | Photomator | Our Plan (Watermark v2.0) |
|---------|-------------|-------------|---------------|------------|---------------------------|
| Batch multi-select | ✓ | ✓ | ✓ | ✓ | ✓ (PhotosPicker, already built) |
| Shared config batch | ✓ | ✓ | ✓ | ✓ | ✓ |
| Per-item override in batch | ✗ | ✗ | Partial (unselect) | ✗ | ✓ (Differentiator) |
| Template save/load | ✓ | ✓ | ✓ | ✓ | ✓ (SwiftData, Codable) |
| Auto-apply default template | ✗ | ✗ | ✗ | ✗ | ✓ (Differentiator) |
| Background batch processing | ✗ | ✓ (server-side) | ✗ | ✗ | ✓ (Differentiator, on-device) |
| Mixed photo+video batch | ✗ | ✓ | ✗ | ✗ | ✓ |
| Template preview | ✗ | ✗ | ✗ | ✗ | ✓ |
| HDR preservation in batch | ✗ | ✗ | ✗ | ✓ | ✓ (inherited from v1.0 engine) |
| Metadata preservation in batch | ✗ | Varies | ✗ | ✓ | ✓ (inherited from v1.0 engine) |
| Share without saving | ✗ | ✗ | ✗ | ✗ | ✓ (core v1.0 feature) |
| On-device only (privacy) | ✗ | ✗ (server) | ✗ | ✓ | ✓ (core constraint) |

**Key takeaway:** No competitor has all three of our differentiators: per-item batch override, auto-apply default template, and background batch with notification. Combined with Watermark's existing strengths (HDR/metadata preservation, share-without-saving, on-device privacy), this positions v2.0 as the most capable watermarking app on iOS.

## Sources

**HIGH confidence:**
- Apple Developer Documentation — `PhotosPicker` multi-select via `maxSelectionCount` (iOS 16+, stable through iOS 18)
- Apple Developer Documentation — SwiftData `@Model` for local CRUD (iOS 17+)
- Apple Developer Documentation — `autoreleasepool` for memory management in batch loops
- Apple Developer Documentation — `UIActivityViewController` multi-item sharing via `[URL]`
- WatermarkCore source code — `WatermarkEngine`, `WatermarkConfiguration`, `AppGroupConfigSync`, `ProcessingResult` (verified v1.0 codebase)

**MEDIUM confidence:**
- Competitor analysis via WebSearch — eZy Watermark, Watermarkly, Add Watermark, Photomator feature comparisons (multiple sources agree)
- UX pattern research — batch processing UX patterns (Google Search, multiple articles)
- Template management UX — preset management, auto-name, swipe-to-delete (Google Search, developer consensus)
- Git worktree safety — conflict resolution patterns (git-scm.com official docs + community consensus)

**LOW confidence (flagged for validation):**
- Exact iOS background task time limits for batch processing (30s per block is documented, but behavior with periodic extension requests varies by iOS version)
- Competitor template features may have changed since last app update (2025 reports)

---
*Feature research for: Watermark v2.0 — Batch Processing, Template Management, and Process Hardening*
*Researched: 2026-06-19*
