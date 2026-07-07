---
quick_id: 260705-2ou
slug: fix-distribution-blockers-app-icon-alpha
description: Fix distribution blockers: app icon alpha channel and C2PAC dSYM upload warning
date: 2026-07-04
status: complete
---

# Quick Task 260705-2ou: Fix Distribution Blockers

## Summary

Fixed the two distribution issues reported during App Store upload:

- Flattened the three `AppIcon.appiconset` PNGs to opaque RGB images so the compiled large app icon no longer contains transparency.
- Added an archive-only WatermarkApp build phase, `Generate C2PAC dSYM`, that creates `C2PAC.framework.dSYM` from the embedded `C2PAC.framework` binary and copies it into the `.xcarchive/dSYMs` folder.

## Verification

- `sips -g hasAlpha` reports `hasAlpha: no` for `icon-default.png`, `icon-dark.png`, and `icon-tinted.png`.
- `xcrun assetutil --info` on the archived `Assets.car` reports `Opaque: true` for all `AppIcon` icon renditions.
- `plutil -lint Watermark.xcodeproj/project.pbxproj` passed.
- `xcodebuild -project Watermark.xcodeproj -scheme "WatermarkApp (Release)" -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO archive -archivePath /tmp/WatermarkDistributionFix-260705-2ou-b.xcarchive -quiet` passed.
- The throwaway archive contains `/tmp/WatermarkDistributionFix-260705-2ou-b.xcarchive/dSYMs/C2PAC.framework.dSYM`.
- `dwarfdump --uuid` reports matching UUID `E02C9727-9981-322A-8920-37C2EC178D3F` for the archived `C2PAC.framework` binary and generated `C2PAC.framework.dSYM`.

## Notes

`AppLogo.png` remains transparent because it is a normal image asset, not an app icon rendition.
