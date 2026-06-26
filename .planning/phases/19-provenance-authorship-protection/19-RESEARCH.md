# Phase 19: Provenance & Authorship Protection - Research

**Researched:** 2026-06-25
**Domain:** C2PA / IPTC / invisible digital watermarking / iOS media metadata preservation
**Confidence:** MEDIUM-HIGH

## Summary

The safest 2026 architecture is a layered provenance system:

1. **Preserve first** - keep source EXIF, XMP/IPTC, C2PA/JUMBF, HDR gain maps, color profiles, and any existing AI provenance where the output format supports them.
2. **Classify conservatively** - report source state from evidence, never from the absence of a watermark.
3. **Add signed professional records** - use C2PA Content Credentials and IPTC rights fields for authorship, licensing, export actions, and user declarations.
4. **Add invisible creator protection only behind a gate** - evaluate MIT/Apache-compatible tools before shipping, and describe the mark as creator protection or soft binding, not proof of camera capture.

The best open-source production candidate for the professional record layer is `contentauth/c2pa-swift` (Apache-2.0 and MIT). The best open-source invisible image watermark candidate to evaluate is Adobe TrustMark (MIT), but current upstream TrustMark is not a drop-in iOS app/share-extension dependency. Microsoft InvisMark (MIT) is worth studying because it is C2PA-listed, but its current public shape is research/PyTorch-oriented and should not be treated as a default iOS dependency.

## iOS Feasibility Conclusion

The production backbone is implementable in iOS:

- **Source analyzer:** ImageIO, AVFoundation, and local metadata parsing are all app/extension-safe patterns.
- **Metadata preservation:** The existing `CGImageSource` -> `CIImage` -> `CGImageDestination` photo path and AVFoundation video path are the correct iOS foundations.
- **C2PA:** `contentauth/c2pa-swift` is the first-choice iOS integration path. If target/package integration blocks, keep the adapter and disable signing until resolved rather than creating invalid C2PA output.
- **IPTC/XMP rights fields:** ImageIO metadata dictionaries are practical for still-image exports; video/container support must be verified per format.
- **UI and receipts:** Shared SwiftUI in WatermarkCore can support the main app and Share Extension.
- **Offline privacy model:** App Group storage, local signing, temp-file export, and no-network defaults fit the existing architecture.

The conditional part is invisible watermarking:

- **TrustMark:** Feasible to evaluate for iOS, but verified upstream status is not production iOS-ready as-is. Python requires a Python/PyTorch-style workflow, the JavaScript example is decode-only/browser-oriented, and the Rust implementation depends on an ONNX runtime whose documented platform list does not establish iOS app/share-extension support. TrustMark must prove a local iOS runtime path through Swift/Rust FFI, ONNX Runtime Mobile, Core ML, or another app-safe runtime with acceptable size and memory before it can ship.
- **InvisMark:** Research-only until it has a realistic iOS packaging path. Its public workflow depends on Python/PyTorch, CUDA-oriented packages, notebook/demo usage, and external model weights, so it is not acceptable for production Markepi.
- **Commercial providers:** Future options only if a native iOS SDK and acceptable license terms exist.

## 2026-06-25 iOS Tool Verification Matrix

| Tool / layer | iOS status | Phase 19 decision |
|--------------|------------|-------------------|
| Apple ImageIO / Core Image / AVFoundation / CryptoKit / Security | Yes. Native Apple iOS frameworks suitable for app and Share Extension use, subject to normal extension memory/time limits. | Use for metadata preservation, rendering, media export, local keys, and receipts. |
| `contentauth/c2pa-swift` | Yes. Provides iOS/macOS Swift Package/XCFramework support, native Swift APIs for reading/verifying/signing C2PA manifests, stream/builder APIs, and Secure Enclave-backed signing on iOS devices. Runtime support listed as iOS 16+, so Markepi's iOS 18 target is compatible. | Production C2PA adapter candidate in Plan 19-02. |
| `contentauth/c2pa-rs` | Yes indirectly. It is the Rust core used by C2PA Swift and exposes a C API, but direct Rust embedding is not the v2.2 plan. | Consume through C2PA Swift unless the adapter spike proves otherwise. |
| C2PA soft-binding algorithm list | Reference only. It lists algorithm identifiers such as Adobe TrustMark and Microsoft InvisMark, but it is not an SDK and does not prove iOS runtime feasibility. | Use only for interoperability naming and evaluation references. |
| Adobe TrustMark | Conditional / not production iOS-ready as-is. MIT licensed and C2PA-listed, but current upstream packaging is Python, browser JS decode, and Rust+ONNX with no confirmed iOS target in the upstream docs. | Evaluate in Plan 19-04. Ship only if an iOS-native runtime is proven and all quality/HDR/metadata/performance gates pass. |
| Microsoft InvisMark | No for production iOS as-is. MIT licensed and C2PA-listed, but public code is research-oriented with Python/PyTorch/CUDA-style dependencies and external model weights. | Research note only. Do not ship as v2.2 dependency. |
| Digimarc / Imatag / NAGRA / other vendors | Possible only if a vendor provides an iOS SDK and acceptable commercial terms. Not MIT/Apache defaults. | Future paid integrations, not v2.2 defaults. |

