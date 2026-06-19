---
phase: 14-process-hardening
plan: 02
subsystem: infra
tags: [worktree, git, cli, process-hardening]

# Dependency graph
requires: []
provides:
  - "precheckWorktreePath() function for stale worktree detection and safe removal"
  - "addWorktreeSafe() function with timestamp fallback for conflict-free worktree creation"
  - "CLI commands worktree.precheck and worktree.add-safe exposed via gsd-tools"
  - "Execute-phase step 3 pre-check bash block that scans and prunes stale worktree-agent-* directories before agent dispatch"
affects: [execute-phase, worktree-cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dependency injection via deps parameter for testability (execGit, existsSync, rmSync, etc.)"
    - "Fail-safe worktree precheck: prefer false-positive 'occupied' over false-negative 'clean'"
    - "Timestamp-suffixed fallback paths when primary worktree path is occupied"

key-files:
  modified:
    - "/Users/osama/.config/opencode/get-shit-done/bin/lib/worktree-safety.cjs"
    - "/Users/osama/.config/opencode/get-shit-done/bin/gsd-tools.cjs"
    - "/Users/osama/.config/opencode/get-shit-done/workflows/execute-phase.md"

key-decisions:
  - "precheckWorktreePath only removes directories that are empty or contain only .planning/ artifacts — never removes directories with source code or non-GSD files"
  - "addWorktreeSafe tries primary path first, falls back to timestamp-suffixed path on 'already exists' conflict"
  - "Both paths occupied returns clear ok:false with reason 'both_paths_occupied'"
  - "Precheck is idempotent — second call on stale_pruned path returns clean (directory_does_not_exist)"
  - "Precheck runs in execute_waves step 3 before any Agent dispatch, not inside the executor agent"

patterns-established:
  - "Worktree pre-check pattern: scan worktree-agent-* directories in WT_ROOT, call worktree.precheck on each, prune stale ones before dispatch"

requirements-completed: [PHRO-02]

# Test tracking
tests_added: 0
tests_modified: 0

# Metrics
duration: 0min
completed: 2026-06-19
---

# Phase 14 Plan 02: Worktree Pre-Check and Safe Add Summary

**Worktree stale-directory detection and timestamp-fallback creation functions with CLI integration, preventing "already exists" git worktree add failures in execute-phase wave dispatch**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-06-19T21:47:30Z
- **Completed:** 2026-06-19
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Added `precheckWorktreePath()` function to worktree-safety.cjs that detects stale worktrees (orphaned directories or missing .git file) and safely removes them when directory is empty or contains only .planning/ artifacts
- Added `addWorktreeSafe()` function that wraps git worktree add with precheck and timestamp fallback when primary path is occupied
- Added CLI command wrappers `cmdWorktreePrecheck` and `cmdWorktreeAddSafe` following existing patterns for JSON stdout output
- Wired `worktree.precheck` and `worktree.add-safe` subcommands into gsd-tools.cjs worktree case block
- Integrated pre-check bash block into execute-phase.md step 3 that scans worktree-agent-* directories and prunes stale ones before agent dispatch
- Added worktree_precheck_note to executor agent prompt informing agents that precheck has already run
- Added manifest append clarification for fallback path handling

## Task Commits

Source files modified outside the Watermark project repo (under `/Users/osama/.config/opencode/get-shit-done/`) — no per-task git commits. Verification via grep checks.

1. **Task 1: Add precheckWorktreePath() and addWorktreeSafe() to worktree-safety.cjs** — 4 new functions, 4 new exports
2. **Task 2: Wire worktree.precheck into gsd-tools.cjs and integrate into execute-phase.md** — 2 new subcommands, 3 insertions into workflow file

## Files Modified
- `/Users/osama/.config/opencode/get-shit-done/bin/lib/worktree-safety.cjs` — Added precheckWorktreePath(), addWorktreeSafe(), cmdWorktreePrecheck(), cmdWorktreeAddSafe() and their module.exports entries (~170 new lines)
- `/Users/osama/.config/opencode/get-shit-done/bin/gsd-tools.cjs` — Added precheck and add-safe subcommands to worktree case block
- `/Users/osama/.config/opencode/get-shit-done/workflows/execute-phase.md` — Added pre-check bash block (B1), worktree_precheck_note in Agent prompt (B2), and manifest append fallback guidance (B3)

## Decisions Made
- precheckWorktreePath only removes directories that are empty or contain only `.planning/` — never removes directories with source code, node_modules, or non-GSD files (safety-first design per T-14-02 threat mitigation)
- addWorktreeSafe returns manifestEntry with worktree_path, branch, and agent_id for WAVE_WORKTREE_MANIFEST integration
- Precheck is non-blocking — warnings on failure, execution continues; the actual "already exists" error is caught by timestamp fallback in the orchestrator's post-dispatch failure handler
- Both functions use dependency injection via deps parameter for testability (execGit, existsSync, rmSync, etc.)

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered
None.

## Known Stubs
None.

## Next Phase Readiness
- worktree pre-check infrastructure ready for use by execute-phase orchestrator during wave dispatch
- Functions are callable via `gsd-sdk query worktree.precheck <path>` and `gsd-sdk query worktree.add-safe <basePath> <agentId> <branch>`
- No automated tests created — plan explicitly marked automated verification as MISSING; manual grep verification passed all checks

---
*Phase: 14-process-hardening*
*Plan: 02*
*Completed: 2026-06-19*
