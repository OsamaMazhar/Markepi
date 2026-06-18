# Phase 9: Wave-Level Build Gate - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers a build gate that runs `xcodebuild` across all 3 targets (WatermarkApp, ShareExtension, PhotoEditExtension) after each execution wave, replacing the untrustworthy file-existence-only self-checks that allowed pre-existing build errors to compound undetected across Phases 5–6 in v1.0.

**Deliverables:**
1. **`scripts/build-gate.sh`** — A bash script that invokes `xcodebuild -scheme WatermarkApp` (which builds all 3 targets through the dependency chain verified by dry-run: WatermarkApp → implicit deps on ShareExtension + PhotoEditExtension → explicit dep on WatermarkCore). Exits non-zero on any build failure.
2. **`scripts/test-build-gate.sh`** — A self-contained fixture test that temporarily injects a syntax error into a Swift source file, runs `build-gate.sh`, asserts non-zero exit + stderr contains the error, restores the file. Proves success criteria #3 (broken-build scenario caught by gate).
3. **AGENTS.md update** — Adds a "Post-Wave Build Gate" section documenting that the gsd-executor MUST run `bash scripts/build-gate.sh` after each execution wave completes and before the next wave begins.

**Out of scope:** Running tests (test phase is separate; 227 tests include 14 known SPM CLI orientation failures). Running the build gate as a git hook or pre-commit hook. Editing GSD workflow files in `~/.config/get-shit-done/` — the gate is repo-local, wired via AGENTS.md documentation (same pattern as Phase 8's sync-requirements post-plan step).
</domain>

<decisions>
## Implementation Decisions

### Build Invocation
- **D-01:** Build via **single WatermarkApp scheme**, not per-target invocations. Dry-run confirmed the WatermarkApp scheme's dependency graph covers all 5 targets: WatermarkApp → implicit deps on ShareExtension + PhotoEditExtension (via Copy Files build phase) → explicit dep on WatermarkCore. `buildImplicitDependencies = "YES"` in the scheme ensures extensions are compiled.
  ```
  xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination 'generic/platform=iOS' build
  ```
- **D-02:** Use **`-destination 'generic/platform=iOS'`**, not `-sdk iphonesimulator`. The generic device destination builds for iOS device without requiring code signing or a provisioning profile, while still catching all compilation errors. Simulator destination requires a booted simulator and would skip device-only code paths.
- **D-03:** Use **Debug** configuration, not Release. Debug catches the identical compilation errors (syntax, type mismatches, enum pattern mismatches, stale pbxproj refs — precisely the failure mode from the retrospective) but compiles ~2–3x faster because it skips optimization passes. The gate's goal is compilation correctness, not optimization verification.

### Script Design
- **D-04:** Script lives at **`scripts/build-gate.sh`** at repo root — follows the Phase 8 convention (`scripts/sync-requirements.sh`). Pure bash, zero dependencies beyond `xcodebuild` (pre-installed on macOS). `set -euo pipefail` for strict error handling.
- **D-05:** The script outputs a **pass/fail summary** to stdout for programmatic consumption (e.g., `BUILD GATE: PASSED` or `BUILD GATE: FAILED — see errors above`), while xcodebuild's natural stdout/stderr flows through transparently so the gsd-executor sees compilation errors inline.

### Wave-Boundary Wiring
- **D-06:** Documented in **AGENTS.md** as a **Post-Wave Build Gate** section, placed alongside the existing Phase 8 post-plan step. The gsd-executor reads AGENTS.md at session start. The step triggers after each execution wave completes (all plans in that wave have SUMMARY.md written) and before the next wave begins. This catches build errors before they compound across waves — exactly what the retrospective flagged.
- **D-07:** The AGENTS.md entry documents: (1) the command (`bash scripts/build-gate.sh`), (2) when to run it (after each execution wave, before the next wave), (3) exit codes (0 = PASSED, non-zero = BLOCKER — resolve build errors before proceeding), and (4) the regression test (`bash scripts/test-build-gate.sh`).

### Exit Code Semantics
- **D-08:** Exit non-zero on **any xcodebuild failure**. The script propagates xcodebuild's exit code directly. No custom error parsing needed — xcodebuild natively exits non-zero on compilation failure and writes errors to stderr with file + line specifics. The script uses `set -euo pipefail` so any pipeline failure stops execution.
- **D-09:** The script does NOT aggregate or retry failed builds. One failure = gate fails. Rationale: build errors are deterministic; re-running doesn't fix them. The gsd-executor sees the failure inline and triages.

### Verification Test
- **D-10:** Self-contained fixture test at **`scripts/test-build-gate.sh`**, following the Phase 8 pattern (`scripts/test-sync-requirements.sh`). Single bash file with inline fixtures, trap-based cleanup, three assertion branches:
  1. **Clean build passes** — runs `build-gate.sh` on the unmodified project, asserts exit 0 + PASSED summary.
  2. **Broken build caught** — temporarily injects a syntax error (e.g., `let x =` with no value) into a non-critical Swift source file, runs `build-gate.sh`, asserts non-zero exit + FAILED summary + stderr contains the injected error text. Restores the file via trap.
  3. **Gate blocks wave progression** — asserts the script exits non-zero (not exit 0 with a warning) — proving success criteria #3 that a broken build stops the wave.
- **D-11:** Test isolation: backs up the original source file before mutation, restores via `trap` on both pass and failure paths. Uses `git checkout <source-file>` in the trap for clean restoration. The test marks itself as a test so the gsd-executor knows not to proceed to the next wave if the test fails.
- **D-12:** The test exits non-zero on any assertion failure, following the Phase 8 test's final assertion pattern. Exit 0 only when all branches pass.

### Scope Boundary
- **D-13:** Build-only gate — **no test execution**. The retrospective specifically identified build errors (compilation failures) going undetected, not test failures. Running 227 tests would slow the gate and introduce noise from 14 known SPM CLI orientation failures. Tests remain a separate concern handled by the testing workflow.
- **D-14:** The gate replaces, not supplements, file-existence self-checks. The AGENTS.md entry explicitly states: "This replaces file-existence-only self-checks as the source of truth for 'build PASSED' in the execute workflow" (matching success criteria #4).

### the agent's Discretion
- The exact bash implementation of `build-gate.sh` (whether to use a temp log file, how to format the summary line, exact `trap` configuration) is left to the planner/researcher. Constraints: must exit non-zero on xcodebuild failure; must pipe xcodebuild output transparently; must run from repo root and find `Watermark.xcodeproj` relative to CWD.
- Which Swift source file to mutate in `test-build-gate.sh` (the fixture test) is left to the planner — choose a non-critical file that's fast to compile and unlikely to conflict with ongoing development. The planner should pick a recently-touched source file from a completed phase for readability.
- Whether `test-build-gate.sh` uses a temp dir with a copy of the project or mutates in place (with git restoration) is left to the planner. Phase 8's test used a temp dir approach — either is acceptable as long as the original state is always restored.
- The exact wording and placement of the AGENTS.md post-wave step is left to the planner. Constraint: must be discoverable by the gsd-executor when it reads AGENTS.md at session start.

### Folded Todos
None — no pending todos matched Phase 9's scope.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope + success criteria
- `.planning/ROADMAP.md` §"Phase 9: Wave-Level Build Gate" — phase goal, depends-on (nothing technically), requirements (BUILD-01), and the 4 success criteria (verbatim source of truth for what "done" means).
- `.planning/REQUIREMENTS.md` §"Build Gate (BUILD)" — defines BUILD-01 and the v1.1 traceability table.
- `.planning/PROJECT.md` §"Current Milestone" and §"Key Decisions" — v1.1 tech-debt framing; confirms the retrospective root cause ("executor self-checks reported 'PASSED' without an actual `xcodebuild` invocation").

### Retrospective root cause
- `.planning/RETROSPECTIVE.md` lines 30, 44–45 — the exact failure mode: "Pre-existing build errors accumulated across phases (enum opacity/isVisible pattern mismatches in 2 extension ViewModels, stale Xcode project file references, struct scoping bug) — only surfaced during Phase 7 post-merge gate. Earlier phases' self-checks reported 'PASSED' despite broken builds." Key Lesson #4: "Executor self-checks claiming 'PASSED' are not trustworthy without an actual build."

### Existing patterns to follow
- `.planning/phases/08-traceability-reconciliation-recurrence-guard/08-CONTEXT.md` §"Implementation Decisions" — Phase 8's D-01 through D-11 establish the pattern for repo-local bash scripts, AGENTS.md documentation, self-contained fixture tests, and exit-code semantics that Phase 9 extends.
- `scripts/sync-requirements.sh` — reference implementation: argument validation, `set -euo pipefail`, `gsd-sdk` delegation, exit-code contract. Phase 9's `build-gate.sh` follows the same bash conventions (but delegates to `xcodebuild`, not `gsd-sdk`).
- `scripts/test-sync-requirements.sh` — reference implementation: self-contained fixture test with inline heredocs, temp dir, trap-based cleanup, three assertion branches, final exit 0/1. Phase 9's `test-build-gate.sh` follows the same pattern.

### GSD workflow integration
- `.planning/config.json` — `parallelization: true` (waves can have multiple parallel plans), `mode: yolo`, `workflow.auto_advance: true`. The build gate runs at wave boundaries where parallel plans have all completed.
- `AGENTS.md` §"GSD Post-Plan Step" (lines 160–197) — Phase 8's documented post-plan step pattern. The build gate adds a companion "Post-Wave Build Gate" section using the same pattern.

### Xcode project structure
- `Watermark.xcodeproj/xcshareddata/xcschemes/WatermarkApp.xcscheme` — the single shared scheme with `buildImplicitDependencies = "YES"`. Dry-run confirmed the dependency graph: WatermarkApp → ShareExtension + PhotoEditExtension (implicit, via Copy Files) → WatermarkCore (explicit). All 5 targets compile under this scheme.
- `xcodebuild -list` output — confirms 3 app targets (WatermarkApp, ShareExtension, PhotoEditExtension) + 1 package target (WatermarkCore) + 4 schemes (one per target + SPM auto-scheme).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`scripts/` directory** — already exists from Phase 8 with `sync-requirements.sh` and `test-sync-requirements.sh`. Phase 9 adds `build-gate.sh` and `test-build-gate.sh` alongside them.
- **Phase 8 conventions** — `set -euo pipefail`, argument validation, trap-based cleanup, self-contained fixture tests, AGENTS.md documentation pattern. All directly reusable.
- **`WatermarkApp.xcscheme`** — already has `buildImplicitDependencies = "YES"`, already covers all 3 targets. No scheme changes needed.

### Established Patterns
- **Repro-local bash scripts with no dependencies** — Phase 8 established `scripts/` as the home for repo tooling. Scripts are pure bash + pre-installed macOS tools (xcodebuild, git, jq). No npm, no Makefile, no SPM dependencies for tooling.
- **AGENTS.md as discoverable integration point** — The gsd-executor reads AGENTS.md at session start. Phase 8 proved this works for post-plan hooks. Phase 9 adds a post-wave hook using the same mechanism.
- **Self-contained fixture tests with trap-based cleanup** — Phase 8's `test-sync-requirements.sh` sets the blueprint: temp dir + inline fixtures + trap cleanup + three branches + final assertion. Phase 9 adapts this for build verification.
- **Exit-code contracts: zero = success, non-zero = blocker** — Both Phase 8's sync-requirements and Phase 9's build-gate follow the same semantic: exit 0 means proceed, exit non-zero means stop and resolve before continuing. The gsd-executor treats non-zero as a plan/wave completion blocker.

### Integration Points
- **AGENTS.md** — where the post-wave build gate step is documented for the gsd-executor. Placed alongside the existing Phase 8 post-plan step so the executor sees both triggers when reading AGENTS.md at session start.
- **Watermark.xcodeproj** — the build target. The script resolves the project path relative to repo root (`$(git rev-parse --show-toplevel)/Watermark.xcodeproj`). The WatermarkApp scheme is the single entry point for all 3 targets.
- **gsd-executor wave completion flow** — the build gate script slots in after all plans in a wave complete (all SUMMARY.md files written) and before the next wave begins. The executor should check exit code: 0 = next wave proceeds, non-zero = halt and report build errors.

### Creative Options
- **Per-target parallel builds:** xcodebuild already parallelizes within a scheme (`parallelizeBuildables = "YES"`), so a single WatermarkApp invocation fully utilizes available cores.
- **Future extension:** If a new target is added to the project and made a dependency of WatermarkApp, the build gate picks it up automatically — no script changes needed.
- **CI integration:** The script works identically in CI (GitHub Actions, Xcode Cloud) since it uses only `xcodebuild` + `bash`, both pre-installed on macOS runners. The `-destination 'generic/platform=iOS'` flag works without signing in both local and CI contexts.

</code_context>

<specifics>
## Specific Ideas

- Script names are locked: `scripts/build-gate.sh` (the gate) and `scripts/test-build-gate.sh` (the test). Both live at repo root under `scripts/`.
- The build command is locked: `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination 'generic/platform=iOS' build`. Verified via dry-run that this compiles all 5 targets.
- The gate is **build-only** (no `test` action), per D-13.
- The gate's exit-code contract: exit 0 = all targets compiled, exit non-zero = at least one target failed.
- The fixture test must verify: (1) clean build passes, (2) injected syntax error is caught with non-zero exit + stderr, (3) original file is restored on both pass and failure paths.
- The AGENTS.md section title is locked: "Post-Wave Build Gate" — matching Phase 8's naming convention ("GSD Post-Plan Step").
- The gate runs at **wave boundaries** (after all plans in a wave complete), not per-plan. This is critical for waves with parallel plans — the build gate runs once after the full wave, not after each individual plan.
- The build gate **replaces** file-existence self-checks as the source of truth for build pass/fail — it does not supplement them. The AGENTS.md entry must explicitly state this (per success criteria #4).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. The following were already deferred at v1.1 milestone definition:
- **PHRO-01** (per-phase VERIFICATION.md template) — deferred to future process-hardening milestone.
- **PHRO-02** (worktree-safety fix for task-tool branching) — GSD tooling concern, deferred.

---

*Phase: 9-Wave-Level Build Gate*
*Context gathered: 2026-06-18*
