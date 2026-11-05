## Why

Markepi signs photo exports with C2PA Content Credentials, but the manifest lives in the file's metadata, and WhatsApp, Instagram, screenshots and most re-uploads strip it. Once that happens, nothing ties the copy back to the signed original. The softbinding probe (`tools/softbinding-probe/HANDOFF.md`, 2026-11-04) showed that an invisible TrustMark P watermark survives WhatsApp-class compression (1080–1600 px, JPEG q55–q80), screenshots and light crops. It also showed the watermark runs on-device within a bounded memory budget. Users also have nowhere in the app to check a photo's credentials today, so even an intact manifest can't be inspected without a third-party verifier.

## What Changes

- **Invisible watermark on signed photo exports.** When a photo export is signed with Content Credentials, Markepi embeds a 61-bit invisible ID in the pixels before writing the file. The ID uses TrustMark P, BCH_5, and a namespace byte, CRC-16 and epoch. A user-facing toggle defaults to on.
- **C2PA soft binding.** The signed manifest gains a `c2pa.soft-binding` assertion (`alg: com.adobe.trustmark.P`) and a `c2pa.watermarked` action. The watermark is applied before signing, so the hard binding covers the watermarked pixels.
- **Perceptual fingerprint.** A PDQ hash of the final pixels is computed for every watermarked export. A watermark ID alone is copyable, so a match is only trusted when the fingerprint also matches.
- **On-device credentials registry.** Each watermarked export stores ID → {signed manifest record, PDQ hash, created date, small thumbnail} in local app storage. No network, no upload, and the user can clear it.
- **Post-sign self-check.** After signing, the export re-decodes the ID from the signed file and checks it. The export receipt reports the result honestly: "Invisible watermark: embedded / could not be verified / not applied".
- **New Verify screen.** A new screen inspects any photo from the photo library or Files. It reports, in honest wording:
  - the C2PA manifest status: signer, creator, date, actions, ingredients, intact or modified, trusted or untrusted signer;
  - the invisible watermark: found, valid or invalid;
  - a registry match plus fingerprint similarity when the ID belongs to one of this device's exports.
  It never says "verified" or "fake" on watermark evidence alone. Entry points are Settings → Content Credentials → "Verify a Photo" and the home screen.
- **HDR-safe compositing.** The residual is applied to the SDR base only. The gain map is carried through untouched and Pro HDR exports keep it.
- **Not in the Share Extension.** The extension stays a handoff bridge. All ML runs in the app, so models never load in the extension's memory budget.
- **Out of scope:** video watermarking, a cloud resolver or public lookup service, CAI trust-list enrolment, the visible QR channel, and verifying photos signed on another device beyond what their embedded manifest says.

## Capabilities

### New Capabilities
- `invisible-watermark`: embedding, payload format, soft-binding assertion, fingerprinting, the local registry, and the export-time self-check for invisible watermarks on signed photo exports.
- `provenance-verification`: the in-app Verify screen. It covers inputs, C2PA manifest inspection, watermark decoding, registry and fingerprint matching, and the honest result wording.

### Modified Capabilities
<!-- None: C2PA signing has no main spec yet (it predates OpenSpec, in .planning phase 19); photo-frames behaviour is unchanged. -->

## Impact

- **MarkepiCore**
  - `Provenance/`: a new watermark provider protocol and TrustMark implementation, plus the payload codec, PDQ and registry.
  - `Engine/WatermarkEngine.swift`: a new step between render and `ImageWriter.write`, and population of `invisibleWatermarkPayloadID`.
  - `C2PAProvenanceClient.buildManifestJSON`: the soft-binding assertion and the watermarked action.
  - `Models/ExportReceipt`: already has `invisibleWatermarkApplied`, which gains a status.
- **App**
  - A new Verify view and its entry points in `ContentView.swift` (Settings Content Credentials section, home).
  - A toggle in `ProvenanceControlsView`.
  - CoreML models (`encoder_P` fp32 17.3 MB, `decoder_P` int8 23.9 MB, about 41 MB) in the app bundle. They need manual `project.pbxproj` resource references because the project uses classic file refs.
- **App size** grows by about 41 MB. The Share Extension binary does not grow.
- **Licences:** TrustMark code and weights are MIT, and PDQ is BSD. Both notices go in the in-app Acknowledgements.
- **Privacy:** fully on-device, so the no-network promise holds. Registry IDs are random per asset with no user or device bits.
- **Copy:** App Store and in-app wording must not claim "proof of authorship" (the identity is self-signed) or video signing.
