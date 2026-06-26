# Requirements: Markepi - Current

**Current Milestone:** v2.2 Provenance & Authorship Protection
**Defined:** 2026-06-25
**Status:** Phase 19 executing

For milestone archive copy, see `.planning/milestones/v2.2-REQUIREMENTS.md`.

## v2.2 Requirements

### Provenance Classification (PROV)

- [x] **PROV-01**: Imported media is classified into one of five source states: Verified Camera Capture, Marked AI / AI-Edited, User-Declared, Unknown Provenance, or Suspected AI.
- [x] **PROV-02**: The app never treats "no AI watermark found" as proof that an image is camera-captured or non-AI.
- [x] **PROV-03**: Existing AI provenance signals are detected and preserved when present, including C2PA/JUMBF manifests, XMP/IPTC Digital Source Type values, EXIF/software markers, and known watermark/provenance metadata.
- [x] **PROV-04**: Existing source metadata, HDR gain maps, color profiles, and embedded provenance records survive export whenever the output format supports them.

### Professional Authorship Records (AUTH)

- [x] **AUTH-01**: Exports can include a signed C2PA Content Credentials manifest using open-source CAI/C2PA tooling under Apache-2.0 and MIT licenses, with Secure Enclave-backed iOS signing preferred and a local Keychain software fallback only where needed.
- [x] **AUTH-02**: C2PA actions honestly describe the export as a Markepi edit/export and include source-state evidence without overstating authenticity.
- [x] **AUTH-03**: IPTC rights metadata can be written or updated for creator name, copyright notice, credit line, usage terms, licensor URL/contact, and Digital Source Type where applicable.
- [x] **AUTH-04**: Existing C2PA manifests are preserved as ingredients or retained source manifests instead of being stripped or overwritten.

### User Controls (CTRL)

- [x] **CTRL-01**: Users can control visible watermark/frame disclosure, rights metadata, privacy level, C2PA signing identity, and creator-protection watermark behavior.
- [x] **CTRL-02**: Users cannot manually enable "Verified Camera Capture", "Captured by Camera", or "No AI Used" labels unless the analyzer has positive evidence that supports the claim.
- [x] **CTRL-03**: Unknown or user-declared sources can still receive copyright/protection watermarks, but the manifest and UI must say Unknown or User-Declared instead of Verified.
- [x] **CTRL-04**: Metadata privacy controls let the user strip sensitive fields such as GPS while preserving non-sensitive rights and provenance records.

### Invisible Creator Protection (IW)

- [ ] **IW-01**: Open-source invisible watermark options are evaluated before production use, prioritizing MIT or Apache-2.0 licensed implementations.
- [ ] **IW-02**: Adobe TrustMark (MIT) is evaluated as the primary open-source image watermark candidate because it is C2PA-listed and designed for imperceptible image payloads.
- [ ] **IW-03**: Microsoft InvisMark (MIT) is evaluated as a research candidate only, not a production default, because its public implementation is PyTorch/research-oriented and focused on AI-generated provenance.
- [ ] **IW-04**: Invisible marks are described as creator-protection or soft-binding marks, not as camera-authenticity marks.
- [ ] **IW-05**: No invisible watermark provider ships unless it runs inside the iOS app and Share Extension and passes visual-quality, HDR/color, metadata-preservation, memory, speed, and license-packaging gates on device.

### Verification & Receipts (VERIFY)

- [x] **VERIFY-01**: The export receipt shows source state, evidence, C2PA signing status and identity type, rights metadata, invisible watermark status, and privacy actions.
- [x] **VERIFY-02**: Tests prove unmarked images remain Unknown Provenance and cannot receive verified-camera claims.
- [x] **VERIFY-03**: Tests prove known AI-marked samples preserve their provenance through export instead of being relabeled or stripped.
- [x] **VERIFY-04**: The baseline works offline inside the iOS app and Share Extension; any optional network lookup is clearly labeled and disabled by default.

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| PROV-01 | Phase 19 | Complete |
| PROV-02 | Phase 19 | Complete |
| PROV-03 | Phase 19 | Complete |
| PROV-04 | Phase 19 | Complete |
| AUTH-01 | Phase 19 | Complete |
| AUTH-02 | Phase 19 | Complete |
| AUTH-03 | Phase 19 | Complete |
| AUTH-04 | Phase 19 | Complete |
| CTRL-01 | Phase 19 | Complete |
| CTRL-02 | Phase 19 | Complete |
| CTRL-03 | Phase 19 | Complete |
| CTRL-04 | Phase 19 | Complete |
| IW-01 | Phase 19 | Planned |
| IW-02 | Phase 19 | Planned |
| IW-03 | Phase 19 | Planned |
| IW-04 | Phase 19 | Planned |
| IW-05 | Phase 19 | Planned |
| VERIFY-01 | Phase 19 | Complete |
| VERIFY-02 | Phase 19 | Complete |
| VERIFY-03 | Phase 19 | Complete |
| VERIFY-04 | Phase 19 | Complete |

---
*Last updated: 2026-06-26 - Phase 19 plans 01-03 complete; invisible watermark requirements remain planned for 19-04*
