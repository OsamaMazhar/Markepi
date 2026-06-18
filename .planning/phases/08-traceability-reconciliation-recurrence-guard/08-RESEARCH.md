# Phase 8: Traceability Reconciliation & Recurrence Guard - Research

**Researched:** 2026-06-18
**Domain:** Documentation traceability automation / process tooling
**Confidence:** HIGH

## Summary

This phase is a documentation-and-tooling phase — no application code changes. It delivers two outcomes: (1) a one-time manual reconciliation of the archived v1.0 REQUIREMENTS.md to reflect the shipped state of all 36 v1.0 requirements, and (2) a bash-based recurrence guard script (`scripts/sync-requirements.sh`) that automates REQUIREMENTS.md checkbox updates after each plan completes, using the existing `gsd-tools requirements mark-complete` infrastructure. The guard is wired as a post-plan step documented in `AGENTS.md`.

The v1.0 archive currently has 10 unchecked checkboxes (EXPT×3, COMP×2, VIDX×3, LIVE×2 under v1) and 5 requirement definitions in the v2 section that lack checkboxes entirely (SIGN×1, IMPS×2, SYSI×2) — all 15 were implemented in Phases 6 and 7. The traceability table has stale `Pending`/`Pending (v2)` statuses for all 15. Seven Phase 7 requirements (LIVE×2, SIGN×1, IMPS×2, SYSI×2) are misclassified under "v2 Requirements" but were shipped in v1.0.

**Primary recommendation:** Implement the guard as a thin bash script reading SUMMARY frontmatter via `gsd-sdk query frontmatter get` and delegating mutations to `gsd-sdk query requirements mark-complete`. Separate the v1.0 archive reconciliation into a single atomic edit per D-06. The fixture test (`scripts/test-sync-requirements.sh`) validates all three branches (happy path, not_found, already_complete) using inline heredoc fixtures.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TRACE-01 | REQUIREMENTS.md is audited against the current codebase — every validated requirement is checked and the traceability table accurately reflects which phase delivered it | Current state audit (§Current State Audit) confirms 10 unchecked boxes + 5 missing checkbox items; MILESTONE-AUDIT.md provides authoritative per-req evidence. |
| TRACE-02 | A reproducible mechanism keeps REQUIREMENTS.md checkboxes in sync with implemented features after each plan, so traceability no longer drifts manually between plans | Guard design (§Recurrence Guard Design) — bash script wrapping `gsd-tools requirements mark-complete` with `gsd-tools frontmatter` extraction; verified by self-contained fixture test (§Guard Verification). Success criteria #4 already satisfied — v1.1 traceability table shows all 5 v1.1 reqs mapped. |
</phase_requirements>

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** The recurrence guard is a **repo-local bash script** at `scripts/sync-requirements.sh` (new `scripts/` dir at repo root). Bash chosen because the script is pure glue: it extracts `requirements-completed` from a SUMMARY's frontmatter and passes the IDs to `gsd-tools requirements mark-complete`. Zero dependencies.
- **D-02:** The script takes the **SUMMARY path as an explicit argument** — `scripts/sync-requirements.sh <path-to-NN-MM-SUMMARY.md>`. No auto-discovery. Rationale: `parallelization: true` is enabled in config, so multiple SUMMARYs can be written in the same wave; mtime-based discovery could pick the wrong one.
- **D-03:** The **gsd-executor runs the script as a documented post-plan step**, immediately after writing the plan's SUMMARY.md. Documented in `AGENTS.md`. The script is idempotent.
- **D-04:** The script's pipeline: `gsd-tools frontmatter <summary> --pick requirements-completed` → parse the JSON array of IDs → `gsd-tools requirements mark-complete <comma-joined-ids>`. Relays `mark-complete`'s JSON result.
- **D-05:** Full cleanup of `.planning/milestones/v1.0-REQUIREMENTS.md` via manual edit — flips 10 unchecked boxes, updates traceability Statuses, reclassifies 7 Phase 7 reqs from v2 up into v1, trims v2 to deferred-only, fixes Coverage counts.
- **D-06:** Add a `## Reconciliation Note` section near the top of the archive. Single atomic commit: `docs(v1.0): reconcile archived REQUIREMENTS.md traceability`.
- **D-07:** Self-contained bash test at `scripts/test-sync-requirements.sh` with inline heredoc fixtures. Exits non-zero on assertion failure.
- **D-08:** The gsd-executor runs the test during Phase 8's own verification AND `AGENTS.md` documents it as a re-runnable regression check.
- **D-09:** Script exits non-zero on any `not_found` IDs. Exits zero on `already_complete` (idempotent).
- **D-10:** On `not_found`, the executor treats the non-zero exit as a plan-completion blocker. AGENTS.md documents the resolution path.
- **D-11:** Fixture test asserts all three branches: happy path, not_found, already_complete.
- **Script names locked:** `scripts/sync-requirements.sh`, `scripts/test-sync-requirements.sh`.
- **Commit message locked:** `docs(v1.0): reconcile archived REQUIREMENTS.md traceability`.
- **Exit-code contract locked:** exit non-zero iff `not_found` is non-empty.

### the agent's Discretion
- Exact bash implementation of `sync-requirements.sh` (how it parses the JSON array — `jq`, `sed`, or a Node one-liner; error handling; output formatting).
- Whether `scripts/test-sync-requirements.sh` uses `set -e`, trap-based cleanup, or explicit checks. Constraint: temp dir must be cleaned up on both pass and failure paths.
- Exact wording/placement of the post-plan step in `AGENTS.md`. Must be discoverable by the gsd-executor.
- Whether the v1.0 archive reconciliation (D-05) is one commit or split. Constraint: D-06 specifies a single atomic commit; if splitting, update commit message scheme and note rationale.

