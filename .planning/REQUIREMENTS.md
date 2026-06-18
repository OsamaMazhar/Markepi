# Requirements: Watermark

**Defined:** 2026-06-17
**Core Value:** Add a watermark and share it instantly — without ever cluttering the camera roll.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Media Import (MEDI)

- [x] **MEDI-01**: User can import photos and videos from in-app picker (PHPicker)
- [x] **MEDI-02**: User can receive photos and videos from other apps via iOS share sheet (app extension)
- [x] **MEDI-03**: User can receive photos and videos via Photos app native edit extension

### Watermark (WMRK)

- [x] **WMRK-01**: User can add custom text watermarks with font, size, color, and opacity controls
- [x] **WMRK-02**: User can import and overlay image/logo watermarks with resize and opacity controls
- [x] **WMRK-03**: User can place watermarks in 8 preset positions (4 corners, 4 edges, center)
- [x] **WMRK-04**: User can see a real-time preview of the watermarked result before sharing

### White Frame (FRME)

- [x] **FRME-01**: User can apply a white frame border to photos and videos
- [x] **FRME-02**: User can overlay device metadata text (e.g., "Taken by: iPhone 16 Pro") on the white frame

### Sharing (SHAR)

- [x] **SHAR-01**: User can share watermarked media via iOS share sheet without the output being saved to the camera roll

### Quality Preservation (QUAL)

- [x] **QUAL-01**: All EXIF and metadata from the source media is preserved in the watermarked output
- [x] **QUAL-02**: HDR (gain maps, color profiles) is preserved in photo output
- [x] **QUAL-03**: Original image and video quality is preserved (no unnecessary re-compression)
- [x] **QUAL-04**: Video watermarking preserves HDR, color space, and audio tracks in output

### ProRAW (PROR)

- [ ] **PROR-01**: User can process Apple ProRAW DNG files at full resolution (48MP) without downsampling or quality loss
- [ ] **PROR-02**: ProRAW HDR gain maps and DNG metadata are preserved through the watermark pipeline

### Dynamic EXIF Tokens (EXIF)

- [ ] **EXIF-01**: User can add dynamic EXIF-based text to watermarks and frames using tokens: {camera_model}, {lens}, {aperture}, {focal_length}, {shutter_speed}, {iso}, {date}, {gps}
- [ ] **EXIF-02**: EXIF tokens render correctly for all supported formats (HEIC, JPEG, ProRAW, DNG)

### Multi-Layer Compositing (MULT)

- [ ] **MULT-01**: User can apply text watermark, image/logo watermark, and white frame simultaneously in a single render pass
- [ ] **MULT-02**: Each layer (text, image, frame) has independent position, opacity, and visibility controls

### Export Control (EXPT)

- [ ] **EXPT-01**: User can choose output format: HEIC, JPEG, PNG, or TIFF
- [ ] **EXPT-02**: User can adjust output quality via a compression/quality slider (60–100%)
- [ ] **EXPT-03**: Format choice is preserved alongside HDR and metadata (lossless re-wrap where possible)

### Before/After Comparison (COMP)

- [ ] **COMP-01**: User can toggle between original source and watermarked result with a gesture (swipe or long-press)
- [ ] **COMP-02**: Comparison view works for both photos and videos in real-time preview

### Video Export UX (VIDX)

- [ ] **VIDX-01**: User sees real-time progress bar with estimated time remaining during video export
- [ ] **VIDX-02**: User can cancel an in-progress video export without losing configuration
- [ ] **VIDX-03**: Video export can run in the background with a system notification on completion

### Live Photos (LIVE)

- [ ] **LIVE-01**: User can watermark Live Photos while preserving the motion video component
- [ ] **LIVE-02**: Still frame and motion component both receive the watermark overlay

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Customization

- **CUST-01**: User can save and reuse watermark configuration templates
- **CUST-02**: User can rotate watermarks
- **CUST-03**: User can customize frame color and style (beyond white)
- **CUST-04**: User can add additional metadata frame types (date, location, camera lens info)

### Batch Processing