## Regulatory Read

### EU AI Act

Article 50 requires providers of AI systems that generate synthetic audio, image, video, or text content to ensure outputs are marked in machine-readable format and detectable as artificially generated or manipulated. Recital 133 explicitly mentions watermarking, metadata identification, cryptographic methods, logging, and fingerprints as possible technical measures.

Product implication: Markepi should preserve existing AI marks and metadata. It should not create false authenticity claims. When Markepi exports an AI-marked or unknown source, it can add creator rights metadata, but the source state must remain honest.

### China AI Labeling Measures

China's AI labeling rules, effective 2025-09-01, require explicit and implicit labels for AI-generated content in relevant contexts and encourage techniques such as metadata and digital watermarking.

Product implication: preservation is important. Stripping an existing AI label or implicit watermark during an export could make downstream compliance worse.

### Worldwide Professional Practice

C2PA Content Credentials have become the strongest interoperability layer for provenance. Invisible watermarking remains valuable for resilience when metadata is stripped, but it is fragmented across vendor and research implementations. Professional systems increasingly combine:

- visible disclosure where appropriate,
- C2PA signed manifests,
- IPTC/XMP rights metadata,
- optional invisible watermark or fingerprint for soft binding,
- receipt/verification UI that explains the evidence.

## Open-Source Tooling Audit

| Tool | License | Role | Fit for Markepi | Decision |
|------|---------|------|-------------------|----------|
| `contentauth/c2pa-swift` | Apache-2.0 and MIT | Swift/iOS APIs for reading, verifying, building, and signing C2PA manifests | Strongest production candidate for C2PA on iOS; supports native Swift APIs, stream APIs, builder APIs, and Secure Enclave-oriented signing patterns | Use first for C2PA adapter |
| `contentauth/c2pa-rs` | Apache-2.0 and MIT | Core C2PA implementation used by CAI tooling | Mature underlying implementation; best consumed through Swift bindings unless the app needs lower-level control | Indirect dependency |
| `adobe/trustmark` | MIT | Invisible image watermark implementation and C2PA soft-binding example | Primary open-source invisible watermark candidate, but not verified as a drop-in iOS dependency; C2PA algorithm list includes Adobe TrustMark entries; payload and ECC design fit creator/export IDs | Evaluate in harness, then decide; disabled unless an iOS runtime passes gates |
| `microsoft/InvisMark` | MIT | Invisible robust watermarking for AI-generated image provenance | Interesting C2PA-listed research; public code depends on Python/PyTorch/CUDA-oriented packages and external model weights, so iOS app integration risk is high | Research-only |
| C2PA soft-binding algorithm list | Spec data, not app code | Interoperability list for watermark/fingerprint algorithms | Authoritative list for algorithms used to find stripped manifests | Reference only |

### Commercial / Professional Non-Open-Source Tools

| Vendor | Role | Why not default in v2.2 |
|--------|------|------------------------|
| Digimarc | Commercial C2PA-linked watermark/provenance system | Professional and likely robust, but not MIT/Apache open source and may require licensing/service terms |
| Imatag | Commercial invisible image watermarking for rights/protection | Professional claims around robustness, but not open-source and likely requires vendor relationship |
| NAGRA / other anti-piracy watermark vendors | Commercial forensic watermarking | Usually enterprise media/broadcast oriented, not a default iOS photographer workflow |

## Recommended Product Architecture

### 1. Source Provenance Analyzer

Inputs:

- C2PA/JUMBF manifests
- XMP/IPTC metadata including Digital Source Type
- EXIF camera/software fields
- file container metadata
- existing watermark/provenance metadata if discoverable
- optional user declaration
- optional detector hints in the future

Output:

```swift
enum ProvenanceState: Codable, Equatable {
    case verifiedCameraCapture
    case markedAI
    case userDeclared
    case unknown
    case suspectedAI
}
```