### Deferred Ideas (OUT OF SCOPE)
- Per-phase VERIFICATION.md templating (PHRO-01) — deferred to future milestone.
- Worktree-safety fix for task-tool branching (PHRO-02) — GSD tooling concern, deferred.
- Extending `requirements mark-complete` with `--path` flag for archived files — rejected for this phase.
</user_constraints>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| v1.0 archive reconciliation (TRACE-01) | Filesystem (`.planning/milestones/v1.0-REQUIREMENTS.md`) | — | Single-file manual edit; no runtime processing |
| Recurrence guard script (TRACE-02) | Shell tooling (`scripts/sync-requirements.sh`) | GSD tooling (`gsd-tools requirements mark-complete`) | Bash script is the glue layer; `mark-complete` is the mutation engine |
| Guard verification | Shell tooling (`scripts/test-sync-requirements.sh`) | — | Self-contained fixture test; no external services |
| Post-plan integration | Documentation (`AGENTS.md`) | gsd-executor workflow | Human/documented trigger, not automated hook |
| REQUIREMENTS.md mutation | GSD tooling (`milestone.cjs`) | Filesystem | Regex-based checkbox + traceability table update in current `REQUIREMENTS.md` |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **bash** | 3.2+ (macOS bundled) | Script glue | Available on every macOS system; the CONTEXT.md explicitly restricts to pure bash glue with no external deps beyond what GSD already provides. `jq` and `node` are present as fallback JSON parsers. [VERIFIED: `bash --version` on target] |
| **gsd-tools** (via `gsd-sdk query`) | bundled with gsd-sdk | Frontmatter extraction + requirements mutation | The existing `requirements mark-complete` handler already performs checkbox + traceability table regex mutations. The recurrence guard is a thin wrapper around it — do NOT reimplement the mutation logic. [VERIFIED: tested against live REQUIREMENTS.md] |
| **jq** | 1.7.1-apple | JSON array parsing | Available on target macOS system. Parses the `requirements-completed` JSON array from `frontmatter get --pick`. [VERIFIED: `command -v jq && jq --version` on target] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **node** | 26.3.0 | Fallback JSON parser | If `jq` is somehow unavailable, `node -e` can parse the JSON array as a fallback. Not primary. [VERIFIED: present on target] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `jq` for JSON parsing | `sed`/`grep` hand-rolled parsing | Hand-rolled parsing of JSON arrays with `sed` is fragile and breaks on edge cases (nested brackets, whitespace variations). `jq -r '.[]'` is a single invocation with well-defined behavior. Recommend `jq` as primary, with `node -e` fallback. |
| Bash regex for frontmatter extraction | `awk` with state tracking | Both are fragile compared to `gsd-tools frontmatter get` which has already-tested YAML parsing. The guard should use the existing tool, not re-parse. |
| Python script for the guard | Bash script | Python would introduce a runtime dependency (Python 3.12 is available, but bash is guaranteed). Bash is specified by D-01. |

**Version verification:**
```bash
# All tools confirmed present on target system (macOS, 2026-06-18):
$ bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin24)

$ command -v gsd-sdk && gsd-sdk query requirements mark-complete --help
/opt/homebrew/bin/gsd-sdk
# Confirmed working — tested with live REQUIREMENTS.md

$ jq --version
jq-1.7.1-apple
```

## Package Legitimacy Audit

> No external packages are installed by this phase. The phase uses only:
> - **bash** — macOS system binary, not a package install
> - **gsd-tools** — already installed as part of GSD SDK
> - **jq** — macOS system binary (`/usr/bin/jq`), Apple-signed

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| — | — | — | — | — | — | No packages to audit — pure shell tooling |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none
**Packages tagged [ASSUMED]:** none — all dependencies are system binaries verified present on target

## Current State Audit

### v1.0 Archive Structure (`.planning/milestones/v1.0-REQUIREMENTS.md`)

The file has 178 lines organized as:

```
## v1 Requirements
  ### Media Import (MEDI)            — 3 checked [x]
  ### Watermark (WMRK)               — 4 checked [x]
  ### White Frame (FRME)             — 2 checked [x]
  ### Sharing (SHAR)                 — 1 checked [x]
  ### Quality Preservation (QUAL)    — 4 checked [x]
  ### ProRAW (PROR)                  — 2 checked [x]
  ### Dynamic EXIF Tokens (EXIF)     — 2 checked [x]
  ### Multi-Layer Compositing (MULT) — 2 checked [x]
  ### Export Control (EXPT)          — 3 UNCHECKED [ ] ← DRIFT
  ### Before/After Comparison (COMP) — 2 UNCHECKED [ ] ← DRIFT
  ### Video Export UX (VIDX)         — 3 UNCHECKED [ ] ← DRIFT
  ### Live Photos (LIVE)             — 2 UNCHECKED [ ] ← DRIFT (misplaced: should be v1, traceability says v2)

## v2 Requirements
  ### Customization                  — 4 items, NO checkboxes (truly deferred)
  ### Batch Processing               — 2 items, NO checkboxes (truly deferred)
  ### Signature (SIGN)               — 1 item, NO checkbox, needs [x] ← DRIFT
  ### Additional Import Sources (IMPS) — 2 items, NO checkboxes, need [x] ← DRIFT
  ### System Integration (SYSI)      — 2 items, NO checkboxes, need [x] ← DRIFT
```

