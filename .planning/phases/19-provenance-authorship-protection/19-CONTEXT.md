# Phase 19: Provenance & Authorship Protection - Context

**Gathered:** 2026-06-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement the app's professional provenance and authorship-protection layer.

This phase supports photographers importing camera-captured media while respecting the reality that some media may be generated or edited by AI. If the source already contains GenAI provenance or an invisible watermark, Markepi preserves it. If the source does not contain any marker, Markepi does **not** infer that the image is human-shot or non-AI.

The phase separates three ideas that are often blurred:

1. **Source provenance** - what evidence exists about how the image was created.
2. **Authorship and rights protection** - what the photographer/exporter wants to assert about ownership, credit, licensing, and contact.
3. **Invisible watermarking** - a possible resilient carrier for creator IDs or C2PA soft binding, not proof of camera capture by itself.

**Requirements:** PROV-01..04, AUTH-01..04, CTRL-01..04, IW-01..05, VERIFY-01..04
</domain>

<decisions>
## Implementation Decisions

### Provenance Policy

- **D-01:** Use explicit provenance states, not a binary AI/not-AI result. States: Verified Camera Capture, Marked AI / AI-Edited, User-Declared, Unknown Provenance, Suspected AI.
- **D-02:** Absence of a watermark, C2PA manifest, or AI label is never proof of camera capture. Open-source/custom GenAI images with no watermark are classified as Unknown Provenance unless the user declares their source.
- **D-03:** Detection is evidence, not truth. EXIF, XMP/IPTC, C2PA, JUMBF, software tags, and detector hints produce weighted evidence items, but only cryptographic provenance or strong platform evidence can unlock verified language.
- **D-04:** Preserve source AI provenance before adding Markepi's own records. Existing C2PA manifests should become ingredients or retained source assertions, not be overwritten.
- **D-05:** Do not ship an "AI detector" as the authenticity gate. If a detector is added later, it can only feed Suspected AI with confidence and caveats.

### Professional Record Strategy

- **D-06:** C2PA Content Credentials are the professional backbone for signed provenance and export action records.
- **D-07:** IPTC metadata remains the practical compatibility layer for creator, copyright, credit, usage terms, licensor, and Digital Source Type fields.
- **D-08:** Invisible watermarking is a secondary resilience layer: it may carry a creator/export ID or C2PA soft-binding pointer, but it must not be marketed as proof of original camera capture.
- **D-09:** The baseline must be offline and on-device. Any C2PA manifest repository lookup, soft-binding service query, or vendor verification service is optional and disabled by default.
- **D-10:** User privacy controls can strip sensitive metadata such as GPS while preserving rights/provenance fields unless the user explicitly chooses a stricter privacy profile.

### Open-Source Tooling

- **D-11:** Use `contentauth/c2pa-swift` as the first C2PA iOS candidate because it provides Swift APIs for CAI/C2PA read/verify/sign flows and is Apache-2.0/MIT licensed.
- **D-12:** Treat `contentauth/c2pa-rs` as the underlying implementation through Swift bindings, not as a hand-embedded Rust dependency unless c2pa-swift cannot satisfy the app target.
- **D-13:** Evaluate Adobe TrustMark (MIT) as the primary open-source invisible image watermark candidate because it is C2PA-listed and includes C2PA soft-binding examples.
- **D-14:** Evaluate Microsoft InvisMark (MIT) as research-only unless its iOS packaging and runtime feasibility improve; the public implementation is Python/PyTorch-oriented.
- **D-15:** Keep commercial/professional vendors such as Digimarc and Imatag in the research notes as future paid integrations, not default dependencies for v2.2.

### User Control Boundaries

