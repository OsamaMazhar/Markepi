# Phase 8: Traceability Reconciliation & Recurrence Guard - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers two outcomes and **no new app/user-facing features**:

1. **TRACE-01 (one-time reconciliation):** Edit the archived `.planning/milestones/v1.0-REQUIREMENTS.md` so every shipped v1.0 requirement has a checked `[x]` checkbox, an accurate traceability Status, and correct section placement — 0 unmapped, 0 stale entries.
2. **TRACE-02 (recurrence guard):** A repo-local bash script that, after each plan completes, reads the plan's SUMMARY.md `requirements-completed` frontmatter and invokes the existing `gsd-tools requirements mark-complete` command to flip the corresponding checkboxes + traceability Status in the current `.planning/REQUIREMENTS.md`. Documented in AGENTS.md as a post-plan step the gsd-executor runs. Verified by a self-contained fixture-based bash test.

**Already satisfied (no work needed):** Success criteria #4 — the v1.1 REQUIREMENTS.md traceability table already shows all 5 v1.1 requirements (TRACE-01, TRACE-02, REFA-01, PHDR-01, BUILD-01) mapped to their phases with Status "Pending". This was completed at v1.1 roadmap creation.

**Out of scope:** Editing the GSD workflow files in `~/.config/get-shit-done/` (the guard is repo-local, not auto-wired into the shared execute-plan workflow). Extending `gsd-tools` with new flags/handlers (the existing `requirements mark-complete` is used as-is). New user-facing features (v1.1 is a tech-debt milestone). Per-phase VERIFICATION.md templating (PHRO-01, deferred). Worktree-safety fixes (PHRO-02, deferred).

</domain>

<decisions>
## Implementation Decisions

### Guard Wiring & Trigger
- **D-01:** The recurrence guard is a **repo-local bash script** at `scripts/sync-requirements.sh` (new `scripts/` dir at repo root). Bash chosen because the script is pure glue: it extracts `requirements-completed` from a SUMMARY's frontmatter and passes the IDs to `gsd-tools requirements mark-complete`. Zero dependencies.
- **D-02:** The script takes the **SUMMARY path as an explicit argument** — `scripts/sync-requirements.sh <path-to-NN-MM-SUMMARY.md>`. No auto-discovery. Rationale: `parallelization: true` is enabled in config, so multiple SUMMARYs can be written in the same wave; mtime-based discovery could pick the wrong one. The executor always knows which plan's SUMMARY just completed.
- **D-03:** The **gsd-executor runs the script as a documented post-plan step**, immediately after writing the plan's SUMMARY.md (passing that SUMMARY's path). This is documented in `AGENTS.md`. This is the "semi-automatic" sweet spot: the agent enforces it as part of plan completion without editing the shared GSD workflow files in `~/.config/`. The script is idempotent, so human re-runs are safe.
- **D-04:** The script's pipeline: `gsd-tools frontmatter <summary> --pick requirements-completed` → parse the JSON array of IDs → `gsd-tools requirements mark-complete <comma-joined-ids>`. The script relays `mark-complete`'s JSON result (`marked_complete`, `already_complete`, `not_found`).

