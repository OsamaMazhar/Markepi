## Purpose

Defines what an exported photo, Live Photo or video contains for a free user versus a Markepi Pro user — resolution, compression, HDR and codec — and that exporting itself is never limited.

## ADDED Requirements

### Requirement: Unlimited exports for every user

The system SHALL NOT limit how many photos, Live Photos or videos any user exports, per day or in total. No export SHALL be refused or interrupted because the user is not Pro. The previous free allowance of 3 photos and 1 video per day SHALL no longer exist.

#### Scenario: Free user exports past the old limit
- **WHEN** a free user exports a fourth photo and a second video on the same day
- **THEN** both exports complete and are offered to the share sheet

#### Scenario: Free batch export
- **WHEN** a free user exports a batch of 20 photos and 3 videos
- **THEN** every item is exported, each with the free tier's treatment

### Requirement: Export tier follows the entitlement at export time

Each export SHALL be produced in exactly one tier: **Pro** when the user holds a Markepi Pro entitlement (purchase, subscription, restore, offer code, or the DEBUG Force Premium override) at the moment the export starts, otherwise **Free**. Every item of a batch SHALL use the same tier.

#### Scenario: Purchase between two exports
- **WHEN** a free user exports a photo, buys Pro, and exports the same photo again
- **THEN** the first file is a Free export and the second is a Pro export

### Requirement: Pro photo exports keep full quality

A Pro photo export SHALL keep the source's full pixel dimensions, the user's chosen output format and quality, every item of source metadata, and the HDR gain map where the source has one, exactly as before this change.

#### Scenario: Pro HDR photo
- **WHEN** a Pro user exports a 48 MP HEIC with an HDR gain map
- **THEN** the output is 48 MP, carries a gain map, and keeps the source's EXIF, GPS and date

### Requirement: Free photo exports are reduced in size

A Free photo export SHALL cap the longest side at 2048 pixels (smaller images keep their size) and SHALL be encoded with lossy quality no higher than 0.7 (a lossless output format choice is written as JPEG, or HEIC when the source is HEIC). For a typical 12 MP or larger camera photo the Free file SHALL be no more than 30% of the size of the Pro export of the same edit (a 10 MB Pro file exports at about 2 MB). Free exports SHALL keep the source's metadata (EXIF, GPS, date, device), with pixel-dimension fields matching the reduced image.

#### Scenario: 12 MP photo, free
- **WHEN** a free user exports a 4032×3024 photo whose Pro export is 10 MB
- **THEN** the output is 2048×1536 and at most 3 MB
- **AND** its EXIF camera, lens, date and GPS match the source

#### Scenario: Small photo, free
- **WHEN** a free user exports a 1600×1200 photo
- **THEN** the output stays 1600×1200 and is encoded at the free quality

### Requirement: Free exports carry no HDR

A Free photo export SHALL NOT carry an HDR gain map (Apple or ISO). A Free video export SHALL be standard dynamic range: an HDR source (HLG or PQ) SHALL be tone-mapped to SDR Rec. 709 so it still looks correct on SDR displays.

#### Scenario: HDR photo, free
- **WHEN** a free user exports a photo that has an HDR gain map
- **THEN** the output has no gain map auxiliary image

#### Scenario: HDR video, free
- **WHEN** a free user exports a Dolby Vision / HLG iPhone video
- **THEN** the output video track is 8-bit SDR with Rec. 709 colour, without blown highlights

### Requirement: Free video exports are capped at 1080p

A Free video export SHALL be H.264, no larger than 1920×1080 (or 1080×1920 portrait) preserving the aspect ratio, at the encoder's standard 1080p bitrate. Audio SHALL be kept. A Pro video export SHALL keep the source resolution and HDR as before this change. Both tiers SHALL keep the source's metadata (creation date, location, device).

#### Scenario: 4K video, free
- **WHEN** a free user exports a 3840×2160 HEVC HDR clip with audio
- **THEN** the output is 1920×1080 H.264 SDR with the audio track and the original creation date

#### Scenario: 4K video, Pro
- **WHEN** a Pro user exports the same clip
- **THEN** the output keeps 3840×2160 and HDR

### Requirement: Live Photos follow the photo and video rules

A Free Live Photo export SHALL apply the free photo rules to its still and the free video rules to its motion component.

#### Scenario: Live Photo, free
- **WHEN** a free user exports a Live Photo
- **THEN** the still is at most 2048 px on its longest side without a gain map, and the motion clip is SDR and at most 1080p

### Requirement: Content Credentials stay available on Free

Signing an export with C2PA Content Credentials, and preserving a source's existing credentials, SHALL work identically in both tiers. A signed Free export's manifest SHALL record that a visible watermark was applied.

#### Scenario: Free user signs a photo
- **WHEN** a free user with a creator name exports a photo with "Sign with Content Credentials" on
- **THEN** the exported file carries a valid C2PA manifest with the creator assertion
- **AND** the manifest states a visible watermark was applied

### Requirement: The live preview is never degraded by the tier

The editor's live preview SHALL look the same for free and Pro users: no reduced resolution, no Markepi mark. The tier SHALL apply only to exported files (and to the comparison sheet's illustration).

#### Scenario: Free user editing
- **WHEN** a free user adjusts a frame, text and logo
- **THEN** the preview shows no Markepi mark and renders at the usual preview quality