### Checkbox State Matrix

| Category | Total Items | `[x]` | `[ ]` | No Checkbox | Needs Action |
|----------|-------------|-------|-------|-------------|--------------|
| MEDI | 3 | 3 | 0 | 0 | — |
| WMRK | 4 | 4 | 0 | 0 | — |
| FRME | 2 | 2 | 0 | 0 | — |
| SHAR | 1 | 1 | 0 | 0 | — |
| QUAL | 4 | 4 | 0 | 0 | — |
| PROR | 2 | 2 | 0 | 0 | — |
| EXIF | 2 | 2 | 0 | 0 | — |
| MULT | 2 | 2 | 0 | 0 | — |
| **EXPT** | **3** | 0 | **3** | 0 | Flip `[ ]` → `[x]` |
| **COMP** | **2** | 0 | **2** | 0 | Flip `[ ]` → `[x]` |
| **VIDX** | **3** | 0 | **3** | 0 | Flip `[ ]` → `[x]` |
| **LIVE** | **2** | 0 | **2** | 0 | Flip `[ ]` → `[x]`; move category to v1 (listed after VIDX but traceability says "Pending (v2)") |
| CUST | 4 | 0 | 0 | 4 | None — truly deferred |
| BATC | 2 | 0 | 0 | 2 | None — truly deferred |
| **SIGN** | **1** | 0 | 0 | **1** | Add `[x]` checkbox + move category to v1 |
| **IMPS** | **2** | 0 | 0 | **2** | Add `[x]` checkboxes + move category to v1 |
| **SYSI** | **2** | 0 | 0 | **2** | Add `[x]` checkboxes + move category to v1 |
| **Total** | **39** | **20** | **10** | **9** | 15 items need reconciliation |

> Verified via: `grep -c '\- \[' .planning/milestones/v1.0-REQUIREMENTS.md` = 10 unchecked, 20 checked. [VERIFIED: file inspection 2026-06-18]

### Traceability Table Status

The traceability table (lines 131-169) has these stale entries:

| Requirement | Current Table Status | Actual Status | Phase | Evidence |
|-------------|---------------------|---------------|-------|----------|
| EXPT-01/02/03 | `Pending` | Complete | 6 | MILESTONE-AUDIT.md §gaps.requirements[] EXPT-01..03 |
| COMP-01/02 | `Pending` | Complete | 6 | MILESTONE-AUDIT.md §gaps.requirements[] COMP-01..02 |
| VIDX-01/02/03 | `Pending` | Complete | 6 | MILESTONE-AUDIT.md §gaps.requirements[] VIDX-01..03 |
| LIVE-01/02 | `Pending (v2)` | Complete | 7 | MILESTONE-AUDIT.md §gaps.requirements[] LIVE-01..02 |
| SIGN-01 | `Pending (v2)` | Complete | 7 | MILESTONE-AUDIT.md §gaps.requirements[] SIGN-01 |
| IMPS-01/02 | `Pending (v2)` | Complete | 7 | MILESTONE-AUDIT.md §gaps.requirements[] IMPS-01..02 |
| SYSI-01/02 | `Pending (v2)` | Complete | 7 | MILESTONE-AUDIT.md §gaps.requirements[] SYSI-01..02 |

**Total stale entries:** 15 (8 `Pending` + 7 `Pending (v2)`)

### Coverage Counts

| Metric | Current Value | Correct Value | Delta |
|--------|--------------|---------------|-------|
| v1 requirements | 28 total (14 original + 14 new) | 35 total (28 + 7 Phase 7) | +7 |
| v2 requirements | 13 total (6 original + 7 new) | 6 total (CUST×4 + BATC×2) | -7 |
| "Last updated" footer | 2026-06-17 | 2026-06-18 | stale date |

### What `mark-complete` Cannot Handle

The `cmdRequirementsMarkComplete` handler in `~/.config/opencode/get-shit-done/bin/lib/milestone.cjs` performs two regex mutations:

1. **Checkbox:** `(-\s*\[)[ ](\]\s*\*\*${reqEscaped}\*\*)` → `$1x$2` — works for `- [ ] **ID**:`
2. **Traceability table:** `(\|\s*${reqEscaped}\s*\*\|[^|]+\|)\s*Pending\s*(\|)` → `$1 Complete $2`

**Limitations for v1.0 archive reconciliation:**
- Regex #2 requires `Pending` immediately followed by `|` — **will not match** `Pending (v2)|`
- The tool targets the **current** `.planning/REQUIREMENTS.md` (v1.1), not the archived milestone file
- The 5 v2 items (SIGN×1, IMPS×2, SYSI×2) have **no checkboxes** at all (`- **ID**:` not `- [ ] **ID**:`) — regex #1 won't match

These limitations confirm that TRACE-01 requires a manual edit, not `mark-complete`.
[VERIFIED: source code inspection of `milestone.cjs` lines 42-77]

## Recurrence Guard Design

### Architecture

