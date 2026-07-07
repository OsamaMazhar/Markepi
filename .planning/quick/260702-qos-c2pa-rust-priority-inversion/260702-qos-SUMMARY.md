---
title: Move C2PA Rust work off user-initiated QoS
date: 2026-07-02
type: quick
requirements-completed: []
---

# Quick Summary: Move C2PA Rust Work Off User-Initiated QoS

## Outcome

Moved concrete `contentauth/c2pa-swift` read, sign, and verify calls onto an explicit utility-priority queue so user-initiated app/export tasks no longer enter the Rust-backed C2PA work directly.

## Changes

- Added a private `runC2PAWork` helper and utility-QoS C2PA work queue in `C2PASwiftProvenanceClient`.
- Wrapped `C2PA.readFile(at:)`, manifest signing, output replacement, and post-sign verification read-back in the utility-priority helper.
- Kept the public async `C2PAProvenanceClient` adapter API and receipt behavior unchanged.

## Verification

- `git diff --check -- .planning/quick/260702-qos-c2pa-rust-priority-inversion/260702-qos-PLAN.md Packages/WatermarkCore/Sources/WatermarkCore/Provenance/C2PAProvenanceClient.swift`: passed.
- `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/watermark-c2pa-qos-dd build-for-testing`: passed.