- **D-16:** Users can control creator name, copyright, credit, usage terms, licensor URL/contact, visible disclosure text, privacy profile, C2PA signing identity, and whether to add a creator-protection invisible mark.
- **D-17:** Users cannot manually enable "Verified Camera Capture", "Captured by Camera", "No AI Used", or equivalent language unless the analyzer has positive supporting evidence.
- **D-18:** Users can declare a source as camera, AI, AI-edited, or composite, but user declarations are recorded as user declarations. They do not become verified claims.
- **D-19:** The export receipt must display the distinction between verified evidence, preserved source provenance, and user-supplied statements.
- **D-20:** For GenAI-marked images, Markepi may add rights/protection data for the exporter, but the exported manifest must preserve and disclose the source as AI/AI-edited.
- **D-21:** All production Phase 19 functionality must be implementable as iOS-native app/extension code. No required desktop process, Python/PyTorch sidecar, server call, or cloud registry can be part of the default export path.
- **D-22:** Invisible watermarking ships only if the selected provider can run locally on iOS with acceptable package size, memory, speed, HDR/color preservation, and license notices. Otherwise it remains an evaluation artifact while C2PA/IPTC protection still ships.
- **D-23:** Product-facing app name is Markepi. Existing package/code identifiers such as `WatermarkCore`, `WatermarkEngine`, and `WatermarkConfiguration` may remain implementation names unless a separate rename phase is created.
- **D-24:** C2PA signing identity is Secure Enclave first on real iOS devices, with a local Keychain software fallback only for simulator/development or unavailable hardware. No cloud signing is required for default export. Receipts must describe this as a "Markepi device signing identity" and must not imply verified legal/person identity.

### Signing UX & Identity Tiers

See `19-RESEARCH.md` → "Identity Assurance Tiers" for the full Tier 1/2/3 model. v2.2 ships **Tier 1** (sealed declaration) only.

- **D-25:** C2PA signing is **user-initiated** from an explicit "Sign with Content Credentials" control placed in a new **More** section of the shared controls. Add a `ControlsSection.more` case (sections today are watermark/style/output). Signing is never automatic and never silent.
- **D-26:** The author/creator name is a **compulsory** field for signing. The Sign action is disabled/blocked until the owner supplies a non-empty creator name, because that name is sealed into both the C2PA manifest `CreativeWork` author assertion and the IPTC creator field (Tier 1). `RightsMetadata.creator` therefore flows into the C2PA manifest, not just IPTC.
- **D-27:** Pressing Sign first presents an **explainer popup** (sheet) the user must acknowledge before signing proceeds. It states: (a) what Content Credentials signing is — it seals the photo and the stated authorship so tampering is detectable; (b) the identity caveat — this is a **Tier 1 sealed declaration** signed by a *Markepi device identity* (D-24), **not** a verified legal/person identity; (c) that verified-identity options (Tier 2 CA-issued certificate, Tier 3 CAWG identity assertion) are **not available in the app**. Wording stays honest: "stated by owner / sealed," never "verified identity."

### the agent's Discretion

- Exact Swift model names and file grouping, as long as state/evidence semantics remain explicit.
- Whether C2PA integration lands as a concrete dependency in the first implementation or behind a protocol adapter plus build flag if Xcode package integration needs a separate spike.
- The exact UI placement of provenance controls inside the redesigned inspector, as long as claims are gated and the receipt is visible before sharing.
- The exact TrustMark harness location, as long as it remains local/offline and does not ship unvetted model binaries into the app target.
</decisions>

<canonical_refs>
## Canonical References

Downstream agents MUST read these before planning or implementation:

### Project-Level

- `.planning/PROJECT.md` - core value and constraints
- `.planning/research/STACK.md` - iOS-native media pipeline and metadata/HDR constraints
- `.planning/milestones/v2.2-REQUIREMENTS.md` - v2.2 requirement IDs
- `.planning/milestones/v2.2-ROADMAP.md` - phase map and wave ordering
- `.planning/STATE.md` - current milestone focus

### Prior Phases and Existing Constraints

- `.planning/phases/05-extended-engine-pro-raw-exif-multi-layer/05-CONTEXT.md` - metadata preservation context if present
- `.planning/phases/18-cross-target-parity-accessibility-polish/18-CONTEXT.md` - shared controls and extension parity context
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift` - photo processing pipeline
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift` - video export pipeline
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` - persisted export configuration
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift` - shared controls entry point
- `Packages/WatermarkCore/Sources/WatermarkCore/UI/InspectorSheetView.swift` - inspector shell
- `App/Views/Editor/ExportControls.swift` - export controls integration point
- `ShareExtension/ShareViewController.swift` and `Packages/WatermarkCore/Sources/WatermarkCore/UI/ShareExtensionRootView.swift` - share extension integration

### External Specifications and Tooling

