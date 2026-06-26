# Watermark

## What This Is

An iOS app that lets users add watermarks or white-frame metadata overlays to photos and videos, then immediately share them to social media without saving. Users can import media from the in-app picker, the iOS share sheet, the Files app, "Open In" from other apps, home screen quick actions, or Siri/Shortcuts. Works for both photos and videos (including Live Photos and ProRAW DNG) while preserving all metadata, HDR, and original image quality. Supports text, image/logo, signature, and white-frame overlays with per-layer opacity, visibility, and 8-position placement.

## Core Value

Add a watermark and share it instantly — without ever cluttering the camera roll.

## Current State

**Shipped:** v2.1 (2026-06-22) — 4 phases, 11 plans, 6 requirements all satisfied.

**Maintenance update (2026-06-24):** The Photos native edit extension was retired. Supported entry points are now the main app and Share Extension; historical milestone records remain unchanged.

**v2.1 delivered:**
- Visual Design System — Liquid Glass chrome, MarkepiTypography, MarkepiButtonStyle, MarkepiScrollEdgeProtection, MarkepiPillBar shared across the main app and Share Extension
- Redesigned ControlsView — Pill-bar-driven 3-section layout with Menu-based pickers, all 6 sub-views restyled on Markepi design
- Inspector Bottom-Sheet Shell — Full-bleed preview hero with drag-to-resize glass detent sheet and pinned Share action bar
- Cross-Target Parity — automated snapshots verify the remaining Share Extension; VoiceOver labels + Reduce Motion gating + Dynamic Type sheet scaling + shared EmptyStateView

**v2.1 stats:** 4 phases, 11 plans, 6/6 requirements satisfied. Built on v2.0 foundation (37 files changed, +2,701/-528 lines).

<details>
<summary>✅ v2.0 Batch, Templates & Process (Phases 12-14) — SHIPPED 2026-06-19</summary>

- Template Management — save, load, manage, and auto-apply watermark templates across the main app and Share Extension (6 requirements)
- Batch Processing — multi-item watermarking with shared config, per-item adjustments, progress tracking, error resilience (7 requirements)
- Process Hardening — VERIFICATION.md per-plan population gate + worktree safety pre-check/fallback (2 requirements)

3 phases, 10 plans, 15/15 requirements satisfied.
</details>

<details>
<summary>✅ v1.0 MVP + v1.1 Tech Debt Hardening (Phases 1-11) — SHIPPED 2026-06-18</summary>

13,820+ lines Swift across 82+ files. 233+ automated tests. 26 plans across 11 phases. Core engine, all 3 entry points, video processing, ProRAW, multi-layer compositing, export controls, signature capture, Siri/Shortcuts integration.

</details>

## Current Focus

Planning next milestone. See `.planning/ROADMAP.md`.

## Requirements

### Validated

- ✓ MEDI-01 — Import photos/videos from in-app picker — v1.0
- ✓ MEDI-02 — Receive photos/videos via iOS share sheet — v1.0
- ✓ MEDI-03 — Receive photos/videos via Photos app native edit extension — v1.0; retired 2026-06-24
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
- ✓ PHDR-01 — PhotosExtensionViewModel HDR/source-format detection — v1.1; retired with the extension 2026-06-24
- ✓ BUILD-01 — Wave-level xcodebuild build gate — v1.1; now covers the two remaining targets
- ✓ TMPL-01 through TMPL-06 — Template CRUD + auto-default-on-import — v2.0; now shared by two targets
- ✓ BATC-01 through BATC-07 — Batch processing with per-item adjustments, progress, error resilience — v2.0
- ✓ PHRO-01 — Per-phase VERIFICATION.md populated during execution — v2.0
- ✓ PHRO-02 — Worktree safety pre-check + timestamp fallback — v2.0
- ✓ XTG-01 — Share Extension renders ControlsView correctly — v2.1
- ✓ XTG-02 — Photos Edit Extension renders ControlsView correctly — v2.1; retired with the extension 2026-06-24
- ✓ UXQ-01 — Dynamic Type scales controls up to 200% — v2.1
- ✓ UXQ-02 — VoiceOver labels preserved or improved — v2.1
- ✓ UXQ-03 — Reduce Motion / Reduce Transparency respected — v2.1
- ✓ UXQ-04 — Empty state redesigned to match visual system — v2.1

### All Requirements Satisfied

All 38 requirements across v1.0/v1.1/v2.0/v2.1 shipped. See milestones archive.

### Out of Scope

- Advanced photo editing (filters, cropping, adjustments) — keep app focused on watermark + share
- Photo library management / organization — outside core value proposition
- Cloud storage or sync — local-only operation
- Account creation / sign-in — anti-pattern for utility apps
- In-app camera / photo capture — users already have iPhone Camera
- Android version — iOS only


## Context

Shipped v1.0 MVP + v1.1 tech-debt hardening + v2.0 batch/templates + v2.1 UI redesign. Tech stack: Swift 6 / SwiftUI (iOS 18), AVFoundation, Core Image, ImageIO, PencilKit, Photos, AppIntents. Architecture: WatermarkCore Swift Package (shared engine) consumed by two targets (Main App and ShareExtension) via an App Group container. The previously shipped PhotoEditExtension was retired on 2026-06-24.

