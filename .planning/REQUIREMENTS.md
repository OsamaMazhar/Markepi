# Requirements: Watermark — v1.1 Tech Debt

**Defined:** 2026-06-18
**Core Value:** Add a watermark and share it instantly — without ever cluttering the camera roll.
**Milestone:** v1.1 — Address tech debt: REQUIREMENTS drift, ViewModel duplication, Photos HDR detection

> v1.0 requirements are archived under `.planning/milestones/v1.0-REQUIREMENTS.md` (all 36 shipped). This file scopes the v1.1 tech-debt milestone only. Requirements here are developer/codebase outcomes (not user-facing capabilities) since this is a hardening milestone.

## v1.1 Requirements

Requirements for the v1.1 tech-debt milestone. Each maps to a roadmap phase.

### Traceability (TRACE)

- [x] **TRACE-01**: REQUIREMENTS.md is audited against the current codebase — every validated requirement is checked and the traceability table accurately reflects which phase delivered it
- [x] **TRACE-02**: A reproducible mechanism keeps REQUIREMENTS.md checkboxes in sync with implemented features after each plan, so traceability no longer drifts manually between plans

### Refactor (REFA)

- [ ] **REFA-01**: `WatermarkConfigurable` protocol provides default implementations for shared layer-management operations (update position, update scale, remove layer, toggle white frame, add logo layer), eliminating ~186 lines of per-target duplication across the Main App, ShareExtension, and PhotoEditExtension ViewModels

### Photos HDR (PHDR)

- [ ] **PHDR-01**: `PhotosExtensionViewModel` populates `sourceHasHDR` and `sourceFormatLabel` from the `PHContentEditingInput` asset so the HDR→JPEG format-conversion warning fires correctly in the Photos extension context

### Build Gate (BUILD)

- [ ] **BUILD-01**: A wave-level build gate runs `xcodebuild` across all 3 targets (Main App, ShareExtension, PhotoEditExtension) after each execution wave — replacing file-existence-only self-checks — so broken builds surface at source rather than at milestone audit

## Future Requirements

Deferred from v1.0 (remain v2+ scope; not in this milestone's roadmap).

### Batch Processing (BATC)

- **BATC-01**: User can select multiple media items and watermark them in a single batch operation
- **BATC-02**: User can apply the same watermark configuration across an entire batch

### Customization Templates (CUST)

- **CUST-01**: User can save a watermark configuration as a reusable template
- **CUST-02**: User can load a previously saved template when starting a new watermark
- **CUST-03**: User can manage (rename/delete) saved templates
- **CUST-04**: User can set a default template applied automatically on import

### Process Hardening (PHRO) — deferred from v1.1

- **PHRO-01**: Per-phase VERIFICATION.md template populated during execution (retrospective gap — deferred this milestone)
- **PHRO-02**: Worktree-safety fix so the task tool creates per-agent branches (retrospective tooling item — deferred this milestone)

## Out of Scope

Explicitly excluded from v1.1. Documented to prevent scope creep.

| Item | Reason |
|------|--------|
| New user-facing features | v1.1 is a tech-debt/hardening milestone; no new product capabilities |
| AppDelegate/SceneDelegate separation (Retrospective Lesson 5) | Current consolidation in `WatermarkApp.swift` works; revisiting adds risk without user value |
| Per-phase VERIFICATION.md templating | Deferred to a future process-hardening milestone per user choice (PHRO-01) |
| Worktree-safety fix for task-tool branching | GSD tooling concern, not app code; deferred (PHRO-02) |
| Batch processing (BATC-01/02) | Remains v2+ scope from v1.0 |
| Customization templates (CUST-01–04) | Remains v2+ scope from v1.0 |
| Cloud storage / sync | Local-only operation (standing constraint) |
| Android version | iOS only (standing constraint) |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TRACE-01 | Phase 8 | Complete |
| TRACE-02 | Phase 8 | Complete |
| REFA-01 | Phase 10 | Pending |
| PHDR-01 | Phase 11 | Pending |
| BUILD-01 | Phase 9 | Pending |

**Coverage:**
- v1.1 requirements: 5 total
- Mapped to phases: 5 ✓
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-18*
*Last updated: 2026-06-18 after v1.1 milestone definition*
