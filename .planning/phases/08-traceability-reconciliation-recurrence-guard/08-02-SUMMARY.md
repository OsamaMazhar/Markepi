---
phase: 08-traceability-reconciliation-recurrence-guard
plan: 02
subsystem: process
tags: [bash, traceability, recurrence-guard, gsd-tools, scripting]

# Dependency graph
requires:
  - phase: 08
    plan: 01
    provides: "Reconciled v1.0 REQUIREMENTS.md archive — TRACE-01 completed"
provides:
  - "Repo-local recurrence guard script (scripts/sync-requirements.sh) that bridges SUMMARY completion to REQUIREMENTS.md checkbox sync"
  - "Self-contained fixture test (scripts/test-sync-requirements.sh) validating all three guard branches"
  - "AGENTS.md post-plan step documentation discoverable by gsd-executor"
affects:
  - "phases/09" — BUILD-01 wave-level build gate (guard runs after build gate plan completes)"
  - "phases/10" — REFA-01 protocol defaults (guard runs after refactor plan completes)"
  - "phases/11" — PHDR-01 HDR detection (guard runs after HDR plan completes)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Bash glue scripts delegating complex logic to gsd-tools (frontmatter get, requirements mark-complete)"
    - "Inline heredoc fixture tests with mktemp + trap EXIT cleanup for isolated state"
    - "GSD section delimiter convention for AGENTS.md discoverable documentation"

key-files:
  created:
    - "scripts/sync-requirements.sh — Recurrence guard: extracts requirements-completed from SUMMARY frontmatter, delegates to gsd-sdk mark-complete, exits non-zero on not_found"
    - "scripts/test-sync-requirements.sh — Self-contained fixture test validating happy path, not_found, and already_complete (idempotency) branches"
  modified:
    - "AGENTS.md — New GSD Post-Plan Step section documenting guard invocation, exit codes, resolution path, and regression check"

key-decisions:
  - "Guard is a repo-local bash script (not a GSD workflow patch) — keeps mutation logic in gsd-tools, script is pure glue per D-01"
  - "Explicit SUMMARY path argument (not mtime auto-discovery) — safe for parallelization:true where multiple plans complete in same wave per D-02"
  - "Script exits non-zero on not_found (not advisory) — directly addresses retrospective Lesson 1's 'drift went silent' root cause per D-09/D-10"
  - "Fixture test uses inline heredocs + mktemp (no scripts/fixtures/ dir) — single-file, self-contained, trap EXIT cleanup per D-07"

patterns-established:
  - "Bash tool delegation: thin scripts call gsd-sdk query commands, never reimplement frontmatter parsing or checkbox regex"
  - "Exit code contract: 0=success/noop, 1=not_found blocker, 2+=script error — explicit and machine-parseable"
  - "Three-branch fixture testing: happy path + error path + idempotency — minimum coverage for a correctness guard"

requirements-completed:
  - TRACE-02

# Metrics
duration: 2 min
completed: 2026-06-18
---

# Phase 8 Plan 02: Recurrence Guard Summary

**Repo-local bash guard script with gsd-tools delegation, self-contained fixture test, and AGENTS.md documentation — prevents v1.0 traceability drift from recurring by making REQUIREMENTS.md checkbox sync a reproducible, verifiable post-plan step that fails noisily on mismatch.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-18T15:07:10Z
- **Completed:** 2026-06-18T15:09:59Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Created `scripts/sync-requirements.sh` — a 60-line bash recurrence guard that extracts `requirements-completed` from a SUMMARY frontmatter via `gsd-sdk query frontmatter get`, parses the JSON array with jq (node fallback), delegates mutation to `gsd-sdk query requirements mark-complete`, and parses the JSON response's `.not_found` array (not relying on exit code — Pitfall #1). Exits 0 on success/noop, 1 on not_found (BLOCKER), 2 on script errors.
- Created `scripts/test-sync-requirements.sh` — a 160-line self-contained fixture test using inline heredoc fixtures written to a temp `.planning/` directory at runtime. Validates all three branches: (1) happy path — unchecked TEST-A01 gets marked_complete; (2) not_found — undefined TEST-B99 detected, REQUIREMENTS.md unmutated; (3) already_complete — pre-checked TEST-A01 detected as already_complete with idempotent no-op. Uses `trap EXIT` for cleanup on both pass and failure paths.
- Updated `AGENTS.md` with a `## GSD Post-Plan Step` section between GSD Workflow Enforcement and Developer Profile, documenting the exact invocation, exit code table with BLOCKER designations, two-step not_found resolution path, and regression check command.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scripts/sync-requirements.sh — the recurrence guard script** - `f326ef0` (feat)
2. **Task 2: Create scripts/test-sync-requirements.sh — the fixture-based test** - `55146c3` (test)
3. **Task 3: Update AGENTS.md with post-plan step documentation** - `4abf745` (docs)

