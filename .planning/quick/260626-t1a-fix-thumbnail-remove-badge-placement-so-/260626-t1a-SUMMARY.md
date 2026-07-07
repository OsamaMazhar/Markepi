---
title: Fix thumbnail remove badge placement
date: 2026-06-26
type: quick
requirements-completed: []
---

# Quick Summary: Fix Thumbnail Remove Badge Placement

## Outcome

Fixed the thumbnail strip delete badges by anchoring each red remove button directly to its thumbnail cell instead of positioning all badges from reconstructed scroll coordinates.

## Changes

- Removed the fragile scroll-offset badge overlay and its preference key.
- Added a top-leading overlay on each thumbnail cell for edit-mode removal.
- Offset the badge by 6pt so it sits professionally on the thumbnail's top-left corner while staying inside the strip's usable bounds.

## Verification

- `git diff --check -- App/Views/Navigation/ThumbnailStripView.swift`: passed.
- `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/watermark-badge-dd build-for-testing`: blocked in the sandbox by user-cache/CoreSimulator permissions.
- Retried the same Xcode build with elevated permissions, but the environment rejected the escalation because the usage limit has been reached.
