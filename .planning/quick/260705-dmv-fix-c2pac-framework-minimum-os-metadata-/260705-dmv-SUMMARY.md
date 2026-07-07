---
quick_id: 260705-dmv
slug: fix-c2pac-framework-minimum-os-metadata-
description: Fix C2PAC framework minimum OS metadata for App Store upload
date: 2026-07-05
status: complete
---

# Quick Task 260705-dmv: Fix C2PAC Framework Minimum OS Metadata

## Summary

Fixed App Store Connect error `90208: Invalid Bundle` for `WatermarkApp.app/Frameworks/C2PAC.framework`.

The issue was a mismatch inside the embedded framework:

- `C2PAC.framework/Info.plist` declared `MinimumOSVersion = 16.0`.
- The `C2PAC` binary load command declared `LC_BUILD_VERSION minos 18.0`.
- The app itself declares `MinimumOSVersion = 18.0`.

Updated the existing WatermarkApp archive phase so archive builds normalize the embedded `C2PAC.framework/Info.plist` `MinimumOSVersion` to the app deployment target, re-sign the framework when code signing is active, and still generate/copy the C2PAC dSYM into the archive.

Also bumped app and share extension build numbers from `1` to `2` for the next upload.

## Verification

- `plutil -lint Watermark.xcodeproj/project.pbxproj` passed.
- `xcodebuild -project Watermark.xcodeproj -scheme "WatermarkApp (Release)" -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO archive -archivePath /tmp/WatermarkC2PACMinOSFix-260705-dmv.xcarchive -quiet` passed.
- Archived app plist: `CFBundleIdentifier = com.osamamazhar.markepi`, `CFBundleVersion = 2`, `MinimumOSVersion = 18.0`.
- Archived share extension plist: `CFBundleIdentifier = com.osamamazhar.markepi.share`, `CFBundleVersion = 2`, `MinimumOSVersion = 18.0`.
- Archived `C2PAC.framework/Info.plist`: `MinimumOSVersion = 18.0`.
- Archived `C2PAC` binary: `LC_BUILD_VERSION minos 18.0`.
- Archived `C2PAC.framework.dSYM` exists and matches framework UUID `6B0A77EB-FD7C-386F-A108-2AF1A900A89E`.
- App icon assets still report `hasAlpha: no`.