- **BATC-01**: User can watermark multiple photos at once
- **BATC-02**: User can watermark multiple videos at once

### Signature (SIGN)

- **SIGN-01**: User can draw or capture a signature to use as a watermark overlay

### Additional Import Sources (IMPS)

- **IMPS-01**: User can import media from the Files app / iCloud Drive directly
- **IMPS-02**: User can open media via "Open In" from other apps and file providers

### System Integration (SYSI)

- **SYSI-01**: User can access "Watermark Last Photo" and "Watermark from Clipboard" from the home screen quick actions menu
- **SYSI-02**: User can trigger watermarking via Siri / Shortcuts / App Intents

## Out of Scope

| Feature | Reason |
|---------|--------|
| Advanced photo editing (filters, color correction, cropping) | Competing with Photoshop/Snapseed; dilutes core value proposition |
| In-app camera / photo capture | Users already have iPhone Camera; adds permission and quality complexity |
| Cloud storage, sync, or backup | Adds server costs, privacy risk, and compliance burden |
| Account creation / sign-in | Anti-pattern for utility apps; one-tap-open is the expectation |
| Photo library management (albums, organization) | Apple Photos handles this; duplication creates confusion |
| QR code watermark generation | Niche feature; users can import QR codes as image watermarks |
| Animated/sticker overlays (GIFs) | Complicates rendering pipeline; adds no value for branding use case |
| AI-based watermark placement | Adds latency and unpredictability; manual placement is sufficient |
| Collage / image stitching | Distinct use case from watermarking; dedicated apps serve this |
| Android version | iOS-only for v1 |
| Social feed / in-app community | Unrelated to watermarking; transforms utility into platform |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| MEDI-01 | Phase 2 | Complete |
| MEDI-02 | Phase 3 | Complete |
| MEDI-03 | Phase 4 | Complete |
| WMRK-01 | Phase 1 | Complete |
| WMRK-02 | Phase 1 | Complete |
| WMRK-03 | Phase 1 | Complete |
| WMRK-04 | Phase 2 | Complete |
| FRME-01 | Phase 1 | Complete |
| FRME-02 | Phase 1 | Complete |
| SHAR-01 | Phase 2 | Complete |
| QUAL-01 | Phase 1 | Complete |
| QUAL-02 | Phase 1 | Complete |
| QUAL-03 | Phase 1 | Complete |
| QUAL-04 | Phase 3 | Complete |
| PROR-01 | Phase 5 | Pending |
| PROR-02 | Phase 5 | Pending |
| EXIF-01 | Phase 5 | Pending |
| EXIF-02 | Phase 5 | Pending |
| MULT-01 | Phase 5 | Pending |
| MULT-02 | Phase 5 | Pending |
| EXPT-01 | Phase 6 | Pending |
| EXPT-02 | Phase 6 | Pending |
| EXPT-03 | Phase 6 | Pending |
| COMP-01 | Phase 6 | Pending |
| COMP-02 | Phase 6 | Pending |
| VIDX-01 | Phase 6 | Pending |
| VIDX-02 | Phase 6 | Pending |
| VIDX-03 | Phase 6 | Pending |
| LIVE-01 | Phase 7 | Pending (v2) |
| LIVE-02 | Phase 7 | Pending (v2) |
| SIGN-01 | Phase 7 | Pending (v2) |
| IMPS-01 | Phase 7 | Pending (v2) |
| IMPS-02 | Phase 7 | Pending (v2) |
| SYSI-01 | Phase 7 | Pending (v2) |
| SYSI-02 | Phase 7 | Pending (v2) |

**Coverage:**
- v1 requirements: 28 total (14 original + 14 new)
- v2 requirements: 13 total (6 original + 7 new)
- All requirements mapped to phases ✓

---
*Requirements defined: 2026-06-17*
*Last updated: 2026-06-17 — added v1 phases 5-6 (ProRAW, EXIF tokens, multi-layer, export control, comparison, video UX) and v2 phase 7 (Live Photos, signature, Files import, system integration) from competitive research gaps*
