# Roadmap: Watermark

## Overview

An iOS app for watermarking photos and videos, then sharing instantly without saving to the camera roll. The roadmap delivers the complete "import → watermark → share" loop across four phases: a rendering engine with quality guarantees first, then the main app UI for photos, then video processing with share sheet integration, and finally the Photos edit extension with comprehensive validation.

## Phases

- [ ] **Phase 1: Core Engine & Photo Pipeline** — WatermarkCore foundation, photo rendering, and quality preservation
- [ ] **Phase 2: Main App (Photo Watermark & Share)** — Complete in-app photo workflow: import, configure, preview, share
- [ ] **Phase 3: Video Processing & Share Extension** — Video watermarking pipeline and share sheet import
- [ ] **Phase 4: Photos Edit Extension & Polish** — Photos app integration and comprehensive quality validation

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

- [ ] 01-02-PLAN.md — PNG image/logo watermark rendering + all 9 position coverage + configurable padding + multi-layer compositing

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 01-03-PLAN.md — White frame border rendering + device metadata text overlay ("Taken by: iPhone 16 Pro")

### Phase 2: Main App (Photo Watermark & Share)

**Goal**: Users can import photos from their library, configure watermarks with real-time preview, and share immediately without saving to the camera roll
**Mode**: mvp
**Depends on**: Phase 1
**Requirements**: MEDI-01, WMRK-04, SHAR-01
**Success Criteria** (what must be TRUE):

  1. User can select photos from their library using a native PhotosPicker
  2. User sees a real-time preview that updates as they configure watermark text, image overlay, position, and white frame settings
  3. User can share the watermarked photo immediately via the iOS share sheet without the output being saved to the camera roll

**Plans**: TBD
**UI hint**: yes

### Phase 3: Video Processing & Share Extension

**Goal**: Users can watermark videos with full quality preservation and receive media from other apps via the iOS share sheet
**Mode**: mvp
**Depends on**: Phase 2
**Requirements**: MEDI-02, QUAL-04
**Success Criteria** (what must be TRUE):

  1. User can receive photos and videos from other apps via the iOS share sheet and watermark them with the same configuration options as the main app
  2. Watermarked video output preserves HDR (Dolby Vision/HLG), color space, and all audio tracks from the source
  3. Video watermarking maintains source-equivalent quality (resolution, frame rate, bitrate) without visible re-encoding degradation

**Plans**: TBD
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

**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Core Engine & Photo Pipeline | 1/3 | In Progress|  |
| 2. Main App (Photo Watermark & Share) | 0/? | Not started | - |
| 3. Video Processing & Share Extension | 0/? | Not started | - |
| 4. Photos Edit Extension & Polish | 0/? | Not started | - |
