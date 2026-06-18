# Watermark

## What This Is

An iOS app that lets users add watermarks or white-frame metadata overlays to photos and videos, then immediately share them to social media without saving. Users can import media from the in-app picker, the iOS share sheet, the Photos app's native edit extension, the Files app, "Open In" from other apps, home screen quick actions, or Siri/Shortcuts. Works for both photos and videos (including Live Photos and ProRAW DNG) while preserving all metadata, HDR, and original image quality. Supports text, image/logo, signature, and white-frame overlays with per-layer opacity, visibility, and 8-position placement.

## Core Value

Add a watermark and share it instantly — without ever cluttering the camera roll.

## Current Milestone: v1.1 Address tech debt — REQUIREMENTS drift, ViewModel duplication, Photos HDR detection

**Goal:** Harden the v1.0 codebase and dev process — collapse duplicated ViewModel code, fix the Photos extension HDR warning, reconcile REQUIREMENTS.md traceability with recurrence prevention, and add a wave-level build gate to catch broken builds early.

**Target work items:**
- REQUIREMENTS drift — audit REQUIREMENTS.md against current code AND add a recurrence guard so checkboxes stay in sync per plan
- ViewModel duplication — add default implementations to `WatermarkConfigurable`; collapse ~186 duplicated lines across 3 ViewModels → ~20
- Photos HDR detection — populate `sourceHasHDR`/`sourceFormatLabel` in `PhotosExtensionViewModel` so the HDR→JPEG warning fires
- Wave-level build gate — per-wave `xcodebuild` verification so pre-existing build errors surface at source

## Requirements

### Validated

- ✓ MEDI-01 — Import photos/videos from in-app picker — v1.0
- ✓ MEDI-02 — Receive photos/videos via iOS share sheet — v1.0
- ✓ MEDI-03 — Receive photos/videos via Photos app native edit extension — v1.0
- ✓ WMRK-01 — Custom text watermarks (font, size, color, opacity) — v1.0
- ✓ WMRK-02 — Image/logo watermarks (resize, opacity) — v1.0
- ✓ WMRK-03 — 8 preset watermark positions — v1.0
- ✓ WMRK-04 — Real-time preview — v1.0
- ✓ FRME-01 — White frame border — v1.0
- ✓ FRME-02 — Device metadata on white frame — v1.0
- ✓ SHAR-01 — Share without saving to camera roll — v1.0
- ✓ QUAL-01 — EXIF/metadata preservation — v1.0
- ✓ QUAL-02 — HDR preservation — v1.0
- ✓ QUAL-03 — Original quality preservation — v1.0
- ✓ QUAL-04 — Video HDR/audio preservation — v1.0
- ✓ PROR-01 — ProRAW DNG at 48MP — v1.0
- ✓ PROR-02 — ProRAW HDR/metadata preservation — v1.0
- ✓ EXIF-01 — Dynamic EXIF tokens — v1.0
- ✓ EXIF-02 — Tokens for all formats — v1.0
- ✓ MULT-01 — Multi-layer compositing — v1.0
- ✓ MULT-02 — Per-layer opacity/visibility — v1.0
- ✓ EXPT-01 — Output format choice (HEIC/JPEG/PNG/TIFF) — v1.0
- ✓ EXPT-02 — Quality slider (60–100%) — v1.0
- ✓ EXPT-03 — Format+HDR preservation — v1.0
- ✓ COMP-01 — Before/after toggle — v1.0
- ✓ COMP-02 — Photo+video comparison — v1.0
- ✓ VIDX-01 — Video progress bar with ETA — v1.0
- ✓ VIDX-02 — Cancel video export — v1.0
- ✓ VIDX-03 — Background video export notification — v1.0
- ✓ LIVE-01 — Live Photo watermarking — v1.0
- ✓ LIVE-02 — Still+video overlay — v1.0
- ✓ SIGN-01 — Signature capture — v1.0
- ✓ IMPS-01 — Files app import — v1.0
- ✓ IMPS-02 — Open In from other apps — v1.0
- ✓ SYSI-01 — Home screen quick actions — v1.0
- ✓ SYSI-02 — Siri/Shortcuts/App Intents — v1.0

### Active

<!-- v1.1 tech-debt milestone — formal REQ-IDs defined in REQUIREMENTS.md -->

- [ ] Audit REQUIREMENTS.md traceability against current code; add recurrence guard for per-plan checkbox sync
- [ ] Add default implementations to `WatermarkConfigurable` protocol; collapse duplicated layer-management code across 3 ViewModels
- [ ] Populate `sourceHasHDR`/`sourceFormatLabel` in `PhotosExtensionViewModel` so HDR→JPEG warning fires in Photos extension
- [ ] Add wave-level `xcodebuild` build gate so broken builds surface at source, not at milestone audit

