# Phase 6: Export Control & UX Polish - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 06-export-control-ux-polish
**Areas discussed:** Export Format & Quality Control, Before/After Comparison, Video Export UX, Export Options UI

---

## Mode

`--auto` — all gray areas auto-selected, recommended options chosen autonomously. No interactive prompts.

---

## Export Format & Quality Control

| Option | Description | Selected |
|--------|-------------|----------|
| Warn + confirm on HDR→SDR | Show confirmation dialog when lossy conversion drops HDR; user confirms | ✓ |
| Just convert silently | JPEG is JPEG — don't warn | |
| Block unsupported conversions | Only allow lossless→lossless, HEIC→HEIC, JPEG→JPEG | |

**Auto-selected choice:** Warn + confirm — follows Phase 3 D-10 "warn on HDR loss" established pattern.
**Notes:** Continuous quality slider (0.6–1.0, Float), displayed as percentage. Disabled for lossless formats (PNG, TIFF). `.tiff` added to OutputFormat enum. Engine respects `config.outputFormat` — overrides source format when explicit.

---

## Before/After Comparison

| Option | Description | Selected |
|--------|-------------|----------|
| Long-press to toggle | Press to show original, release to show watermarked | ✓ |
| Swipe left/right | Slide gesture on preview area | |
| Toggle button | Persistent UI button for comparison mode | |

**Auto-selected choice:** Long-press — matches iOS "peek" pattern, avoids gesture conflict with thumbnail swipe navigation.
**Notes:** "Original" label overlay with fade animation and `.light` haptic. Works for both photos and videos (static frame comparison). Disabled when no preview loaded.

---

## Video Progress Bar

| Option | Description | Selected |
|--------|-------------|----------|
| Inline progress bar + cancel button | Linear bar in controls area replacing share button | ✓ |
| Modal progress sheet | Full-screen overlay during export | |
| Reuse existing rendering spinner | Replace "Rendering..." text with progress bar | |

**Auto-selected choice:** Inline progress bar — least disruptive, keeps user in context of the control area.
**Notes:** Simple linear ETA projection. Cancel button triggers `exportSession.cancelExport()`. Config preserved on cancel. `RenderingState.renderingVideo(progress:estimatedTimeRemaining:)` added.

---

## Background Notification

| Option | Description | Selected |
|--------|-------------|----------|
| UNUserNotificationCenter + background task | System notification with deep link | ✓ |
| No notification, foreground update only | Only update UI when app comes to foreground | |
| Background task with completion handler | UIBackgroundTaskIdentifier only | |

**Auto-selected choice:** UNUserNotificationCenter — requirement VIDX-03 explicitly calls for "system notification on background completion."

---

## Export Options UI

| Option | Description | Selected |
|--------|-------------|----------|
| Collapsible DisclosureGroup in ControlsView | Inline expandable section | ✓ |
| Separate sheet from toolbar | Modal sheet for export settings | |
| Settings in a separate tab | Persistent bottom tab for export config | |

**Auto-selected choice:** DisclosureGroup in ControlsView — discoverable without toolbar clutter, collapsed by default to keep main flow clean.

---

## Claude's Discretion

- TIFF bit depth limitation (8-bit on iOS) — document, don't hack around
- Haptic style for comparison toggle (`.light` impact)
- Notification deep-link URL scheme design
- Progress bar KVO throttle interval
- WatermarkConfigurable protocol extension for format/quality
- Color profile handling for HEIC→JPEG conversion
- Video format picker scope (preserveSource only vs explicit HEVC/H.264)
- ImageWriter signature change for resolved output UTI

## Deferred Ideas

None — auto mode selected recommendations within phase scope only.
