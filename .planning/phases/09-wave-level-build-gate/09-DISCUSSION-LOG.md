# Phase 9: Wave-Level Build Gate - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 09-wave-level-build-gate
**Mode:** --auto (all decisions auto-selected)
**Areas discussed:** Build invocation strategy, Script design, Wave-boundary wiring, Exit code semantics, Verification test

---

## Build Invocation Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Single WatermarkApp scheme | One xcodebuild invocation, builds all 3 targets through dependency chain | ✓ |
| Per-target invocations | Three separate xcodebuild calls, granular failure reporting | |

**[auto] Selected:** Build via single WatermarkApp scheme (recommended — simpler, one invocation, dependency chain covers all targets per dry-run verification).

**Notes:** Dry-run confirmed WatermarkApp → implicit deps on ShareExtension + PhotoEditExtension → explicit dep on WatermarkCore. All 5 targets compile.

---

## Script Design

| Option | Description | Selected |
|--------|-------------|----------|
| `scripts/build-gate.sh` | Bash script at repo root, follows Phase 8 convention | ✓ |
| Different name/location | Alternative naming or placement | |

**[auto] Selected:** `scripts/build-gate.sh` at repo root (recommended — matches Phase 8's `scripts/sync-requirements.sh` convention).

**Notes:** Pure bash, zero dependencies beyond xcodebuild. `set -euo pipefail` for strict error handling. Summary line to stdout, xcodebuild output flows transparently.

---

## Build Configuration

| Option | Description | Selected |
|--------|-------------|----------|
| Debug | Fastest compilation, catches same compilation errors as Release | ✓ |
| Release | Includes optimization passes, catches optimization-specific issues | |

**[auto] Selected:** Debug configuration (recommended — ~2–3x faster, catches identical compilation errors; the gate's goal is compilation correctness, not optimization verification).

---

## Wave-Boundary Wiring

| Option | Description | Selected |
|--------|-------------|----------|
| AGENTS.md documentation | Documented post-wave step the gsd-executor reads at session start | ✓ |
| GSD workflow file edit | Edit shared GSD workflow files in ~/.config/ | |

**[auto] Selected:** AGENTS.md documentation pattern (recommended — same pattern as Phase 8's sync-requirements post-plan step; repo-local, no shared workflow file editing).

**Notes:** Gate runs after each execution wave completes (all parallel plans in that wave done) and before the next wave begins. Catches build errors before they compound across waves.

---

## Exit Code Semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Aggregate failure | Exit non-zero on any xcodebuild failure, stderr shows which target | ✓ |
| Per-target parsing | Custom error parsing with per-target status | |

**[auto] Selected:** Aggregate failure (recommended — simplest correct contract; xcodebuild already exits non-zero on compilation failure and writes errors to stderr with file + line specifics).

---

## Verification Test

| Option | Description | Selected |
|--------|-------------|----------|
| Self-contained fixture test | Inline fixtures, trap-based cleanup, three branches (pass, fail, restore) | ✓ |
| Manual dry-run only | Document a manual verification procedure | |

**[auto] Selected:** Self-contained fixture test at `scripts/test-build-gate.sh` (recommended — proves success criteria #3; follows Phase 8's test pattern).

**Notes:** Three assertion branches: clean build passes, broken build caught with non-zero exit + stderr, original file always restored via trap.

---

## the agent's Discretion

- Exact bash implementation details (temp log file vs streaming, summary format, trap configuration)
- Which Swift source file to mutate in the fixture test
- Whether to use temp dir or in-place mutation for the test
- Exact wording and placement of the AGENTS.md post-wave step

## Deferred Ideas

None — discussion stayed within phase scope. PHRO-01 and PHRO-02 were already deferred at v1.1 milestone definition.
