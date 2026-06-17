# Phase 3: Video Processing & Share Extension - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-17
**Phase:** 3-Video Processing & Share Extension
**Areas discussed:** Video compositing strategy, Share extension UX depth, Video HDR preservation approach, Photo handling in share extension

---

## Video Compositing Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| CALayer overlay | AVVideoComposition + AVVideoCompositionCoreAnimationTool. Simpler, HDR via HEVC preset | ✓ |
| CIFilter per-frame | AVAssetReader/Writer, reuses WatermarkCore compositing per frame | |
| You decide | Planner determines approach | |

**User's choice:** CALayer overlay (Recommended)
**Notes:** Chose the simpler, proven pattern. CIFilter per-frame rejected as overly complex for the requirements.

### Layer Parity

| Option | Description | Selected |
|--------|-------------|----------|
| All layers, full parity | Text, logo, white frame — same as photos | ✓ |
| Text + logo only, skip white frame | White frame is unusual on video | |
| You decide | Planner determines | |

**User's choice:** All layers, full parity
**Notes:** Video gets the same watermark treatment as photos — no feature gap.

### Preview Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Static frame preview | Single representative frame with watermarks | ✓ |
| Low-res video preview | Downscaled preview video with watermarks | |
| You decide | Planner determines | |

**User's choice:** Static frame preview
**Notes:** Lightweight, instant updates. True WYSIWYG since frame is extracted from actual video and processed through same pipeline.

### Export Format

| Option | Description | Selected |
|--------|-------------|----------|
| Preserve source format | Match container/codec/bitrate | ✓ |
| Always export HEVC | Standardize on HEVC output | |
| You decide | Planner determines | |

**User's choice:** Preserve source format
**Notes:** No unnecessary re-encoding. H.264 in → H.264 out, HEVC in → HEVC out.

---

## Share Extension UX Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full watermarking UI | Same SwiftUI views as main app via UIHostingController | ✓ |
| Streamlined quick config | Simplified controls + open in app button | |
| Apply & share (preset only) | No config UI, applies last-used/default preset | |

**User's choice:** Full watermarking UI
**Notes:** Complete parity with main app. Users expect the same controls regardless of entry point.

### Extension Flow

| Option | Description | Selected |
|--------|-------------|----------|
| Configure → Render → Share | Config UI first, then render, then share sheet | ✓ |
| Quick preview → Configure → Share | Preview first, then config | |
| You decide | Planner determines | |

**User's choice:** Configure → Render → Share
**Notes:** Direct path from receiving media to watermarking controls — minimal friction.

### Post-Share Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Extension closes automatically | completeRequest after share sheet dismisses | ✓ |
| Return to config for next item | Stay open for next item | |
| You decide | Planner determines | |

**User's choice:** Extension closes automatically
**Notes:** One-shot workflow. Clean and simple.

### Config Sync

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, sync via App Group | Share config between extension and main app | ✓ |
| No, extension is independent | Extension starts fresh each time | |
| You decide | Planner determines | |

**User's choice:** Yes, sync via App Group
**Notes:** Watermark config set in either context becomes default in the other. App Group UserDefaults shared container.

---

## Video HDR Preservation Approach

| Option | Description | Selected |
|--------|-------------|----------|
| All common formats | Dolby Vision 8.4, HLG, HDR10 — validate all three | ✓ |
| Dolby Vision only | Focus on default iPhone format | |
| Best effort, no validation | Trust Apple's pipeline | |

**User's choice:** All common formats
**Notes:** Explicitly test and validate all three HDR formats in output verification.

### HDR Fallback

| Option | Description | Selected |
|--------|-------------|----------|
| Fail with clear error | Refuse to process if HDR can't be preserved | |
| Fall back to SDR with warning | Tone-map to SDR, show warning | ✓ |
| Silent best-effort | Let Apple decide, no notification | |

**User's choice:** Fall back to SDR with warning
**Notes:** Maximizes usability — user can still share even if HDR is lost, but they'll know.

### Audio

| Option | Description | Selected |
|--------|-------------|----------|
| Passthrough all audio | Keep all tracks intact (stereo, spatial, multi-channel) | ✓ |
| Mixdown to stereo AAC | Convert to single stereo track | |
| You decide | Planner determines | |

**User's choice:** Passthrough all audio
**Notes:** Preserve spatial audio and multi-channel tracks. No quality loss from mixdown.

### Validation

| Option | Description | Selected |
|--------|-------------|----------|
| Validate and report | Inspect output tracks post-export for HDR + audio | ✓ |
| Trust the pipeline | AVAssetExportSession handles it | |

**User's choice:** Validate and report
**Notes:** Post-export inspection of HDR metadata (color primaries, transfer function) and audio tracks. Log warnings if anything lost.

---

## Photo Handling in Share Extension

| Option | Description | Selected |
|--------|-------------|----------|
| Process inline, no choice | Use existing WatermarkEngine directly in extension | ✓ |
| Offer 'Open in app' button | Inline processing + option to open main app | |
| Route all photos to main app | Extension handles only video | |

**User's choice:** Process inline, no choice
**Notes:** Seamless — user doesn't distinguish between extension and main app processing.

### Multi-Item Handling

| Option | Description | Selected |
|--------|-------------|----------|
| First item only | Process only first item, ignore rest | |
| Process all sequentially | Configure once, apply to all, share each | ✓ |
| You decide | Planner determines | |

**User's choice:** Process all sequentially
**Notes:** Extends one-shot flow to cover all shared items without reconfiguring.

### Media Types

| Option | Description | Selected |
|--------|-------------|----------|
| Photos + videos only | Image and movie types | |
| Photos + videos + Live Photos | Include Live Photos now | ✓ |
| You decide | Planner determines | |

**User's choice:** Photos + videos + Live Photos
**Notes:** Accept Live Photos in the activation rule now to avoid a later extension update, even though processing is Phase 7.

### Unsupported Media

| Option | Description | Selected |
|--------|-------------|----------|
| Show error, skip item | Alert + continue with remaining items | |
| Silently skip unsupported | Don't alert, just ignore | |
| Offer to open in main app | Dialog with option to open in full app | ✓ |

**User's choice:** Offer to open in main app
**Notes:** Graceful fallback — unsupported types get a dialog with an option to try the main app.

---

## Claude's Discretion

- CALayer hierarchy design for watermark overlay layers
- AVAssetExportSession preset selection for HDR preservation
- Export validation heuristic details (metadata keys, tolerance thresholds)
- App Group UserDefaults serialization format for WatermarkConfiguration
- Multi-item sequential processing orchestration in ShareViewController
- UIHostingController integration pattern
- NSItemProvider async loading strategy and error recovery
- Temp file lifecycle in extension sandbox
- ShareViewController lifecycle management with NSExtensionContext

## Deferred Ideas

None — discussion stayed within phase scope.
