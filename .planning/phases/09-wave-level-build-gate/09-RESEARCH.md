# Phase 09: Wave-Level Build Gate - Research

**Researched:** 2026-06-18
**Domain:** iOS/xcodebuild CI gate + bash scripting + GSD workflow integration
**Confidence:** HIGH

## Summary

Phase 09 delivers a build gate that runs `xcodebuild` across all 3 targets (WatermarkApp, ShareExtension, PhotoEditExtension) after each execution wave. The phase is pure bash scripting — no external packages, no framework integration, no code changes to the app itself. The deliverable is two scripts (`build-gate.sh`, `test-build-gate.sh`) and an AGENTS.md documentation update, following the exact pattern established by Phase 8's `sync-requirements.sh` / `test-sync-requirements.sh`.

The build command is locked and verified: `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination 'generic/platform=iOS' build`. The WatermarkApp scheme covers all targets via `buildImplicitDependencies = "YES"` (scheme-level setting — no CLI flag exists for this). All dependencies verified: Xcode 26.2, git 2.50.1, bash 3.2 with pipefail support — all present and compatible.

**Primary recommendation:** Follow Phase 8's bash patterns exactly (`set -euo pipefail`, argument validation, `trap`-based cleanup, three-branch fixture tests, `git checkout` for file restoration). The build gate is structurally simpler than Phase 8's recurrence guard — no `jq` parsing, no `gsd-sdk` delegation — just pure bash calling `xcodebuild` and propagating its exit code.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

| ID | Decision | Constraint |
|----|----------|------------|
| D-01 | Build via single WatermarkApp scheme | `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination 'generic/platform=iOS' build` |
| D-02 | Use `-destination 'generic/platform=iOS'` | Not `-sdk iphonesimulator`. Generic device builds without signing/code-signing while catching all compilation errors. |
| D-03 | Use Debug configuration | Debug catches same compilation errors, compiles ~2-3x faster (no optimization passes). Gate goal is correctness verification. |
| D-04 | Script at `scripts/build-gate.sh` | Pure bash, zero deps beyond xcodebuild. `set -euo pipefail`. |
| D-05 | Pass/fail summary to stdout | `BUILD GATE: PASSED` or `BUILD GATE: FAILED — see errors above` |
| D-06 | AGENTS.md documentation | "Post-Wave Build Gate" section alongside Phase 8's post-plan step |
| D-07 | Wired at wave boundaries | Runs after all plans in a wave complete, before next wave begins |
| D-08 | Exit non-zero on any failure | Propagate xcodebuild exit code directly. No custom error parsing. |
| D-09 | No aggregation or retry | One failure = gate fails. Errors are deterministic. |
| D-10 | Fixture test at `scripts/test-build-gate.sh` | Three branches: clean build passes, broken build caught, gate blocks wave progression |
| D-11 | Test isolation with trap | Backup original file before mutation, restore via `trap` using `git checkout` |
| D-12 | Test exits non-zero on failure | Exit 0 only when all branches pass |
| D-13 | Build-only gate | No `test` action. Tests remain separate concern. |
| D-14 | Replaces file-existence self-checks | The AGENTS.md entry must explicitly state this replaces old self-checks as source of truth |

### the agent's Discretion

- Exact bash implementation details (temp log file, summary line format, trap configuration)
- Which Swift source file to mutate in `test-build-gate.sh` (non-critical, fast to compile, unlikely to conflict)
- Whether test uses temp dir with project copy or in-place mutation with git restoration
- Exact wording and placement of AGENTS.md post-wave step

### Deferred Ideas (OUT OF SCOPE)

- PHRO-01 (per-phase VERIFICATION.md template) — deferred to future process-hardening milestone
- PHRO-02 (worktree-safety fix for task-tool branching) — GSD tooling concern, deferred
- Running build gate as git hook or pre-commit hook
- Editing GSD workflow files in `~/.config/get-shit-done/`
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BUILD-01 | A wave-level build gate runs `xcodebuild` across all 3 targets (Main App, ShareExtension, PhotoEditExtension) after each execution wave — replacing file-existence-only self-checks — so broken builds surface at source rather than at milestone audit | Verified: single WatermarkApp scheme covers all 3 targets via `buildImplicitDependencies = "YES"`. The `-destination 'generic/platform=iOS'` builds without code signing. Debug config compiles faster (Section: Architecture Patterns). The AGENTS.md documentation makes discovery automatic for gsd-executor (Section: Architecture Patterns — Wave Boundary Wiring). |
</phase_requirements>

## Architectural Responsibility Map

