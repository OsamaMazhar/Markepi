---
quick_id: 260705-dmv
slug: fix-c2pac-framework-minimum-os-metadata-
description: Fix C2PAC framework minimum OS metadata for App Store upload
date: 2026-07-05
status: complete
---

# Quick Task 260705-dmv: Fix C2PAC Framework Minimum OS Metadata

## Goal

Resolve App Store Connect error `90208: Invalid Bundle` for `WatermarkApp.app/Frameworks/C2PAC.framework`.

## Finding

The archived app has `MinimumOSVersion = 18.0`, and the archived `C2PAC` binary has `LC_BUILD_VERSION minos 18.0`, but `C2PAC.framework/Info.plist` declares `MinimumOSVersion = 16.0`. App Store Connect validates the framework bundle metadata against the binary load command and rejects the mismatch.

## Tasks

1. Update the existing archive-only C2PAC build phase to set the embedded framework plist `MinimumOSVersion` to the app deployment target.
2. Re-sign the framework after plist normalization when code signing is active.
3. Bump the app and extension build number for a clean re-upload.
4. Archive and verify that the embedded `C2PAC.framework` plist and binary both report iOS 18.0.
