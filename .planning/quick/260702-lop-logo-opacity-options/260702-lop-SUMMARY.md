---
title: Add logo opacity options
date: 2026-07-02
type: quick
requirements-completed: []
---

# Quick Summary: Add Logo Opacity Options

## Outcome

Added an opacity slider to the active logo row in the shared logo picker/options UI. The control edits the image watermark's existing opacity value, so the displayed default matches the renderer's logo default instead of layering a second opacity setting on top.

## Changes

- Added `ImageWatermarkInput.withOpacity(_:)` to preserve logo data, scale, and rotation while clamping opacity to 0...1.
- Expanded `LogoPickerView` so the active logo shows an `Opacity` slider with a percent value.
- Preserved the existing layer-level opacity controls in `LayerListView` for advanced per-layer compositing.

## Verification

- `git diff --check -- .planning/quick/260702-lop-logo-opacity-options/260702-lop-PLAN.md Packages/WatermarkCore/Sources/WatermarkCore/Models/ImageWatermarkInput.swift Packages/WatermarkCore/Sources/WatermarkCore/UI/LogoPickerView.swift`: passed.
- `CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --filter ImageWatermarkRendererTests`: blocked for this package because SwiftPM compiled the package as macOS and hit the existing `UIKit` import in `ShareSheetView`.
- `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/watermark-logo-opacity-dd build-for-testing`: passed.
