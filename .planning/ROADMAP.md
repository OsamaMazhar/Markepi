# Roadmap: Markepi

## Milestones

- ✅ **v1.0 MVP** — Phases 1-7 (shipped 2026-06-18)
- ✅ **v1.1 Tech Debt Hardening** — Phases 8-11 (shipped 2026-06-18)
- ✅ **v2.0 Batch, Templates & Process** — Phases 12-14 (shipped 2026-06-19)
- ✅ **v2.1 UI Redesign** — Phases 15-18 (shipped 2026-06-22)
- 🚧 **v2.2 Provenance & Authorship Protection** — Phase 19 (planned)

## Phases

### v2.2 Provenance & Authorship Protection (Phase 19)

- [ ] **Phase 19: Provenance & Authorship Protection** - Conservative source-state analyzer, metadata/C2PA preservation, user-controlled rights/protection settings, export receipt, and MIT/Apache invisible watermark evaluation.

## Phase Details

### Phase 19: Provenance & Authorship Protection

**Goal**: Give photographers a professional, on-device authorship protection workflow that preserves existing AI provenance, adds honest C2PA/IPTC rights records, and optionally evaluates invisible creator watermarking without making unsupported camera-authenticity claims.
**Depends on**: v2.1 UI Redesign complete; existing image/video metadata preservation pipeline; Share Extension parity
**Requirements**: PROV-01..04, AUTH-01..04, CTRL-01..04, IW-01..05, VERIFY-01..04
**Success Criteria** (what must be TRUE):

  1. Every import receives a source-provenance report with one of five states: Verified Camera Capture, Marked AI / AI-Edited, User-Declared, Unknown Provenance, or Suspected AI
  2. Unmarked files, including open-source/custom GenAI images with no watermark, remain Unknown Provenance unless the user declares them
  3. Existing C2PA/JUMBF, XMP/IPTC, EXIF, HDR gain maps, color profiles, and AI provenance are preserved or carried as source ingredients
  4. Exports can include signed C2PA manifests and IPTC rights metadata using Apache-2.0/MIT CAI/C2PA tooling
  5. Users can control rights, privacy, signing, disclosure, and creator-protection settings, but cannot enable unsupported verified-camera/no-AI claims
  6. Adobe TrustMark (MIT) and Microsoft InvisMark (MIT) are evaluated behind a no-shipping gate before any invisible watermark provider becomes active

**Plans**: 4 plans in 2 waves
Plans:
**Wave 1**

- [x] 19-01-PLAN.md — Provenance State Model & Import Analyzer (PROV-01, PROV-02, PROV-03, VERIFY-02)
- [x] 19-02-PLAN.md — Metadata Preservation & C2PA Manifest Integration (PROV-04, AUTH-01, AUTH-02, AUTH-03, AUTH-04, VERIFY-03, VERIFY-04)

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 19-03-PLAN.md — User Controls, Disclosure UI & Export Receipt (CTRL-01, CTRL-02, CTRL-03, CTRL-04, VERIFY-01)
- [ ] 19-04-PLAN.md — Invisible Watermark Evaluation Harness & Production Gate (IW-01, IW-02, IW-03, IW-04, IW-05)

See `.planning/milestones/v2.2-ROADMAP.md` for full phase details.

---

<details>
<summary>✅ v2.1 UI Redesign (Phases 15-18) — SHIPPED 2026-06-22</summary>

- [x] Phase 15: Visual Design System & Shared Primitives (3/3 plans) — completed 2026-06-22
- [x] Phase 16: Redesigned Controls (2/2 plans) — completed 2026-06-21
- [x] Phase 17: Inspector Bottom-Sheet Shell (3/3 plans) — completed 2026-06-22
- [x] Phase 18: Cross-Target Parity & Accessibility Polish (3/3 plans) — completed 2026-06-22

See `.planning/milestones/v2.1-ROADMAP.md` for full phase details.

</details>

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 15. Visual Design System & Shared Primitives | 3/3 | Complete   | 2026-06-22 |
| 16. Redesigned Controls | 2/2 | Complete   | 2026-06-21 |
| 17. Inspector Bottom-Sheet Shell | 3/3 | Complete   | 2026-06-22 |
| 18. Cross-Target Parity & Accessibility Polish | 3/3 | Complete   | 2026-06-22 |
| 19. Provenance & Authorship Protection | 2/4 | In Progress|  |

---

<details>
<summary>✅ v2.0 Batch, Templates & Process (Phases 12-14) — SHIPPED 2026-06-19</summary>

- [x] Phase 12: Template Management (5/5 plans) — completed 2026-06-19
- [x] Phase 13: Batch Processing (3/3 plans) — completed 2026-06-19
- [x] Phase 14: Process Hardening (2/2 plans) — completed 2026-06-19

See `.planning/milestones/v2.0-ROADMAP.md` for full phase details.

</details>

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