The analyzer emits `SourceProvenanceReport` with evidence items, confidence, warnings, and locked/unlocked claim capabilities. It must not return `verifiedCameraCapture` from editable EXIF alone.

### 2. C2PA/IPTC Rights Layer

Use C2PA to record:

- Markepi app version and export action
- source ingredient relationship
- source-state evidence summary
- visible watermark/frame action
- privacy action, such as GPS stripped
- user declaration as a declaration, not a verified fact
- optional invisible watermark payload ID or soft-binding reference

Use IPTC/XMP to record:

- creator,
- copyright,
- credit,
- usage terms,
- licensor URL/contact,
- Digital Source Type.

### 3. Invisible Watermark Provider Boundary

Define a provider protocol before shipping any model:

```swift
protocol InvisibleWatermarkProvider {
    var providerID: String { get }
    var licenseNotice: String { get }
    func embed(payload: Data, into source: URL, options: InvisibleWatermarkOptions) async throws -> InvisibleWatermarkResult
    func detect(from source: URL) async throws -> InvisibleWatermarkDetection
}
```

This keeps TrustMark/InvisMark evaluation away from the main rendering engine until quality and packaging pass.

### 4. Receipt UI

The receipt should show:

- source state,
- evidence list,
- preserved source provenance,
- rights metadata added,
- C2PA signing status,
- invisible watermark provider/status,
- privacy changes,
- warnings for Unknown or Suspected AI.

## Identity Assurance Tiers (creator name vs verified identity)

A C2PA signature proves *integrity and binding* ("this exact asset + manifest was sealed by this key and has not changed since"). It does **not**, by itself, prove the signer's real-world legal identity. The owner's name can still be attached — but what that name *means* falls into three tiers. Markepi v2.2 ships **Tier 1 only**; Tier 2 and Tier 3 are documented here so the product wording and roadmap stay honest.

### Tier 1 — Sealed declaration (SHIPS in v2.2)

- The owner's name is written into both the IPTC creator/copyright fields **and** a C2PA `stds.schema-org.CreativeWork` author assertion inside the signed manifest.
- Once the manifest is signed (Markepi device identity, per D-24), the name is **cryptographically bound and tamper-evident** — it cannot be altered without breaking the signature.
- Assurance level: the *binding and integrity* are proven; the *truth of the name* rests on the owner's own assertion. This is exactly how Lightroom/Photoshop Content Credentials behave by default.
- Honest wording everywhere (receipt, popup, manifest display): "Creator (stated by owner): <name> — sealed in this export." Never "Verified: <name>."
- Example manifest assertion:
  ```json
  {
    "label": "stds.schema-org.CreativeWork",
    "data": {
      "@context": "https://schema.org",
      "@type": "CreativeWork",
      "author": [{ "@type": "Person", "name": "Jane Doe" }],
      "copyrightNotice": "© 2026 Jane Doe"
    }
  }
  ```

### Tier 2 — Verified signer identity via CA-issued certificate (FUTURE)

- Instead of a self-signed device certificate, the owner signs with a certificate **issued to them by a Certificate Authority** (Subject e.g. `CN=Jane Doe Photography`). The named identity then becomes part of the verifiable trust chain a verifier checks.
- Requires a real PKI step (obtaining/managing a CA-issued signing cert, possibly paid). This is what agencies/newsrooms do.
- Deferred: out of v2.2 scope. D-24 deliberately keeps Markepi at a *device* identity and forbids implying legal identity until/unless this tier is implemented.

### Tier 3 — Third-party identity attestation / CAWG identity assertion (FUTURE)

- C2PA's Creator Assertions Working Group (CAWG) defines an **identity assertion** where an external identity provider or a verifiable credential vouches that the signer really is the named person/org, binding a verified identity into the manifest.
- This is the only tier that genuinely *proves* "a specific named person."
- Requires an identity-provider integration and network access → falls under the phase's deferred cloud/identity items. Not in v2.2.

**Product rule:** the signing UI must make Tier 1's meaning explicit at the moment of signing (see D-25..D-27) so users are never led to believe a sealed declaration is a verified legal identity.

## Best Approach for the User's Core Question

The best approach is **not** to choose one invisible watermark and call it authenticity. It is:

1. Preserve existing GenAI/provenance watermarks and metadata.
2. Add C2PA signed export records and IPTC rights metadata as the default professional protection.
3. Let photographers add an invisible creator-protection mark if the selected provider passes quality gates.
4. Block unsupported verified-camera claims.
5. For unmarked custom-model AI images, use Unknown Provenance unless the user declares the source.