```
Phase completes → SUMMARY.md written (with requirements-completed frontmatter)
                              ↓
                   gsd-executor runs:
                   scripts/sync-requirements.sh <path-to-SUMMARY.md>
                              ↓
          ┌───────────────────────────────────────┐
          │ 1. gsd-sdk query frontmatter get      │
          │    <summary> --pick requirements-      │
          │    completed                           │
          │    → JSON array: ["TRACE-01","TRACE-02"]
          │                                        │
          │ 2. Parse JSON array → comma-joined IDs │
          │    (jq -r '.[]' | paste -sd,)          │
          │                                        │
          │ 3. gsd-sdk query requirements          │
          │    mark-complete <comma-joined-ids>     │
          │    → JSON: {marked_complete,             │
          │             already_complete,           │
          │             not_found}                  │
          │                                        │
          │ 4. Relay JSON result to executor       │
          │    Exit non-zero iff not_found non-empty│
          └───────────────────────────────────────┘
```

### Invocation Syntax Confirmed

The `gsd-tools` commands referenced in CONTEXT.md are invoked via `gsd-sdk query`:

```bash
# Extract requirements-completed array from SUMMARY frontmatter
gsd-sdk query frontmatter get <path> --pick requirements-completed
# Returns: ["TRACE-01", "TRACE-02"]

# Mark requirements complete in current REQUIREMENTS.md
gsd-sdk query requirements mark-complete TRACE-01,TRACE-02
# Returns: {"updated":true,"marked_complete":["TRACE-01","TRACE-02"],"already_complete":[],"not_found":[],"total":2}
```

**Confirmed behavior** [VERIFIED: tested against live REQUIREMENTS.md 2026-06-18]:
- `frontmatter get <path>` returns full YAML frontmatter as JSON
- `--pick requirements-completed` extracts just that field as a JSON array
- `requirements mark-complete` accepts comma-separated IDs (also handles space-separated and bracket-wrapped)
- `mark-complete` returns `marked_complete`, `already_complete`, `not_found` arrays
- `mark-complete` exits non-zero only on CLI usage errors (not on `not_found` results — the script must parse the JSON response)

**Critical finding:** `mark-complete` does NOT exit non-zero on `not_found`. The JSON response is the truth. The script must check `not_found.length > 0` in the parsed JSON response, not rely on exit code. This is important for D-09 compliance.

### JSON Parsing Strategy

`jq` is the recommended primary parser (confirmed present on target: `jq-1.7.1-apple`):

```bash
# Extract array from --pick output
IDS=$(gsd-sdk query frontmatter get "$SUMMARY_PATH" --pick requirements-completed 2>/dev/null)

# Parse to comma-joined string
COMMA_IDS=$(echo "$IDS" | jq -r '.[]' 2>/dev/null | paste -sd, -)

# Or check if array is empty
COUNT=$(echo "$IDS" | jq -r 'length' 2>/dev/null)
```

**Fallback:** If `jq` is unavailable, use `node -e`:
```bash
COMMA_IDS=$(echo "$IDS" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).join(','))")
```

### Guard Verification (Success Criteria #3)

The fixture test (`scripts/test-sync-requirements.sh`) follows this pattern:

```bash
#!/usr/bin/env bash
# Test: scripts/test-sync-requirements.sh
# Inline heredoc fixtures, temp dir, three assertion blocks

set -euo pipefail
TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT

# --- Fixture 1: Happy Path ---
cat > "$TESTDIR/REQUIREMENTS.md" << 'REQEOF'
- [ ] **TEST-A01**: Some requirement
| TEST-A01 | Phase 99 | Pending |
REQEOF

cat > "$TESTDIR/SUMMARY.md" << 'SUMEOF'
---
requirements-completed: ["TEST-A01"]
---
SUMEOF

# Run guard against fixture
RESULT=$(cd "$TESTDIR" && gsd-sdk query requirements mark-complete TEST-A01 2>&1)
echo "$RESULT" | jq -e '.marked_complete | index("TEST-A01")' > /dev/null \
  && echo "PASS: happy path" || { echo "FAIL: happy path"; exit 1; }

# --- Fixture 2: not_found ---
# ... (re-create REQUIREMENTS.md with no TEST-B99)
RESULT2=$(cd "$TESTDIR" && gsd-sdk query requirements mark-complete TEST-B99 2>&1)
echo "$RESULT2" | jq -e '.not_found | length > 0' > /dev/null \
  && echo "PASS: not_found detected" || { echo "FAIL: not_found"; exit 1; }

# --- Fixture 3: already_complete ---
# ... (re-create with already-checked TEST-A01)
RESULT3=$(cd "$TESTDIR" && gsd-sdk query requirements mark-complete TEST-A01 2>&1)
echo "$RESULT3" | jq -e '.already_complete | index("TEST-A01")' > /dev/null \
  && echo "PASS: already_complete idempotent" || { echo "FAIL: already_complete"; exit 1; }

echo "ALL TESTS PASSED"
```

**Constraint from D-07:** Fixtures are inline heredocs within the test script — no separate `scripts/fixtures/` directory.

**Constraint from CONTEXT.md:** Temp dir is cleaned up on both pass and failure paths (via `trap EXIT`).

### Post-Plan Integration in AGENTS.md

The AGENTS.md currently has these sections: `## Project`, `## Technology Stack`, `## Conventions`, `## Architecture`, `## Project Skills`, `## GSD Workflow Enforcement`, `## Developer Profile`. The post-plan step should be added:

**Recommendation:** Add a new `## GSD Post-Plan Step` section between `## GSD Workflow Enforcement` and `## Developer Profile`. This placement is discoverable by the executor scanning AGENTS.md at session start, and follows the existing GSD section grouping. The section should document:

