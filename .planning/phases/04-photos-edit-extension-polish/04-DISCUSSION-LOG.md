# Phase 4: Photos Edit Extension & Polish - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 4-Photos Edit Extension & Polish
**Areas discussed:** Photos Extension UI flow, PHAdjustmentData strategy, Photo output format, Video handling, QA validation scope

---

## Photos Extension UI Flow

| Option | Description | Selected |
|--------|-------------|----------|
| Full parity with main app | Same ControlsView, configure→render→done flow, hosted via UIHostingController | ✓ |
| Simplified modal | Minimal controls, auto-apply watermark with preset config | |

**User's choice:** [auto] Full parity — host same ControlsView via UIHostingController, same Configure → Preview → Done flow. Follows ShareExtension pattern (Phase 3 D-05).
**Notes:** Done button commits edit (PHContentEditingOutput) instead of Share. Pattern already proven in ShareExtension.

---

## PHAdjustmentData Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| WatermarkConfiguration JSON + format version | Serialize config as JSON with "formatVersion": "1.0" key | ✓ |
| Binary serialization | Custom binary format for size efficiency | |
| Minimal token | Just a "1" indicating an edit occurred, no re-editing support | |

**User's choice:** [auto] JSON serialization matching App Group sync format. Enables undo to original and re-editing with previous config loaded.
**Notes:** Format version key enables forward compatibility.

---

## Photo Output Format in Extension

| Option | Description | Selected |
|--------|-------------|----------|
| Preserve source format | Match input (HEIC→HEIC, JPEG→JPEG) via FormatDetector | ✓ |
| Force HEIC always | Always output HEIC for Photos extension | |
| Match PHContentEditingInput | Let Photos framework decide, write what it expects | |

**User's choice:** [auto] Preserve source format. Consistent with Phase 1 D-09/D-10. Engine's FormatDetector handles format detection.
**Notes:** PHContentEditingInput may provide HEIC for JPEG sources (Photos re-wraps). Use the format the user originally imported.

---

## Video Handling in Photos Extension

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse VideoProcessor | Same AVFoundation pipeline with HDR + audio preservation | ✓ |
| Simplified video path | Basic composition without HDR preservation for extension | |
| Photo-only in extension | Extension handles photos only, videos deferred | |

**User's choice:** [auto] Full VideoProcessor reuse. Same HDR preservation + audio passthrough + post-export validation as Phase 3.
**Notes:** PHContentEditingInput.audiovisualAsset provides AVAsset URL directly.

---

## QA Validation Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Automated + manual device | Unit tests in WatermarkCoreTests + physical iPhone QA checklist | ✓ |
| Automated only | Unit tests only, no device testing | |
| Manual only | Device testing only, no automated validation | |

**User's choice:** [auto] Combined approach: automated tests for pipeline correctness + manual QA on physical iPhone (A13+, iOS 18).
**Notes:** QA checklist validates HDR gain map preservation (exiftool), metadata integrity, all 8 EXIF orientations, memory under 500MB for 4K video, PHAdjustmentData undo/redo, Photos edit history entry.

---

## Claude's Discretion

- PHContentEditingController lifecycle implementation (startContentEditing, canHandle, finishContentEditing, cancelContentEditing)
- PHContentEditingOutput file format and extension selection
- Memory management for large video assets in extension sandbox
- Photos Extension Info.plist configuration
- Preview (placeholderImage) generation
- Xcode project target configuration (new Photo Editing Extension target + share extension target integration)
- Extension entitlements (App Groups)

## Deferred Ideas

None — discussion stayed within phase scope.
