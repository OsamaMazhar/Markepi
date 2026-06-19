# Project Research Summary

**Project:** Watermark v2.0 — Batch Processing, Template Management & Process Hardening
**Domain:** iOS Photo/Video Watermarking App (native Swift/SwiftUI, on-device only)
**Researched:** 2026-06-19
**Confidence:** HIGH

## Executive Summary

Watermark v2.0 expands a shipped iOS watermarking app with batch processing (multi-item watermarking with shared config), template management (save/load/delete watermark presets with auto-default on import), and process hardening (per-phase VERIFICATION.md templating and worktree-safety fixes). The existing v1.0 architecture — a WatermarkCore Swift Package consumed by three targets (main app, share extension, Photos edit extension) with App Group sync and an actor-based `WatermarkEngine` — provides a strong, additive foundation. No existing components need breaking changes.

The recommended approach is a **three-phase build** ordered by dependency: **Templates first** (pure data layer + thin UI that validates the persistence pattern and feeds into batch), **Batch second** (orchestration layer wrapping the existing per-item engine with serial processing, per-item config overrides, and progress tracking), and **Process Hardening third** (tooling-only changes to GSD workflow files with zero app code impact). All three phases use the existing Apple-native stack — no third-party dependencies — and the same WatermarkCore Swift Package with strictly additive integration.