1. After writing a plan's SUMMARY.md, run `scripts/sync-requirements.sh <path-to-SUMMARY.md>`
2. If the script exits non-zero (any `not_found` IDs), resolve the mismatch before marking the plan complete:
   - If the SUMMARY's `requirements-completed` ID is a typo → fix the SUMMARY frontmatter
   - If the ID is missing from REQUIREMENTS.md → add the requirement definition to REQUIREMENTS.md, then re-run
3. `scripts/test-sync-requirements.sh` is a re-runnable regression check for the guard

### Error Handling Contract (D-09/D-10)

```
┌────────────────────────────────────────────────────┐
│           sync-requirements.sh exit codes          │
├──────────┬─────────────────────────────────────────┤
│ Exit 0   │ All IDs marked_complete or              │
│          │ already_complete. No not_found.          │
│          │ Safe to proceed.                        │
├──────────┼─────────────────────────────────────────┤
│ Exit 1   │ At least one ID in not_found.            │
│          │ Plan-completion BLOCKER.                 │
│          │ Executor must resolve before marking     │
│          │ plan complete.                           │
├──────────┼─────────────────────────────────────────┤
│ Exit 2+  │ Script error (missing SUMMARY, invalid  │
│          │ frontmatter, frontmatter tool failure).  │
│          │ Plan-completion BLOCKER.                 │
└──────────┴─────────────────────────────────────────┘
```

**Key implementation detail:** Since `mark-complete` does NOT exit non-zero on `not_found` (it returns JSON), the script MUST parse the JSON response's `.not_found` array and check its length. The script's exit code is determined by `[ "${#NOT_FOUND[@]}" -gt 0 ]` (bash array check) or `[ "$NOT_FOUND_COUNT" -gt 0 ]` (jq length check).

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     PHASE 8 DATA FLOW                           │
│                                                                 │
│  TRACE-01 (one-time, manual)          TRACE-02 (recurring)      │
│  ═══════════════════════════          ════════════════════════  │
│                                                                 │
│  MILESTONE-AUDIT.md                     Plan execution          │
│  (authoritative evidence)                    │                  │
│       │                                      ▼                  │
│       ▼                              SUMMARY.md written         │
│  Manual edit of                      (requirements-completed    │
│  v1.0-REQUIREMENTS.md                 frontmatter populated)    │
│       │                                      │                  │
│       ▼                                      ▼                  │
│  - Flip 10 [ ] → [x]               gsd-executor invokes:        │
│  - Add 5 [x] checkboxes            sync-requirements.sh         │
│  - Move 4 categories v2→v1              <SUMMARY.md>            │
│  - Update traceability table               │                    │
│  - Fix Coverage counts                     ▼                    │
│  - Add Reconciliation Note          ┌──────────────────┐        │
│       │                             │ frontmatter get   │        │
│       ▼                             │ --pick reqs-comp  │        │
│  Single commit:                     │ → ["TRACE-01",    │        │
│  docs(v1.0): reconcile...           │    "TRACE-02"]    │        │
│                                     └──────┬───────────┘        │
│                                            │                    │
│                                            ▼                    │
│                                     ┌──────────────────┐        │
│                                     │ requirements      │        │
│                                     │ mark-complete     │        │
│                                     │ <comma-ids>       │        │
│                                     │ → {marked,        │        │
│                                     │    already,       │        │
│                                     │    not_found}     │        │
│                                     └──────┬───────────┘        │
│                                            │                    │
│                                     ┌──────▼───────────┐        │
│                                     │ not_found empty?  │        │
│                                     └──┬───────────┬───┘        │
│                                   YES  │           │  NO        │
│                                        ▼           ▼            │
│                                   Exit 0      Exit 1            │
│                                   Plan done    BLOCK plan        │
│                                                Resolve mismatch  │
│                                                                 │
│  VERIFICATION: test-sync-requirements.sh                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Fixture 1: valid ID → checkbox flips, exits 0            │   │
│  │ Fixture 2: bogus ID  → not_found, exits 1, no mutation   │   │
│  │ Fixture 3: already [x] → already_complete, exits 0, noop │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
scripts/                                    # NEW — first non-Swift tooling in repo
├── sync-requirements.sh                    # TRACE-02: recurrence guard script
└── test-sync-requirements.sh               # TRACE-02: self-contained fixture test

.planning/
├── milestones/
│   └── v1.0-REQUIREMENTS.md                # TRACE-01: edit target
├── REQUIREMENTS.md                          # TRACE-02: mutation target
└── phases/
    └── 08-traceability-reconciliation-recurrence-guard/
        ├── 08-CONTEXT.md
        ├── 08-RESEARCH.md
        └── 08-01-PLAN.md                    # (to be created by planner)

AGENTS.md                                    # D-03/D-10: post-plan step documented here
```

### Pattern 1: Thin Wrapper Script

**What:** A bash script that delegates all complex logic to existing GSD tooling. The script is glue — it extracts data from one tool and feeds it to another.

**When to use:** When the underlying tool (gsd-tools) already provides the core capability (frontmatter parsing, regex mutation), and the script only needs to bridge them with minimal transformation.

**Example:**
```bash
#!/usr/bin/env bash
# Source: CONTEXT.md D-04 pipeline specification
set -euo pipefail

SUMMARY_PATH="$1"
if [ ! -f "$SUMMARY_PATH" ]; then
  echo "ERROR: SUMMARY not found: $SUMMARY_PATH" >&2
  exit 2
fi

