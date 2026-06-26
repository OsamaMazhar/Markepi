---
gsd_state_version: 1.0
milestone: v2.2
milestone_name: Provenance & Authorship Protection
status: executing
stopped_at: Completed 19-03-PLAN.md plus Phase 19 review fixes
last_updated: "2026-06-26T13:30:00+02:00"
last_activity: 2026-06-26
progress:
  total_phases: 1
  completed_phases: 0
  total_plans: 4
  completed_plans: 3
  percent: 75
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-21)

**Core value:** Add a watermark and share it instantly — without ever cluttering the camera roll.
**Current focus:** Phase 19 — provenance-authorship-protection

## Current Position

Phase: 19 (provenance-authorship-protection) — EXECUTING
Plan: 4 of 4
Status: Ready to execute 19-04 after review-fix verification
Last activity: 2026-06-26

### v2.2 Phase Map

| Phase | Goal | Requirements |
|-------|------|--------------|
| 19. Provenance & Authorship Protection | Source-state analyzer, C2PA/IPTC rights records, user controls, export receipt, and MIT/Apache invisible watermark evaluation | PROV-01..04, AUTH-01..04, CTRL-01..04, IW-01..05, VERIFY-01..04 |

## Performance Metrics

**Velocity:**

- Total plans completed (all milestones): 26
- v2.2 plans completed: 3

**By Phase (v2.2):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 19. Provenance & Authorship Protection | 3/4 | — | — |

*Updated after each plan completion*
| Phase 19 P02 | 21min | 6 tasks | 11 files |
| Phase 19 P03 | 55min | 6 tasks | 14 files |
| Phase 19 review fixes | — | 7 findings | code + planning |

## Accumulated Context

### Decisions

- [v2.2 roadmap]: Phase 19 uses explicit source states instead of binary AI detection. Absence of a watermark is not proof of camera capture; unmarked custom/open-source GenAI output remains Unknown Provenance unless the user declares it.
- [v2.2 roadmap]: C2PA/IPTC records are the production backbone. Invisible watermarking is evaluated as a creator-protection/soft-binding layer, not an authenticity proof.
- [v2.2 roadmap]: Product-facing name is Markepi. Existing package/code identifiers such as `WatermarkCore`, `WatermarkEngine`, and `WatermarkConfiguration` remain implementation names unless separately renamed.
- [v2.2 roadmap]: C2PA signing is Secure Enclave first on real iOS devices, with local Keychain software fallback for simulator/development or unavailable hardware. Receipts must call this a Markepi device signing identity, not verified legal identity.
- [v2.2 roadmap]: Production implementation must be iOS-native in the app and Share Extension. Desktop scripts, Python/PyTorch flows, and cloud calls may support evaluation only; they cannot be required for export.
- [v2.2 roadmap]: Open-source tooling preference is Apache-2.0/MIT: `contentauth/c2pa-swift`, `contentauth/c2pa-rs`, Adobe TrustMark, and Microsoft InvisMark. Commercial vendors stay deferred/future.
- [v2.1 roadmap]: Phases 15-18 ordered by dependency: Design System (15) → Controls (16) → App Shell (17) → Cross-Target + A11y (18). Shared visual primitives ship first because every control and shell consumes them. Controls are rebuilt on those primitives before the app shell rearranges them into the bottom sheet. Cross-target parity and accessibility verification run last, after the redesigned ControlsView is final.
- [maintenance 2026-06-24]: The Photos native edit extension was retired. `ControlsView` is now consumed by the main app and Share Extension; historical XTG-02 evidence remains archived.
- [v2.1 roadmap]: Pure presentation-layer milestone. WatermarkEngine, WatermarkConfigurable protocol surface, ViewModels' public behavior, and the data/config model are frozen. Every requirement is an observable look-and-feel change.
- [v2.1 roadmap]: Layout decision — inspector bottom-sheet: full-bleed photo hero + resizable detent sheet (peek + expanded) + pinned Share action bar. Adaptive light/dark (NOT permanent dark). iOS 26 Liquid Glass on the chrome layer with graceful fallback on the iOS 18 floor.
- [Phase 19 P02 correction]: c2pa-spike completed with PREFERRED verdict. `contentauth/c2pa-swift` v0.0.12 is linked through WatermarkCore, and `C2PASwiftProvenanceClient` is the default production client. `NoopC2PAProvenanceClient` remains only for fallback builds and injected tests.
- [Phase 19 review fixes]: photo signing now signs the already-rendered export in place, creator gating is enforced in the engine, provenance receipts/controls are wired through photo, video, Live Photo, batch, app, and Share Extension paths, source analysis reads C2PA summaries at import time, signing identity tags cannot mislabel software keys as Secure Enclave, and the receipt sheet can continue to sharing.

### Pending Todos

- Execute `.planning/phases/19-provenance-authorship-protection/19-04-PLAN.md`.
- Run build/test verification when local approval/runtime budget permits.
- Decide after 19-04 whether invisible watermarking ships, remains disabled, or is deferred.

### Blockers/Concerns

- **Verification budget**: Phase 19 review fixes are statically reconciled here; rerun `swift test` and `bash scripts/build-gate.sh` when local approval/runtime budget permits.
- **Invisible watermarking**: TrustMark/InvisMark evaluation must stay behind a production gate. Do not ship model binaries or active invisible marks until quality, HDR, metadata, performance, and license checks pass.
- **Authenticity language**: Unknown, user-declared, suspected-AI, or AI-marked media must never receive verified-camera or "No AI Used" labels.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260624-tag | Implement the Photo Edit Extension removal audit | 2026-06-25 | working tree | [260624-tag-implement-the-photo-edit-extension-remov](./quick/260624-tag-implement-the-photo-edit-extension-remov/) |
| 260624-t4x | Save the Photo Edit Extension removal audit findings in a Markdown file | 2026-06-24 | 4f0b038 | [260624-t4x-save-the-photo-edit-extension-removal-au](./quick/260624-t4x-save-the-photo-edit-extension-removal-au/) |
| 260626-fix | Fix Phase 19 provenance/authorship review issues | 2026-06-26 | working tree | [260626-fix-phase-19-review-issues](./quick/260626-fix-phase-19-review-issues/) |

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| v2.2+ | Drag-to-position watermark on preview (VIS-05) | Deferred — beyond 9 presets; future milestone | 2026-06-21 |
| v2.2+ | Glass-morph transitions via glassEffectID (VIS-06) | Deferred — polish beyond v2.1 scope | 2026-06-21 |
| v2.1+ | Template folders/categories | Deferred — premature at v2.0 | 2026-06-19 |
| v2.1+ | Template version history/undo | Deferred — overwrite-on-save sufficient for utility app | 2026-06-19 |
| v2.1+ | Batch "smart auto-position" (Vision framework) | Deferred — latency per photo kills throughput | 2026-06-19 |
| v2.1+ | Batch preview — spot check before full batch | Deferred — per-item override provides equivalent value | 2026-06-19 |

## Session Continuity

Last session: 2026-06-26T13:30:00+02:00
Stopped at: Completed 19-03-PLAN.md plus Phase 19 review fixes
Resume file: None

## Operator Next Steps

- Execute `.planning/phases/19-provenance-authorship-protection/19-04-PLAN.md`