The **critical risk is memory management in batch processing**. Processing full-resolution media in parallel will trigger iOS jetsam kills (Pitfall #1). The architecture mandates serial processing through an actor-based `BatchProcessor`, `autoreleasepool` wrapping per item, lazy `PhotosPickerItem` loading instead of eager `loadTransferable`, and a `BatchSession` lifecycle that tracks and cleans all temp files on cancellation. The second material risk is **Codable schema evolution** breaking saved templates — this must be solved with a `schemaVersion` field and migration functions before the first template save ships, not retrofitted after users have data. Both risks are fully understood and have concrete prevention strategies documented.

## Key Findings

### Recommended Stack

All additions use existing Apple system frameworks already present in the v1.0 stack. No third-party libraries are needed — all batch processing, template persistence, and progress tracking are covered natively. The WatermarkCore Swift Package gains four new files (`TemplateStore`, `WatermarkTemplate`, `BatchProcessor`, `BatchProgressTracker`) and zero dependency changes.

**Core technologies for v2.0:**
- **PhotosPicker (iOS 18 SDK):** Multi-select batch import via existing `maxSelectionCount` — no new framework needed. Thumbnails loaded via `PHImageManager` to avoid memory spikes; full data loaded on-demand per item.
- **Swift Concurrency `TaskGroup` (throttled):** Parallel batch processing limited to 3–4 concurrent tasks max, with strict `autoreleasepool` per iteration. The `WatermarkEngine` actor already serializes access to the shared `CIContext`.
- **`Foundation.Progress` (parent-child hierarchy):** Batch progress tracking where parent tracks N items and children track per-item export. Bridged to SwiftUI via `@Observable @MainActor` with KVO observation.
- **`FileManager` App Group container:** Template persistence as individual JSON files in `templates/` directory — **not** SwiftData (ORM overkill), **not** Core Data (boilerplate overkill), **not** `UserDefaults` (size bloat risk with image data). Single `templates.json` manifest file with atomic write-via-temp-file pattern. `UserDefaults(suiteName:)` stores only the `defaultTemplateID` pointer.

### Expected Features

**Must have (table stakes) — all ship in v2.0:**
- **Multi-select batch import** — PhotosPicker with count badge, already partially built
- **Shared config applied to all items** — one `WatermarkConfiguration` drives the batch
- **Per-item progress indicator** — "Processing 3 of 15" with determinate progress bar and ETA
- **Sequential processing with `autoreleasepool`** — safety-critical for memory; non-negotiable
- **Error isolation** — one corrupted file doesn't abort the entire batch; results collected per-item
- **Share all results at end** — `UIActivityViewController` with `[URL]` for multi-item sharing
- **Save/Load/Delete template CRUD** — JSON file persistence via `TemplateStore`, Codable throughout
- **Template auto-name with rename** — "Template 1" default, inline rename
- **Auto-apply default template on import** — one template marked as default, applied on every import across all three targets
- **Smart proportional watermark scaling** — already works in v1.0 engine, applies automatically in batch

**Should have (competitive differentiators) — ship in v2.0 if time permits:**
- **Per-item config override within batch** — the #1 complaint about competitor batch; lightweight `PerItemConfigOverride` struct for text, position, scale, white frame toggle per item
- **Background batch processing with notification** — large batches (20+) complete in background; notification on finish
- **Mixed photo+video batch** — process photos and videos in one batch; engine already handles both types
- **Template preview on current media** — browse templates, see how each looks on the active photo before committing
- **Cancel batch mid-processing** — `BatchSession` lifecycle with full temp file cleanup on cancel

**Defer (v2.1+):**
- **Template export/import as `.watermarktemplate` file** — manual backup/transfer via share sheet, no backend
- **Template version history / undo** — simple overwrite-on-save suffices for utility app
- **Template folders / categories** — premature; flat list with search if it exceeds ~15 items
- **Batch-wide "smart auto-position"** — Vision framework latency per photo kills batch throughput; stick with 8-position presets

### Architecture Approach

The v2.0 architecture is strictly additive on top of the shipped v1.0 + v1.1 codebase (13,820 lines, 82+ files, 233 tests). Template management is a new data concern (persisted named configurations in WatermarkCore for cross-target access). Batch processing is a new orchestration concern (sequential multi-item processing with progress aggregation and per-item config overrides, also in WatermarkCore but driven primarily by the main app's ViewModel). Process hardening is a GSD tooling concern that does not affect app Swift code at all.

**Major new components (all in WatermarkCore Swift Package):**
1. **`WatermarkTemplate` (Model)** — Codable struct wrapping `WatermarkConfiguration` with `id: UUID`, `name: String`, timestamps. Just a persistence wrapper — no config duplication.
2. **`TemplateStore` (Storage)** — CRUD operations on `templates.json` in App Group container. Atomic write-via-temp-file. `defaultTemplateID` stored as a pointer in `UserDefaults(suiteName:)`.
3. **`BatchProcessor` (Processing)** — Actor-isolated coordinator. Processes items sequentially with shared config + optional per-item overrides. Reports `BatchProgress`. Handles cancellation.
4. **`PerItemConfigOverride` (Model)** — Lightweight struct for per-item field overrides (text, position, scale, format, white frame toggle). Merged with shared config at processing time — not full config duplication.
5. **`BatchViewModel` (Main App Only)** — `@Observable @MainActor` ViewModel for batch UI: config management, progress display, share orchestration. Extensions get read-only template access only.

**Architectural boundaries enforced:**
- Template management UI (CRUD, list, save sheets) lives in the main app only — extensions are read-only consumers
- Batch processing is main-app only — share extension and Photos extension are inherently single-item workflows
- `WatermarkEngine` is **unchanged** — batch wraps it in a serial loop, not a separate engine
- `AppGroupConfigSync` is **unchanged** — still syncs the active config pointer; templates use independent `TemplateStore`

### Critical Pitfalls

1. **Parallel Batch Processing Memory Explosion** — Processing multiple full-resolution items concurrently causes 1.5GB+ memory spikes and iOS jetsam kills. **Prevention:** Serial processing via actor-based `BatchProcessor`, `autoreleasepool` per item, max 1 concurrent video export, memory budget tracking with `os_proc_available_memory()`, lazy `PhotosPickerItem` loading instead of eager `loadTransferable`.

2. **Codable Template Schema Evolution Breaking Saved Templates** — When `WatermarkConfiguration` evolves (new fields, new layer types), old templates fail to decode with `DecodingError`. **Prevention:** `schemaVersion` field on `WatermarkConfiguration`, migration function for each version, `LayerType` fallback on unknown cases, `decodeIfPresent` on ALL new fields, template museum test fixtures for all historical schemas. Must ship with the first template save.

3. **App Group Template Sync Race Conditions** — Simultaneous reads/writes from main app and extension on shared container files cause last-writer-wins data loss. **Prevention:** Individual template JSON files per UUID (filesystem-level atomicity), manifest file with `NSFileCoordinator` for cross-process safety, `UserDefaults` stores only the pointer, Darwin notifications (`CFNotificationCenter`) for cross-process change propagation.

4. **`AVAssetExportSession` Hardware Decoder Exhaustion** — Running multiple video exports without resource release causes error -11839 "Cannot Decode". **Prevention:** Serial video export queue, 0.5s inter-export delay, explicit nil-out of all AVFoundation references after each export, exportSession cancellation and yield after completion.

5. **Per-Item Config State Bleeding** — Navigating between batch items with a single shared `config` property causes changes to "bleed" across items. **Prevention:** Per-item config dictionary `[Int: WatermarkConfiguration]`, copy-on-switch from current to new item, "Apply to All" action for bulk configuration, dirty-tracking badges on thumbnails for items with custom overrides.

## Implications for Roadmap

Based on combined research, the suggested phase structure is three phases ordered by dependency:

### Phase 1: Template Management (CUST-01 through CUST-04)
**Rationale:** Templates are the foundation. They have no processing dependency — they're pure data persistence + thin UI. Building them first validates the persistence pattern (JSON files in App Group container) before batch processing touches the pipeline. Templates also provide the default config entry point for batch: when users import 10 photos, the default template auto-applies to all of them, and then per-item tweaks (Phase 2) layer on top. The Codable schema migration infrastructure (Pitfall #2) must ship here — retrofitting after users have templates is 3-5× more expensive.

**Delivers:** `WatermarkTemplate` model, `TemplateStore` with CRUD operations, template save/load/delete/rename UI, default template marking with auto-apply on import across all three targets, schema versioning + migration functions, template museum test fixtures.

**Addresses features:** Save/Load/Delete template CRUD, template auto-name with rename, auto-apply default template on import, swipe-to-delete, empty state UI.

**Avoids pitfalls:** Pitfall #4 (Codable schema evolution), Pitfall #5 (App Group sync races), Pitfall #6 (UserDefaults size bloat), Pitfall #10 (template auto-apply race with import).

**Stack elements:** Codable + JSONEncoder/JSONDecoder, FileManager App Group container, UserDefaults(suiteName:) for pointer only, NSFileCoordinator.

### Phase 2: Batch Processing (BATC-01, BATC-02)
**Rationale:** Batch depends on templates — users want to select a template and apply it to an entire batch. The auto-default feature from Phase 1 is the integration point: import 10 photos → all get the default template → user tweaks per-item overrides. The core processing loop wraps the existing `WatermarkEngine.process()`/`processVideo()` serially. This phase carries the highest correctness risk (memory management, decoder exhaustion, per-item state isolation) and requires the most testing.

**Delivers:** `BatchItem` and `PerItemConfigOverride` models, `BatchProcessor` actor with serial queue, `BatchProgressTracker` with KVO bridge, `BatchViewModel` with config management and share orchestration, batch config UI with per-item adjustment, batch progress UI, batch share flow, `BatchSession` lifecycle with temp file cleanup.

**Addresses features:** Multi-select batch import, shared config across batch, per-item progress indicator, sequential `autoreleasepool` processing, error isolation, share all results, cancel batch mid-processing, per-item config override (differentiator), mixed photo+video batch, background batch notification.

**Avoids pitfalls:** Pitfall #1 (parallel memory explosion), Pitfall #2 (AVAssetExportSession decoder exhaustion), Pitfall #3 (share extension memory crash), Pitfall #7 (PhotosPicker eager import), Pitfall #8 (cancellation orphaned files), Pitfall #9 (per-item config state bleeding).

**Stack elements:** Swift Concurrency (serial actor queue), Foundation.Progress (parent-child), PhotosPicker lazy loading, PHImageManager for thumbnails, AVAssetExportSession serial queue with delay.

### Phase 3: Process Hardening (PHRO-01, PHRO-02)
**Rationale:** This phase is independent of both templates and batch — it modifies GSD workflow tooling with zero app Swift code changes. Placing it after functional features avoids slowing feature delivery with tooling work. It can also be done in parallel with Phase 1 or Phase 2 if resources permit.

**Delivers:** Per-phase `VERIFICATION.md` template with automation for populating UAT checkboxes, test counts, and manual QA steps. Worktree-safety fix (`scripts/worktree-safe-add.sh`) that pre-checks for stale worktrees, runs `git worktree prune` when needed, and falls back to timestamp-suffixed directory names.

**Addresses features:** VERIFICATION.md templating, worktree-safety fix (both DEV-ONLY).

**No app code changes.** Entirely in `scripts/` and `.planning/templates/`.

### Phase Ordering Rationale

- **Phase 1 before Phase 2:** Templates are simpler and independently testable. They validate the App Group file-based persistence approach. Batch processing benefits from templates (auto-default on import, template as batch base config). The "load template → mark as default → import media → batch process" workflow is fully integrated from Phase 2 day one.
- **Phase 3 is independent:** Can be done at any point. Deferring to last keeps focus on user-facing features during the first two phases. No risk to app stability.
- **Why not one combined phase:** Templates (data concern) and Batch (processing concern) have different risk profiles, different testing strategies, and different verification criteria. Separating them gives clean success criteria for each.

### Research Flags

**Phases likely needing deeper research during planning (use `--research-phase N`):**
- **Phase 2 (Batch):** Background task time limits for batch notification need validation against actual iOS behavior (documented 30s blocks, but periodic extension behavior varies by iOS version). Per-item config override UX design needs user-testing to validate the "swipe to item → adjust → swipe back" interaction model. Video serialization delay tuning (0.5s between exports) needs real-device profiling.
- **Phase 1 (Templates):** `NSFileCoordinator` cross-process safety needs validation with simultaneous main app + extension access (theoretical concern — may be lower risk than pitfall suggests if extension is invoked only when app is backgrounded). Darwin notification latency for cross-process template change propagation needs real-device timing.

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Templates):** JSON file persistence + Codable is well-documented. Atomic file writes via temp-file → rename is a standard Apple pattern. Template CRUD UI follows standard iOS SwiftUI List patterns (swipe-to-delete, sheets, empty states).
- **Phase 3 (Process Hardening):** Both tasks are mechanical — templating a markdown file and adding a pre-check to a shell script. No domain research needed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technologies are existing Apple frameworks already in the v1.0 stack. No new dependencies. Verified against Apple docs, v1.0 codebase analysis, and community consensus (multiple sources agree JSON files > SwiftData for this use case). |
| Features | HIGH | Competitor analysis verified against 4 apps (eZy, Watermarkly, Add Watermark, Photomator). Feature dependencies cross-referenced with v1.0 codebase — all touchpoints exist and are compatible. Priority matrix grounded in user value and implementation cost. LOW confidence only on exact iOS background task time limits. |
| Architecture | HIGH | Based on direct inspection of the shipped v1.0 + v1.1 codebase (13,820 lines, 82+ files, 233 tests). All new components verified to fit within existing protocol conformances and actor boundaries. No breaking changes to existing components. Phase dependency graph validated against feature dependency tree. |
| Pitfalls | HIGH | Top 3 pitfalls (parallel memory, schema evolution, sync races) verified against Apple docs and community reports (Stack Overflow, Apple Developer Forums). Secondary pitfalls verified against codebase analysis. Recovery costs estimated from similar refactors in the v1.0 codebase. Pitfall-to-phase mapping is consistent across all four research files. |

**Overall confidence: HIGH** — All four research files are internally consistent. No contradictory findings. Architecture directly addresses every identified pitfall. Feature priorities align with dependency graph and phase ordering.

### Gaps to Address

- **iOS background task time limits for batch processing:** Documented as 30-second blocks, but periodic extension behavior varies. **Handle during Phase 2 planning:** Build with conservative estimates (30s blocks, request extensions every 25s). Profile on real devices with 20+ item batches.
- **Darwin notification latency for cross-process template sync:** Theoretical concern — real-world latency may be negligible for this use case. **Handle during Phase 1 planning:** Implement notification and measure. If latency is significant, add explicit refresh-on-foreground in extension view lifecycle.
- **Per-item config override UX:** The "swipe → adjust → swipe back" interaction model for batch per-item editing is unvalidated against real users. **Handle during Phase 2 planning:** Spike a prototype before full implementation. Consider "grid of thumbnails → tap to edit → back to grid" as an alternative if swipe navigation is disorienting.
- **Video serialization delay tuning:** The recommended 0.5s delay between video exports is a starting estimate. **Handle during Phase 2 execution:** Profile with Instruments on A16+ and A15 devices. Tune delay based on actual `AVAssetExportSession` resource release timing.

## Sources

### Primary (HIGH confidence)
- **Apple Developer Documentation** — `PhotosPicker`, `PHImageManager`, `AVAssetExportSession`, `AVMutableComposition`, `Foundation.Progress`, `FileManager` atomic writes, `NSFileCoordinator`, `UserDefaults` suite, App Group entitlements, `Codable`, `Sendable`, `actors`, `TaskGroup`
- **Apple WWDC Sessions (2024)** — "What's new in Photos" (PhotosPicker enhancements), "Supporting HDR images in your app" (gain map preservation), "Modernizing your app for iOS 18" (@Observable, Swift 6 strict concurrency)
- **Watermark v1.0 + v1.1 codebase** — Direct inspection of `WatermarkEngine.swift`, `WatermarkConfiguration.swift`, `AppGroupConfigSync.swift`, `WatermarkConfigurable.swift`, `WatermarkViewModel.swift`, `ShareExtensionViewModel.swift`, `PhotosExtensionViewModel.swift`, `PhotoItem.swift`, `TempFileManager.swift`, `ProcessingResult.swift`, `WhiteFrameConfig.swift` (13,820 lines, 82+ files, 233 tests)

### Secondary (MEDIUM confidence)
- **Stack Overflow** — iOS concurrent `AVAssetExportSession` "Cannot Decode" error -11839 (verified by multiple sources across iOS 14–18); batch processing memory management patterns
- **Apple Developer Forums** — App Group file coordination patterns; `NSFileCoordinator` best practices for cross-process access
- **Kulman.sk** — Share extension memory limits and batch processing strategies (2024)
- **Cedric Bahirwe** — PhotosPicker multiple image memory management patterns (2025)
- **Swift by Sundell** — Codable backward compatibility strategies (2024)
- **Merowing.info** — Codable schema versioning and migration techniques (2024)
- **Christian Selig (Apollo dev)** — App Group communication patterns, Darwin notifications (2024)
- **Kodeco (raywenderlich.com)** — AVVideoCompositionCoreAnimationTool patterns for video watermarking; batch photo loading with PhotosPicker + TaskGroup
- **Greg Benz Photography** — Apple HDR gain map architecture and preservation techniques

### Tertiary (LOW confidence, flagged for validation)
- **Background task time limits** — iOS background task periodic extension behavior varies by iOS version; community reports inconsistent on devices
- **Competitor template features** — May have changed since last app update (2025 reports)
- **Community discussions (Reddit)** — r/iOSProgramming, r/swift threads on batch processing crashes and template persistence (consistent patterns across threads but not individually authoritative)

---
*Research completed: 2026-06-19*
*Ready for roadmapping: yes*