v2.1 rebuilt the presentation layer: Liquid Glass design system with semantic typography, pill-bar-driven ControlsView, inspector bottom-sheet shell, cross-target snapshot verification, and accessibility polish (VoiceOver, Reduce Motion, Dynamic Type). Zero changes to WatermarkEngine, ViewModels, or data model — pure presentation-layer rework.

v1.1 hardened the dev process: REQUIREMENTS.md traceability became automated with `scripts/sync-requirements.sh`; the wave-level `scripts/build-gate.sh` replaced file-existence self-checks; and ViewModel layer-management duplication collapsed via WatermarkConfigurable protocol defaults. Its Photos extension HDR work remains historical evidence for the extension retired in 2026.

## Constraints

- **Platform**: iOS 18+ — native Swift/SwiftUI with a UIKit bridge for the Share Extension entry point
- **Quality**: Must preserve HDR, color profile, and all EXIF/metadata in output
- **Performance**: Watermarking must work on-device for large video files without excessive memory pressure
- **Privacy**: No network calls required; all processing on-device
- **Compatibility**: Support in-app import and the iOS share sheet app extension

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Native iOS (Swift/SwiftUI) | Required for the share sheet and HDR/metadata preservation | ✓ Good — main app and Share Extension supported |
| On-device rendering only | Privacy, offline use, and avoiding quality loss from server uploads | ✓ Good — zero network calls |
| No save-by-default workflow | Core value: watermark and share, don't clutter camera roll | ✓ Good — share-without-saving across all flows |
| CGImageSource → CIImage → CGImageDestination pipeline | Only Apple-native path that preserves HDR gain maps + all metadata | ✓ Good — QUAL-01/02/03 verified |
| WatermarkCore Swift Package shared by 2 targets | Eliminates code duplication between app and Share Extension | ✓ Good — single engine source of truth |
| App Group container for config sync | Bidirectional config sync between app and Share Extension | ✓ Good — AppGroupConfigSync works across both targets |
| WatermarkConfigurable protocol + defaults | Abstracts ViewModel interface for shared ControlsView; v1.1 added default implementations | ✓ Good — 186 duplicated lines collapsed to ~20 |
| CGColor Codable via RGBA [CGFloat] array | Preserves full color fidelity for config sync | ✓ Good — consistent across text/image/signature layers |
| Per-layer opacity via CIFilter.colorMatrix.aVector | Separate from per-element rendering alpha | ✓ Good — MULT-02 verified |
| D-12 compositing order: text → image → frame | Predictable layer stacking in single pass | ✓ Good — enforced in both photo and video paths |
| Backward-compatible Codable (decodeIfPresent with defaults) | Old configs decode without crash when new fields added | ✓ Good — Phase 5/7 enum extensions worked |
| PencilKit for signature capture | Apple-native drawing framework, vector stroke data | ✓ Good — SIGN-01 delivered, <100KB per signature |
| Two-phase Live Photo watermarking (still + video separately) | PhotosPicker supplies component URLs rather than a native editing session | ✓ Good — supports the main app flow without a Photos edit extension |
| @AssistantIntent(schema: .photos.edit) for App Intents | Enables Siri AI integration per iOS 18 | ✓ Good — SYSI-02 delivered |
| Wave-level xcodebuild build gate | Replaces untrustworthy file-existence self-checks; catches build errors at source | ✓ Good — covers WatermarkApp and ShareExtension |
| REQUIREMENTS.md recurrence guard | Keeps checkboxes in sync per plan; exits non-zero on drift | ✓ Good — TRACE-01/02 verified, idempotent |
| Consolidated AppDelegate + SceneDelegate into WatermarkApp.swift | Avoided pbxproj complexity for new target files | ⚠️ Revisit — works but deviates from conventional separation |
| Markepi design system as WatermarkCore/DesignSystem/ subpackage | Shared visual primitives consumed by both targets; zero duplication | ✓ Good — app and Share Extension render consistently |
| InspectorSheetView as ZStack-compatible custom sheet | `.inspector` API unavailable at iOS 18 minimum; custom DragGesture-based approach avoids it | ✓ Good — works across all iOS 18+ devices |
| ControlsView reorganized via MarkepiPillBar sections | 3-section layout (Watermark/Style/Output) replaces flat stack; sub-views unchanged | ✓ Good — cleaner UX, zero ViewModel changes |
| Snapshot tests for the Share Extension root via UIHostingController | Proves ControlsView renders in the remaining extension without manual QA | ✓ Good — Share Extension references retained |
| Share Extension root view in WatermarkCore package | Enables @testable import from package tests; generic over its rendering protocol | ✓ Good — testability without production code duplication |
| Reduce Motion gating via accessibilityReduceMotion environment | All animations (pill bar, preview, batch overlay) respect system setting | ✓ Good — UXQ-03 verified |

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
*Last updated: 2026-06-24 after retiring the Photos native edit extension*
