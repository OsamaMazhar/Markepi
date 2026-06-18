# Phase 8: Traceability Reconciliation & Recurrence Guard - Pattern Map

**Mapped:** 2026-06-18
**Files analyzed:** 4 new/modified files
**Analogs found:** 2 / 4

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/sync-requirements.sh` | utility/script | transform | RESEARCH.md lines 450-489 (no bash scripts in repo) | no-analog |
| `scripts/test-sync-requirements.sh` | test/script | transform | RESEARCH.md lines 284-324 (no test scripts in repo) | no-analog |
| `.planning/milestones/v1.0-REQUIREMENTS.md` | config/doc | N/A (manual edit) | Self (same file, existing structure) + `.planning/REQUIREMENTS.md` | exact |
| `AGENTS.md` | config/doc | N/A (manual edit) | Self (same file, existing section delimiters) | exact |

**Note:** This repo is a pure iOS/Swift project — no bash scripts, Makefile, package.json, or `.github/` tooling exist. The two new `scripts/` files are the first non-Swift tooling introduced. Their closest analogs are the code patterns documented in RESEARCH.md (derived from the GSD tooling in `~/.config/opencode/get-shit-done/bin/lib/milestone.cjs`), not from existing repo files.

---

## Pattern Assignments

### `scripts/sync-requirements.sh` (utility/script, transform)

**Analog:** RESEARCH.md §"Recurrence Guard Design" lines 450-489 — proposed implementation pattern. No existing bash scripts exist in the repo. The script's sole purpose is glue: extract `requirements-completed` from a SUMMARY frontmatter → parse JSON → delegate mutation to `gsd-sdk query requirements mark-complete`.

**Shebang and strict mode** (pattern from RESEARCH.md line 454):
```bash
#!/usr/bin/env bash
# Source: D-04 pipeline specification from CONTEXT.md
set -euo pipefail
```

**Argument validation** (pattern from RESEARCH.md lines 456-460):
```bash
SUMMARY_PATH="$1"
if [ ! -f "$SUMMARY_PATH" ]; then
  echo "ERROR: SUMMARY not found: $SUMMARY_PATH" >&2
  exit 2
fi
```

**Frontmatter extraction via GSD SDK** (pattern from RESEARCH.md lines 462-467):
```bash
# Step 1: Extract requirement IDs from SUMMARY frontmatter
IDS_JSON=$(gsd-sdk query frontmatter get "$SUMMARY_PATH" --pick requirements-completed 2>/dev/null)
if [ -z "$IDS_JSON" ] || [ "$IDS_JSON" = "null" ]; then
  echo "No requirements-completed found in SUMMARY frontmatter" >&2
  exit 0  # Not an error — plan may not have delivered new requirements
fi
```

**JSON parsing with jq** (primary, RESEARCH.md line 470):
```bash
# Step 2: Parse JSON array → comma-joined string
COMMA_IDS=$(echo "$IDS_JSON" | jq -r '.[]' 2>/dev/null | paste -sd, -)
if [ -z "$COMMA_IDS" ]; then
  echo "requirements-completed array is empty" >&2
  exit 0
fi
```

**Fallback JSON parsing with node** (RESEARCH.md line 277):
```bash
# Fallback if jq unavailable:
COMMA_IDS=$(echo "$IDS_JSON" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).join(','))")
```

**Delegating to mark-complete** (pattern from RESEARCH.md lines 476-477; tool behavior from milestone.cjs lines 14-90):
```bash
# Step 3: Mark requirements complete
# milestone.cjs cmdRequirementsMarkComplete (lines 14-90):
#   - Accepts comma-separated, space-separated, or bracket-wrapped IDs
#   - Regex for checkbox: (-\s*\[)[ ](\]\s*\*\*REQ-ID\*\*) → $1x$2
#   - Regex for traceability: (|\s*REQ-ID\s*\|[^|]+\|)\s*Pending\s*(|) → $1 Complete $2
#   - Returns JSON: {updated, marked_complete:[], already_complete:[], not_found:[], total}
#   - Does NOT exit non-zero on not_found — must parse JSON response
RESULT=$(gsd-sdk query requirements mark-complete "$COMMA_IDS" 2>&1)
echo "$RESULT"
```

**Error handling — not_found detection** (D-09 contract, pattern from RESEARCH.md lines 480-487):
```bash
# Step 4: Check for not_found (exit non-zero per D-09)
# CRITICAL: mark-complete returns JSON {not_found: [...]} but exits 0.
# The script MUST parse the JSON response, NOT rely on exit code.
# (milestone.cjs lines 83-89: error() only called for CLI usage errors, not not_found)
NOT_FOUND_COUNT=$(echo "$RESULT" | jq -r '.not_found | length' 2>/dev/null)
if [ "${NOT_FOUND_COUNT:-0}" -gt 0 ]; then
  echo "BLOCKER: ${NOT_FOUND_COUNT} requirement ID(s) not found in REQUIREMENTS.md" >&2
  echo "$RESULT" | jq -r '.not_found[]' >&2
  exit 1
