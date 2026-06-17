# Requirements: Watermark

**Defined:** 2026-06-17
**Core Value:** Add a watermark and share it instantly — without ever cluttering the camera roll.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Media Import (MEDI)

- [ ] **MEDI-01**: User can import photos and videos from in-app picker (PHPicker)
- [ ] **MEDI-02**: User can receive photos and videos from other apps via iOS share sheet (app extension)
- [ ] **MEDI-03**: User can receive photos and videos via Photos app native edit extension

### Watermark (WMRK)

- [ ] **WMRK-01**: User can add custom text watermarks with font, size, color, and opacity controls
- [ ] **WMRK-02**: User can import and overlay image/logo watermarks with resize and opacity controls
- [ ] **WMRK-03**: User can place watermarks in 8 preset positions (4 corners, 4 edges, center)
- [ ] **WMRK-04**: User can see a real-time preview of the watermarked result before sharing

### White Frame (FRME)

- [ ] **FRME-01**: User can apply a white frame border to photos and videos
- [ ] **FRME-02**: User can overlay device metadata text (e.g., "Taken by: iPhone 16 Pro") on the white frame

### Sharing (SHAR)

- [ ] **SHAR-01**: User can share watermarked media via iOS share sheet without the output being saved to the camera roll

### Quality Preservation (QUAL)

- [ ] **QUAL-01**: All EXIF and metadata from the source media is preserved in the watermarked output
- [ ] **QUAL-02**: HDR (gain maps, color profiles) is preserved in photo output
- [ ] **QUAL-03**: Original image and video quality is preserved (no unnecessary re-compression)
- [ ] **QUAL-04**: Video watermarking preserves HDR, color space, and audio tracks in output

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
| MEDI-01 | Phase 1 | Pending |
| MEDI-02 | Phase 1 | Pending |
| MEDI-03 | Phase 2 | Pending |
| WMRK-01 | Phase 1 | Pending |
| WMRK-02 | Phase 1 | Pending |
| WMRK-03 | Phase 1 | Pending |
| WMRK-04 | Phase 1 | Pending |
| FRME-01 | Phase 1 | Pending |
| FRME-02 | Phase 1 | Pending |
| SHAR-01 | Phase 1 | Pending |
| QUAL-01 | Phase 1 | Pending |
| QUAL-02 | Phase 1 | Pending |
| QUAL-03 | Phase 1 | Pending |
| QUAL-04 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-17*
*Last updated: 2026-06-17 after initial definition*
