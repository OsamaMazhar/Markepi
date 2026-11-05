## Purpose

Embeds an imperceptible, compression-robust identifier in Markepi's signed photo exports so a copy that has lost its C2PA metadata (messaging apps, screenshots, re-uploads) can still be linked back to the signed original on the device that made it.

## ADDED Requirements

### Requirement: Invisible watermark on signed photo exports
The system SHALL embed an invisible watermark in a photo export whenever that export is signed with Content Credentials at the user's request and the invisible-watermark setting is on. The system SHALL NOT embed it in live previews, thumbnails, videos, unsigned exports, or exports signed only to preserve a source's credentials.

#### Scenario: Signed photo export gets a watermark
- **WHEN** the user exports a JPEG or HEIC photo with Content Credentials signing on and the invisible-watermark setting on
- **THEN** the exported file's pixels carry a decodable Markepi watermark ID

#### Scenario: Unsigned export is untouched
- **WHEN** the user exports a photo with Content Credentials signing off
- **THEN** no invisible watermark is embedded and the export's pixels are identical to an export from a build without this feature

#### Scenario: Setting off
- **WHEN** Content Credentials signing is on but the invisible-watermark setting is off
- **THEN** the export is signed without a watermark and without a soft-binding assertion

#### Scenario: Previews are never watermarked
- **WHEN** the editor renders a live preview or thumbnail
- **THEN** no watermark is embedded

#### Scenario: Videos are not watermarked
- **WHEN** the user exports a video
- **THEN** no invisible watermark is embedded and the receipt does not claim one

### Requirement: Invisible-watermark setting
The system SHALL provide a user-visible toggle for the invisible watermark next to the Content Credentials controls. It SHALL default to on, persist across launches, and be available exactly when Content Credentials signing is available.

#### Scenario: Default state
- **WHEN** a user enables Content Credentials signing for the first time
- **THEN** the invisible-watermark toggle is shown and is on

#### Scenario: Persistence
- **WHEN** the user turns the toggle off and relaunches the app
- **THEN** the toggle is still off

### Requirement: Imperceptible quality
The watermark SHALL NOT be visible at normal viewing. Against the same export without it, the watermarked export SHALL measure at least 46 dB PSNR. The watermark SHALL NOT alter colour profile, EXIF, GPS, IPTC, or other preserved metadata.

#### Scenario: Quality threshold
- **WHEN** a 12 MP reference photo is exported with and without the watermark
- **THEN** PSNR between the two is ≥ 46 dB

#### Scenario: Metadata preserved
- **WHEN** a watermarked export is compared with the same unwatermarked export using exiftool
- **THEN** every metadata field is identical

### Requirement: HDR gain map preserved
The system SHALL apply the watermark to the SDR base image only. An HDR source's gain map SHALL be carried into the export unchanged, and the export SHALL still render as HDR.

#### Scenario: HDR export keeps its gain map
- **WHEN** an HDR HEIC or JPEG photo with a gain map is exported with the watermark on
- **THEN** the output contains the gain map auxiliary image, displays as HDR, and the watermark decodes from the SDR base

### Requirement: Robustness to sharing
The watermark ID SHALL decode correctly after the export is resized to 1080–1600 px on the long edge and re-encoded as JPEG at quality 55–80. It SHALL also decode after a phone screenshot and after a centre-preserving crop of up to 10 % per side. The system MAY fail to decode after crops above 10 % or JPEG quality below 50, and the specification does not require decoding there.

#### Scenario: WhatsApp-class re-encode
- **WHEN** a watermarked 12 MP export is downscaled to 1600 px and saved as JPEG q60
- **THEN** decoding returns the original ID with a valid CRC

#### Scenario: Large source
- **WHEN** a watermarked 48 MP export is downscaled to 1600 px and saved as JPEG q60
- **THEN** decoding returns the original ID with a valid CRC

#### Scenario: Screenshot
- **WHEN** a watermarked export is displayed full-screen and screenshotted on an iPhone
- **THEN** decoding the screenshot returns the original ID with a valid CRC

### Requirement: Payload format
The watermark payload SHALL be 61 bits:
- an 8-bit namespace marking it as Markepi's;
- a 32-bit asset ID;
- a 16-bit CRC over the namespace and ID;
- a 5-bit epoch.