This gives photographers protection without creating legal or trust risk.

## User-Controlled vs App-Controlled

### User Can Control

- visible watermark text/logo/frame,
- copyright and creator details,
- credit line and usage terms,
- licensor/contact URL,
- whether to include a C2PA manifest,
- which signing identity to use,
- whether to add invisible creator protection,
- payload privacy level, such as opaque export ID instead of personal data,
- whether to strip sensitive metadata such as GPS,
- user declaration of source type.

### App Must Control

- whether "Verified Camera Capture" is available,
- whether "No AI Used" language is allowed,
- whether a source is marked AI from stronger evidence,
- preservation of existing AI provenance,
- receipt wording that distinguishes verified evidence from user declarations,
- warnings for Unknown or Suspected AI.

## iOS Implementation Notes

- Keep image processing in the `CGImageSource` -> `CIImage` -> `CGImageDestination` path. Avoid `UIImage` for the export pipeline because it can strip metadata/HDR.
- Attach C2PA after the image/video render step, or use stream APIs if the selected C2PA library requires source/destination streams.
- For videos, confirm support by container and API. If signing or C2PA manifest attachment is limited, record the limitation in the receipt.
- Do not make network calls during import/export. Optional C2PA repository fetch can be a future explicit action.
- Sign locally. Prefer Secure Enclave-backed identities on real iOS devices; provide a local Keychain software signing fallback only for simulator/development or unavailable hardware.
- In receipts and manifest display fields, call the signer a "Markepi device signing identity"; do not imply verified legal/person identity.
- Store user rights metadata in App Group configuration so the Share Extension can use it.
- Do not ship any invisible watermark implementation that requires a desktop helper, Python runtime, PyTorch runtime, or mandatory network verification.

## Testing Strategy

| Test | Purpose |
|------|---------|
| Unknown source fixture | Proves absence of AI marks remains Unknown, not Verified |
| Marked AI fixture | Proves C2PA/IPTC AI markers classify as Marked AI and survive export |
| User declaration fixture | Proves declaration is recorded as declaration, not verification |
| EXIF camera-only fixture | Proves editable EXIF alone does not unlock verified-camera wording |
| GPS strip fixture | Proves privacy profile removes GPS while keeping rights/provenance fields |
| C2PA signing fixture | Proves manifest is signed and readable after export |
| HDR/gain map fixture | Proves provenance work does not regress HDR preservation |
| TrustMark harness fixture | Measures roundtrip detectability, visual difference, metadata/HDR preservation, runtime, and memory |

## Threats and Mitigations

| Threat | Risk | Mitigation |
|--------|------|------------|
| False authenticity claims | Legal/trust damage | Gate verified language behind positive evidence and show evidence in receipt |
| Stripping AI provenance | Regulatory/compliance harm | Preserve C2PA/JUMBF/XMP/IPTC and include source as ingredient |
| Invisible watermark robustness overstated | User relies on weak protection | Present invisible marks as protection/soft binding and publish realistic limitations |
| PII leakage | Creator contact/GPS may reveal sensitive info | Privacy profiles and payload minimization |
| Vendor lock-in | Commercial watermarking could lock product | MIT/Apache default tooling; vendors only as optional future |
| Model/package bloat | TrustMark/InvisMark may add large assets | Harness gate before app target integration |

## Sources

- C2PA 2.4 Soft Binding API: https://spec.c2pa.org/specifications/specifications/2.4/softbinding/Decoupled.html
- C2PA soft-binding algorithm list: https://spec.c2pa.org/softbinding-alg-list/softbinding-algorithm-list.json
- C2PA Swift docs: https://opensource.contentauthenticity.org/docs/c2pa-ios/
- C2PA Swift repository: https://github.com/contentauth/c2pa-swift
- C2PA Rust repository: https://github.com/contentauth/c2pa-rs
- Adobe TrustMark: https://github.com/adobe/trustmark
- Microsoft InvisMark: https://github.com/microsoft/InvisMark
- IPTC Digital Source Type: https://cv.iptc.org/newscodes/digitalsourcetype/
- EU AI Act Article 50: https://artificialintelligenceact.eu/article/50/
- EU AI Act Recital 133: https://artificialintelligenceact.eu/recital/133/
- China CAC AI labeling measures: https://www.cac.gov.cn/2025-03/14/c_1743654684782215.htm

---
*Research gathered: 2026-06-25*