This is a tooling/infrastructure phase — not a tiered application architecture. The build gate operates entirely at the developer tooling layer:

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Build verification (xcodebuild) | Developer Tooling (scripts/) | — | Runs as a CLI script, not in-app |
| Wave-boundary hook | GSD Workflow (AGENTS.md) | — | Discovered by gsd-executor at session start |
| Fixture test | Developer Tooling (scripts/) | — | Self-contained bash test, follows Phase 8 pattern |
| Build failure blocking | GSD Workflow (AGENTS.md) | — | Exit-code contract: 0 = proceed, non-zero = BLOCKER |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 3.2.57 (Apple) | Script runtime | Pre-installed on macOS. `set -euo pipefail` fully supported since bash 3.0. No alternatives needed. [VERIFIED: system] |
| xcodebuild | 26.2 (Xcode 26.2) | Build verification | The only CLI for building Xcode projects. Pre-installed with Xcode. Exit codes: 0 = success, non-zero = failure. [VERIFIED: system] |
| git | 2.50.1 (Apple Git-155) | File restoration in fixture test | Pre-installed on macOS. Used only by `test-build-gate.sh` to restore mutated source files via `git checkout`. [VERIFIED: system] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| jq | 1.7.1-apple | JSON parsing | Not needed for build-gate.sh. Available if planner wants to parse BUILD_LOGS output, but D-08 explicitly forbids custom error parsing. [VERIFIED: system] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `-destination 'generic/platform=iOS'` | `-sdk iphonesimulator` | Simulator requires booted simulator, skips device-only code paths. Generic destination catches all compilation errors without requiring a device or simulator. [CITED: apple.com documentation] |
| Debug configuration | Release | Release runs optimization passes (~2-3x slower), same compilation errors caught. Debug is sufficient for correctness verification. [CITED: apple.com documentation] |
| Per-target xcodebuild invocations | Single WatermarkApp scheme | Single scheme covers all targets via implicit dependency resolution. Per-target would require 3 separate invocations and miss inter-target dependency errors. [VERIFIED: xcodebuild -list + scheme inspection] |

**Installation:** No package manager needed. All tools are pre-installed on macOS with Xcode.

**Version verification:**
```bash
xcodebuild -version        # Verified: Xcode 26.2, Build version 17C52
git --version              # Verified: git version 2.50.1 (Apple Git-155)
bash --version             # Verified: GNU bash, version 3.2.57(1)-release
```

## Package Legitimacy Audit

> **SKIPPED** — This phase installs zero external packages. All tools (bash, xcodebuild, git) are pre-installed system binaries on macOS. No npm, pip, or cargo packages are needed. The slopcheck verification gate is not applicable.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| xcodebuild | build-gate.sh (build verification) | ✓ | 26.2 (Xcode 26.2) | — |
| bash | Both scripts (runtime) | ✓ | 3.2.57(1)-release | — |
| git | test-build-gate.sh (file restoration via `git checkout`) | ✓ | 2.50.1 (Apple Git-155) | — |
| mktemp | test-build-gate.sh (temp directory creation) | ✓ | macOS built-in | — |
| Watermark.xcodeproj | build-gate.sh (build target) | ✓ | Present at repo root | — |
| WatermarkApp scheme | build-gate.sh (build entry point) | ✓ | Verified: `xcodebuild -list` shows it; scheme has `buildImplicitDependencies = "YES"` | — |
| SPM packages (WatermarkCore) | Build dependency | ✓ | Resolves from `Packages/WatermarkCore` | — |

**Missing dependencies with no fallback:** None — all dependencies verified present and correct version.

**Missing dependencies with fallback:** None.