### v1.0 Archive Reconciliation (TRACE-01)
- **D-05:** **Full cleanup** of `.planning/milestones/v1.0-REQUIREMENTS.md` via a manual edit (not via `mark-complete`, which only targets the current `.planning/REQUIREMENTS.md` and whose regex won't match the archive's `Pending (v2)` status string). The edit:
  - Flips the 10 unchecked boxes `[ ]` → `[x]` for: EXPT-01/02/03, COMP-01/02, VIDX-01/02/03 (Phase 6) and LIVE-01/02, SIGN-01, IMPS-01/02, SYSI-01/02 (Phase 7).
  - Updates the traceability table Status for those 10 from `Pending` / `Pending (v2)` → `Complete` (phase column stays accurate — audit confirmed Phase 6 for EXPT/COMP/VIDX, Phase 7 for LIVE/SIGN/IMPS/SYSI).
  - **Reclassifies the 7 Phase 7 reqs from `## v2 Requirements` up into `## v1 Requirements`** by moving their 4 category headings (### Live Photos, ### Signature, ### Additional Import Sources, ### System Integration) wholesale, appended after the existing "Video Export UX" section in phase order. Removes those 4 categories from `## v2 Requirements`.
  - Trims `## v2 Requirements` to retain only the truly-deferred categories (Customization CUST-01..04, Batch Processing BATC-01/02), relabeled `## v2 Requirements (deferred)`.
  - Fixes the "Coverage" counts to reflect the new structure (v1: 35 total = 28 + 7; v2: 6 total = CUST-01..04 + BATC-01/02) and updates the "Last updated" footer line.
- **D-06:** Add a **`## Reconciliation Note` section near the top** of the archive documenting: reconciled on 2026-06-18 against `.planning/milestones/v1.0-MILESTONE-AUDIT.md` evidence; 10 checkboxes flipped; 7 Phase 7 reqs reclassified v2 → v1. Single atomic commit: `docs(v1.0): reconcile archived REQUIREMENTS.md traceability`.

### Guard Verification (Success Criteria #3)
- **D-07:** A **self-contained bash test** at `scripts/test-sync-requirements.sh`. It embeds fixture REQUIREMENTS.md + SUMMARY.md content as inline heredocs, writes them to a temp dir at runtime, runs `sync-requirements.sh` against the temp REQUIREMENTS.md, asserts via grep, then cleans up the temp dir. Single file — no separate `scripts/fixtures/` dir to maintain. Exits non-zero on assertion failure. Documented invocation: `bash scripts/test-sync-requirements.sh`.
- **D-08:** The **gsd-executor runs the test during Phase 8's own verification** to prove success criteria #3 (records pass/fail in the plan's SUMMARY), AND `AGENTS.md` documents it as a re-runnable regression check for any future change to `sync-requirements.sh` or `mark-complete`. Both one-shot proof and ongoing protection.