- C2PA 2.4 Soft Binding API - https://spec.c2pa.org/specifications/specifications/2.4/softbinding/Decoupled.html
- C2PA soft-binding algorithm list - https://spec.c2pa.org/softbinding-alg-list/softbinding-algorithm-list.json
- C2PA Swift docs - https://opensource.contentauthenticity.org/docs/c2pa-ios/
- C2PA Swift repo - https://github.com/contentauth/c2pa-swift
- C2PA Rust repo - https://github.com/contentauth/c2pa-rs
- Adobe TrustMark - https://github.com/adobe/trustmark
- Microsoft InvisMark - https://github.com/microsoft/InvisMark
- IPTC Digital Source Type vocabulary - https://cv.iptc.org/newscodes/digitalsourcetype/
</canonical_refs>

<code_context>
## Existing Code Insights

### Likely New Model Layer

Add these or equivalent models under `Packages/WatermarkCore/Sources/WatermarkCore/Models/`:

- `ProvenanceState`
- `ProvenanceEvidence`
- `SourceProvenanceReport`
- `RightsMetadata`
- `DisclosurePolicy`
- `ProtectionWatermarkSettings`
- `ExportReceipt`

The models must be `Codable`, migration-safe, and extension-safe because settings flow through the main app and Share Extension.

### Likely New Services

Add these or equivalent services under `Packages/WatermarkCore/Sources/WatermarkCore/Provenance/`:

- `SourceProvenanceAnalyzer` - reads evidence and emits reports
- `MetadataPreservationPolicy` - decides what to keep/strip under privacy profiles
- `C2PAProvenanceClient` protocol - read/verify/sign abstraction
- `C2PASwiftProvenanceClient` - concrete implementation if c2pa-swift integrates cleanly
- `IPTCRightsMetadataWriter` - rights/digital-source fields
- `InvisibleWatermarkProvider` protocol - evaluation and future production boundary
- `ProvenanceReceiptBuilder` - final receipt shown in UI/share flow

All production services must be usable from both the main app and Share Extension. If a library is app-only, uses unavailable APIs in extensions, or requires writable locations outside the App Group/temp container, it must be isolated behind a disabled adapter until resolved.

### Existing Pipeline Hooks

- Photo export should analyze source before rendering and attach/merge provenance after rendering, using the existing metadata-preserving ImageIO pipeline.
- Video export should preserve existing metadata and write C2PA/IPTC records where container support and tool APIs allow. If full video C2PA signing is not available in v2.2, the app must record that limitation in the receipt.
- Share Extension must use the same shared services. Do not fork provenance behavior between main app and extension.

### UX Hooks

- Add a compact provenance state badge near export controls.
- Add an expanded provenance/rights sheet or inspector section for rights metadata and protection settings.
- Show a receipt before presenting the system share sheet, or provide a persistent receipt row in the final share flow.
- Keep labels short and professional: "Verified source", "AI-marked source", "User-declared", "Unknown source", "Suspected AI".
</code_context>

<specifics>
## Specific Product Rules

1. If source has valid C2PA that indicates AI generation or AI edit, classify as Marked AI / AI-Edited and preserve it.
2. If source has IPTC Digital Source Type `trainedAlgorithmicMedia`, `compositeWithTrainedAlgorithmicMedia`, or `compositeSynthetic`, classify as Marked AI / AI-Edited unless stronger evidence says otherwise.
3. If source has no reliable provenance, classify as Unknown Provenance. The user can still add copyright/protection data.
4. If source has only editable EXIF camera make/model, show it as evidence but do not unlock verified-camera language.
5. If source has verified cryptographic camera provenance in a C2PA manifest or equivalent trusted capture credential, classify as Verified Camera Capture.
6. If a user declares source type, record that as User-Declared unless it conflicts with stronger marked-AI evidence.
7. If source has suspicious software markers or detector hints but no firm label, classify as Suspected AI and keep the confidence/caveat visible.
8. If Markepi adds invisible creator protection, record the provider, payload type, and whether decoding was verified after export.
9. Do not accept a provider as "implemented" if it only works from a desktop script. The shipping implementation must run inside iOS app/extension constraints.
</specifics>

<deferred>
## Deferred Ideas

- Cloud manifest repository integration for C2PA soft binding.
- Commercial vendor SDK integration (Digimarc, Imatag, NAGRA, etc.).
- On-device AI detector model training or bundled detector.
- Full cross-platform verification portal.
- Public authenticity badge infrastructure beyond local export receipts.
</deferred>

---
*Phase: 19-Provenance & Authorship Protection*
*Context gathered: 2026-06-25*