### Out of Scope

- Advanced photo editing (filters, cropping, adjustments) — keep app focused on watermark + share
- Photo library management / organization — outside core value proposition
- Cloud storage or sync — local-only operation
- Account creation / sign-in — anti-pattern for utility apps
- In-app camera / photo capture — users already have iPhone Camera
- Android version — iOS only
- Batch processing (BATC-01, BATC-02) — deferred to future milestone
- Customization templates (CUST-01 through CUST-04) — deferred to future milestone

## Context

Shipped v1.0 MVP with 13,222 lines of Swift across 82 files. Tech stack: Swift 6 / SwiftUI (iOS 18), AVFoundation, Core Image, ImageIO, PencilKit, Photos, AppIntents. Architecture: WatermarkCore Swift Package (shared engine) consumed by 3 targets (Main App, ShareExtension, PhotoEditExtension) via App Group container. 137 commits over 1 day, 44 tasks across 20 plans. 227 automated tests (14 pre-existing EXIF orientation test failures in SPM CLI mode — pass under xcodebuild).

Initial development revealed: (1) REQUIREMENTS.md traceability drift — 5 requirements remained unchecked despite implementation (reconciled at archive, but no prevention mechanism); (2) ViewModel layer-management code is near-duplicated across 3 targets — `WatermarkConfigurable` protocol would benefit from default implementations; (3) PhotosExtensionViewModel doesn't populate `sourceHasHDR`/`sourceFormatLabel` (minor — HDR preserved by default). The v1.0 retrospective (RETROSPECTIVE.md) also flagged that pre-existing build errors from Phases 5–6 compounded undetected until Phase 7 because executor self-checks reported "PASSED" without an actual `xcodebuild` invocation. **v1.1 addresses all four items** as a focused tech-debt milestone — no new user-facing features.

## Constraints

- **Platform**: iOS 18+ — native Swift/SwiftUI with UIKit bridges for extension entry points
- **Quality**: Must preserve HDR, color profile, and all EXIF/metadata in output
- **Performance**: Watermarking must work on-device for large video files without excessive memory pressure
- **Privacy**: No network calls required; all processing on-device
- **Compatibility**: Support iOS Photos edit extension and share sheet app extension

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Native iOS (Swift/SwiftUI) | Required for Photos extension, share sheet, and HDR/metadata preservation | ✓ Good — all 3 entry points shipped |
| On-device rendering only | Privacy, offline use, and avoiding quality loss from server uploads | ✓ Good — zero network calls |
| No save-by-default workflow | Core value: watermark and share, don't clutter camera roll | ✓ Good — share-without-saving across all flows |
| CGImageSource → CIImage → CGImageDestination pipeline | Only Apple-native path that preserves HDR gain maps + all metadata | ✓ Good — QUAL-01/02/03 verified |
| WatermarkCore Swift Package shared by 3 targets | Eliminates code duplication between app + extensions | ✓ Good — single engine source of truth |
| App Group container for config sync | Bidirectional config sync between app and extensions | ✓ Good — AppGroupConfigSync works across all 3 targets |
| WatermarkConfigurable protocol | Abstracts ViewModel interface for shared ControlsView | ⚠️ Revisit — 186 lines of near-duplicate layer management code; add default implementations |
| CGColor Codable via RGBA [CGFloat] array | Preserves full color fidelity for config sync | ✓ Good — consistent across text/image/signature layers |
| Per-layer opacity via CIFilter.colorMatrix.aVector | Separate from per-element rendering alpha | ✓ Good — MULT-02 verified |
| D-12 compositing order: text → image → frame | Predictable layer stacking in single pass | ✓ Good — enforced in both photo and video paths |
| Backward-compatible Codable (decodeIfPresent with defaults) | Old configs decode without crash when new fields added | ✓ Good — Phase 5/7 enum extensions worked |
| PencilKit for signature capture | Apple-native drawing framework, vector stroke data | ✓ Good — SIGN-01 delivered, <100KB per signature |
| Two-phase Live Photo watermarking (still + video separately) | PHLivePhotoEditingContext requires PHContentEditingInput (unavailable from PhotosPicker) | ✓ Good — pragmatic bridge for main app flow |
| @AssistantIntent(schema: .photos.edit) for App Intents | Enables Siri AI integration per iOS 18 | ✓ Good — SYSI-02 delivered |
| Consolidated AppDelegate + SceneDelegate into WatermarkApp.swift | Avoided pbxproj complexity for new target files | ⚠️ Revisit — works but deviates from conventional separation |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-18 after v1.1 milestone start*
