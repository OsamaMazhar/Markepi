---
title: Fix logo opacity slider jitter
date: 2026-07-02
type: quick
requirements-completed: []
---

# Quick Summary: Fix Logo Opacity Slider Jitter

## Outcome

Removed the visible preview jitter while dragging opacity sliders and made logo opacity interaction cheaper. The slider still updates the model during the drag, but expensive persistence and loading-overlay churn no longer happen on every tick.

## Changes

- Logo opacity now steps in 1% increments and ignores duplicate same-value updates.
- Opacity sliders notify the view model when a drag starts/ends so App Group config persistence is deferred until release.
- Existing previews are no longer covered by the loading overlay during regeneration, and preview debounce for already-rendered media is shorter.
- Share Extension preview identifiers now include logo/text/layer opacity so shared controls refresh correctly there too.

## Verification

- `git diff --check -- .planning/quick/260702-jtr-fix-logo-opacity-slider-jitter/260702-jtr-PLAN.md Packages/WatermarkCore/Sources/WatermarkCore/UI/LogoPickerView.swift Packages/WatermarkCore/Sources/WatermarkCore/UI/LayerListView.swift Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift App/ViewModels/WatermarkViewModel.swift App/Views/PreviewArea/PreviewView.swift ShareExtension/ShareExtensionViewModel.swift`: passed.
- `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/watermark-logo-jitter-dd build-for-testing`: passed.