### Failure Semantics (not_found / already_complete)
- **D-09:** The script **exits non-zero on any `not_found` IDs** (a SUMMARY claims a requirement ID that doesn't exist in REQUIREMENTS.md — typo, or a req that was never defined). It **exits zero on `already_complete`** (idempotent re-runs are safe). This directly addresses retrospective Lesson 1's "drift went silent" root cause — a not_found is a real signal of mismatch, not noise.
- **D-10:** On `not_found`, the **executor treats the non-zero exit as a plan-completion blocker and resolves the mismatch** before the plan can be marked complete: if the SUMMARY's `requirements-completed` ID is a typo → fix the SUMMARY; if the ID is legitimately missing from REQUIREMENTS.md → add the req definition to REQUIREMENTS.md first, then re-run the script. AGENTS.md documents this resolution path. The guard is a real gate, not advisory.
- **D-11:** The fixture test (D-07) **asserts all three branches**: (1) happy path — valid req ID → checkbox flips to `[x]` + traceability shows `Complete`; (2) not_found — SUMMARY with a typo'd/undefined req ID → script exits non-zero AND mutates nothing; (3) already_complete — SUMMARY with an already-checked req ID → script exits zero, no-op. Three inline heredoc fixtures, one assertion block each. The test enforces the failure semantics, not just the happy path.

### the agent's Discretion
- The exact bash implementation details of `sync-requirements.sh` (how it parses the `requirements-completed` JSON array — `jq`, `sed`, or a Node one-liner; error handling for missing frontmatter field; output formatting) are left to the planner/researcher. Constraint: the script must relay `mark-complete`'s exit code and JSON result faithfully, and must exit non-zero iff `not_found` is non-empty.
- Whether `scripts/test-sync-requirements.sh` uses a `set -e` strict mode, trap-based cleanup, or explicit checks is left to the planner. Constraint: temp dir must be cleaned up on both pass and failure paths.
- The exact wording/placement of the post-plan step in `AGENTS.md` is left to the planner (must be discoverable by the gsd-executor and reference both `sync-requirements.sh` and the resolution path for `not_found`).
- Whether the v1.0 archive reconciliation (D-05) is one commit or split (e.g., checkboxes separate from reclassification) is left to the planner. Constraint: D-06 specifies a single atomic commit `docs(v1.0): reconcile archived REQUIREMENTS.md traceability` — if the planner prefers to split, it must update the commit message scheme and note the rationale.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Planning context (phase scope + success criteria)
- `.planning/ROADMAP.md` §"Phase 8: Traceability Reconciliation & Recurrence Guard" — phase goal, depends-on, requirements (TRACE-01, TRACE-02), and the 4 success criteria (verbatim source of truth for what "done" means).
- `.planning/REQUIREMENTS.md` §"Traceability (TRACE)" and §"Traceability" — defines TRACE-01/TRACE-02 and the v1.1 traceability table (already satisfies success criteria #4).
- `.planning/PROJECT.md` §"Current Milestone", §"Requirements / Active", §"Key Decisions" — v1.1 tech-debt framing; confirms v1.0 has 36 shipped reqs and that the drift issue is the documented motivation.
- `.planning/STATE.md` §"Current Position", §"Blockers/Concerns" — confirms Phase 8 is first v1.1 phase, ready to plan.

### v1.0 audit evidence (source of truth for TRACE-01 reconciliation)
- `.planning/milestones/v1.0-MILESTONE-AUDIT.md` — frontmatter `gaps.requirements[]` lists all 10 drifted reqs with `status: satisfied`, `phase`, `claimed_by_plans`, `completed_by_plans`, and per-req `evidence`. **This is the authoritative evidence the reconciliation edit (D-05/D-06) must be grounded in.** §"Tech Debt Inventory" rows #1 and #2 are the drift being fixed.
- `.planning/milestones/v1.0-REQUIREMENTS.md` — the **edit target** for TRACE-01. Currently has 10 unchecked `[ ]` boxes (EXPT/COMP/VIDX under "v1 Requirements" with Status "Pending"; LIVE/SIGN/IMPS/SYSI under "## v2 Requirements" with Status "Pending (v2)") and stale Coverage counts.
- `.planning/RETROSPECTIVE.md` §"What Was Inefficient" and §"Key Lessons" #1 — documents the drift root cause ("manual traceability updates drift — 10/35 requirements were unchecked at milestone close") and the decided direction ("Automate REQUIREMENTS.md checkbox updates per plan completion"). Anchors D-01..D-11.

### GSD tooling (the mechanism TRACE-02 wires up — read to understand exact behavior)
- `~/.config/opencode/get-shit-done/bin/lib/milestone.cjs` `cmdRequirementsMarkComplete` (lines 14-90) — the `requirements mark-complete` handler. **Read this to understand the exact regex transformations:** checkbox `(-\s*\[)[ ](\]\s*\*\*${reqEscaped}\*\*)` → `$1x$2`; traceability table `(\|\s*${reqEscaped}\s*\|[^|]+\|)\s*Pending\s*(\|)` → `$1 Complete $2`. Note the table regex requires `Pending` immediately followed by `|` — it will NOT match `Pending (v2)` (this is why D-05 uses a manual edit for the archive, not `mark-complete`).
- `~/.config/opencode/get-shit-done/templates/summary.md` line 41 — `requirements-completed: []  # REQUIRED — Copy ALL requirement IDs from this plan's requirements frontmatter field.` **This is the field `sync-requirements.sh` reads.** Every plan SUMMARY MUST populate it.
- `~/.config/opencode/get-shit-done/templates/phase-prompt.md` line 23, §141 — `requirements: []  # REQUIRED — Requirement IDs from ROADMAP this plan addresses. MUST NOT be empty.` The plan's `requirements` field is the source that SUMMARY's `requirements-completed` copies.
- `~/.config/opencode/get-shit-done/bin/lib/commands.cjs` line 475 — `gsd-tools frontmatter <summary> --pick requirements-completed` extracts the array used by the script.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`gsd-tools requirements mark-complete <ids>`** — already shipped, does the actual REQUIREMENTS.md mutation (checkbox + traceability table). The recurrence guard script is a thin wrapper around this; do NOT reimplement the mutation logic.
- **`gsd-tools frontmatter <path> --pick requirements-completed`** — extracts the `requirements-completed` array from a SUMMARY. Use this in `sync-requirements.sh` rather than hand-rolling frontmatter parsing.
- **`gsd-tools verify-summary --summary-path <path>`** — exists for SUMMARY validation (not required by this phase, but available if the planner wants to assert the SUMMARY is well-formed before extracting `requirements-completed`).

### Established Patterns
- **No Makefile / no `scripts/` / no `package.json` / no `.github/`** — the repo is a pure iOS/Swift project + `.planning/`. This phase introduces the first `scripts/` directory and the first non-Swift tooling. Keep the scripts self-contained (bash, no npm deps) to avoid importing a Node toolchain into the iOS repo beyond what GSD already uses.
- **GSD config** (`.planning/config.json`): `parallelization: true`, `mode: yolo`, `commit_docs: true`, `git.branching_strategy: none`, `workflow.auto_advance: true`. The `parallelization: true` setting is why D-02 mandates an explicit SUMMARY path arg (no mtime auto-discovery).
- **Atomic commits with scoped messages** — repo history uses `docs(...)`, `feat(...)`, `fix(...)` prefixes. D-06's commit message `docs(v1.0): reconcile archived REQUIREMENTS.md traceability` follows this.

### Integration Points
- **`AGENTS.md`** — where the post-plan step (D-03) and the `not_found` resolution path (D-10) are documented for the gsd-executor. The executor reads AGENTS.md at session start, so the post-plan step must be placed where the executor's plan-completion flow will encounter it.
- **`.planning/REQUIREMENTS.md`** — the mutation target for the recurrence guard (current milestone). Format: `- [ ] **REQ-ID**: ...` and `| REQ-ID | Phase N | Pending |` — both matched by `mark-complete`'s regex.
- **`gsd-executor` plan-completion flow** — the script slots in after SUMMARY.md is written and before the plan is marked complete. The planner should specify the exact ordering relative to the executor's existing self-check and commit steps.

</code_context>

<specifics>
## Specific Ideas

- Script names are locked: `scripts/sync-requirements.sh` (the guard) and `scripts/test-sync-requirements.sh` (the test). Both live at repo root under `scripts/`.
- The reconciliation commit message is locked: `docs(v1.0): reconcile archived REQUIREMENTS.md traceability` (D-06).
- The 10 specific requirement IDs to reconcile (with their phases): EXPT-01, EXPT-02, EXPT-03, COMP-01, COMP-02, VIDX-01, VIDX-02, VIDX-03 (Phase 6); LIVE-01, LIVE-02, SIGN-01, IMPS-01, IMPS-02, SYSI-01, SYSI-02 (Phase 7). Evidence for each is in `.planning/milestones/v1.0-MILESTONE-AUDIT.md` frontmatter `gaps.requirements[]`.
- The 4 category headings to move v2 → v1 in the archive: `### Live Photos`, `### Signature`, `### Additional Import Sources`, `### System Integration` — appended after `### Video Export UX` in the v1 section, in that order.
- The script's exit-code contract is locked: exit non-zero iff `mark-complete` returns a non-empty `not_found` array; exit zero otherwise (including when `already_complete` is non-empty, or when `marked_complete` is empty because all IDs were already complete).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. The following were already deferred at v1.1 milestone definition (recorded in `.planning/REQUIREMENTS.md` §"Process Hardening (PHRO)" and `.planning/STATE.md` §"Deferred Items") and are NOT pulled into Phase 8:
- **PHRO-01** (per-phase VERIFICATION.md template) — deferred to a future process-hardening milestone.
- **PHRO-02** (worktree-safety fix for task-tool branching) — GSD tooling concern, deferred.

A possible follow-up that arose during scouting but is out of scope: extending `requirements mark-complete` with a `--path <file>` flag so it could reconcile archived REQUIREMENTS.md files repeatably. Rejected for this phase (D-05 uses a manual edit instead) but worth revisiting if a future milestone archives another drifted REQUIREMENTS.md.

</deferred>

---

*Phase: 8-Traceability Reconciliation & Recurrence Guard*
*Context gathered: 2026-06-18*
