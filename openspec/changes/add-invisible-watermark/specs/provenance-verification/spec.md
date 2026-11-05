## Purpose

Gives users an in-app place to check a photo's Content Credentials and invisible watermark. It explains what the evidence does and does not prove, in honest wording, without any network lookup.

## ADDED Requirements

### Requirement: Verify screen entry points
The system SHALL provide a Verify screen reachable from Settings → Content Credentials ("Verify a Photo") and from the home screen. It SHALL be fully usable offline.

#### Scenario: Open from Settings
- **WHEN** the user taps "Verify a Photo" in the Content Credentials section of Settings
- **THEN** the Verify screen opens with options to pick a photo

#### Scenario: Open from home
- **WHEN** the user taps the Verify entry on the home screen
- **THEN** the same Verify screen opens

### Requirement: Photo input without metadata loss
The Verify screen SHALL accept a photo from the photo library or from Files. It SHALL inspect the original file bytes, never a re-encoded rendition, so an embedded C2PA manifest is not stripped before inspection. Picking a photo SHALL NOT start an export, change the photo, or save anything to the camera roll.

#### Scenario: Pick from Files
- **WHEN** the user picks a signed Markepi JPEG from Files
- **THEN** the screen reports the embedded C2PA manifest

#### Scenario: Pick from photo library
- **WHEN** the user picks a signed Markepi export saved in the photo library
- **THEN** the screen reports the embedded C2PA manifest, as it does for the same file picked from Files

#### Scenario: Non-photo input
- **WHEN** the user picks a video
- **THEN** the screen says video verification isn't supported and reports no watermark result

#### Scenario: Unreadable input
- **WHEN** the picked file cannot be decoded as an image
- **THEN** the screen shows an error and no verification result

### Requirement: Content Credentials report
When a photo has a C2PA manifest, the Verify screen SHALL show:
- whether the signature is intact;
- whether the file was modified after signing;
- whether the signer is on a trust list;
- the claim generator, signer display name, creator (if asserted) and signing date;
- the recorded actions;
- whether the photo carries earlier credentials as an ingredient.

A self-signed Markepi device identity SHALL be described as an unrecognized signer, never as a verified identity.

#### Scenario: Intact Markepi export
- **WHEN** the user verifies an untouched signed Markepi export
- **THEN** the screen shows the signature as intact and the file as unmodified since signing, with Markepi as the generator, the creator name, the date, and the signer marked as not on a trust list

#### Scenario: Modified after signing
- **WHEN** the user verifies a signed file whose pixels were changed after signing
- **THEN** the screen reports that the file was modified after it was signed

#### Scenario: Credentials from another app
- **WHEN** the user verifies a photo signed by another C2PA-capable app or camera
- **THEN** the screen reports that manifest's generator, signer and validation result

#### Scenario: No manifest
- **WHEN** the photo has no C2PA manifest
- **THEN** the screen states that no Content Credentials were found in the file

### Requirement: Invisible watermark report
The Verify screen SHALL attempt to decode a Markepi invisible watermark from every photo. It SHALL report a watermark only when the namespace and CRC validate. When a valid watermark is found, the screen SHALL show the asset ID and say whether it matches an export in this device's registry.

#### Scenario: Watermark found and registered
- **WHEN** the user verifies a WhatsApp-compressed copy of an export made on this device
- **THEN** the screen reports a Markepi invisible watermark, a matching export on this device with its date and thumbnail, and the fingerprint similarity

#### Scenario: Watermark found, not in registry
- **WHEN** a valid watermark is decoded whose ID is not in this device's registry
- **THEN** the screen reports that a Markepi watermark is present but no matching export exists on this device, and draws no conclusion about who made it

#### Scenario: Invalid decode
- **WHEN** the decoder reports a watermark but the CRC fails
- **THEN** the screen reports that no Markepi watermark was found

### Requirement: Fingerprint confirmation
A registry match SHALL be confirmed only when the photo's perceptual fingerprint is within the calibrated distance of the registered export's fingerprint. When the ID matches but the fingerprint does not, the screen SHALL say the watermark ID matches but the image content differs.

#### Scenario: Re-encoded copy confirms
- **WHEN** a registered export is downscaled and JPEG-compressed, then verified
- **THEN** the fingerprint is within threshold and the match is reported as confirmed

#### Scenario: Copied ID on different content
- **WHEN** a photo carries a registered ID but its content differs from the registered export
- **THEN** the screen reports that the watermark ID matches but the image content does not, and does not confirm a match

### Requirement: Honest verdict wording
The Verify screen SHALL summarise its findings with a single headline drawn only from this set:
- "Signed by Markepi — unmodified since signing"
- "Signed — modified after signing"
- "Signed by <generator>"
- "Copy of a photo you signed on <date>" (watermark plus confirmed fingerprint match, with no intact manifest)
- "Markepi watermark found — original not on this device"
- "Watermark matches, but the image content differs"
- "No Content Credentials found"

The screen SHALL NOT use the words "verified", "authentic", "fake" or "proof of authorship" for any result. It SHALL NOT imply that a photo with no evidence is manipulated.

#### Scenario: Stripped copy of own export
- **WHEN** a WhatsApp copy of this device's signed export, with its manifest stripped, is verified
- **THEN** the headline reads "Copy of a photo you signed on <date>"

#### Scenario: No evidence
- **WHEN** a photo has no manifest and no valid watermark
- **THEN** the headline reads "No Content Credentials found" and nothing suggests the photo is fake

### Requirement: Registered manifest detail
When a confirmed registry match exists and the photo itself has no intact manifest, the Verify screen SHALL let the user view the registered export's signed manifest details: creator, date, actions and signer. They SHALL be labelled as coming from this device's record of the original export.

#### Scenario: View original credentials
- **WHEN** the user taps the matched export on a stripped copy's result
- **THEN** the original export's manifest details are shown, labelled as recorded on this device

### Requirement: Read-only and private
Verification SHALL NOT modify the inspected file, write to the photo library, add registry entries, or make network requests.

#### Scenario: Offline verification
- **WHEN** the user verifies a photo with networking disabled
- **THEN** the full result is shown and no network request is made

#### Scenario: Registry unchanged
- **WHEN** the user verifies any photo
- **THEN** the registry's entry count is unchanged