# Step 1: Extract requirement IDs from SUMMARY frontmatter
IDS_JSON=$(gsd-sdk query frontmatter get "$SUMMARY_PATH" --pick requirements-completed 2>/dev/null)
if [ -z "$IDS_JSON" ] || [ "$IDS_JSON" = "null" ]; then
  echo "No requirements-completed found in SUMMARY frontmatter" >&2
  exit 0  # Not an error — plan may not have delivered new requirements
fi

# Step 2: Parse JSON array → comma-joined string
COMMA_IDS=$(echo "$IDS_JSON" | jq -r '.[]' 2>/dev/null | paste -sd, -)
if [ -z "$COMMA_IDS" ]; then
  echo "requirements-completed array is empty" >&2
  exit 0
fi

# Step 3: Mark requirements complete
RESULT=$(gsd-sdk query requirements mark-complete "$COMMA_IDS" 2>&1)
echo "$RESULT"

# Step 4: Check for not_found (exit non-zero per D-09)
NOT_FOUND_COUNT=$(echo "$RESULT" | jq -r '.not_found | length' 2>/dev/null)
if [ "${NOT_FOUND_COUNT:-0}" -gt 0 ]; then
  echo "BLOCKER: ${NOT_FOUND_COUNT} requirement ID(s) not found in REQUIREMENTS.md" >&2
  echo "$RESULT" | jq -r '.not_found[]' >&2
  exit 1
fi