fi

exit 0
```

**Exit code contract** (pattern from CONTEXT.md D-09/D-10, RESEARCH.md lines 360-363):
```
Exit 0  → All IDs marked_complete or already_complete. No not_found. Safe to proceed.
Exit 1  → At least one ID in not_found. Plan-completion BLOCKER.
Exit 2+ → Script error (missing SUMMARY, invalid frontmatter, tool failure). BLOCKER.
```

---

### `scripts/test-sync-requirements.sh` (test/script, transform)

**Analog:** RESEARCH.md §"Guard Verification" lines 284-324. No existing test scripts in repo. The pattern: self-contained bash script with inline heredoc fixtures, temp directory, trap-based cleanup, and jq assertions across three branches.

**Shebang and strict mode with trap cleanup** (pattern from RESEARCH.md lines 290-292):
```bash
#!/usr/bin/env bash
# Test: scripts/test-sync-requirements.sh
# Inline heredoc fixtures, temp dir, three assertion blocks

set -euo pipefail
TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT  # Cleanup on both pass and failure paths (D-07 constraint)
```

**Fixture 1: Happy path** (pattern from RESEARCH.md lines 295-309):
```bash
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
```

**Fixture 2: not_found** (pattern from RESEARCH.md lines 311-315):
```bash
# --- Fixture 2: not_found ---
# (re-create REQUIREMENTS.md with no TEST-B99 — or different temp dir)
echo "$RESULT2" | jq -e '.not_found | length > 0' > /dev/null \
  && echo "PASS: not_found detected" || { echo "FAIL: not_found"; exit 1; }
```

**Fixture 3: already_complete (idempotency)** (pattern from RESEARCH.md lines 317-321):
```bash
# --- Fixture 3: already_complete ---
# (re-create with already-checked TEST-A01)
echo "$RESULT3" | jq -e '.already_complete | index("TEST-A01")' > /dev/null \
  && echo "PASS: already_complete idempotent" || { echo "FAIL: already_complete"; exit 1; }
```

**Final assertion** (pattern from RESEARCH.md line 323):
```bash
echo "ALL TESTS PASSED"
```

**No-mutation assertion for not_found branch** (D-11 constraint — test must verify that not_found mutates nothing):
```bash
# After fixture 2, verify REQUIREMENTS.md is unmodified:
grep -q 'TEST-B99' "$TESTDIR/REQUIREMENTS.md" && { echo "FAIL: not_found mutated REQUIREMENTS.md"; exit 1; }
echo "PASS: not_found did not mutate"
```

---

### `.planning/milestones/v1.0-REQUIREMENTS.md` (config/doc, manual edit)

**Analog:** Self — the existing file structure at `.planning/milestones/v1.0-REQUIREMENTS.md` (178 lines). The edit follows the existing document conventions. Also references `.planning/REQUIREMENTS.md` for the current milestone's structure pattern.

**Document header** (pattern from lines 1-6 of existing file):
```markdown
# Requirements Archive: v1.0 MVP

**Archived:** 2026-06-18
**Status:** SHIPPED

For current requirements, see `.planning/REQUIREMENTS.md`.
```

**Reconciliation Note section** — NEW, to be inserted after the header (D-06 pattern):
```markdown
## Reconciliation Note

**Reconciled:** 2026-06-18
**Evidence:** `.planning/milestones/v1.0-MILESTONE-AUDIT.md` (authoritative per-requirement audit)