**Note on xcodebuild availability:** xcodebuild requires Xcode.app to be installed at `/Applications/Xcode.app/`. Verified present (Xcode 26.2). If the xcode command-line tools path differs, the script should not assume `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild` — the bare `xcodebuild` command resolves via `xcode-select -p` and is the correct invocation.

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│              GSD EXECUTE-PHASE WAVE              │
│                                                  │
│  Plan P01 │ Plan P02 │ Plan P03 (parallel)       │
│     │          │          │                       │
│     ▼          ▼          ▼                       │
│  SUMMARY.md  SUMMARY.md  SUMMARY.md              │
│     │          │          │                       │
│     └──────────┴──────────┘                       │
│                │  (wave complete)                 │
│                ▼                                  │
│     ┌──────────────────────┐                     │
│     │  bash scripts/       │                     │
│     │  build-gate.sh       │  ◄── WAVE BOUNDARY  │
│     │                      │                     │
│     │  xcodebuild          │                     │
│     │  -project ...        │                     │
│     │  -scheme             │                     │
│     │  WatermarkApp        │                     │
│     └──────┬───────────────┘                     │
│            │                                      │
│     ┌──────▼───────────────┐                     │
│     │  Exit 0:             │  Exit ≠0:           │
│     │  "BUILD GATE:        │  "BUILD GATE:       │
│     │   PASSED"            │   FAILED..."        │
│     │  → Next wave         │  → BLOCKER          │
│     └──────────────────────┴─────────────────────┘│
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│            xcodebuild INTERNALS                  │
│                                                  │
│  WatermarkApp scheme                             │
│  buildImplicitDependencies = YES                 │
│       │                                          │
│       ├── WatermarkApp (main target)             │
│       │                                          │
│       ├── ShareExtension (implicit dep)          │
│       │                                          │
│       ├── PhotoEditExtension (implicit dep)      │
│       │                                          │
│       └── WatermarkCore (explicit dep, SPM)      │
│                                                  │
│  All targets compiled in single invocation       │
│  Any failure → non-zero exit code                │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│         test-build-gate.sh FLOW                  │
│                                                  │
│  BRANCH 1: Clean build                           │
│  ┌────────────────────┐                          │
│  │ Unmodified project  │ → build-gate.sh         │
│  │                    │ → assert exit 0          │
│  │                    │ → assert "PASSED"        │
│  └────────────────────┘                          │
│                                                  │
│  BRANCH 2: Broken build caught                   │
│  ┌────────────────────┐                          │
│  │ git checkout --     │  ←── trap EXIT           │
│  │ <source-file>       │                          │
│  └────────┬───────────┘                          │
│           │                                       │
│  ┌────────▼───────────┐                          │
│  │ echo "let x =" >>   │  (syntax error inj.)    │
│  │ <source-file>.swift  │                          │
│  └────────┬───────────┘                          │
│           │                                       │
│  ┌────────▼───────────┐                          │
│  │ build-gate.sh       │ → assert exit ≠0        │
│  │                    │ → assert "FAILED"        │
│  │                    │ → assert stderr has err  │
│  └────────┬───────────┘                          │
│           │                                       │
│  ┌────────▼───────────┐                          │
│  │ trap EXIT fires     │ → git checkout restores │
│  │                    │   original file          │
│  └────────────────────┘                          │
│                                                  │
│  BRANCH 3: Gate blocks progression               │
│  ┌────────────────────┐                          │
│  │ Assert exit ≠0      │  (not exit 0 with       │
│  │                    │   warning)               │
│  └────────────────────┘                          │
└─────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
scripts/
├── build-gate.sh             # NEW: xcodebuild gate for all 3 targets
├── test-build-gate.sh        # NEW: self-contained fixture test
├── sync-requirements.sh      # Existing (Phase 8)
└── test-sync-requirements.sh # Existing (Phase 8)

AGENTS.md                     # MODIFIED: add "Post-Wave Build Gate" section
```

### Pattern 1: Bash Script with Strict Error Handling

**What:** Every script uses `set -euo pipefail` at the top, argument validation, and explicit exit codes. This is the Phase 8 convention and applies identically to Phase 9.

**When to use:** All scripts in the `scripts/` directory. The build gate propagates xcodebuild's exit code; the test script exits non-zero on any assertion failure.

**Example (from Phase 8, adapted for Phase 9):**
```bash
#!/usr/bin/env bash
# build-gate.sh — xcodebuild verification for all 3 targets
set -euo pipefail

# Resolve project root (script may be called from any CWD under repo)
REPO_ROOT=$(git rev-parse --show-toplevel)
PROJECT="$REPO_ROOT/Watermark.xcodeproj"

echo "=== Build Gate: WatermarkApp (all targets) ==="
echo ""

# xcodebuild outputs to stdout/stderr transparently — no tee/buffering needed
xcodebuild \
  -project "$PROJECT" \
  -scheme WatermarkApp \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  build

BUILD_EXIT=$?

echo ""
if [ $BUILD_EXIT -eq 0 ]; then
  echo "BUILD GATE: PASSED"
  exit 0
else
  echo "BUILD GATE: FAILED — see errors above"
  exit $BUILD_EXIT
