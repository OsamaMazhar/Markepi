---
quick_id: 260702-jtr
title: Fix logo opacity slider jitter
status: completed
created: 2026-07-02
---

# Quick Plan: Fix Logo Opacity Slider Jitter

## Goal

Make logo opacity changes feel responsive while removing preview jitter during slider drags.

## Tasks

1. Reduce opacity slider update spam by snapping logo opacity to visible percent increments.
2. Defer expensive App Group config persistence while an interactive slider drag is active.
3. Stop the existing preview from being covered by loading chrome during interactive preview regeneration.
4. Run focused iOS build verification.

## Verification

- Run `git diff --check` on touched files.
- Run the WatermarkApp iOS build-for-testing gate.
