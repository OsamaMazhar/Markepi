# Phase 19: Provenance & Authorship Protection - Discussion Log

**Started:** 2026-06-25

## 2026-06-25 - Initial Product Direction

### User Request

The user asked for the latest digital watermarking methods to support photographers and comply with EU/worldwide AI regulation expectations in 2026.

### Clarification

The target user is a photographer importing photos from camera or share sheet. If an imported image was created with GenAI and already contains a watermark/provenance signal, Markepi should preserve that signal. The app should protect photographers without falsely claiming that every image is camera-authentic.

### Key Decision

Separate:

- **provenance** - what evidence says about the source,
- **authorship rights** - what the photographer/exporter can assert,
- **invisible watermarking** - a resilience layer, not proof of authenticity.

### User-Control Boundary

The user can control visible watermarks, rights metadata, privacy, C2PA signing identity, and creator-protection watermark settings.

The app controls whether verified-camera language is allowed. An unmarked image from an open-source/custom GenAI model remains Unknown Provenance unless the user declares it.

### Tooling Direction

Open-source MIT/Apache-compatible tools are preferred:

- `contentauth/c2pa-swift` - C2PA on iOS; Apache-2.0/MIT
- `contentauth/c2pa-rs` - underlying C2PA engine; Apache-2.0/MIT
- `adobe/trustmark` - primary invisible watermark evaluation candidate; MIT
- `microsoft/InvisMark` - research-only invisible watermark candidate; MIT

Commercial systems such as Digimarc and Imatag are professional references and possible future integrations, but not default v2.2 dependencies.

## Deferred Questions

- Which signing identity UX is acceptable for v2.2: local software certificate first, Secure Enclave first, or both?
- Does c2pa-swift integrate cleanly into the existing Xcode project and package layout, or should the first implementation use a protocol adapter with a disabled concrete client?
- Should invisible watermarking ship in v2.2 if TrustMark passes gates, or should v2.2 ship C2PA/IPTC first and keep the invisible mark as a research artifact?
- Which export receipt moment is best: pre-share confirmation, post-export detail sheet, or both?

## 2026-06-25 - iOS Implementation Constraint Confirmed

The user confirmed the target should be implementable fully in iOS.

Planning response:

- C2PA/IPTC/provenance analyzer/receipt work is treated as shippable iOS scope.
- Invisible watermarking is accepted only if it can run locally in the iOS app and Share Extension.
- Desktop scripts, Python/PyTorch flows, and cloud services can support evaluation, but they cannot be required for production export.
- If TrustMark cannot be packaged cleanly for iOS, v2.2 should still ship the C2PA/IPTC protection backbone and leave invisible watermarking disabled/deferred.

## 2026-06-25 - C2PA Signing Identity and App Name Locked

The user selected discussion area 1, C2PA signing identity, and clarified that the app/product name is **Markepi**, not Watermark.

Locked decisions:

- Product-facing name is Markepi in receipts, manifests, and UI text.
- Existing implementation identifiers such as `WatermarkCore`, `WatermarkEngine`, and `WatermarkConfiguration` can remain code/package names unless a separate rename phase is created.
- C2PA signing is Secure Enclave first on real iOS devices.
- A local Keychain software signing identity is allowed only for simulator/development or unavailable Secure Enclave hardware.
- Default export must not require cloud signing.
- Receipt wording should say "Markepi device signing identity" and must not imply verified legal/person identity.

---
*Last updated: 2026-06-25*