fi
```

**Key design decisions in this pattern:**
- `git rev-parse --show-toplevel` resolves the project root regardless of CWD — the gsd-executor may invoke the script from a subdirectory
- xcodebuild output flows transparently — the gsd-executor sees compilation errors inline
- Exit code propagates directly from xcodebuild — no custom parsing (per D-08)
- No `-derivedDataPath` — the gate uses default DerivedData. The Debug config's incremental builds are fast; stale cache is not a concern for a gate that primarily catches new syntax errors
- No `-buildImplicitDependencies` flag — this setting is scheme-level only (no CLI flag exists). The scheme already has `buildImplicitDependencies = "YES"`. [VERIFIED: scheme inspection + xcodebuild documentation search]

### Pattern 2: Self-Contained Fixture Test with Trap-Based Cleanup

**What:** The test script is a single bash file that creates its own fixtures, runs assertions, and restores state via `trap EXIT` regardless of pass/fail. Mirrors Phase 8's `test-sync-requirements.sh` exactly.

**When to use:** The `test-build-gate.sh` fixture test. Three branches: (1) clean build passes, (2) broken build caught, (3) gate blocks progression.

**Principles:**
- `trap` fires on EXIT signal — covers both normal exit and early failure from `set -e`
- `git checkout <source-file>` in the trap restores the original file atomically
- `FAILURES` counter tracks assertion results; final exit 0 only when all pass
- No temp directory needed if mutating in-place with git restoration (simpler than Phase 8's temp dir approach since xcodebuild requires the full project context)

**Example (structure):**
```bash
#!/usr/bin/env bash
set -euo pipefail

FAILURES=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$SCRIPT_DIR/build-gate.sh"

# Source file to mutate for broken-build test
# Non-critical, fast-compiling file from a completed phase
TEST_FILE="$REPO_ROOT/App/Intents/WatermarkAppShortcuts.swift"

# Trap: restore source file on ANY exit (pass or fail)
trap 'git -C "$REPO_ROOT" checkout -- "$TEST_FILE" 2>/dev/null || true' EXIT

echo "=== Build Gate Fixture Tests ==="
echo ""

# --- Branch 1: Clean build ---
echo "--- Branch 1: Clean Build ---"
if "$GATE"; then
  echo "  PASS: clean build"
else
  echo "  FAIL: clean build"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Branch 2: Broken build caught ---
echo "--- Branch 2: Broken Build Caught ---"
# Backup original
cp "$TEST_FILE" "$TEST_FILE.bak"
# Inject syntax error
echo 'let x =' >> "$TEST_FILE"
# Run gate, capture exit code and stderr
GATE_OUTPUT=$("$GATE" 2>&1) || GATE_EXIT=$?
if [ "${GATE_EXIT:-0}" -ne 0 ]; then
  if echo "$GATE_OUTPUT" | grep -qi "error"; then
    echo "  PASS: broken build caught (exit=$GATE_EXIT, stderr has error)"
  else
    echo "  FAIL: broken build exit non-zero but no error in stderr"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo "  FAIL: broken build not caught (exit 0)"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Branch 3: Gate blocks wave progression ---
echo "--- Branch 3: Gate Blocks Progression ---"
# Re-inject error (trap will restore at end)
echo 'let y =' >> "$TEST_FILE"
if ! "$GATE" > /dev/null 2>&1; then
  echo "  PASS: gate blocks wave progression (exit non-zero)"
else
  echo "  FAIL: gate should block but returned exit 0"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Final assertion ---
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "${FAILURES} TEST(S) FAILED"
  exit 1
fi
```

### Pattern 3: Wave Boundary Wiring via AGENTS.md

**What:** The gsd-executor reads AGENTS.md at session start. Phase 8 proved this mechanism works for post-plan hooks. Phase 9 adds a post-wave hook using the same pattern.

**When to use:** The AGENTS.md "Post-Wave Build Gate" section documents: (1) the command, (2) when to run it, (3) exit codes, (4) the regression test.

**Structure (matching Phase 8's pattern):**
```markdown
<!-- GSD:post-wave-start source=Phase 9 -->
## GSD Post-Wave Build Gate

After all plans in an execution wave complete (all SUMMARY.md files written) and before the next wave begins, the gsd-executor MUST run:

```
bash scripts/build-gate.sh
```

This gate replaces file-existence-only self-checks as the source of truth for "build PASSED" in the execute workflow. It runs `xcodebuild` across all 3 targets (WatermarkApp, ShareExtension, PhotoEditExtension) via the single WatermarkApp scheme.

### Exit Codes and Resolution

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | All targets compiled successfully. "BUILD GATE: PASSED" | Proceed to next wave. |
| non-zero | At least one target failed compilation. "BUILD GATE: FAILED" | **BLOCKER.** Resolve build errors before proceeding. Compilation errors appear inline in the xcodebuild output above. |

### Regression Check

Verify the gate works:

```
bash scripts/test-build-gate.sh
```

