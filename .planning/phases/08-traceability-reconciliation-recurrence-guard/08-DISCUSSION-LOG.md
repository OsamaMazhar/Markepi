# Phase 8: Traceability Reconciliation & Recurrence Guard - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 8-Traceability Reconciliation & Recurrence Guard
**Areas discussed:** Guard wiring & trigger, v1.0 archive reconciliation depth, Guard verification method, Failure semantics (not_found)

---

## Guard Wiring & Trigger

### Q1 — How should the recurrence guard be invoked per plan?

| Option | Description | Selected |
|--------|-------------|----------|
| Repo-local script + documented invocation | Add a script that reads the latest SUMMARY's `requirements-completed` and calls `gsd-tools requirements mark-complete <ids>`. Documented in AGENTS.md as a post-plan step. Change lives in-repo, repeatable. | ✓ |
| Auto-wire into execute-plan workflow | Edit GSD workflow files in ~/.config to call `mark-complete` after SUMMARY is written. Fully automatic; matches retrospective Lesson 1's ideal. Touches shared GSD workflow files outside the repo. | |
| Manual invocation only | Document `gsd-tools requirements mark-complete <ids>` in AGENTS.md as a hand-run post-plan step. Lightest; relies on human discipline (v1.0 drift root cause). | |

**User's choice:** Repo-local script + documented invocation
**Notes:** Balances in-repo repeatability with enforcement; avoids editing shared GSD workflow files in ~/.config.

### Q2 — Where should the script live and what language?

| Option | Description | Selected |
|--------|-------------|----------|
| scripts/sync-requirements.sh (bash wrapper) | Bash at repo root; pipes `gsd-tools frontmatter <summary> --pick requirements-completed` into `requirements mark-complete <ids>`. Zero deps, pure glue. | ✓ |
| scripts/reconcile-requirements.cjs (Node) | Node/CJS matching gsd-tools' stack; robust JSON array parsing. Introduces a Node script into a pure iOS repo. | |
| .planning/scripts/... (planning-local) | Node/CJS colocated with planning artifacts. Puts executable tooling inside .planning/ (usually docs, not code). | |

**User's choice:** scripts/sync-requirements.sh (bash wrapper)

### Q3 — How does the script know which SUMMARY to read requirements-completed from?

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit SUMMARY path as arg | `scripts/sync-requirements.sh <path>`. Executor passes the plan's own SUMMARY. Safe under parallel waves (`parallelization: true`). | ✓ |
| Auto-discover latest SUMMARY | Scan `.planning/phases/**/*-SUMMARY.md`, pick most-recently-modified. Risky under parallel waves (mtime ties). | |
| Both (arg precedence, auto fallback) | Optional arg; auto-discover fallback. Ergonomic but adds branching + inherits auto-discover ambiguity. | |

**User's choice:** Explicit SUMMARY path as arg

### Q4 — Who invokes the script?

| Option | Description | Selected |
|--------|-------------|----------|
| Executor runs it as a post-plan step | AGENTS.md documents it; gsd-executor runs it right after writing SUMMARY.md. Semi-automatic, idempotent. Closest to retrospective's ideal without touching ~/.config. | ✓ |
| Human runs it manually | Documented as a developer step; executor does NOT call it. Relies on human discipline (drift root cause). | |
| Executor attempts, human can re-run | Executor tries it; on absence/failure, human can re-run. Two code paths to maintain. | |

**User's choice:** Executor runs it as a post-plan step

---

## v1.0 Archive Reconciliation Depth

### Q1 — How far should the TRACE-01 cleanup go on the archived v1.0-REQUIREMENTS.md?

| Option | Description | Selected |
|--------|-------------|----------|
| Full cleanup (manual edit) | Flip 10 boxes, update Status, reclassify 7 Phase 7 reqs v2→v1, fix Coverage counts. Audit flagged v2 mislabel as tech debt. Fully satisfies "0 stale entries". | ✓ |
| Checkboxes + status only | Flip 10 boxes, update Status to Complete. Leave v2 section structure. "0 stale entries" borderline (shipped reqs under v2 heading). | |
| Extend mark-complete with --path flag | Add `--path` to `mark-complete` so it can target the archive. Requires GSD tooling change + "Pending (v2)" regex handling. More work for a one-time fix. | |

**User's choice:** Full cleanup (manual edit)
**Notes:** The archive is a frozen historical doc — a one-time reconciliation edit is appropriate; the repeatable mechanism (mark-complete + sync script) is for the current REQUIREMENTS.md going forward.

### Q2 — How should the 7 Phase 7 reqs be structured when reclassified v2 → v1?

| Option | Description | Selected |
|--------|-------------|----------|
| Move category headings up; trim v2 | Move 4 category headings (Live Photos, Signature, Additional Import Sources, System Integration) up into v1 in phase order; remove from v2; relabel v2 as "(deferred)". Cleanest. | ✓ |
| Single Phase 7 subsection in v1 | One "Phase 7 — Additional Inputs" subsection in v1 with all 7 reqs grouped. Leaves categories in v2 → duplicate risk. | |
| Disperse into existing v1 categories | Move req lines into closest-fitting v1 categories. Mixes Phase 7 work into earlier-phase groupings, obscures phase delivery history. | |

**User's choice:** Move category headings up; trim v2

### Q3 — How should the reconciliation be recorded for future readers?

| Option | Description | Selected |
|--------|-------------|----------|
| Reconciliation Note section + atomic commit | Add `## Reconciliation Note` near top documenting date, audit evidence source, 10 boxes flipped, 7 reclassified. Single atomic commit `docs(v1.0): reconcile archived REQUIREMENTS.md traceability`. | ✓ |
| Footer line only; git log is the trail | Update only the footer "Last updated" line; commit message is the detailed trail. | |
| Silent edit; commit message only | Just bump footer date; rely entirely on commit message. No in-file signal. | |

