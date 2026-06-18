# Roadmap: Watermark

## Overview

An iOS app for watermarking photos and videos, then sharing instantly without saving to the camera roll. The roadmap delivers the complete "import → watermark → share" loop across four phases: a rendering engine with quality guarantees first, then the main app UI for photos, then video processing with share sheet integration, and finally the Photos edit extension with comprehensive validation.

## Phases

- [x] **Phase 1: Core Engine & Photo Pipeline** — WatermarkCore foundation, photo rendering, and quality preservation (completed 2026-06-17)
- [x] **Phase 2: Main App (Photo Watermark & Share)** — Complete in-app photo workflow: import, configure, preview, share (completed 2026-06-17)
- [x] **Phase 3: Video Processing & Share Extension** — Video watermarking pipeline and share sheet import (completed 2026-06-17)
- [ ] **Phase 4: Photos Edit Extension & Polish** — Photos app integration and comprehensive quality validation
- [ ] **Phase 5: Extended Engine (ProRAW, EXIF Tokens, Multi-Layer)** — ProRAW support, dynamic EXIF-based text tokens, multi-layer compositing
- [ ] **Phase 6: Export Control & UX Polish** — Format/quality selection, before/after comparison, video progress UX
- [ ] **Phase 7: Additional Inputs & System Integration (v2)** — Live Photos, signature, Files import, quick actions, App Intents

## Phase Details

### Phase 1: Core Engine & Photo Pipeline

**Goal**: A photo watermarking engine that renders text/image overlays and white frames while preserving HDR, metadata, and original quality — testable end-to-end without any UI
**Mode**: mvp
**Depends on**: Nothing (first phase)
**Requirements**: WMRK-01, WMRK-02, WMRK-03, FRME-01, FRME-02, QUAL-01, QUAL-02, QUAL-03
**Success Criteria** (what must be TRUE):

  1. Photo processor generates output with text watermarks at any of 8 preset positions, with configurable font, size, color, and opacity
  2. Photo processor generates output with image/logo watermarks at any of 8 preset positions, with configurable resize and opacity
  3. Photo processor applies white frame border with device model metadata (e.g., "Taken by: iPhone 16 Pro") overlaid on the frame
  4. Output photos retain all source EXIF, GPS, and metadata fields (verifiable via exiftool before/after comparison)
  5. Output photos preserve HDR gain maps and color profiles through the rendering pipeline with no unnecessary re-compression

**Plans**: 3 plans

Plans:
**Wave 1**

- [x] 01-01-PLAN.md — WatermarkCore Swift Package skeleton + text watermark pipeline with full quality preservation (HDR, metadata, format)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — PNG image/logo watermark rendering + all 9 position coverage + configurable padding + multi-layer compositing

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-03-PLAN.md — White frame border rendering + device metadata text overlay ("Taken by: iPhone 16 Pro")

### Phase 2: Main App (Photo Watermark & Share)

**Goal**: Users can import photos from their library, configure watermarks with real-time preview, and share immediately without saving to the camera roll
**Mode**: mvp
**Depends on**: Phase 1
**Requirements**: MEDI-01, WMRK-04, SHAR-01
**Success Criteria** (what must be TRUE):

  1. User can select photos from their library using a native PhotosPicker
  2. User sees a real-time preview that updates as they configure watermark text, image overlay, position, and white frame settings
  3. User can share the watermarked photo immediately via the iOS share sheet without the output being saved to the camera roll

**Plans**: 2 plans

Plans:
**Wave 1**

- [x] 02-01-PLAN.md — Core vertical slice: app target + PhotosPicker import + text watermark controls + debounced preview rendering + two-tap share flow + thumbnail navigation + error handling

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-02-PLAN.md — Extended features: logo/image watermark picker + white frame toggle + layer list with X removal + pinch-to-resize gesture + accessibility labels + animations + validation

### Phase 3: Video Processing & Share Extension

**Goal**: Users can watermark videos with full quality preservation and receive media from other apps via the iOS share sheet
**Mode**: mvp
**Depends on**: Phase 2
**Requirements**: MEDI-02, QUAL-04
**Success Criteria** (what must be TRUE):

  1. User can receive photos and videos from other apps via the iOS share sheet and watermark them with the same configuration options as the main app
  2. Watermarked video output preserves HDR (Dolby Vision/HLG), color space, and all audio tracks from the source
  3. Video watermarking maintains source-equivalent quality (resolution, frame rate, bitrate) without visible re-encoding degradation

**Plans**: 3 plans

Plans:
**Wave 1** *(parallel — no file overlap)*

- [x] 03-01-PLAN.md — Share Extension + Photo Watermarking: share extension target scaffold, SwiftUI watermarking UI via UIHostingController, NSItemProvider photo loading, WatermarkEngine integration, App Group config sync, NSExtensionActivationRule
- [x] 03-02-PLAN.md — Video Watermarking Engine: VideoProcessor (AVFoundation AVVideoCompositionCoreAnimationTool + CALayer overlay), VideoLayerBuilder, VideoFrameExtractor, ExportValidator, HDR preservation + audio passthrough

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 03-03-PLAN.md — Video in Share Extension: NSItemProvider video loading via loadFileRepresentation, static frame preview, VideoProcessor rendering, multi-item sequential processing, HDR fallback warnings, unsupported type dialog, controls sharing refactor

