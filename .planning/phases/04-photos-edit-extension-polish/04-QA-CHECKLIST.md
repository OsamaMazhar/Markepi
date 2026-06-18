# Phase 4: Photos Edit Extension — QA Checklist

**Device:** [TBD — fill in during testing]
**iOS Version:** [TBD — fill in during testing]
**Tester:** [TBD — fill in during testing]
**Date:** [TBD — fill in during testing]

## Instructions

Run each test case on a physical iPhone (iOS 18, A13 Bionic or newer). Mark ✅ (Pass) or ❌ (Fail) in the Pass/Fail column. Add notes for any unexpected behavior, error messages, or deviations.

All tests must pass before Phase 4 sign-off (D-11, D-12).

---

## Extension Appearance

Verify the Watermark extension appears in the Photos app edit menu for all supported media types.

| # | Test Case | Expected Behavior | Pass/Fail | Notes |
|---|-----------|-------------------|-----------|-------|
| 1 | Open HEIC photo in Photos → tap Edit → tap "…" extensions menu | "Watermark" option appears in the extensions list | | |
| 2 | Open JPEG photo in Photos → tap Edit → tap "…" extensions menu | "Watermark" option appears in the extensions list | | |
| 3 | Open PNG photo in Photos → tap Edit → tap "…" extensions menu | "Watermark" option appears in the extensions list | | |

---

## Photo Processing

Verify watermark rendering, HDR preservation, metadata integrity, and orientation handling for photos.

| # | Test Case | Expected Behavior | Pass/Fail | Notes |
|---|-----------|-------------------|-----------|-------|
| 4 | Select Watermark extension for HEIC photo → configure text watermark → tap Done | Watermark renders at configured position; photo saved back to Photos library with edit | | |
| 5 | Verify HDR gain map preserved in HEIC output (exiftool: check for HDR gain map auxiliary data) | exiftool confirms gain map auxiliary data present in output | | Requires exiftool CLI |
| 6 | Verify EXIF metadata preserved (exiftool before/after comparison) | All EXIF fields (camera model, lens, ISO, aperture, GPS) match source | | Requires exiftool CLI |
| 7 | Process photos with all 8 EXIF orientations (1-8) through extension | Output displays with correct orientation; no rotated/stretched output | | Test each orientation individually |

---

## Video Processing

Verify video watermarking from the Photos edit menu with HDR preservation and audio passthrough.

| # | Test Case | Expected Behavior | Pass/Fail | Notes |
|---|-----------|-------------------|-----------|-------|
| 8 | Open H.264 video in Photos → Edit → Watermark extension → configure watermark → Done | Watermark renders on video output; video saves back to Photos | | Test with short clip |
| 9 | Open HEVC video in Photos → Edit → Watermark extension → configure watermark → Done | HEVC video watermarked successfully; no format conversion | | |
| 10 | Open Dolby Vision HDR video in Photos → Edit → Watermark extension → Done | HDR preserved in output; no SDR fallback warning (or warning shown if HDR lost) | | Verify with HDR test footage |
| 11 | Watermark video with multiple audio tracks (e.g., spatial audio) | All audio tracks preserved in output; no audio channel loss | | Verify with AVFoundation or exiftool |

---

## PHAdjustmentData (Undo / Re-edit)

Verify non-destructive editing — undo restores original, re-edit loads saved config.

| # | Test Case | Expected Behavior | Pass/Fail | Notes |
|---|-----------|-------------------|-----------|-------|
| 12 | Watermark a photo → open Photos edit history → tap "Revert to Original" | Original unmodified photo restored; watermark removed | | |
| 13 | Watermark a photo → Done → re-open Edit → select Watermark extension | Previous watermark configuration is loaded (text, position, scale restored) | | |
| 14 | Open Photos edit history for watermarked photo | Edit history shows "Watermark" entry; Undo button visible | | |

---

## Memory & Stability

Verify the extension handles large assets without crashing (jetsam) or memory warnings.

| # | Test Case | Expected Behavior | Pass/Fail | Notes |
|---|-----------|-------------------|-----------|-------|
| 15 | Open 4K HEVC video with Dolby Vision + spatial audio → configure watermark → Done | No crash or memory termination; export completes successfully | | Monitor Xcode console for memory warnings |
| 16 | Open large JPEG photo (40MP, e.g., iPhone 16 Pro main camera) → configure watermark → Done | No crash; export completes; no memory pressure spike | | Check Instruments Allocations if available |
| 17 | Rapidly tap Done → Cancel → Done → Cancel multiple times | No crash; extension responds correctly; no double-render | | Stress test for guard state |

---

## Deviations

Record any test failures, unexpected behavior, or deviations from expected results here.

| Test # | Issue Description | Severity | Resolution |
|--------|-------------------|----------|------------|
| | | | |

---

**Summary:**
- Total test cases: 17
- Passed: [TBD]
- Failed: [TBD]
- Blocked: [TBD]

**Sign-off:** [TBD — tester name and date]
