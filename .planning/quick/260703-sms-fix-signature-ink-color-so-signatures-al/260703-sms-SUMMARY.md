---
title: Fix signature ink color so signatures always draw in black, including dark mode
date: 2026-07-03
type: quick
status: complete
requirements-completed: []
---

# Quick Summary: Fix Signature Ink Color

## Outcome

Newly captured signatures now save with fixed black ink regardless of light or dark mode. The capture canvas still draws black strokes on white paper, and existing signature color choices are preserved when editing an existing signature.

## Changes

- Changed the new-signature save fallback in `SignatureCaptureView` from white ink to `CGColor(gray: 0, alpha: 1)`.
- Updated the nearby comment so it reflects the fixed black default instead of the old white default.

## Verification

- `git diff --check -- .planning/quick/260703-sms-fix-signature-ink-color-so-signatures-al/260703-sms-PLAN.md Packages/WatermarkCore/Sources/WatermarkCore/UI/SignatureCaptureView.swift`: passed.
- `CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift test --filter Signature`: blocked for this package because SwiftPM builds the target for macOS and `ShareSheetView.swift` imports UIKit.
- `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/watermark-signature-ink-dd build-for-testing`: passed.