**UI hint**: yes

### Phase 4: Photos Edit Extension & Polish

**Goal**: Users can access Watermark from the Photos app's edit menu, and the app passes comprehensive quality validation on physical devices
**Mode**: mvp
**Depends on**: Phase 3
**Requirements**: MEDI-03
**Success Criteria** (what must be TRUE):

  1. User can open any photo or video in the Photos app and select Watermark from the edit extensions menu
  2. Photos extension watermarked output includes an undoable adjustment entry in the Photos edit history (non-destructive editing)
  3. Comprehensive QA confirms HDR preservation, metadata integrity, and orientation correctness across the supported iOS 18 device range without memory crashes

**Plans**: 2 plans

Plans:
**Wave 1**

- [ ] 04-01-PLAN.md — Complete Photo Editing Extension: Xcode targets (PhotoEdit + ShareExtension), PHContentEditingController, photo watermarking via WatermarkEngine, PHAdjustmentData undo/re-edit, automated tests

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 04-02-PLAN.md — Video support in Photos extension (audiovisualAsset → VideoProcessor), PHAdjustmentData image watermark stripping, comprehensive automated test suite, manual QA checklist

**UI hint**: yes

### Phase 5: Extended Engine (ProRAW, EXIF Tokens, Multi-Layer)

**Goal**: Extend the WatermarkCore engine to support ProRAW at full resolution, dynamic EXIF-based text tokens for "Shot On" style attribution, and true multi-layer compositing (text + logo + frame simultaneously)
**Mode**: mvp
**Depends on**: Phase 1 (extends engine; can run parallel to Phases 2-4)
**Requirements**: PROR-01, PROR-02, EXIF-01, EXIF-02, MULT-01, MULT-02
**Success Criteria** (what must be TRUE):

  1. Apple ProRAW DNG files process through the pipeline at full 48MP resolution without downsampling, preserving HDR gain maps and DNG metadata
  2. Dynamic EXIF tokens ({camera_model}, {lens}, {aperture}, {focal_length}, {shutter_speed}, {iso}, {date}, {gps}) render correctly in watermarks and frame text for all supported photo formats
  3. Text watermark, image/logo watermark, and white frame can all be active and rendered in a single compositing pass with independent position/opacity/visibility per layer

**Plans**: TBD

### Phase 6: Export Control & UX Polish

**Goal**: Users have full control over output format and quality, can compare original vs watermarked before sharing, and get a polished video export experience with progress tracking
**Mode**: mvp
**Depends on**: Phases 2, 3, 5 (requires main app UI + video engine + extended engine)
**Requirements**: EXPT-01, EXPT-02, EXPT-03, COMP-01, COMP-02, VIDX-01, VIDX-02, VIDX-03
**Success Criteria** (what must be TRUE):

  1. User can select output format from HEIC, JPEG, PNG, or TIFF with a quality slider (60–100%), and the choice is honored without stripping HDR/metadata
  2. Swipe or long-press gesture toggles between original source and watermarked preview for both photos and videos in the preview screen
  3. Video export shows a real-time progress bar with estimated time remaining, a cancel button that stops export cleanly, and a system notification on background completion

**Plans**: TBD
**UI hint**: yes

### Phase 7: Additional Inputs & System Integration (v2)

**Goal**: Expand import sources (Live Photos, Files app, signature capture) and integrate with iOS system features (home screen quick actions, Siri/Shortcuts/App Intents)
**Mode**: mvp
**Depends on**: Phases 4, 6 (requires all entry points + export control)
**Requirements**: LIVE-01, LIVE-02, SIGN-01, IMPS-01, IMPS-02, SYSI-01, SYSI-02
**Success Criteria** (what must be TRUE):

  1. Live Photos retain their motion video component after watermarking, with the overlay applied to both the still frame and motion frames
  2. User can draw or capture a signature within the app and use it as a watermark overlay with configurable opacity and position
  3. User can import media directly from the Files app / iCloud Drive and via "Open In" from other apps
  4. Long-pressing the app icon shows "Watermark Last Photo" and "Watermark from Clipboard" quick actions; Siri/Shortcuts integration allows triggering watermarking via voice or automation

**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7
(Phase 5 can run parallel to 2-4 since it extends the engine; Phase 6 requires 2+3+5; Phase 7 is v2)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Core Engine & Photo Pipeline | 3/3 | Complete   | 2026-06-17 |
| 2. Main App (Photo Watermark & Share) | 2/2 | Complete   | 2026-06-17 |
| 3. Video Processing & Share Extension | 3/3 | Complete   | 2026-06-17 |
| 4. Photos Edit Extension & Polish | 0/? | Not started | - |
| 5. Extended Engine (ProRAW, EXIF, Multi-Layer) | 0/? | Not started | - |
| 6. Export Control & UX Polish | 0/? | Not started | - |
| 7. Additional Inputs & System Integration (v2) | 0/? | Not started | - |
