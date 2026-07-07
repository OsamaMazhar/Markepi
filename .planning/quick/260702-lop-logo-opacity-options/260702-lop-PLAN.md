---
quick_id: 260702-lop
title: Add logo opacity options
status: completed
created: 2026-07-02
---

# Quick Plan: Add Logo Opacity Options

## Goal

Expose opacity editing in the logo options UI so users can tune image/logo watermark transparency without going through the generic layer list.

## Tasks

1. Add a safe image watermark opacity copy helper that preserves existing logo data and rotation.
2. Add an active-logo opacity slider to the shared logo picker/options view.
3. Run focused static/build verification and record the result.

## Verification

- Run `git diff --check` on touched files.
- Run focused Swift package tests if local toolchain permissions allow it.
