---
quick_id: 260703-sms
title: Fix signature ink color so signatures always draw in black, including dark mode
status: completed
created: 2026-07-03
---

# Quick Plan: Fix Signature Ink Color

## Goal

Make newly captured signatures save with black ink in every appearance mode.

## Tasks

1. Change the signature capture save path so a brand-new signature uses a fixed black `CGColor` instead of a white/theme-derived default.
2. Keep the existing black-on-white PencilKit capture canvas behavior unchanged.
3. Run focused static/test verification and record the result.

## Verification

- Run `git diff --check` on touched files.
- Run focused Swift package signature tests if the local toolchain permits it.