A decoded payload SHALL count as a Markepi watermark only when the namespace matches and the CRC validates. The asset ID SHALL be random per export, contain no user, device or account information, and be unique within the local registry.

#### Scenario: Garbage decode rejected
- **WHEN** the decoder reports a watermark present but the CRC does not validate
- **THEN** the system treats the image as having no Markepi watermark

#### Scenario: Foreign watermark rejected
- **WHEN** a TrustMark payload from another product is decoded
- **THEN** the namespace check fails and the system reports no Markepi watermark

#### Scenario: ID uniqueness
- **WHEN** a newly generated ID already exists in the local registry
- **THEN** a new ID is generated before embedding

### Requirement: Soft-binding assertion and signing order
A watermarked export SHALL be signed after the watermark is embedded, so the signature's hard binding covers the watermarked pixels. Its manifest SHALL include:
- a `c2pa.soft-binding` assertion with algorithm `com.adobe.trustmark.P` and the encoded payload;
- a `c2pa.watermarked` action in `c2pa.actions`;
- the payload ID in Markepi's provenance assertion.

#### Scenario: Manifest declares the watermark
- **WHEN** a watermarked export's manifest is read with a C2PA reader
- **THEN** it contains the soft-binding assertion with `alg` `com.adobe.trustmark.P`, a `c2pa.watermarked` action, and the hard binding validates

#### Scenario: Unwatermarked manifest unchanged
- **WHEN** an export is signed without the watermark
- **THEN** its manifest contains no soft-binding assertion and no `c2pa.watermarked` action

### Requirement: Export-time self-check and receipt
After signing, the system SHALL decode the watermark from the final signed file and compare it with the embedded ID. The export receipt SHALL report exactly one of three outcomes: "embedded", "embedded but could not be verified", or "not applied". A failed self-check SHALL NOT block the export.

#### Scenario: Successful self-check
- **WHEN** the signed file decodes to the embedded ID
- **THEN** the receipt reports the invisible watermark as embedded

#### Scenario: Self-check fails
- **WHEN** the signed file does not decode to the embedded ID
- **THEN** the export still completes, the receipt reports "embedded but could not be verified", and the registry entry is still stored

### Requirement: Local credentials registry
For each watermarked export the system SHALL store on the device:
- the asset ID;
- a record of the signed C2PA manifest (as read back from the final file);
- a perceptual fingerprint of the final pixels;
- the export date;
- a small thumbnail.

The registry SHALL never leave the device. Users SHALL be able to see how many entries exist and clear the registry. Clearing it SHALL NOT affect already-exported files.

#### Scenario: Entry recorded
- **WHEN** a watermarked export completes
- **THEN** the registry contains an entry for its ID with manifest, fingerprint, date and thumbnail

#### Scenario: No network
- **WHEN** a watermarked export completes with networking disabled
- **THEN** the export and registry write succeed and no network request is made

#### Scenario: Clear registry
- **WHEN** the user clears the registry in Settings
- **THEN** all entries are deleted and later verification of old copies reports no matching export on this device

### Requirement: Share Extension memory safety
The Share Extension SHALL NOT load watermark models or run watermark inference. It SHALL keep handing media to the app, which performs the watermarked export.

#### Scenario: Share Extension path
- **WHEN** a photo is shared into Markepi via the share sheet
- **THEN** the extension hands it to the app without loading watermark models, and a signed export from the app carries the watermark

### Requirement: Bounded memory and time
Embedding SHALL keep extra peak memory at or below 250 MB for photos up to 48 MP on a 4 GB device. Photos above 48 MP SHALL use the same bounded path. Embedding a 12 MP photo SHALL add no more than 1.5 s to an export on an A13 or newer device.

#### Scenario: 48 MP on a 4 GB device
- **WHEN** a 48 MP photo is exported with the watermark on a 4 GB iPhone
- **THEN** the export completes without a memory termination and the extra peak memory is ≤ 250 MB

#### Scenario: 12 MP time budget
- **WHEN** a 12 MP photo is exported with the watermark on an A13-class device
- **THEN** the watermark step adds ≤ 1.5 s