**User's choice:** Reconciliation Note section + atomic commit

---

## Guard Verification Method

### Q1 — How should success criteria #3 be satisfied?

| Option | Description | Selected |
|--------|-------------|----------|
| Fixture-based bash test | `scripts/test-sync-requirements.sh` creates temp fixture REQUIREMENTS.md + SUMMARY.md, runs the guard, asserts via grep. Persistent regression protection. No external harness. | ✓ |
| --dry-run flag on the script | Print parsed IDs + intended `mark-complete` command without executing. Proves parsing but not file mutation. | |
| Real-plan diff | Run against a real completed v1.1 plan and `git diff` before/after. Pragmatic, one-shot, no regression protection. | |

**User's choice:** Fixture-based bash test

### Q2 — How should the test fixture be structured?

| Option | Description | Selected |
|--------|-------------|----------|
| Self-contained script with inline heredoc fixtures | Single bash file; fixtures as heredocs written to temp dir at runtime; cleans up. One file, no separate fixtures to maintain. | ✓ |
| Separate fixture files in scripts/fixtures/ | Committed .md fixture files + test script. Inspectable but 3 files to keep in sync; fixtures can drift from real format. | |
| Generate fixture from real REQUIREMENTS.md slice | Extract a slice of the real v1.1 TRACE section + synthetic SUMMARY. Realistic but couples test to real file format. | |

**User's choice:** Self-contained script with inline heredoc fixtures

### Q3 — When is the test invoked?

| Option | Description | Selected |
|--------|-------------|----------|
| Executor verifies in Phase 8 + documented regression check | Executor runs it during Phase 8 verification (records pass/fail in SUMMARY); AGENTS.md documents it as re-runnable regression check. Both one-shot proof and ongoing protection. | ✓ |
| Executor runs once in Phase 8 only | Only during Phase 8 verification; not documented as ongoing. Regression protection goes unused later. | |
| Documented manual dev step only | Not run by executor; developer runs by hand. Criteria #3 satisfied by test existing, but no pass/fail record in phase. | |

**User's choice:** Executor verifies in Phase 8 + documented regression check

---

## Failure Semantics (not_found)

### Q1 — What should the guard do when mark-complete returns not_found and/or already_complete?

| Option | Description | Selected |
|--------|-------------|----------|
| Fail on not_found; tolerate already_complete | Exit non-zero on not_found (typo/missing req definition); exit zero on already_complete (idempotent re-runs safe). Addresses "drift went silent" root cause. | ✓ |
| Fail on not_found AND already_complete | Strictest; blocks on any non-ideal outcome. already_complete is benign → spurious blocks → risk of working around the guard. | |
| Warn only; always exit zero | Report in stdout, never block. Matches current mark-complete behavior; easy to miss in long executor logs (the drift failure mode). | |

**User's choice:** Fail on not_found; tolerate already_complete

### Q2 — When not_found fires, what is the executor's resolution path?

| Option | Description | Selected |
|--------|-------------|----------|
| Executor blocks + resolves the mismatch | Non-zero exit blocks plan completion. Executor diagnoses: typo → fix SUMMARY; legitimately missing → add req to REQUIREMENTS.md, re-run. Documented in AGENTS.md. Real gate. | ✓ |
| Executor reports in SUMMARY; human resolves later | Failure visible in SUMMARY but not enforced; under time pressure human may skip → silent drift. | |
| Escalate to human immediately | Pauses execution for any not_found, even trivial typos the executor could fix itself. Adds friction. | |

**User's choice:** Executor blocks + resolves the mismatch

### Q3 — Should the fixture test cover the not_found and already_complete branches too?

| Option | Description | Selected |
|--------|-------------|----------|
| Test all three branches | Happy (flip + Complete), not_found (exit non-zero, no mutation), already_complete (exit zero, no-op). Three heredoc fixtures. Enforces failure semantics, not just happy path. | ✓ |
| Happy + not_found only | Skip already_complete (benign). A regression breaking idempotency (e.g., [x] flipped back to [ ]) goes uncaught. | |
| Happy path only | not_found/already_complete documented but not tested. A not_found exit-code regression passes the test. | |

**User's choice:** Test all three branches

---

## the agent's Discretion

- Exact bash implementation of `sync-requirements.sh` (JSON array parsing via `jq`/`sed`/Node one-liner; missing-frontmatter error handling; output formatting) — left to planner/researcher. Constraint: relay `mark-complete`'s exit code + JSON faithfully; exit non-zero iff `not_found` is non-empty.
- Test script internals (`set -e`, trap-based cleanup, explicit checks) — left to planner. Constraint: temp dir cleaned on both pass and failure paths.
- Exact wording/placement of the post-plan step + resolution path in `AGENTS.md` — left to planner. Constraint: discoverable by gsd-executor; references both `sync-requirements.sh` and the `not_found` resolution path.
- Whether the v1.0 archive reconciliation is one commit or split — left to planner. Constraint: D-06 locks a single atomic commit message; if split, planner must update the commit scheme + note rationale.

## Deferred Ideas

None pulled into Phase 8. Already-deferred items (recorded in REQUIREMENTS.md PHRO section + STATE.md Deferred Items):
- PHRO-01 (per-phase VERIFICATION.md template) — future process-hardening milestone.
- PHRO-02 (worktree-safety fix for task-tool branching) — GSD tooling concern.

Arose during scouting but rejected for this phase: extending `requirements mark-complete` with a `--path <file>` flag for repeatably reconciling archived REQUIREMENTS.md files. Rejected (D-05 uses a manual edit). Worth revisiting if a future milestone archives another drifted REQUIREMENTS.md.