This self-contained fixture test validates three branches (clean build, broken build caught, gate blocks wave progression) and exits non-zero on failure. Run after any change to `build-gate.sh` or the Xcode project structure.
<!-- GSD:post-wave-end -->
```

### Anti-Patterns to Avoid

- **`xcodebuild 2>/dev/null`**: Suppresses compilation errors, defeating the purpose of the gate. The gsd-executor needs to see errors inline. [D-05 requires transparent output]
- **`xcodebuild ... | grep -v warning`**: Filtering warnings hides potentially useful diagnostic output. Let all output flow through.
- **`xcodebuild -quiet`**: Only prints errors but suppresses file-level progress context. The build gate doesn't need quiet mode — the gsd-executor can scan long output.
- **Retry-on-failure**: D-09 explicitly forbids retry. Build errors are deterministic. Retrying wastes time and masks real issues.
- **Per-target invocations**: Running `xcodebuild` 3 times (once per target) is slower than a single WatermarkApp scheme invocation and misses inter-target dependency errors. [D-01 locks single scheme]
- **Using `-scheme all`**: xcodebuild does NOT recognize `all` as a built-in scheme name. Must use the actual scheme name `WatermarkApp`. [VERIFIED: xcodebuild -list + documentation search]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Build dependency tracking | Custom script checking target build order | WatermarkApp scheme with `buildImplicitDependencies = "YES"` | Xcode's build system already tracks implicit + explicit dependencies correctly. Hand-rolling would miss edge cases (SPM resolution, extension embedding). |
| Exit code interpretation | grep/parse xcodebuild output for error patterns | Propagate xcodebuild exit code directly | xcodebuild exits non-zero on any failure. Parsing output adds complexity and risk of false negatives (e.g., error messages that change format across Xcode versions). D-08 locks this. |
| File restoration in tests | Manual `cp + cp` backup chain | `git checkout -- <file>` in a `trap EXIT` | git checkout is atomic, works with binary files, and restores the exact tracked state. Manual cp chains risk leaving stale backups. Phase 8's test-sync-requirements.sh established this pattern. |
| Project root resolution | Hardcoded paths or `$PWD` assumption | `git rev-parse --show-toplevel` | The gsd-executor may invoke the script from any CWD. git rev-parse always returns the correct repo root. |

**Key insight:** The build system (Xcode) and version control system (git) already solve the hard coordination problems. The build gate is a thin orchestration layer — don't reinvent what Xcode/git provide natively.

## Common Pitfalls

### Pitfall 1: `set -e` + `xcodebuild` exit code masking in pipelines

**What goes wrong:** If the script pipes xcodebuild to `tee` or another command, `set -e` (errexit) does NOT catch pipeline failures. The script could report "PASSED" despite a build failure because only the last command's exit code is checked.

**Why it happens:** POSIX shell behavior — `set -e` only checks the exit status of the last command in a pipeline unless `pipefail` is also set.

**How to avoid:** Always use `set -o pipefail` (included in `set -euo pipefail`). Additionally, avoid unnecessary pipes — xcodebuild output should flow directly to stdout/stderr without intermediate filtering. [VERIFIED: multiple bash documentation sources]

**Warning signs:** Build errors appear in output but script exits 0. The "BUILD GATE: PASSED" message prints despite visible compilation errors in the preceding output.

### Pitfall 2: `xcodebuild` returning exit 0 on scheme-not-found

**What goes wrong:** If the WatermarkApp scheme is deleted or renamed, `xcodebuild -scheme WatermarkApp` may exit non-zero (with a clear error message), but some xcodebuild versions might silently fall back to building nothing and exit 0 if no buildable targets are found.

**Why it happens:** Xcode's build system has complex fallback behavior when schemes are unresolvable. The exact exit behavior depends on Xcode version.

**How to avoid (defense in depth):** In addition to checking exit code, the script could capture and check the xcodebuild output for the string "BUILD SUCCEEDED" (which xcodebuild always prints on success). However, D-08 says to propagate exit code directly — so this is documented as a known edge case the gate test (Branch 1: clean build) implicitly verifies. If the scheme is renamed, the clean build test fails. [CITED: xcodebuild man page — scheme resolution behavior]

**Warning signs:** Gate passes instantly (no build output) after project restructuring. The `test-build-gate.sh` Branch 1 is the safeguard — it runs on the unmodified project and would catch a missing scheme immediately.

### Pitfall 3: `trap` cleanup interacting with `set -e`

**What goes wrong:** If the trap handler itself fails (e.g., `git checkout` fails because the file has uncommitted changes the user doesn't want to lose), the trap's non-zero exit could mask the original test failure or cause confusing error messages.

**Why it happens:** `trap` handlers execute in the same shell context. If `set -e` is active and the trap command fails, the script exits with the trap's exit code instead of propagating the original assertion failure.

**How to avoid:** Append `|| true` to the trap command to suppress its exit code. The trap should be: `trap 'git -C "$REPO_ROOT" checkout -- "$TEST_FILE" 2>/dev/null || true' EXIT`. This ensures file restoration is best-effort and never masks the real test result. [CITED: Phase 8's test-sync-requirements.sh trap pattern]

**Warning signs:** Test reports "PASSED" but file is not restored. Test exits with git error code instead of assertion failure count.

### Pitfall 4: Stale DerivedData causing false build failures

**What goes wrong:** A previous broken build leaves corrupted DerivedData. The gate fails on the first run post-fix because Xcode caches the stale compilation error state.

**Why it happens:** Xcode's incremental build system caches module interfaces, Swift compile units, and linker state in `~/Library/Developer/Xcode/DerivedData`. A corrupted cache can persist phantom errors even after the source file is fixed.

**How to avoid:** The gate script should NOT clean DerivedData by default (it's slow and defeats incremental builds). Instead, the AGENTS.md exit-code resolution table should include: "If xcodebuild reports errors that don't appear in Xcode IDE, run `xcodebuild clean` via the script and retry." Alternatively, the script could accept a `--clean` flag that prepends `xcodebuild clean`:
```bash
if [ "${1:-}" = "--clean" ]; then
  xcodebuild -project "$PROJECT" -scheme WatermarkApp clean > /dev/null 2>&1
