# Roadmap: Watermark

## Milestones

- ✅ **v1.0 MVP** — Phases 1-7 (shipped 2026-06-18)
- ✅ **v1.1 Tech Debt Hardening** — Phases 8-11 (shipped 2026-06-18)
- 🚧 **v2.0 Batch, Templates & Process** — Phases 12-14 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-7) — SHIPPED 2026-06-18</summary>

- [x] Phase 1: Core Engine & Photo Pipeline (3/3 plans) — completed 2026-06-17
- [x] Phase 2: Main App (Photo Watermark & Share) (2/2 plans) — completed 2026-06-17
- [x] Phase 3: Video Processing & Share Extension (3/3 plans) — completed 2026-06-17
- [x] Phase 4: Photos Edit Extension & Polish (2/2 plans) — completed 2026-06-18
- [x] Phase 5: Extended Engine (ProRAW, EXIF, Multi-Layer) (4/4 plans) — completed 2026-06-18
- [x] Phase 6: Export Control & UX Polish (3/3 plans) — completed 2026-06-18
- [x] Phase 7: Additional Inputs & System Integration (v2) (3/3 plans) — completed 2026-06-18

See `.planning/milestones/v1.0-ROADMAP.md` for full phase details.

</details>

<details>
<summary>✅ v1.1 Tech Debt Hardening (Phases 8-11) — SHIPPED 2026-06-18</summary>

- [x] Phase 8: Traceability Reconciliation & Recurrence Guard (2/2 plans) — completed 2026-06-18
- [x] Phase 9: Wave-Level Build Gate (1/1 plan) — completed 2026-06-18
- [x] Phase 10: WatermarkConfigurable Protocol Defaults (2/2 plans) — completed 2026-06-18
- [x] Phase 11: Photos Extension HDR Detection (1/1 plan) — completed 2026-06-18

See `.planning/milestones/v1.1-ROADMAP.md` for full phase details.

</details>

## 🚧 v2.0: Batch, Templates & Process (In Progress)

**Milestone Goal:** Ship deferred v1.0 features: batch processing with per-item config adjustments, full template CRUD + auto-default, and process hardening.

- [ ] **Phase 12: Template Management** — Save/load/manage watermark templates with auto-default on import
- [ ] **Phase 13: Batch Processing** — Multi-item watermarking with shared config, per-item adjustments, and progress tracking
- [ ] **Phase 14: Process Hardening** — VERIFICATION.md templating and worktree-safety fix

## Phase Details

### Phase 12: Template Management

**Goal**: Users can save, load, manage, and auto-apply watermark templates across all app entry points
**Depends on**: Phase 11 (v1.1 shipped foundation)
**Requirements**: TMPL-01, TMPL-02, TMPL-03, TMPL-04, TMPL-05, TMPL-06
**Success Criteria** (what must be TRUE):

  1. User can save the current watermark configuration as a named template and see it appear in the template list
  2. User can browse saved templates with preview thumbnails applied to current media, and tap one to apply it instantly
  3. User can rename, duplicate, and swipe-to-delete any saved template from the list
  4. User can mark a template as default; the default template auto-applies when new media is imported in the main app, share extension, and Photos edit extension
   5. User can export a template as a `.watermarktemplate` file and import one from Files or share sheet into the template library

**Plans**: 5 plans

Plans:
**Wave 1**

- [ ] 12-01-PLAN.md — Core data layer: Template model, TemplateStore with migration chain, App.entitlements

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 12-02-PLAN.md — Protocol additions, Save as Template button, SaveTemplateAlertModifier

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 12-03-PLAN.md — Template list UI: row view, preview thumbnails, import, context menus
- [ ] 12-05-PLAN.md — Extension auto-apply + .watermarktemplate UTI registration

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 12-04-PLAN.md — Main app integration: WatermarkViewModel auto-apply, ContentView sheet+alert

**UI hint**: yes

### Phase 13: Batch Processing

**Goal**: Users can watermark multiple photos and videos in one operation with shared configuration, per-item adjustments, progress tracking, and error resilience
**Depends on**: Phase 12 (templates provide auto-default-on-import for batch workflows)
**Requirements**: BATC-01, BATC-02, BATC-03, BATC-04, BATC-05, BATC-06, BATC-07
**Success Criteria** (what must be TRUE):

  1. User can select multiple photos and videos in the picker and apply a single watermark configuration to all items simultaneously
  2. User sees per-item progress with a determinate progress bar and ETA, can cancel processing at any time with full temp file cleanup, and can background the app to receive a system notification when the batch completes
  3. When one file in a batch fails (corrupted or unsupported), the remaining items continue processing; a summary reports successes and failures after completion
  4. User can share all successfully watermarked batch results together in a single share sheet
  5. User can adjust watermark position, scale, or text for an individual item within the batch without affecting other items

**Plans**: TBD
**UI hint**: yes

### Phase 14: Process Hardening

**Goal**: GSD workflow tooling improvements that make phase execution more reliable and auditable
**Depends on**: Nothing (independent tooling changes; zero app code impact)
**Requirements**: PHRO-01, PHRO-02
**Success Criteria** (what must be TRUE):

  1. A per-phase VERIFICATION.md template is populated during execution with UAT checkboxes, automated test counts, and manual QA steps — no empty template left unfilled after a plan completes
  2. Git worktree operations are protected against stale worktree directory failures: a pre-check detects stale worktrees, prunes when safe, and falls back to timestamp-suffixed directory names when the primary path is occupied

**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Core Engine & Photo Pipeline | v1.0 | 3/3 | Complete | 2026-06-17 |
| 2. Main App (Photo Watermark & Share) | v1.0 | 2/2 | Complete | 2026-06-17 |
| 3. Video Processing & Share Extension | v1.0 | 3/3 | Complete | 2026-06-17 |
| 4. Photos Edit Extension & Polish | v1.0 | 2/2 | Complete | 2026-06-18 |
| 5. Extended Engine (ProRAW, EXIF, Multi-Layer) | v1.0 | 4/4 | Complete | 2026-06-18 |
| 6. Export Control & UX Polish | v1.0 | 3/3 | Complete | 2026-06-18 |
| 7. Additional Inputs & System Integration (v2) | v1.0 | 3/3 | Complete | 2026-06-18 |
| 8. Traceability Reconciliation & Recurrence Guard | v1.1 | 2/2 | Complete | 2026-06-18 |
| 9. Wave-Level Build Gate | v1.1 | 1/1 | Complete | 2026-06-18 |
| 10. WatermarkConfigurable Protocol Defaults | v1.1 | 2/2 | Complete | 2026-06-18 |
| 11. Photos Extension HDR Detection | v1.1 | 1/1 | Complete | 2026-06-18 |
| 12. Template Management | v2.0 | 0/TBD | Not started | — |
| 13. Batch Processing | v2.0 | 0/TBD | Not started | — |
| 14. Process Hardening | v2.0 | 0/TBD | Not started | — |
