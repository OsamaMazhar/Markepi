# Roadmap: Watermark

## Milestones

- ✅ **v1.0 MVP** — Phases 1-7 (shipped 2026-06-18)
- 🚧 **v1.1 Tech Debt Hardening** — Phases 8-11 (in progress)

## Overview

v1.1 is a focused tech-debt milestone — no new user-facing features. It hardens the v1.0 codebase and dev process across four fronts: (1) reconcile REQUIREMENTS.md traceability with the shipped code and add a recurrence guard so checkboxes no longer drift per plan; (2) add a wave-level `xcodebuild` gate so broken builds surface at source, not at milestone audit; (3) collapse ~186 lines of duplicated ViewModel layer-management code via `WatermarkConfigurable` protocol default implementations; (4) fix the Photos extension's missing HDR/format population so the HDR→JPEG warning fires correctly. Phases continue numbering from v1.0 (Phase 7 → Phase 8).

## Phases

**Phase Numbering:**
- Integer phases (8, 9, 10, 11): Planned v1.1 milestone work
- Decimal phases (e.g., 9.1): Urgent insertions (marked INSERTED)

v1.0 phases 1-7 are archived under `.planning/milestones/v1.0-ROADMAP.md`.

- [x] **Phase 8: Traceability Reconciliation & Recurrence Guard** - Audit REQUIREMENTS.md against shipped v1.0 code and add a mechanism that keeps checkboxes in sync per plan (completed 2026-06-18)
- [ ] **Phase 9: Wave-Level Build Gate** - Per-wave xcodebuild verification across all 3 targets, replacing file-existence-only self-checks [🔨 planned]
- [ ] **Phase 10: WatermarkConfigurable Protocol Defaults** - Default implementations for layer-management ops, collapsing ~186 duplicated lines across 3 ViewModels to ~20
- [ ] **Phase 11: Photos Extension HDR Detection** - Populate sourceHasHDR/sourceFormatLabel in PhotosExtensionViewModel so HDR→JPEG warning fires in Photos extension

## Phase Details

### Phase 8: Traceability Reconciliation & Recurrence Guard
**Goal**: REQUIREMENTS.md traceability is reconciled with the v1.0 codebase and a recurrence guard prevents future per-plan checkbox drift
**Depends on**: Nothing (first phase of v1.1)
**Requirements**: TRACE-01, TRACE-02
**Success Criteria** (what must be TRUE):
  1. Every v1.0 validated requirement in `.planning/milestones/v1.0-REQUIREMENTS.md` has a checked checkbox and an accurate phase reference in its traceability table — 0 unmapped, 0 stale entries
  2. A reproducible mechanism (script, make target, or workflow hook) exists that updates REQUIREMENTS.md checkboxes after each plan completes, with documented invocation
  3. Running the recurrence-guard mechanism against a plan with completed requirements produces the correct checkbox state without manual edits (verified by dry-run or test)
  4. The v1.1 REQUIREMENTS.md traceability table shows all 5 v1.1 requirements (TRACE-01, TRACE-02, REFA-01, PHDR-01, BUILD-01) mapped to their phases with Status "Pending"
**Plans**: 2 plans

Plans:
- [x] 08-01-PLAN.md — Reconcile v1.0 archive REQUIREMENTS.md: flip 10 unchecked checkboxes, add 5 missing checkboxes, update 15 stale traceability entries, reclassify 7 shipped Phase 7 requirements v2→v1, fix coverage counts, add Reconciliation Note
- [x] 08-02-PLAN.md — Build recurrence guard: create scripts/sync-requirements.sh, scripts/test-sync-requirements.sh (fixture test with 3 branches), update AGENTS.md with post-plan step and not_found resolution path