**Plan metadata:** (pending final commit)

## Files Created/Modified
- `scripts/sync-requirements.sh` — 60-line bash guard: frontmatter extraction → JSON parse → mark-complete delegation → not_found detection
- `scripts/test-sync-requirements.sh` — 160-line fixture test: 3 inline heredoc branches, jq assertions, trap cleanup
- `AGENTS.md` — +38 lines: GSD Post-Plan Step section with invocation, exit codes, resolution path, regression check

## Decisions Made
None — followed plan as specified. The RESEARCH.md and PATTERNS.md provided near-complete implementation code; the only deviation was adding `.planning/` subdirectory creation in the test script since `gsd-sdk query requirements mark-complete` resolves `.planning/REQUIREMENTS.md` relative to CWD (the RESEARCH.md pattern used a top-level REQUIREMENTS.md path which differed from the actual tool behavior).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Test fixture path correction — mark-complete resolves .planning/REQUIREMENTS.md relative to CWD**
- **Found during:** Task 2 (running the test script)
- **Issue:** The RESEARCH.md test pattern wrote REQUIREMENTS.md at `$TESTDIR/REQUIREMENTS.md`, but `gsd-sdk query requirements mark-complete` looks for `.planning/REQUIREMENTS.md` relative to CWD. All three fixtures failed with "REQUIREMENTS.md not found".
- **Fix:** Added `mkdir -p "$TESTDIR/.planning"` and updated all fixture paths from `$TESTDIR/REQUIREMENTS.md` to `$TESTDIR/.planning/REQUIREMENTS.md`. Updated grep assertions to match new paths.
- **Files modified:** `scripts/test-sync-requirements.sh`
- **Verification:** All 3 fixture branches pass, `bash scripts/test-sync-requirements.sh` exits 0 with `ALL TESTS PASSED`
- **Committed in:** `55146c3` (Task 2 commit)

**2. [Rule 1 - Bug] Fixed `set -u` trip on missing argument validation**
- **Found during:** Task 1 (verifying argument validation)
- **Issue:** `SUMMARY_PATH="$1"` on line 9 tripped `set -u` when no arguments were passed (because `$1` is unbound).
- **Fix:** Restructured argument validation to check `$#` before accessing `$1`. Split into two checks: (1) `$# -ne 1` → exit 2, (2) `-f "$SUMMARY_PATH"` → exit 2.
- **Files modified:** `scripts/sync-requirements.sh`
- **Verification:** `bash scripts/sync-requirements.sh` (no args) exits 2; `bash scripts/sync-requirements.sh /nonexistent` exits 2
- **Committed in:** `f326ef0` (Task 1 commit, as part of the same Task 1 commit after edit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both auto-fixes necessary for correctness. The path correction was critical — without it, all 3 test fixtures would fail. No scope creep.

## Issues Encountered
None — the plan and RESEARCH.md patterns were thorough. The two auto-fixed issues were minor environmental differences (gsd-sdk tooling path resolution, bash strict mode edge case).

## User Setup Required
None — no external service configuration required. The guard is a repo-local bash script with no dependencies beyond `jq` (already installed on target) and the existing `gsd-sdk` tooling.

## Next Phase Readiness
- Phase 08 is complete. Both TRACE-01 (Plan 01) and TRACE-02 (Plan 02) are delivered.
- The recurrence guard is ready to be used in Phase 09 (Build Gate), Phase 10 (Protocol Defaults), and Phase 11 (Photos HDR) — each plan's SUMMARY will trigger the guard via `bash scripts/sync-requirements.sh`.
- Success criteria #3 from ROADMAP.md is met: running `bash scripts/test-sync-requirements.sh` exits 0 and prints `ALL TESTS PASSED`.
- AGENTS.md now has discoverable documentation for the gsd-executor at every plan completion.
- Ready for `/gsd-execute-phase 09` or `/gsd-plan-phase 09`.

---

*Phase: 08-traceability-reconciliation-recurrence-guard*
*Completed: 2026-06-18*
