# Phase 11: Photos Extension HDR Detection - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-18
**Phase:** 11-photos-extension-hdr-detection
**Areas discussed:** HDR Detection for Photos, HDR Detection for Videos, Format Label Detection, Detection Timing, Code Organization

---

## HDR Detection for Photos

| Option | Description | Selected |
|--------|-------------|----------|
| CGImageSource UTI heuristic (match main app) | Check if source UTI is "public.heic" — same as WatermarkViewModel and ShareExtensionViewModel | ✓ |
| Deeper gain map auxiliary data check | Check actual HDR gain map presence via CGImageSourceCopyAuxiliaryDataInfoAtIndex | |
| Both (UTI + fallback) | UTI first, gain map for confirmation | |

**User's choice:** [auto] CGImageSource UTI heuristic — consistent with main app and share extension. Both existing ViewModels use the same approach with the comment "Full HDR gain map detection is deferred."
**Notes:** The ROADMAP success criteria #1 says "gain map presence or transfer function inspection — consistent with the Main App's HDR detection approach." The Main App's approach IS the UTI heuristic. A deeper check would be a new feature, not a consistency fix.

---

## HDR Detection for Videos

| Option | Description | Selected |
|--------|-------------|----------|
| AVAssetTrack.hasMediaCharacteristic (match VideoProcessor) | Check `containsHDRVideo` characteristic on audiovisualAsset tracks | ✓ |
| File extension heuristic only | Treat certain formats (e.g., .mov with Dolby Vision) as HDR based on extension | |
| Skip video HDR detection | Only detect HDR for photos | |

**User's choice:** [auto] AVAssetTrack.hasMediaCharacteristic(.containsHDRVideo) — consistent with VideoProcessor in WatermarkCore.
**Notes:** The Photos extension already handles videos (lines 155–161 cast audiovisualAsset to AVURLAsset). Adding video HDR detection ensures the warning works for both media types.

---

## Format Label Detection

| Option | Description | Selected |
|--------|-------------|----------|
| CGImage UTI for photos + extension for videos | CGImageSourceGetType mapping for photos; path extension for videos | ✓ |
| UTType-based detection | Use UniformTypeIdentifiers framework for both | |
| PHAsset mediaSubtypes | Query PHAsset for format info | |

**User's choice:** [auto] CGImageSource UTI mapping for photos (public.heic→"HEIC", public.jpeg→"JPEG", public.png→"PNG", public.tiff→"TIFF"). File extension mapping for videos (.mov→"MOV", .mp4→"MP4").
**Notes:** This replicates the exact mapping from WatermarkViewModel.detectSourceFormatLabel(from:) lines 210–223. Video format labeling is a pragmatic extension — the other ViewModels don't label video formats, but adding it improves the Photos extension UX.

---

## Detection Timing

| Option | Description | Selected |
|--------|-------------|----------|
| Eager (startEditing, match main app) | Detect during media loading in startEditing(with:placeholderImage:) | ✓ |
| Lazy (when ControlsView first reads) | Detect on first access to sourceHasHDR/sourceFormatLabel | |
| On renderAndCommit only | Detect only when the user commits the edit | |

**User's choice:** [auto] Eager in startEditing — matches WatermarkViewModel and ShareExtensionViewModel pattern.
**Notes:** Both existing ViewModels detect HDR/format during their media-loading methods. Eager detection ensures the properties are populated before the user opens ControlsView's export options.

---

## Code Organization

| Option | Description | Selected |
|--------|-------------|----------|
| Inline in PhotosExtensionViewModel (minimum) | Add detection logic directly in startEditing | ✓ |
| Extract to WatermarkCore (de-duplicate all 3) | Move shared helpers to WatermarkCore, remove duplicates from WatermarkViewModel and ShareExtensionViewModel | |
| Both: inline first, extract as follow-up | Minimum approach now, extraction in later phase | |

**User's choice:** [auto] Inline in PhotosExtensionViewModel — minimum viable for Phase 11. Researcher should evaluate WatermarkCore extraction as a bonus.
**Notes:** The `detectHDRSource` and `detectSourceFormatLabel` helpers are duplicated identically in WatermarkViewModel (lines 200–223) and ShareExtensionViewModel (lines 691–712). Extracting them to WatermarkCore would follow Phase 10's refactoring pattern and reduce code duplication further — but Phase 11's success criteria only require fixing PhotosExtensionViewModel.

---

## the agent's Discretion

- Whether to use `CGImageSourceCreateWithURL` (zero-copy header read) or `Data(contentsOf:)` (simpler) for file reading.
- Whether to extract shared helpers to WatermarkCore (D-09/D-10) — researcher evaluates, planner decides.
- Exact file placement if shared helpers are extracted to WatermarkCore.
- Video format label mapping of extensions to labels.

## Deferred Ideas

None — all areas stayed within phase scope. One optional extension noted:
- Extracting duplicated HDR/format detection helpers from WatermarkViewModel and ShareExtensionViewModel to WatermarkCore — bonus, not required for Phase 11 success.
