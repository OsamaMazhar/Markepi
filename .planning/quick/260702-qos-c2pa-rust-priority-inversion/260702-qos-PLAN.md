---
quick_id: 260702-qos
title: Move C2PA Rust work off user-initiated QoS
status: completed
created: 2026-07-02
---

# Quick Plan: Move C2PA Rust Work Off User-Initiated QoS

## Goal

Address Thread Performance Checker hang-risk warnings where `contentauth/c2pa-swift` parks Rust threads while app work is running at user-initiated QoS.

## Tasks

1. Wrap concrete C2PA read/sign/verify operations in utility-priority background execution.
2. Keep the public async C2PA adapter behavior unchanged for source analysis and export receipts.
3. Run focused static and iOS build verification.

## Verification

- Run `git diff --check` on touched files.
- Run the WatermarkApp iOS build-for-testing gate.
