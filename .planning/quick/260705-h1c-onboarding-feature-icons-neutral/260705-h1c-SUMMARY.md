---
quick_id: 260705-h1c
slug: onboarding-feature-icons-neutral
description: Make onboarding feature icons neutral instead of blue
date: 2026-07-05
status: complete
---

# Summary

Changed the second onboarding page feature icon glyphs from blue accent color to white, with a subtle shadow for contrast on the frosted badge.

## Files Changed

- App/WatermarkApp.swift

## Verification

- Confirmed `featureIconBadge` no longer uses `Color.accentColor`.
- Ran Release build with signing disabled:
  `xcodebuild -project Watermark.xcodeproj -scheme "WatermarkApp (Release)" -configuration Release -destination "generic/platform=iOS" -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build -quiet`
  Result: passed.