fi
```
This is a planner discretion item (within the agent's discretion per CONTEXT.md). [CITED: multiple CI/CD xcodebuild best practices sources]

**Warning signs:** Gate reports errors in files that have been fixed. Re-running the gate without changes resolves the issue. Xcode IDE builds succeed but `xcodebuild` CLI fails.

### Pitfall 5: xcodebuild output buffering with `set -euo pipefail`

**What goes wrong:** When xcodebuild output is captured to a variable (e.g., `OUTPUT=$("$GATE" 2>&1)`) for assertion checking, `set -e` causes the script to exit immediately because the captured command returns non-zero.

**Why it happens:** `set -e` treats any non-zero exit in a subshell as fatal. The typical pattern `OUTPUT=$(command_that_may_fail)` will abort the script before the variable is captured.

**How to avoid:** Use `||` to capture the exit code separately:
```bash
GATE_OUTPUT=$("$GATE" 2>&1) || GATE_EXIT=$?
```
This tells bash: "run the command, capture output, and if it fails, capture the exit code but don't abort." [CITED: bash manual — errexit + command substitution behavior]

**Warning signs:** Test script aborts during Branch 2 without reaching the assertion. Error message references line with command substitution `$(...)`.

## Code Examples

Verified patterns from official sources and Phase 8 reference implementation:

### xcodebuild Exit Code Semantics

```bash
# Source: xcodebuild man page (verified via websearch + system observation)
# xcodebuild exits 0 on success, non-zero on failure.
# Common non-zero codes: 65 (data format/input error), 70 (software error),
# 64 (command-line usage), 66 (no input), 74 (IO error).
# Compilation errors (syntax, type mismatches) → non-zero exit.
#
# The gate does NOT differentiate between exit codes — any non-zero is a BLOCKER.
```

### git checkout for Atomic File Restoration

```bash
# Source: git documentation + Phase 8 trap pattern
# git checkout -- <file> restores the file to its HEAD state.
# This is atomic — it succeeds completely or fails completely.
# Safer than cp-based backup chains which can leave stale backups.
trap 'git -C "$REPO_ROOT" checkout -- "$TEST_FILE" 2>/dev/null || true' EXIT
```

### Wave-Boundary Check Pattern (for gsd-executor)

```bash
# Source: AGENTS.md pattern from Phase 8, adapted for Phase 9
# The gsd-executor runs this after all plans in a wave complete:
bash scripts/build-gate.sh
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "Build gate FAILED — resolve compilation errors before next wave"
  exit $EXIT_CODE  # Block wave progression
fi
# Proceed to next wave
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| File-existence self-checks ("PASSED" = files exist) | xcodebuild compilation verification | Phase 9 (v1.1) | Replaces untrustworthy self-checks that allowed pre-existing build errors to compound undetected across Phases 5–6 in v1.0 |
| Manual milestone audit builds | Automated wave-level gate | Phase 9 (v1.1) | Surfaces build errors at source (the wave that introduced them), not at retrospective milestone audit |
| `-sdk iphonesimulator` for build verification | `-destination 'generic/platform=iOS'` | Established pattern | Generic device builds without code signing, catches device-only code paths |
| `-scheme all` (invalid) or per-target builds | Single WatermarkApp scheme with implicit deps | Established pattern | Single invocation covers all targets; no need for 3 separate xcodebuild calls |