exit 0
```

### Pattern 2: Inline Heredoc Fixture Test

**What:** A self-contained test script that embeds fixture data as heredocs, writes them to a temp directory at runtime, executes the system under test, asserts with `jq`/`grep`, and always cleans up the temp directory.

**When to use:** When the SUT is a bash script that mutates a file; the test needs isolated state but should not require a separate fixtures directory (per D-07).

### Anti-Patterns to Avoid
- **Reimplementing `mark-complete` behavior:** The guard script should NOT contain its own regex for checkbox/table mutations. Use `gsd-sdk query requirements mark-complete`.
- **Auto-discovery of SUMMARY path:** Do NOT scan for the most recent SUMMARY by mtime. `parallelization: true` means multiple SUMMARYs can be written in the same wave. The executor always knows which SUMMARY to pass.
- **Silent failure on `not_found`:** Do NOT exit zero when IDs are missing from REQUIREMENTS.md. The v1.0 retrospective's Lesson 1 specifically identifies "drift went silent" as the root cause.
- **Leaving temp files on failure:** The fixture test must clean up its temp directory on both pass and failure paths (use `trap EXIT`, not just `rm` at the end).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| YAML frontmatter parsing | Custom `sed`/`awk` frontmatter extractor | `gsd-sdk query frontmatter get <path> --pick requirements-completed` | GSD's frontmatter parser handles YAML multi-line arrays, comments, key variations. Hand-rolled regex will break on edge cases. [VERIFIED: tested frontmatter extraction] |
| Checkbox/table regex mutation | Custom `sed -i` replacements | `gsd-sdk query requirements mark-complete <ids>` | The mutation logic (checkbox `$1x$2`, table `$1 Complete $2`) already exists in `milestone.cjs`, tested across v1.0 plans. Reimplementing risks regex incompatibility and divergence. [VERIFIED: source code inspection confirms regex patterns] |
| JSON array parsing | `grep` + `tr` splitting | `jq -r '.[]'` (primary) or `node -e 'JSON.parse()'` (fallback) | JSON arrays can contain commas within quoted strings. `jq` is a purpose-built JSON processor available on the target system. `grep`/`tr` is a correctness hazard. |

**Key insight:** The sole purpose of `sync-requirements.sh` is to bridge the gap between "SUMMARY.md was just written" and "REQUIREMENTS.md should now reflect that." Every piece of complex logic (frontmatter parsing, regex mutation) is already handled by `gsd-tools`. The script's value is in the integration and the failure semantics (D-09/D-10), not in the mechanics of text manipulation.

## Runtime State Inventory

> Omitted — this is not a rename/refactor/migration phase. Phase 8 introduces new files (`scripts/`) and edits documentation (`.planning/milestones/v1.0-REQUIREMENTS.md`, `AGENTS.md`). No runtime state, stored data, live service config, OS-registered state, secrets, or build artifacts reference the old state that need migration.

## Common Pitfalls

### Pitfall 1: `mark-complete` Does Not Exit Non-Zero on `not_found`

**What goes wrong:** The script author assumes `gsd-sdk query requirements mark-complete BOGUS-99` will exit non-zero. It doesn't — it returns JSON with `"not_found": ["BOGUS-99"]` and exits 0. If the guard script only checks exit codes, it will silently ignore missing requirements — recreating the exact drift the phase is designed to prevent.

**Why it happens:** `milestone.cjs` only calls `error()` (which exits non-zero) for CLI usage errors (no IDs provided). The `not_found` array is returned as data in the JSON response, not as a process exit code.

**How to avoid:** Parse the JSON response's `.not_found` array. Check `not_found.length > 0`. Only then exit non-zero.

**Warning signs:** `sync-requirements.sh` exits 0 when passed a non-existent requirement ID.

[VERIFIED: tested with `gsd-sdk query requirements mark-complete BOGUS-99` — returned JSON with `not_found: ["BOGUS-99"]`, exit code 0]

### Pitfall 2: `frontmatter get --pick` Returns `null` for Missing Fields

**What goes wrong:** If the SUMMARY has an empty `requirements-completed: []` or the field is missing entirely, `--pick requirements-completed` returns `null` (JSON literal). The script pipes `null` into `jq -r '.[]'` which produces no output — but also no error. The script thinks "no requirements to process" and exits 0, when it should at minimum warn.

**Why it happens:** `frontmatter get` returns `null` for undefined/missing keys. An empty `[]` returns `[]` which `jq -r '.[]'` handles correctly (no output).

**How to avoid:** Check for `null` or empty string after extraction. If the frontmatter field is `null`, either warn (the plan had no requirements) or skip silently (not all plans deliver requirements). This is at the agent's discretion per CONTEXT.

**Warning signs:** `sync-requirements.sh` runs silently with no output after a plan that should have completed requirements.

### Pitfall 3: `requirements mark-complete` Targets Current Milestone Only

**What goes wrong:** Someone tries to run `sync-requirements.sh` against a v1.0 SUMMARY to reconcile the archive. The command targets `.planning/REQUIREMENTS.md` (v1.1), not the archive. IDs from v1.0 (like WMRK-01) will appear in `not_found`.

**Why it happens:** `planningPaths(cwd).requirements` resolves to the current `.planning/REQUIREMENTS.md`, not archived milestone files. The `mark-complete` handler has no `--path` override flag.

**How to avoid:** Document that the guard is for the current milestone only. The v1.0 archive reconciliation is a separate manual edit (TRACE-01, D-05). This is by design.

[VERIFIED: tested `mark-complete WMRK-01` — returned `not_found: ["WMRK-01"]` because WMRK-01 exists in the archive but not in v1.1 REQUIREMENTS.md]

### Pitfall 4: Temp Directory Leak in Fixture Test

**What goes wrong:** The test script creates a temp dir with `mktemp -d`, but if an assertion fails and `exit 1` is called, the cleanup `rm -rf` at the end of the script is never reached.

**Why it happens:** `exit` terminates the script immediately, skipping subsequent commands.

**How to avoid:** Use `trap 'rm -rf "$TESTDIR"' EXIT` at the top of the script. `trap EXIT` fires on both normal exit and error exits (but not on SIGKILL). This satisfies D-07's constraint that cleanup must happen on both pass and failure paths.

### Pitfall 5: Shell Injection via Frontmatter

**What goes wrong:** If a SUMMARY frontmatter's `requirements-completed` array contains shell metacharacters (e.g., `["$(rm -rf /)"]`), and the script passes the unescaped values to `eval` or interpolates them unsafely.

**Why it happens:** The frontmatter is written by the gsd-executor (trusted), but the script should still be defensive. The `requirements-completed` field is expected to contain simple identifiers like `REQ-01`.

**How to avoid:** Never use `eval` with extracted data. The JSON is parsed by `jq` which handles string quoting. The comma-joined string is passed as a command-line argument to `mark-complete`, which re-parses it. GSD tools expect plain IDs (`[A-Z]+-\d+`). No direct shell interpolation of raw JSON values.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash | sync-requirements.sh, test-sync-requirements.sh | ✓ | 3.2.57(1)-release | — (mandatory per D-01) |
| gsd-sdk (gsd-tools bridge) | frontmatter get, requirements mark-complete | ✓ | bundled with gsd-sdk | — (mandatory; GSD is installed) |
| jq | JSON array parsing in sync-requirements.sh | ✓ | jq-1.7.1-apple | node -e (Node.js v26.3.0 available) |
| node | Fallback JSON parser | ✓ | v26.3.0 | — (only used if jq unavailable) |
| Python 3 | — | ✓ | 3.12.0 | Not used by this phase |

**Missing dependencies with no fallback:** None — all required tools are present on the target system.

**Missing dependencies with fallback:** None.

## Security Domain

> `security_enforcement` is absent from `.planning/config.json` — per RESEARCH.md template, absent = enabled. However, this phase introduces no application code, no network services, and no user data handling. The threat surface is limited to script-level integrity.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | — |
| V3 Session Management | No | — |
| V4 Access Control | No | — |
| V5 Input Validation | Yes (script level) | Validate requirement IDs against expected pattern `[A-Z]+-\d+` before passing to `mark-complete` |
| V6 Cryptography | No | — |

### Known Threat Patterns for Bash Scripting

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Shell injection via untrusted frontmatter data | Tampering | Never `eval` frontmatter values. Use `jq` for JSON parsing which handles quoting. Pass IDs as individual arguments, not through shell interpolation. |
| REQUIREMENTS.md corruption from buggy regex | Tampering | The mutation regex lives in `milestone.cjs` (already tested across v1.0). The bash script does not perform regex mutations itself. |
| Fixture test temp dir leak | Information Disclosure | `trap EXIT` cleanup, `mktemp -d` in $TMPDIR (already outside workspace). No sensitive data in test fixtures. |
| Accidental mutation of wrong REQUIREMENTS.md | Tampering | `planningPaths(cwd).requirements` resolves relative to cwd. The script inherits the project root from the executor. No path traversal risk — paths are hardcoded in the tool. |

### Threat Model

```
                    ┌─────────────────────────┐
                    │   sync-requirements.sh   │
                    │   (bash, runs post-plan) │
                    └───────────┬─────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
    ┌─────────────────┐ ┌─────────────┐ ┌──────────────────┐
    │ Frontmatter JSON │ │ jq parsing  │ │ mark-complete    │
    │ (trusted source  │ │ (no eval)   │ │ (Node.js, regex  │
    │  from executor)  │ │             │ │  in milestone.cjs)│
    └─────────────────┘ └─────────────┘ └──────────────────┘
    
    Risk: LOW — all data originates from the gsd-executor (trusted),
    not from external input. The frontmatter is written by a known
    template. The mark-complete handler already validates ID format.
