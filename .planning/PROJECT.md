# Watermark

## What This Is

An iOS app that lets users add watermarks or white-frame metadata overlays to photos and videos, then immediately share them to social media without saving. Users can import media from the in-app picker, the iOS share sheet, the Photos app's native edit extension, the Files app, "Open In" from other apps, home screen quick actions, or Siri/Shortcuts. Works for both photos and videos (including Live Photos and ProRAW DNG) while preserving all metadata, HDR, and original image quality. Supports text, image/logo, signature, and white-frame overlays with per-layer opacity, visibility, and 8-position placement.

## Core Value

Add a watermark and share it instantly — without ever cluttering the camera roll.

## Current State

**Shipped:** v2.0 (2026-06-19) — 3 phases, 10 plans, 15 requirements all satisfied.

**v2.0 delivered:**
- Template Management — save, load, manage, and auto-apply watermark templates across all 3 targets (6 requirements)
- Batch Processing — multi-item watermarking with shared config, per-item adjustments, progress tracking, error resilience (7 requirements)
- Process Hardening — VERIFICATION.md per-plan population gate + worktree safety pre-check/fallback (2 requirements)

**v2.0 stats:** 3 phases, 10 plans, 15/15 requirements satisfied. Built on v1.0 + v1.1 foundation (13,820+ lines Swift, 82+ files, 233+ tests).

## Current Milestone: v2.1 UI Redesign

**Goal:** Rebuild the watermark editor's presentation layer into a polished, professional iOS 26 experience — without touching the rendering engine, ViewModels, or data model.

**Target features:**
- Inspector bottom-sheet layout — photo as full-bleed hero; controls in a resizable detent sheet with a pinned Share action bar
- Grouped, sectioned controls (inset cards) replacing the flat stack of heavy section titles; clear typographic hierarchy
- Liquid Glass navigation/control layer — floating glass chrome, scroll-edge effects, adaptive tint on the primary action only
- Visual 9-position picker replacing the cryptic TL/TC/TR text grid
- Native components throughout — Menus, segmented controls, refined steppers/sliders; one consistent button language
- Adaptive light/dark appearance
- Redesign flows to all 3 targets (App, ShareExtension, PhotoEditExtension) via the shared `ControlsView`

**Key context / constraints:**
- Pure presentation-layer change. `WatermarkConfigurable` protocol, ViewModels, and `WatermarkEngine` are unchanged.
- Risk concentrated in the shared `ControlsView` (consumed by all 3 targets) — redesign must not break extension reuse.
- Targets iOS 26+ Liquid Glass APIs with graceful behavior on the existing iOS 18 deployment floor where required.
- Continues phase numbering at Phase 15.

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
- ✓ TRACE-01 — REQUIREMENTS.md audited against codebase; traceability table accurate — v1.1
- ✓ TRACE-02 — Recurrence guard keeps REQUIREMENTS.md checkboxes in sync per plan — v1.1
- ✓ REFA-01 — WatermarkConfigurable protocol defaults collapse ~186 duplicated lines across 3 ViewModels — v1.1
- ✓ PHDR-01 — PhotosExtensionViewModel populates sourceHasHDR/sourceFormatLabel; HDR→JPEG warning fires — v1.1
- ✓ BUILD-01 — Wave-level xcodebuild build gate across all 3 targets — v1.1
- ✓ TMPL-01 through TMPL-06 — Template CRUD + auto-default-on-import across all 3 targets — v2.0
- ✓ BATC-01 through BATC-07 — Batch processing with per-item adjustments, progress, error resilience — v2.0
- ✓ PHRO-01 — Per-phase VERIFICATION.md populated during execution — v2.0
- ✓ PHRO-02 — Worktree safety pre-check + timestamp fallback — v2.0

### All Requirements Satisfied

All 15 v2.0 requirements shipped. See `.planning/milestones/v2.0-REQUIREMENTS.md`.

### Out of Scope

- Advanced photo editing (filters, cropping, adjustments) — keep app focused on watermark + share
- Photo library management / organization — outside core value proposition
- Cloud storage or sync — local-only operation
- Account creation / sign-in — anti-pattern for utility apps
- In-app camera / photo capture — users already have iPhone Camera
- Android version — iOS only


## Context

Shipped v1.0 MVP + v1.1 tech-debt hardening. 13,820 lines of Swift across 82+ files. Tech stack: Swift 6 / SwiftUI (iOS 18), AVFoundation, Core Image, ImageIO, PencilKit, Photos, AppIntents. Architecture: WatermarkCore Swift Package (shared engine) consumed by 3 targets (Main App, ShareExtension, PhotoEditExtension) via App Group container. 182+ commits across v1.0 (137) + v1.1 (45). 26 plans across 11 phases. 233 automated tests.

v1.1 hardened the dev process: REQUIREMENTS.md traceability now automated with `scripts/sync-requirements.sh` recurrence guard; wave-level `scripts/build-gate.sh` xcodebuild gate replaces untrustworthy self-checks; ViewModel layer-management duplication collapsed from ~186 lines to ~20 via WatermarkConfigurable protocol defaults; Photos extension HDR→JPEG warning now functional via proper sourceHasHDR/sourceFormatLabel population from PHContentEditingInput.

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
| WatermarkConfigurable protocol + defaults | Abstracts ViewModel interface for shared ControlsView; v1.1 added default implementations | ✓ Good — 186 duplicated lines collapsed to ~20 |
| CGColor Codable via RGBA [CGFloat] array | Preserves full color fidelity for config sync | ✓ Good — consistent across text/image/signature layers |
| Per-layer opacity via CIFilter.colorMatrix.aVector | Separate from per-element rendering alpha | ✓ Good — MULT-02 verified |
| D-12 compositing order: text → image → frame | Predictable layer stacking in single pass | ✓ Good — enforced in both photo and video paths |
| Backward-compatible Codable (decodeIfPresent with defaults) | Old configs decode without crash when new fields added | ✓ Good — Phase 5/7 enum extensions worked |
| PencilKit for signature capture | Apple-native drawing framework, vector stroke data | ✓ Good — SIGN-01 delivered, <100KB per signature |
| Two-phase Live Photo watermarking (still + video separately) | PHLivePhotoEditingContext requires PHContentEditingInput (unavailable from PhotosPicker) | ✓ Good — pragmatic bridge for main app flow |
| @AssistantIntent(schema: .photos.edit) for App Intents | Enables Siri AI integration per iOS 18 | ✓ Good — SYSI-02 delivered |
| Wave-level xcodebuild build gate | Replaces untrustworthy file-existence self-checks; catches build errors at source | ✓ Good — BUILD-01 verified, 3-target gate passes |
| REQUIREMENTS.md recurrence guard | Keeps checkboxes in sync per plan; exits non-zero on drift | ✓ Good — TRACE-01/02 verified, idempotent |
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
*Last updated: 2026-06-21 after v2.1 UI Redesign milestone start*