**Deprecated/outdated:**
- `xcodebuild -sdk iphonesimulator` for build verification — simulator requires booted sim, misses device-only code paths. Use `-destination 'generic/platform=iOS'`.
- File-existence self-checks as build pass/fail signal — these reported "PASSED" in v1.0 despite real compilation errors. The build gate replaces this mechanism entirely (D-14).
- `xcodebuild -scheme all` — this is not a valid xcodebuild invocation. "all" is not a recognized scheme name. Use the actual scheme name.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The WatermarkApp scheme's `buildImplicitDependencies = "YES"` covers all 3 app targets | Standard Stack, Architecture Patterns | Medium: If a future scheme change removes implicit dependency resolution, the gate would only build WatermarkApp. The fixture test (Branch 1: clean build) would catch this because the full project would fail to compile if extensions are not built (Copy Files build phase fails). |
| A2 | The project will always have a single shared scheme called `WatermarkApp` | Standard Stack | Medium: If the scheme is renamed, the gate command breaks. The fixture test Branch 1 catches this immediately. The AGENTS.md documentation can be updated alongside any scheme rename. |
| A3 | `$PATH` includes xcodebuild (via `xcode-select -p`) | Environment Availability | Low: All macOS machines with Xcode installed have xcodebuild on PATH. If missing, the script fails immediately with "command not found" — a clear error. |
| A4 | No uncommitted changes to the test source file when `test-build-gate.sh` runs | Common Pitfalls | Low: `git checkout` would fail to restore if the file has staged changes. The trap uses `|| true` to prevent this from masking test results, but the file would remain mutated. Documented in Pitfall 3. |

## Open Questions

1. **Should `build-gate.sh` support a `--clean` flag for stale DerivedData recovery?**
   - What we know: Stale DerivedData can cause phantom build failures (Pitfall 4). A `--clean` flag would prepend `xcodebuild clean`.
   - What's unclear: Whether the added complexity (flag parsing, clean time overhead) is worth it for a gate that primarily catches new syntax errors (not cached corruption).
   - Recommendation: Include as a planner discretion item. If included, document in AGENTS.md. If excluded, document the manual `xcodebuild clean` workaround in the exit-code resolution table.

2. **Which Swift source file for the test fixture mutation?**
   - What we know: Must be non-critical, fast-compiling, recently created, and unlikely to conflict with ongoing Phase 10-11 development. Ideal candidate: a simple struct file in a leaf package or app target.
   - What's unclear: The planner has discretion. Current best candidate is `App/Intents/WatermarkAppShortcuts.swift` — 25 lines, part of WatermarkApp target, created in Phase 7 (commit `6e4957d`), no Phase 10-11 plans modify it.
   - Recommendation: Planner selects `App/Intents/WatermarkAppShortcuts.swift`. If Phase 10-11 plans touch this file, fall back to `App/Intents/WatermarkPhotoIntent.swift`.

3. **In-place mutation vs. temp directory copy for the fixture test?**
   - What we know: Phase 8's test used a temp dir with inline fixture files. For xcodebuild, a temp dir copy would require copying the entire project (SPM packages, xcodeproj, source files) — significantly heavier than in-place mutation with git restoration.
   - What's unclear: Whether in-place mutation could interfere with a concurrently running gsd-executor (multiple waves are never concurrent per the sequential wave model).
   - Recommendation: Use in-place mutation with `git checkout` restoration via `trap`. Simpler, faster, and perfectly safe since waves are sequential. Phase 8's temp dir approach was necessary because it needed to create synthetic .planning/REQUIREMENTS.md files; Phase 9 mutates a real source file in a real project.

## Security Domain

> `security_enforcement` is not explicitly `false` in `.planning/config.json` — defaulting to enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | No | Not applicable — build gate is a developer tooling script |
| V3 Session Management | No | Not applicable |
| V4 Access Control | No | Not applicable |
| V5 Input Validation | Yes (minimal) | The build gate script has no user-facing input. The test script validates arguments (e.g., no arbitrary command injection via `$1`). `set -u` catches unset variable references. |
| V6 Cryptography | No | Not applicable |

