# Phase 14: Process Hardening - Context

**Gathered:** 2026-06-19
**Status:** Ready for planning

<domain>
## Phase Boundary

GSD workflow tooling improvements that make phase execution more reliable and auditable. Two independent tooling changes with zero app code impact:

1. **PHRO-01**: A per-phase VERIFICATION.md template is populated during execution with UAT checkboxes, automated test counts, and manual QA steps for each plan — no empty template left unfilled after a plan completes.
2. **PHRO-02**: A worktree-safety fix prevents git worktree branching failures from stale worktree directories, with pre-check, prune, and timestamp-suffixed fallback.

Changes live in the GSD tooling infrastructure at `/Users/osama/.config/opencode/get-shit-done/`. Key files touched: `workflows/execute-plan.md`, `workflows/execute-phase.md`, `bin/lib/worktree-safety.cjs`, templates.
</domain>

<decisions>
## Implementation Decisions

### VERIFICATION.md Population Strategy
- Triggered in `execute-plan.md` — executor writes VERIFICATION.md after each task commit, ensuring it's populated before plan completes
- Contents: UAT checkboxes per task, automated test count (auto-detected), manual QA steps column, and a "Verification Status" summary table
- Automated test count detected by parsing SUMMARY.md frontmatter for `tests_added` / `tests_modified` fields
- If executor fails to populate VERIFICATION.md: halt plan completion with a gate — SUMMARY.md must reference a populated VERIFICATION.md before plan is marked done

### Worktree Safety Pre-Check
- Runs in `execute_waves` step 3, just before `git worktree add` — catches stale directories at the exact point of failure
- "Stale" defined as: directory exists on disk but is NOT in `git worktree list` (orphaned directory) OR directory exists and IS in `git worktree list` but `.git` file is missing
- Handling: prune git metadata (`git worktree prune`), then `rm -rf` the orphaned directory if it's empty or only contains stale GSD artifacts
- Pre-check is idempotent — if the helper runs twice (re-entrant orchestrator), second run is a no-op

### Timestamp Fallback Path
- Activates when `git worktree add` fails with "already exists" error — primary path occupied (locked worktree from another agent or stale directory unreachable by pre-check)
- Fallback naming: `worktree-agent-{id}-{unix_timestamp}` — unique, sortable, zero collision risk
- Fallback paths appended to `WAVE_WORKTREE_MANIFEST` with the actual path used, so `cleanup-wave` merges and removes them naturally
- If both primary and fallback paths occupied: fail immediately with "Both primary and fallback worktree paths occupied — manual cleanup required"

### the agent's Discretion
All implementation choices are at the agent's discretion within the decisions above.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `bin/lib/worktree-safety.cjs` — existing `reapOrphanWorktrees()`, `planWorktreePrune()`, `executeWorktreePrunePlan()`, `inspectWorktreeHealth()`, `snapshotWorktreeInventory()` — extend with stale-detection logic
- `workflows/execute-plan.md` — plan executor contract; add VERIFICATION.md write step
- `workflows/execute-phase.md` — orchestrator with `execute_waves` step 3 where pre-check needs to run; step 5.5 cleanup-wave integration
- `templates/verification-report.md` — existing verification report template (may be repurposed/extended)
- `templates/summary.md` — SUMMARY.md frontmatter has schema for plan metadata that VERIFICATION.md reads

### Established Patterns
- Worktree safety functions use dependency injection (deps pattern) for testability
- Executor agents read `execute-plan.md` inline; new VERIFICATION step inserts into that contract
- Wave cleanup uses `WAVE_WORKTREE_MANIFEST` JSON file as source of truth — fallback paths must append to this
- Git subprocess calls have timeout guards and `timedOut` surfacing

### Integration Points
- `execute_plan.md` — insert VERIFICATION.md write + gate after task commits
- `execute-phase.md` `execute_waves` step 3 — insert pre-check before `git worktree add` dispatch
- `execute-phase.md` step 5.5 (worktree cleanup) — fallback paths integrate via manifest append
- `bin/lib/worktree-safety.cjs` — new `precheckWorktreePath()` and `addWorktreeSafe()` functions
</code_context>

<specifics>
## Specific Ideas

- PHRO-01 and PHRO-02 are independent — can be planned and executed in separate plans within the same wave
- The VERIFICATION.md template should use a markdown frontmatter header (matching existing GSD conventions) with `status`, `plan_id`, `uat_checks`, `test_count`, `verified_by` fields
- The worktree pre-check should be a standalone Node.js function in `worktree-safety.cjs` callable via `gsd-sdk query worktree.precheck`
- `execute_waves` step 3 already has the `Agent()` dispatch loop — pre-check fits naturally as a bash block before agent spawn
- Timestamp format: Unix epoch seconds (`date +%s`) — not ISO 8601, to keep directory names filesystem-safe
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.
</deferred>
