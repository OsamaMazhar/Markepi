# Watermark

## What This Is

An iOS app that lets users add watermarks or white-frame metadata overlays to photos and videos, then immediately share them to social media without saving. Users can import media from the in-app picker, the iOS share sheet, or directly from the Photos app's native edit extension. Works for both photos and videos while preserving all metadata, HDR, and original image quality.

## Core Value

Add a watermark and share it instantly — without ever cluttering the camera roll.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Import photos/videos from in-app picker (plus button)
- [ ] Receive photos/videos via iOS share sheet
- [ ] Receive photos/videos via Photos app native edit extension
- [ ] Apply watermark overlay in 8 configurable positions
- [ ] Apply white frame with device metadata overlay (e.g., "Taken by: iPhone")
- [ ] Share watermarked media via share sheet without saving
- [ ] Preserve all EXIF/metadata in output
- [ ] Preserve HDR and original image/video quality

### Out of Scope

- Advanced photo editing (filters, cropping, adjustments) — keep app focused on watermark + share
- Photo library management / organization — outside core value proposition
- Cloud storage or sync — local-only operation
- Android version — iOS only for v1

## Context

This is a greenfield iOS project. Users want to brand their content for social media with watermarks or attribution frames (the "Taken by: iPhone" style overlays popular on Instagram/TikTok). The key insight is that saving watermarked copies clutters the photo library — the app should watermark in-memory/in-place and share directly. Preserving HDR and metadata is critical for professional-looking output. The app needs native iOS integration (share sheet, Photos extension) for seamless workflows.

## Constraints

- **Platform**: iOS — native (Swift/SwiftUI or UIKit)
- **Quality**: Must preserve HDR, color profile, and all EXIF/metadata in output
- **Performance**: Watermarking must work on-device for large video files without excessive memory pressure
- **Privacy**: No network calls required; all processing on-device
- **Compatibility**: Support iOS Photos edit extension and share sheet app extension

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Native iOS (Swift/SwiftUI) | Required for Photos extension, share sheet, and HDR/metadata preservation | — Pending |
| On-device rendering only | Privacy, offline use, and avoiding quality loss from server uploads | — Pending |
| No save-by-default workflow | Core value: watermark and share, don't clutter camera roll | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-17 after initialization*