### Known Threat Patterns for Bash/xcodebuild Tooling

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Command injection via `$1` or `$@` in scripts | Tampering | `set -u` catches unset variables. Build gate accepts no arguments (no injection surface). Test script is run by developers only. |
| Incomplete file restoration leaving mutated source | Tampering | `trap EXIT` with `git checkout` ensures restoration on both pass and failure paths. `|| true` on trap prevents cleanup failures from masking errors. |
| xcodebuild executing build-phase scripts | Elevation of Privilege | Build phases in the Xcode project are trusted (committed to repo). The gate does not add new build phases. |
| Sensitive data in xcodebuild output | Information Disclosure | xcodebuild outputs build settings and compiler messages — no secrets. The gate does not log build output to files (only stdout/stderr, which the gsd-executor already sees). |
| Race condition: file mutated while test runs | Denial of Service | In-place mutation could theoretically conflict if another script/process modifies the same file. Waves are sequential — no concurrent execution. |

**Assessment:** The build gate has minimal security surface. It runs locally, makes no network calls, handles no user input, and processes no secrets. The primary risk is incomplete file restoration in the fixture test — mitigated by `trap EXIT` with `|| true` on cleanup.

## Sources

### Primary (HIGH confidence)

- **Xcode 26.2 system inspection** — `xcodebuild -version` (Xcode 26.2, Build 17C52), `xcodebuild -project Watermark.xcodeproj -list` (3 targets: WatermarkApp, ShareExtension, PhotoEditExtension; 4 schemes), `xcodebuild -showBuildSettings` (build settings verified)
- **WatermarkApp.xcscheme** — `buildImplicitDependencies = "YES"`, `parallelizeBuildables = "YES"`, verified at `/Users/osama/Projects/Watermark/Watermark.xcodeproj/xcshareddata/xcschemes/WatermarkApp.xcscheme`
- **Phase 8 reference scripts** — `scripts/sync-requirements.sh` (57 lines) and `scripts/test-sync-requirements.sh` (163 lines) — established bash patterns: `set -euo pipefail`, argument validation, `trap EXIT`, inline fixture heredocs, three-branch tests, final assertion
- **Phase 8 CONTEXT.md** — D-01 through D-11 establish the pattern for repo-local bash scripts, AGENTS.md documentation, self-contained fixture tests, and exit-code semantics

### Secondary (MEDIUM confidence)

- **xcodebuild man page / Apple documentation** — exit codes: 0 = success, non-zero = failure (common: 65, 70, 64, 66, 74). Verified via websearch across multiple sources (leancrew.com, stackoverflow.com, circleci.com, dev.to).
- **xcodebuild scheme resolution** — `buildImplicitDependencies` is a scheme-level setting only. No CLI flag exists to override it. Verified via websearch (apple.com, kodeco.com, stackoverflow.com). Scheme already has the correct setting.
- **xcodebuild `-destination 'generic/platform=iOS'`** — builds for generic iOS device without requiring code signing or a connected device. Verified via websearch across multiple sources (mokacoding.com, flowdeck.studio, stackoverflow.com).
- **Bash `set -euo pipefail`** — `pipefail` requires bash 3.0+ (macOS bash 3.2 supports it). `set -u` catches unset variables. Verified via system testing: `bash -c 'set -o pipefail && echo OK'` succeeds.
- **`trap EXIT` behavior with `set -e`** — trap fires on script exit regardless of cause (normal exit, error, signal). Verified via system testing: `bash -c 'set -e; d=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; echo "$d"'` succeeds and cleans up.

### Tertiary (LOW confidence)

- **DerivedData staleness patterns** — CI/CD best practice is to use project-specific `-derivedDataPath` or run `xcodebuild clean` before builds. For the build gate, stale cache is unlikely to cause false positives for new syntax errors. [WebSearch only — not verified against this project's specific Xcode version behavior]
- **Bash 3.2 feature limitations** — `readarray`/`mapfile` not available (bash 4.0+), `shopt -s inherit_errexit` not available (bash 4.4+). These features are not needed for build-gate.sh. [WebSearch + training data — not exhaustively tested on this system]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All tools verified present (xcodebuild 26.2, git 2.50.1, bash 3.2). Scheme inspected. Build settings verified.
- Architecture: HIGH — Phase 8 provides a production-verified reference pattern. All architectural decisions are locked in CONTEXT.md.
- Pitfalls: MEDIUM — Identified from websearch (multiple sources agree on xcodebuild exit codes, scheme resolution). Pitfall 4 (DerivedData) is lower confidence because the specific Xcode 26.2 caching behavior wasn't exhaustively tested.
- Security: HIGH — Minimal surface. No secrets, no network, no user input.

**Research date:** 2026-06-18
**Valid until:** 2026-12-18 (6 months — stable tooling; xcodebuild CLI is very stable across Xcode versions)
