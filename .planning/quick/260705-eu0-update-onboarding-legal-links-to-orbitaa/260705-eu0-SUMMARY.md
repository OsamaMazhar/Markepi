---
quick_id: 260705-eu0
slug: update-onboarding-legal-links-to-orbitaa
description: Update onboarding legal links to orbitaar Markepi URLs
date: 2026-07-05
status: complete
---

# Summary

Updated the app legal links to the hosted Markepi pages:

- Terms: https://www.orbitaar.com/markepi/terms-of-use.html
- Privacy: https://www.orbitaar.com/markepi/privacy-policy.html

## Files Changed

- App/Views/Premium/PaywallView.swift
- App/Views/ContentView.swift

## Verification

- Confirmed stale AutoAlign, placeholder Markepi terms, and Apple EULA legal button URLs no longer appear in app UI sources searched.
- Ran Release build with signing disabled:
  `xcodebuild -project Watermark.xcodeproj -scheme "WatermarkApp (Release)" -configuration Release -destination "generic/platform=iOS" -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build -quiet`
  Result: passed.