**Changes made:**
- Flipped 10 unchecked `[ ]` checkboxes → `[x]` for EXPT×3, COMP×2, VIDX×3 (Phase 6), LIVE×2 (Phase 7)
- Reclassified 7 shipped Phase 7 requirements from `## v2 Requirements` up into `## v1 Requirements`: LIVE×2, SIGN×1, IMPS×2, SYSI×2
- Moved 4 category headings (### Live Photos, ### Signature, ### Additional Import Sources, ### System Integration) from v2 → v1 section, appended after ### Video Export UX
- Updated traceability table: 10 `Pending` → `Complete`, 5 `Pending (v2)` → `Complete`
- Corrected Coverage counts: v1 = 35 (28 + 7), v2 = 6 (CUST×4 + BATC×2)
- Updated "Last updated" footer to 2026-06-18
```

**Checkbox pattern — flippable entry** (existing pattern from lines 65-67):
```markdown
### Export Control (EXPT)

- [ ] **EXPT-01**: User can choose output format: HEIC, JPEG, PNG, or TIFF
- [ ] **EXPT-02**: User can adjust output quality via a compression/quality slider (60–100%)
- [ ] **EXPT-03**: Format choice is preserved alongside HDR and metadata (lossless re-wrap where possible)
```
→ After edit: `[ ]` becomes `[x]` for all 10 drifted entries.

**Checkbox pattern — missing checkbox item** (existing pattern from line 103 — SIGN-01 has NO checkbox, just `- **SIGN-01**:`):
```markdown
### Signature (SIGN)

- **SIGN-01**: User can draw or capture a signature to use as a watermark overlay
```
→ After edit: becomes `- [x] **SIGN-01**:` (same for IMPS×2, SYSI×2 = 5 items total)

**Category heading — v2 to v1 reclassification** (existing pattern from lines 80-113):
Move these 4 headings wholesale from `## v2 Requirements` up into `## v1 Requirements`, appended after `### Video Export UX (VIDX)`:
```markdown
### Live Photos (LIVE)
### Signature (SIGN)
### Additional Import Sources (IMPS)
### System Integration (SYSI)
```

**Traceability table — status update** (existing pattern from lines 163-169):
```markdown
| LIVE-01 | Phase 7 | Pending (v2) |
| LIVE-02 | Phase 7 | Pending (v2) |
| SIGN-01 | Phase 7 | Pending (v2) |
| IMPS-01 | Phase 7 | Pending (v2) |
| IMPS-02 | Phase 7 | Pending (v2) |
| SYSI-01 | Phase 7 | Pending (v2) |
| SYSI-02 | Phase 7 | Pending (v2) |
```
→ After edit: `Pending (v2)` becomes `Complete`. Phase column stays.

**Also update lines 155-162:** `Pending` → `Complete` for EXPT×3, COMP×2, VIDX×3.

**Coverage counts — fix** (existing pattern from lines 171-173):
```markdown
**Coverage:**
- v1 requirements: 28 total (14 original + 14 new)
- v2 requirements: 13 total (6 original + 7 new)
- All requirements mapped to phases ✓
```
→ After edit:
```markdown
**Coverage:**
- v1 requirements: 35 total (28 original + 7 reclassified from v2)
- v2 requirements: 6 total (CUST×4 + BATC×2, truly deferred)
- All requirements mapped to phases ✓
```

**Footer — update date** (existing pattern from lines 177-178):
```markdown
*Requirements defined: 2026-06-17*
*Last updated: 2026-06-17 — added v1 phases 5-6 (ProRAW, EXIF tokens, multi-layer, export control, comparison, video UX) and v2 phase 7 (Live Photos, signature, Files import, system integration) from competitive research gaps*
```
→ After edit:
```markdown
*Requirements defined: 2026-06-17*
*Last updated: 2026-06-18 — reconciled against v1.0-MILESTONE-AUDIT.md: 10 checkboxes flipped, 7 Phase 7 reqs reclassified v2→v1, traceability table corrected*
```

**v2 Requirements — trim to deferred only** (existing pattern from lines 85-113):
The `## v2 Requirements` section should retain only:
```markdown
## v2 Requirements (deferred)

Deferred to future release. Not in current roadmap.

### Customization

- **CUST-01**: User can save and reuse watermark configuration templates
- **CUST-02**: User can rotate watermarks
- **CUST-03**: User can customize frame color and style (beyond white)
- **CUST-04**: User can add additional metadata frame types (date, location, camera lens info)

### Batch Processing

- **BATC-01**: User can watermark multiple photos at once
- **BATC-02**: User can watermark multiple videos at once
```

---

### `AGENTS.md` (config/doc, manual edit)

**Analog:** Self — the existing structure at `AGENTS.md` (167 lines). New sections follow the established HTML comment delimiter pattern.

**Section delimiter pattern** (from existing file — all sections use this convention):
```markdown
<!-- GSD:xxx-start source:yyy -->
## Section Name

...content...

<!-- GSD:xxx-end -->
```

**Existing sections in order** (from AGENTS.md lines 1-167):
```
<!-- GSD:project-start source:PROJECT.md -->         → ## Project
<!-- GSD:stack-start source:research/STACK.md -->     → ## Technology Stack
<!-- GSD:conventions-start source:CONVENTIONS.md -->  → ## Conventions
<!-- GSD:architecture-start source:ARCHITECTURE.md --> → ## Architecture
<!-- GSD:skills-start source:skills/ -->              → ## Project Skills
<!-- GSD:workflow-start source:GSD defaults -->       → ## GSD Workflow Enforcement
<!-- GSD:profile-start -->                            → ## Developer Profile
```

**New section placement** (per RESEARCH.md lines 333-334): Insert between `## GSD Workflow Enforcement` (`<!-- GSD:workflow-end -->` at line 158) and `## Developer Profile` (`<!-- GSD:profile-start -->` at line 162). The existing blank lines (159-160) are the insertion point.

**Post-plan step section** (content pattern from RESEARCH.md lines 335-340):
```markdown
<!-- GSD:post-plan-start source=.planning/phases/08-traceability-reconciliation-recurrence-guard -->
## GSD Post-Plan Step

After writing a plan's SUMMARY.md, the gsd-executor MUST run:

```
bash scripts/sync-requirements.sh <path-to-summary>
```

This keeps `.planning/REQUIREMENTS.md` checkboxes and traceability table in sync with shipped features, preventing the manual drift that affected v1.0 (10/35 requirements unchecked at milestone close).

### Exit Codes and Resolution

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | All requirement IDs marked complete or already complete. No `not_found`. | Proceed — plan completion is unblocked. |
| 1 | At least one requirement ID in `not_found`. **BLOCKER.** | Resolve before marking plan complete: |
| 2+ | Script error (missing SUMMARY, invalid frontmatter, tool failure). **BLOCKER.** | Diagnose and fix the script or SUMMARY. |

### Not-Found Resolution Path

If the script exits 1 (IDs in `not_found`):

1. **Typo in SUMMARY `requirements-completed`:** Fix the requirement ID in the SUMMARY frontmatter, then re-run the script.
2. **Requirement ID missing from REQUIREMENTS.md:** Add the requirement definition to `.planning/REQUIREMENTS.md` (with `- [ ] **ID**:` checkbox and traceability table row), then re-run the script.
3. The script is idempotent — re-running with corrected data is always safe.

### Regression Check

Verify the guard works:

```bash
bash scripts/test-sync-requirements.sh
```

This self-contained fixture test validates three branches (happy path, not_found, already_complete) and exits non-zero on failure. Run after any change to `sync-requirements.sh` or the GSD `mark-complete` tool.

<!-- GSD:post-plan-end -->
```

**Commit message for this edit** (following existing convention — `config(GSD): ...`):
```
docs(AGENTS.md): document sync-requirements.sh post-plan step for recurrence guard
```

---

## Shared Patterns

### GSD Section Delimiters (AGENTS.md)

**Source:** `AGENTS.md` lines 1, 19, 129, 135, 141, 147, 158, 162, 167
**Apply to:** New section addition in AGENTS.md
```markdown
<!-- GSD:xxx-start source:yyy -->
## Section Name
...content...
<!-- GSD:xxx-end -->
```
Convention: blank line between `<!-- GSD:xxx-end -->` and next `<!-- GSD:yyy-start -->`.

### REQUIREMENTS.md Structure

**Source:** `.planning/milestones/v1.0-REQUIREMENTS.md` and `.planning/REQUIREMENTS.md`
**Apply to:** Manual edit of v1.0 archive
```markdown
# Requirements: Watermark — v1.0 MVP
**Defined:** YYYY-MM-DD
**Core Value:** ...
**Status:** SHIPPED

## v1 Requirements
### Category (PREFIX)
- [x] **REQ-ID**: Description
### Another Category (ANOTHER)
- [x] **REQ-ID**: Description

## v2 Requirements (deferred)
### Deferred Category
- **REQ-ID**: Description  (no checkbox for truly deferred)

## Traceability
| Requirement | Phase | Status |
|-------------|-------|--------|
| REQ-ID | Phase N | Status |

**Coverage:**
- v1 requirements: N total (...)
- v2 requirements: N total (...)

*Requirements defined: YYYY-MM-DD*
*Last updated: YYYY-MM-DD — description of changes*
```

### Commit Message Convention

**Source:** `.planning/config.json` + D-06 specification
**Apply to:** All commits in this phase
```
type(scope): description
```
Examples:
- `docs(v1.0): reconcile archived REQUIREMENTS.md traceability` (locked per D-06)
- `docs(AGENTS.md): document sync-requirements.sh post-plan step for recurrence guard`
- `feat(scripts): add sync-requirements.sh recurrence guard for REQUIREMENTS.md`
- `test(scripts): add test-sync-requirements.sh fixture-based bash test`

### GSD SDK Invocation Pattern

**Source:** RESEARCH.md lines 242-257, verified against live system
**Apply to:** `scripts/sync-requirements.sh`
```bash
# Frontmatter extraction
gsd-sdk query frontmatter get <path> --pick requirements-completed
# Returns JSON array: ["TRACE-01", "TRACE-02"]

# Requirements mutation
gsd-sdk query requirements mark-complete TRACE-01,TRACE-02
# Returns JSON: {"updated":true,"marked_complete":["TRACE-01","TRACE-02"],"already_complete":[],"not_found":[],"total":2}
```
Note: `mark-complete` does NOT exit non-zero on `not_found` — the script must parse the JSON response.

### mark-complete Mutation Behavior

**Source:** `~/.config/opencode/get-shit-done/bin/lib/milestone.cjs` lines 14-90
**Apply to:** Understanding what the guard script delegates to
```javascript
// Checkbox regex (line 49):
//   /(-\s*\[)[ ](\]\s*\*\*<REQ-ID>\*\*)/gi  →  $1x$2
//   Matches: - [ ] **REQ-ID** → - [x] **REQ-ID**
//
// Traceability table regex (line 57):
//   /(\|\s*<REQ-ID>\s*\*\|[^|]+\|)\s*Pending\s*(|)/gi  →  $1 Complete $2
//   Matches: | REQ-ID | Phase N | Pending | → | REQ-ID | Phase N | Complete |
//
// Limitations for archive reconciliation:
//   - Table regex requires "Pending" immediately before "|" — won't match "Pending (v2)|"
//   - Targets cwd's .planning/REQUIREMENTS.md, not archived milestone files
//   - Items without checkbox syntax (- **ID**:) won't match checkbox regex
//   - Exit code 0 even on not_found (JSON response is the truth)
```

### Requirements ID Format Convention

**Source:** All REQUIREMENTS.md files (both v1.0 archive and v1.1 current)
**Apply to:** All new requirements and SUMMARY frontmatter
```
Pattern: [A-Z]+-\d{2}
Examples: TRACE-01, EXPT-03, BUILD-01
Not: EXPT-1, expt-01, EXPORT-01
```

---

## No Analog Found

Files with no close match in the codebase (planner should use RESEARCH.md patterns instead):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `scripts/sync-requirements.sh` | utility/script | transform | This is the first bash script in the repo. Repo is pure iOS/Swift — no Makefile, no shell scripts, no Node.js tooling beyond `.planning/`. Use RESEARCH.md §"Recurrence Guard Design" (lines 450-489) as the primary implementation pattern, referencing `milestone.cjs` lines 14-90 for the delegated `mark-complete` behavior. |
| `scripts/test-sync-requirements.sh` | test/script | transform | First bash test script in repo. No existing test infrastructure for non-Swift tooling. Use RESEARCH.md §"Guard Verification" (lines 284-324) as the primary pattern: inline heredoc fixtures, `mktemp -d` temp dir, `trap EXIT` cleanup, `jq` assertions across three branches. |

**Guidance for planner:** The RESEARCH.md code examples for both scripts are near-complete implementations derived from live testing against the actual GSD tooling. The planner should treat these as the definitive patterns, not as abstract suggestions. The key implementation detail to get right is Pitfall #1 (RESEARCH.md lines 519-529): `mark-complete` exits 0 even on `not_found` — the script MUST parse the JSON response.

---

## Metadata

**Analog search scope:**
- `scripts/**` — verified empty (no prior scripts dir)
- `**/*.sh` — 0 results (no bash scripts exist)
- `Makefile*` — 0 results
- `package.json` — 0 results
- `.planning/milestones/` — 3 files (v1.0 audit, requirements, roadmap)
- `.planning/*.md` — current milestone documentation
- `AGENTS.md` — project instructions (167 lines)
- `~/.config/opencode/get-shit-done/bin/lib/milestone.cjs` — mark-complete handler source

**Files scanned:** 12 (6 glob patterns + 4 file reads + GSD tooling source)
**Pattern extraction date:** 2026-06-18
**Phase type:** Documentation + tooling — no application code changes
