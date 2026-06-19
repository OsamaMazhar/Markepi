# Requirements: Watermark

**Defined:** 2026-06-19
**Core Value:** Add a watermark and share it instantly — without ever cluttering the camera roll.
**Milestone:** v2.0 — Batch Processing, Template Management & Process Hardening

> v1.0 requirements (35 shipped) archived at `.planning/milestones/v1.0-REQUIREMENTS.md`
> v1.1 requirements (5 shipped) archived at `.planning/milestones/v1.1-REQUIREMENTS.md`

## v2.0 Requirements

Requirements for the v2.0 milestone. Each maps to a roadmap phase.

### Template Management (TMPL)

- [ ] **TMPL-01**: User can save current watermark configuration as a named, reusable template
- [ ] **TMPL-02**: User can browse saved templates in a list and apply one with a single tap
- [ ] **TMPL-03**: User can manage templates — rename, duplicate, and swipe-to-delete any saved template
- [ ] **TMPL-04**: User can mark a template as default; it auto-applies when new media is imported across all 3 targets (main app, share extension, Photos edit extension)
- [ ] **TMPL-05**: User can export a template as a `.watermarktemplate` file and import one via share sheet or Files picker
- [ ] **TMPL-06**: User can see a preview thumbnail of each template applied to the current media while browsing the template list

### Batch Processing (BATC)

- [ ] **BATC-01**: User can select multiple photos and videos in the picker and apply one watermark configuration to all items
- [ ] **BATC-02**: User sees per-item progress (e.g., "3 of 15") with a determinate progress bar, ETA, and cancel button with full temp file cleanup
- [ ] **BATC-03**: A single corrupted or unsupported file does not abort the entire batch; failures are collected and reported alongside successes after completion
- [ ] **BATC-04**: User can share all watermarked batch results together in a single share sheet (array of output URLs)
- [ ] **BATC-05**: User can adjust watermark position, scale, or text per individual item within a batch without affecting other items
- [ ] **BATC-06**: User can background the app during batch processing and receive a system notification when the batch completes
- [ ] **BATC-07**: User can process photos and videos together in a single batch operation with progress weighted by processing time

### Process Hardening (PHRO)

- [ ] **PHRO-01**: A per-phase VERIFICATION.md template is populated during execution with UAT checkboxes, automated test counts, and manual QA steps for each plan
- [ ] **PHRO-02**: A worktree-safety fix prevents git worktree branching failures from stale worktree directories, with pre-check, prune, and timestamp-suffixed fallback

## Future Requirements

Deferred to future milestone. Not in current roadmap.

### Deferred v2.1+

- **TMPL-F01**: Template folders/categories for organizing large template collections
- **TMPL-F02**: Template version history / undo for accidental overwrites
- **BATC-F01**: Batch-wide "smart auto-position" using on-device Vision framework to avoid faces
- **BATC-F02**: Batch preview — "spot check" watermark on one item before processing full batch

## Out of Scope

Explicitly excluded from v2.0. Documented to prevent scope creep.

| Item | Reason |
|------|--------|
| Template cloud sync (iCloud/custom backend) | Violates on-device-only privacy constraint; manual export/import sufficient |
| Template marketplace / sharing platform | Requires backend, auth, moderation — anti-pattern for utility app |
| Parallel/concurrent batch processing | Guaranteed memory explosion and iOS jetsam kill; sequential is mandatory |
| Auto-save batch results to camera roll | Violates core value: "share without cluttering camera roll" |
| Batch video format conversion | Re-encoding dozens of videos takes hours; keep source format/hold HDR |
| AI-based auto-positioning in batch | Latency per photo kills throughput; 8-position presets sufficient |
| Adaptive watermark sizing based on content | Complex detection without clear user value; proportional scaling already works |
| Template auto-detect/suggest via ML | Solves a non-problem; manual template selection is fast and predictable |
| Android version | iOS only (standing constraint) |
| Advanced photo editing (filters, cropping) | Dilutes core value proposition (standing constraint) |
| In-app camera / photo capture | Users already have iPhone Camera (standing constraint) |
| Cloud storage or sync | Local-only operation (standing constraint) |
| Account creation / sign-in | Anti-pattern for utility apps (standing constraint) |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TMPL-01 | — | Pending |
| TMPL-02 | — | Pending |
| TMPL-03 | — | Pending |
| TMPL-04 | — | Pending |
| TMPL-05 | — | Pending |
| TMPL-06 | — | Pending |
| BATC-01 | — | Pending |
| BATC-02 | — | Pending |
| BATC-03 | — | Pending |
| BATC-04 | — | Pending |
| BATC-05 | — | Pending |
| BATC-06 | — | Pending |
| BATC-07 | — | Pending |
| PHRO-01 | — | Pending |
| PHRO-02 | — | Pending |

**Coverage:**
- v2.0 requirements: 15 total
- Mapped to phases: 0
- Unmapped: 15 ⚠️

---
*Requirements defined: 2026-06-19*
*Last updated: 2026-06-19 after v2.0 milestone definition*