### Phase 9: Wave-Level Build Gate
**Goal**: A per-wave xcodebuild verification runs across all 3 targets so broken builds surface at source, not at milestone audit
**Depends on**: Nothing technically (independent tooling); scheduled after Phase 8 to keep the TRACE audit baseline clean and before Phases 10-11 so code-changing phases are protected by the gate
**Requirements**: BUILD-01
**Success Criteria** (what must be TRUE):
  1. A build-gate script or make target invokes `xcodebuild` for all 3 targets (Main App, ShareExtension, PhotoEditExtension) and exits non-zero on any build failure
  2. The build gate is wired into the execute-phase wave boundary so it runs automatically after each execution wave (not just at milestone audit)
  3. A broken-build scenario (e.g., an intentional syntax error injected into a source file) is caught by the gate and blocks wave progression — verified by a test or documented dry-run
  4. The build gate replaces file-existence-only self-checks as the source of truth for "build PASSED" in the execute workflow
**Plans**: 1 plan

Plans:
- [ ] 09-01-PLAN.md — Create build-gate.sh (xcodebuild gate for 3 targets), test-build-gate.sh (fixture test with 3 assertion branches), and AGENTS.md Post-Wave Build Gate section

### Phase 10: WatermarkConfigurable Protocol Defaults
**Goal**: The WatermarkConfigurable protocol provides default implementations for shared layer-management operations, collapsing ~186 duplicated lines across 3 ViewModels to ~20
**Depends on**: Phase 9 (build gate in place to catch any refactor-induced breakage across the 3 targets at source)
**Requirements**: REFA-01
**Success Criteria** (what must be TRUE):
  1. `WatermarkConfigurable` protocol extension provides default implementations for `updateLayerPosition`, `updateLayerScale`, `removeLayer`, `toggleWhiteFrame`, and `addLogoLayer`
  2. grep finds zero duplicated implementations of those 5 ops across MainAppViewModel, ShareExtensionViewModel, and PhotosExtensionViewModel — each ViewModel calls the protocol default, not its own copy
  3. Total layer-management code across the 3 ViewModels is reduced from ~186 lines to ~20 lines (measured by grep/line count)
  4. All 227 existing automated tests still pass after the refactor
  5. The Phase 9 build gate passes for all 3 targets after the refactor
**Plans**: TBD

### Phase 11: Photos Extension HDR Detection
**Goal**: PhotosExtensionViewModel populates sourceHasHDR and sourceFormatLabel from PHContentEditingInput so the HDR→JPEG format-conversion warning fires correctly in the Photos extension context
**Depends on**: Phase 10 (uses the refactored PhotosExtensionViewModel from the protocol-defaults refactor)
**Requirements**: PHDR-01
**Success Criteria** (what must be TRUE):
  1. PhotosExtensionViewModel sets `sourceHasHDR` based on HDR detection from PHContentEditingInput's full-size asset (gain map presence or transfer function inspection — consistent with the Main App's HDR detection approach)
  2. PhotosExtensionViewModel sets `sourceFormatLabel` from the input asset's format (HEIC/JPEG/DNG/etc.)
  3. When a Dolby Vision or HLG HDR source is loaded in the Photos extension and the user selects JPEG output, the HDR→JPEG format-conversion warning fires (verified by test or manual QA)
  4. All 227 existing automated tests still pass and the Phase 9 build gate passes for all 3 targets
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 8 → 9 → 10 → 11

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Core Engine & Photo Pipeline | v1.0 | 3/3 | Complete | 2026-06-17 |
| 2. Main App (Photo Watermark & Share) | v1.0 | 2/2 | Complete | 2026-06-17 |
| 3. Video Processing & Share Extension | v1.0 | 3/3 | Complete | 2026-06-17 |
| 4. Photos Edit Extension & Polish | v1.0 | 2/2 | Complete | 2026-06-18 |
| 5. Extended Engine (ProRAW, EXIF, Multi-Layer) | v1.0 | 4/4 | Complete | 2026-06-18 |
| 6. Export Control & UX Polish | v1.0 | 3/3 | Complete | 2026-06-18 |
| 7. Additional Inputs & System Integration (v2) | v1.0 | 3/3 | Complete | 2026-06-18 |
| 8. Traceability Reconciliation & Recurrence Guard | v1.1 | 2/2 | Complete   | 2026-06-18 |
| 9. Wave-Level Build Gate | v1.1 | 0/1 | Not started | - |
| 10. WatermarkConfigurable Protocol Defaults | v1.1 | 0/TBD | Not started | - |
| 11. Photos Extension HDR Detection | v1.1 | 0/TBD | Not started | - |
