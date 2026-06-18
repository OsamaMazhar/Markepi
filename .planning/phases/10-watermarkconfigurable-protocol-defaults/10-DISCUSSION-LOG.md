# Phase 10: WatermarkConfigurable Protocol Defaults - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 10-WatermarkConfigurable Protocol Defaults
**Areas discussed:** Error handling strategy, Computed property scope, addSignatureLayer default, Mutating self pattern, WatermarkLayer helpers, Scope boundary, Verification strategy

---

## Error Handling Strategy (addLogoLayer)

| Option | Description | Selected |
|--------|-------------|----------|
| Add error fields to protocol | Add `errorMessage: String?` and `showError: Bool` to `WatermarkConfigurable` so the default impl can set them directly | ✓ |
| @discardableResult returning Bool | Keep protocol clean; each ViewModel wraps with its own error handling | |
| Throw errors | Use `throws` in addLogoLayer signature; ViewModels handle with do/catch | |

**Mode:** --auto — recommended option auto-selected.
**Notes:** All 3 conformers already have `errorMessage` and `showError` as `@Published`/observable properties. Adding them to the protocol collapses the most code without changing call-site behavior. LogoPickerView's error alert binding already reads from these ViewModel properties.

---

## Computed Property Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Include computed properties | Also collapse `whiteFrameEnabled`, `outputFormat`, `outputQuality` in the protocol extension | ✓ |
| Stick to 5 methods only | Only collapse the 5 methods listed in success criteria #1 | |

**Mode:** --auto — recommended option auto-selected.
**Notes:** All 3 computed properties are identical 3-5 line wrappers around `config`. Collapsing them reduces duplication further with zero risk. They already have protocol requirements declared.

---

## addSignatureLayer Default

| Option | Description | Selected |
|--------|-------------|----------|
| Add default no-op | Protocol extension provides empty body; extensions don't need stubs | ✓ |
| Keep per-ViewModel stubs | Each extension keeps its own empty implementation | |

**Mode:** --auto — recommended option auto-selected.
**Notes:** ShareExtensionViewModel and PhotosExtensionViewModel both have `func addSignatureLayer(...) { }` empty stubs. A default no-op removes these 2 boilerplate lines. WatermarkViewModel overrides with the real PencilKit implementation — no behavior change.

---

## Mutating Self Pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Direct mutation on self.config | Protocol extension mutates `self.config` and `self.activeLayerIndex` directly via the protocol's get/set requirements | ✓ |
| @discardableResult returning config | Methods return new WatermarkConfiguration; ViewModels assign the result | |

**Mode:** --auto — recommended option auto-selected.
**Notes:** The `AnyObject` class constraint guarantees reference semantics — no copy-on-write concerns. Direct mutation matches the existing code's style exactly, minimizing behavioral change. The protocol already declares `config` and `activeLayerIndex` as `{ get set }`.

---

## WatermarkLayer Helpers

| Option | Description | Selected |
|--------|-------------|----------|
| Keep switch in protocol extension | 3-case switch for text/image/signature stays in the extension as-is | ✓ |
| Add with(position:)/with(scale:) to WatermarkLayer | Add helper methods to the data model; extension calls those | |

**Mode:** --auto — recommended option auto-selected.
**Notes:** The 3-case switch is ~6 lines. Adding helpers to the data model increases API surface without reducing total code. The extension is the single point of deduplication — not a data model enhancement.

---

## Scope Boundary

| Method | Default? | Rationale |
|--------|----------|-----------|
| addLogoLayer | Yes (D-01) | Identical across all 3 |
| removeLayer | Yes | Identical across all 3 |
| updateLayerPosition | Yes | Identical across all 3 |
| updateLayerScale | Yes | Identical across all 3 |
| toggleWhiteFrame | Yes | Identical across all 3 |
| addSignatureLayer | Yes (no-op, D-03) | Extensions have empty stubs; WatermarkVM overrides |
| whiteFrameEnabled | Yes (D-02) | Identical across all 3 |
| outputFormat | Yes (D-02) | Identical across all 3 |
| outputQuality | Yes (D-02) | Identical across all 3 |
| renderAndPrepareShare | No (D-06) | Different behavior per target |
| cancelVideoExport | No (D-06) | Different cancelation targets |
| presentShareSheet | No (D-06) | Different presentation contexts |

---

## Verification Strategy

| Method | Details |
|--------|---------|
| Existing tests (227) | Must all pass — refactor changes zero behavior |
| Build gate | `bash scripts/build-gate.sh` must pass for all 3 targets |
| grep audit | Confirm zero duplicated implementations of the 5 methods in any ViewModel |

**Mode:** --auto — recommended option auto-selected.
**Notes:** No new automated tests required. The refactor is purely structural — moving code from 3 locations to 1. Existing tests exercise the same code paths. Build gate + grep provide equivalent verification.

---

## the agent's Discretion

- File placement for protocol extension (same file vs. new file)
- MARK organization within the extension
- Exact ordering of protocol requirements and error properties
- Whether `outputFormat`/`outputQuality` protocol requirements need adjustment for default computed property implementations

## Deferred Ideas

None — all deferred items already captured at milestone level in `.planning/REQUIREMENTS.md` §"Out of Scope".

---

*Discussion log generated: 2026-06-18*
*Mode: --auto (all areas auto-selected, recommended options auto-picked)*