```

**Highest severity threat:** If a bug in `milestone.cjs`'s regex causes incorrect `requirements mark-complete` mutations (e.g., matching partial requirement IDs), the script would propagate the bug. Mitigation: the fixture test (`test-sync-requirements.sh`) validates exact mutation behavior against known inputs, providing a regression gate.

## Sources

### Primary (HIGH confidence)
- `.planning/milestones/v1.0-MILESTONE-AUDIT.md` — Authoritative evidence for all 15 drifted requirements. Frontmatter `gaps.requirements[]` lists per-req status, phase, plans, and code evidence. [VERIFIED: file inspection 2026-06-18]
- `.planning/milestones/v1.0-REQUIREMENTS.md` — Edit target for TRACE-01. Confirmed 10 unchecked `[ ]` checkboxes, 5 missing checkbox items, 15 stale traceability entries. [VERIFIED: file inspection 2026-06-18]
- `~/.config/opencode/get-shit-done/bin/lib/milestone.cjs` lines 14-90 — `cmdRequirementsMarkComplete` source. Confirmed regex patterns, JSON response structure, exit behavior. [VERIFIED: source code read]
- `~/.config/opencode/get-shit-done/bin/lib/commands.cjs` lines 475-476 — `requirements_completed` field extraction from `frontmatter` command. [VERIFIED: source code read]
- `.planning/phases/08-traceability-reconciliation-recurrence-guard/08-CONTEXT.md` — Locked decisions D-01 through D-11. [VERIFIED: file inspection]
- Target system — Confirmed `bash` 3.2.57, `jq` 1.7.1, `node` v26.3.0, `gsd-sdk` present. [VERIFIED: command execution 2026-06-18]

### Secondary (MEDIUM confidence)
- `.planning/RETROSPECTIVE.md` §"Key Lessons" #1 — Documents the drift root cause and motivation for automation. [CITED: file inspection]
- `.planning/REQUIREMENTS.md` — v1.1 requirements and traceability table (confirms success criteria #4 satisfied). [CITED: file inspection]
- `.planning/ROADMAP.md` §"Phase 8" — Success criteria and phase dependencies. [CITED: file inspection]

### Tertiary (LOW confidence)
- None — all claims verified against primary sources or direct testing.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `jq` will remain available on the gsd-executor's machine for future plan completions (not just the current session) | Standard Stack | LOW — `jq` is bundled with macOS. If removed, fallback to `node -e` is trivial to add. |
| A2 | SUMMARY.md `requirements-completed` frontmatter will always contain valid requirement IDs matching the `[A-Z]+-\d+` pattern | Recurrence Guard Design | LOW — the SUMMARY template enforces this format; invalid IDs are caught by `not_found`. |
| A3 | The gsd-executor will run `sync-requirements.sh` from the project root (so `planningPaths(cwd)` resolves correctly) | Recurrence Guard Design | LOW — the executor always operates from the project root by convention. |
| A4 | `gsd-sdk query frontmatter get` continues to use the `--pick` flag with the same semantics in future GSD versions | Recurrence Guard Design | MEDIUM — if the CLI changes, the script needs updating. This is a documented dependency; the fixture test would catch breakage. |

## Open Questions (RESOLVED)

1. **RESOLVED: One commit or split for TRACE-01?**
   - What we know: D-06 specifies a single atomic commit. The planner may prefer to split checkbox updates from category reclassification for reviewability.
   - Resolution: Single atomic commit as specified. The plan (08-01-PLAN.md Task 2, Part F) implements a single commit with the locked message. No splitting needed — all edits are confined to one file and the atomicity of "reconciliation happened" is more important than per-change granularity for an archived document.

2. **RESOLVED: What if SUMMARY.md has `requirements-completed: []` (empty array)?**
   - What we know: `frontmatter get --pick` returns `[]`. `jq -r '.[]'` produces no output. The script should exit 0 (not an error — the plan simply didn't deliver new requirements).
   - Resolution: The script (08-02-PLAN.md Task 1, step 3) handles three cases explicitly: JSON array with IDs → proceed; `null` or empty string → exit 0; empty array `[]` → exit 0. This is a normal case covered in the implementation contract.

3. **RESOLVED: What if the gsd-executor skips running `sync-requirements.sh`?**
   - What we know: The recurrence guard is "semi-automatic" — documented in AGENTS.md as a step the executor runs, not a hard enforcement in the GSD workflow code.
   - Resolution: The AGENTS.md post-plan step (08-02-PLAN.md Task 3) is documented with a prominent `## GSD Post-Plan Step` heading, a MUST invocation, an exit code table with BLOCKER designations, and a resolution path. The executor's adherence is trust-based. A future phase could wire it into the GSD workflow files, but that's deferred (D-03 explicitly keeps it repo-local).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools verified present on target; `mark-complete` behavior confirmed through live testing.
- Architecture: HIGH — CONTEXT.md provides detailed locked decisions; tool behavior confirmed through source inspection and live testing.
- Pitfalls: HIGH — pitfall #1 (`mark-complete` exit code behavior) discovered through live testing and is the most critical implementation detail.
- Current state: HIGH — v1.0 archive audited line-by-line; counts verified via grep; MILESTONE-AUDIT.md cross-referenced.

**Research date:** 2026-06-18
**Valid until:** 2026-08-18 (60 days — process tooling phase; unlikely to change within the v1.1 milestone)
