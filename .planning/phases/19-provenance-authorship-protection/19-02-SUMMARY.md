---
phase: 19-provenance-authorship-protection
plan: "02"
subsystem: provenance
tags: [c2pa, iptc, metadata, provenance, secure-enclave, keychain, privacy, swift-testing]

requires:
  - phase: 19-01
    provides: ProvenanceState, SourceProvenanceReport, SourceProvenanceAnalyzer, C2PASummary bridge
provides:
  - C2PAProvenanceClient protocol + NoopC2PAProvenanceClient (fallback adapter)
  - C2PASigningIdentityStore (Secure Enclave first, Keychain software fallback)
  - C2PAManifestRequest / C2PASigningResult models
  - IPTCRightsMetadataWriter + RightsMetadata model
  - MetadataPreservationPolicy with three privacy profiles
  - ExportReceipt model (source report + signing result)
  - ProvenanceExportOptions (rights, privacy, C2PA flag, injected client)
  - WatermarkEngine.process provenance hook (additive, backward-compatible)
  - VideoProcessor provenance hook with honest video C2PA warning
  - 27 Swift Testing tests across 8 suites
affects:
  - 19-03 (UI controls consume ExportReceipt, RightsMetadata, privacy profiles)
  - 19-04 (invisible watermark eval references ProvenanceExportOptions.invisibleWatermarkPayloadID)
  - future C2PA integration spike (concrete client guarded by #if canImport(C2PA))

tech-stack:
  added: []  # No third-party deps — fallback path (c2pa-swift NOT added)
  patterns:
    - Adapter boundary: protocol + noop default so engine never depends on concrete C2PA library
    - Additive API: provenance param defaults to nil — nil ⇒ today's behavior, no receipt
    - Pure dict transforms: privacy + IPTC merge return new dicts, never mutate input
    - Honest receipt: noop always reports 'not signed' so receipts never claim success falsely
    - Secure Enclave first with Keychain software fallback (D-24); @unchecked Sendable for SecKey

key-files:
  created:
    - Packages/WatermarkCore/Sources/WatermarkCore/Provenance/C2PASigningIdentityStore.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Provenance/C2PAProvenanceClient.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Provenance/IPTCRightsMetadataWriter.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Provenance/MetadataPreservationPolicy.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Provenance/ProvenanceExportOptions.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/RightsMetadata.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/ExportReceipt.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/ProvenanceExportTests.swift
  modified:
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift

key-decisions:
  - "FALLBACK path taken: c2pa-spike (tools/c2pa-spike/) was NEVER COMPLETED — only HANDOFF.md exists, no Certs/, no RESULT.md. c2pa-swift was NOT added as a dependency. NoopC2PAProvenanceClient is the only concrete client that ships."
  - "ExportReceipt + ProvenanceExportOptions added additively with default nil — every existing caller of WatermarkEngine.process and ProcessingResult.init compiles unchanged."
  - "IPTC rights + privacy profile merged BEFORE ImageWriter.write; C2PA signing happens AFTER write (manifest attaches to written file)."
  - "Video C2PA signing surfaces honest warning 'Video Content Credentials not available for this format' rather than claiming success."
  - "C2PASigningIdentity uses @unchecked Sendable for SecKey (CF reference type, only crosses the client boundary)."
  - "Simulator returns .unsupported identity type (SE unavailable, no entitlements) — this is correct, not a bug."

patterns-established:
  - "Adapter boundary pattern: protocol + noop default insulates engine from external C2PA library; concrete client lands behind #if canImport(C2PA) when spike completes"
  - "Additive pipeline hook: new optional param defaults to nil; nil path is byte-for-byte today's behavior"
  - "Pure dict transforms for metadata: privacy policy and IPTC writer never mutate input dict, return new dict"
  - "Honest receipt discipline: noop client reports .notSigned with warnings; never claims a manifest was attached"

requirements-completed:
  - PROV-04
  - AUTH-01
  - AUTH-02
  - AUTH-03
  - AUTH-04
  - VERIFY-03
  - VERIFY-04

tests_added: 1
tests_modified: 0

duration: 21min
completed: 2026-06-26
---

# Phase 19 Plan 02: Metadata Preservation & C2PA Manifest Integration Summary

**C2PA adapter boundary (noop client), Secure Enclave-first signing identity store, IPTC rights writer, three privacy profiles, and additive export-pipeline hook with honest receipts — 27 tests, fallback path because c2pa-spike was never completed**

## Performance

- **Duration:** 21 min
- **Started:** 2026-06-26T08:29:41Z
- **Completed:** 2026-06-26T08:51:06Z
- **Tasks:** 6
- **Files modified:** 11

## Accomplishments
- C2PA fallback path documented and shipped: NoopC2PAProvenanceClient + protocol boundary (no c2pa-swift dependency)
- C2PASigningIdentityStore: Secure Enclave first, local Keychain software fallback, receipt-safe "Markepi device signing identity" display name
- IPTC rights metadata writer: creator, copyright (IPTC + TIFF mirror), credit line, usage terms, licensor URL, Digital Source Type — pure dict merge preserving existing EXIF/XMP
- MetadataPreservationPolicy: preserveAll / stripSensitive / minimalPublic — GPS strip, body/lens serial removal, Apple maker note removal, rights/provenance survive
- ExportReceipt + ProvenanceExportOptions + WatermarkEngine.process hook: additive `provenance: ProvenanceExportOptions? = nil` param — nil ⇒ today's behavior, non-nil ⇒ analyze → privacy → IPTC → write → sign → receipt
- VideoProcessor surfaces honest "Video Content Credentials not available for this format" warning when C2PA requested for video
- 27 Swift Testing tests across 8 suites — all pass; build gate PASSED for WatermarkApp + ShareExtension

## Task Commits

Each task was committed atomically (TDD tasks have RED → GREEN):

1. **Task 1: C2PA Dependency Decision (FALLBACK)** - `c29118f` (docs)
2. **Task 2: C2PA Signing Identity Store** - `7634a41` (test/RED) → `1d0fdee` (feat/GREEN)
3. **Task 3: C2PAProvenanceClient Protocol + Noop** - `3bb30c2` (test/RED) → `b66f115` (feat/GREEN)
4. **Task 4: IPTC Rights Metadata Writer** - `1ac5357` (test/RED) → `d2b9f1f` (feat/GREEN)
5. **Task 5: Metadata Preservation Policy** - `6a12896` (test/RED) → `b8532ed` (feat/GREEN)
6. **Task 6: Export Pipeline Hook + Receipt** - `dcd3b70` (test/RED) → `026a19a` (feat/GREEN)

## Files Created/Modified
- `Packages/WatermarkCore/Sources/WatermarkCore/Provenance/C2PASigningIdentityStore.swift` - SE-first signing identity with Keychain fallback (D-24)
- `Packages/WatermarkCore/Sources/WatermarkCore/Provenance/C2PAProvenanceClient.swift` - Protocol + NoopC2PAProvenanceClient + manifest request/signing result models
- `Packages/WatermarkCore/Sources/WatermarkCore/Provenance/IPTCRightsMetadataWriter.swift` - Pure dict merge of IPTC rights into ImageIO metadata (AUTH-03, D-07)
- `Packages/WatermarkCore/Sources/WatermarkCore/Provenance/MetadataPreservationPolicy.swift` - Three privacy profiles; pure dict transform (D-10)
- `Packages/WatermarkCore/Sources/WatermarkCore/Provenance/ProvenanceExportOptions.swift` - Caller-facing options (rights, privacy, C2PA flag, injected client)
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/RightsMetadata.swift` - Codable rights model
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ExportReceipt.swift` - Receipt wrapping source report + signing result (Codable + Sendable)
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ProcessingResult.swift` - Added additive `provenanceReceipt: ExportReceipt?` field (default nil)
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift` - Additive `provenance` param; analyze → privacy → IPTC → write → sign → receipt
- `Packages/WatermarkCore/Sources/WatermarkCore/Processing/VideoProcessor.swift` - Additive `provenance` param; honest video C2PA warning
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/ProvenanceExportTests.swift` - 27 tests across 8 suites

## Decisions Made
- **FALLBACK path (Task 1):** The c2pa-spike (tools/c2pa-spike/) was never completed — only HANDOFF.md exists (no Certs/, no RESULT.md, no main.swift). Per the plan's Fallback path, c2pa-swift was NOT added to Package.swift. NoopC2PAProvenanceClient is the only concrete client. The adapter boundary (protocol) means a concrete C2PASwiftProvenanceClient can ship later behind `#if canImport(C2PA)` without touching the engine.
- **Additive API (Task 6):** `provenance: ProvenanceExportOptions? = nil` and `provenanceReceipt: ExportReceipt? = nil` both default to nil — every existing caller compiles unchanged. Verified: build gate PASSED for WatermarkApp + ShareExtension.
- **Simulator identity (Task 2):** On the Simulator, SecKeyCreateRandomKey fails for both SE (no token) and software (no entitlements) paths → returns `.unsupported`. This is correct behavior, not a bug — tests assert the display name and type enum, not key creation.
- **Video C2PA (Task 6):** Video containers are format-limited for C2PA. Rather than silently claiming success, VideoProcessor surfaces an honest warning "Video Content Credentials not available for this format" in the validation result.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SecKey is not Sendable in Swift 6**
- **Found during:** Task 2 (C2PA Signing Identity Store)
- **Issue:** `C2PASigningIdentity` was declared `Sendable`, but its stored `secKey: SecKey?` property is a CoreFoundation reference type not marked Sendable in Swift 6.
- **Fix:** Marked the struct `@unchecked Sendable` — the SecKey only crosses the C2PA client actor boundary (or the noop path), never a data race.
- **Files modified:** C2PASigningIdentityStore.swift
- **Verification:** Tests pass; build gate PASSED.
- **Committed in:** `1d0fdee` (Task 2 GREEN)

**2. [Rule 1 - Bug] Conditional downcast to CoreFoundation type 'SecKey' always succeeds**
- **Found during:** Task 2 (C2PA Signing Identity Store)
- **Issue:** `result as? SecKey` triggers a Swift 6 error because CF-type conditional downcasts always succeed.
- **Fix:** Changed to `guard let ref = result` then `ref as! SecKey` — safe because `kSecReturnRef: true` guarantees a SecKey reference.
- **Files modified:** C2PASigningIdentityStore.swift
- **Verification:** Tests pass; build gate PASSED.
- **Committed in:** `1d0fdee` (Task 2 GREEN)

**3. [Rule 1 - Bug] C2PAManifestRequest init missing exportedAt assignment**
- **Found during:** Task 3 (C2PAProvenanceClient Protocol)
- **Issue:** The init listed `exportedAt` as a stored property but the initializer did not assign it — "return from initializer without initializing all stored properties".
- **Fix:** Added `exportedAt` as an init parameter with a default value `Date()`.
- **Files modified:** C2PAProvenanceClient.swift
- **Verification:** Tests pass.
- **Committed in:** `b66f115` (Task 3 GREEN)

---

**Total deviations:** 3 auto-fixed (3 Rule 1 bugs — Swift 6 Sendable/CF-cast/init correctness)
**Impact on plan:** All auto-fixes necessary for Swift 6 strict concurrency compilation. No scope creep.

## Issues Encountered
- c2pa-spike incomplete — handled via Fallback path (documented blocker, not a code issue).

## Authentication Gates
None — no external services or auth required. All processing is on-device.

## C2PA Integration Blocker

**Blocker:** The c2pa-spike (tools/c2pa-spike/) was NEVER COMPLETED. Only `HANDOFF.md` exists — there is no `Certs/` directory, no `RESULT.md`, no `main.swift`, and no `Package.swift`. The spike never validated that `contentauth/c2pa-swift` integrates cleanly into the Xcode build gate for iOS.

**Resolution (this plan):** Per the plan's documented Fallback path:
- `contentauth/c2pa-swift` was NOT added to `Packages/WatermarkCore/Package.swift`.
- Only the `C2PAProvenanceClient` protocol + `NoopC2PAProvenanceClient` ship. The noop client always reports `status: .notSigned` with a warning — receipts stay honest.
- A future concrete `C2PASwiftProvenanceClient` will live in `C2PAProvenanceClient.swift` guarded by `#if canImport(C2PA)` once a spike proves the dependency links for iOS in `build-gate.sh`.
- No C2PA manifest serialization was hand-rolled (plan requirement honored — an invalid manifest is worse than none).

**Impact on requirements:** AUTH-01 ("Exports CAN include a signed C2PA manifest") is satisfied at the capability/contract level (the adapter boundary, protocol, identity store, and pipeline hook all exist), but the concrete signing is disabled in this build. This is the documented Fallback outcome.

## Next Phase Readiness
- Ready for 19-03 (User Controls, Disclosure UI & Export Receipt) — `ProvenanceExportOptions`, `RightsMetadata`, `MetadataPrivacyProfile`, and `ExportReceipt` are all in place for the UI layer.
- Ready for 19-04 (Invisible Watermark Evaluation) — `ProvenanceExportOptions.invisibleWatermarkPayloadID` is wired through the manifest request.
- C2PA concrete signing is deferred until a future spike completes the c2pa-swift integration. The adapter boundary means no engine changes will be needed when it lands.

## Self-Check: PASSED

- [x] C2PASigningIdentityStore.swift exists on disk
- [x] C2PAProvenanceClient.swift exists on disk
- [x] IPTCRightsMetadataWriter.swift + RightsMetadata.swift exist on disk
- [x] MetadataPreservationPolicy.swift exists on disk
- [x] ExportReceipt.swift + ProvenanceExportOptions.swift exist on disk
- [x] ProcessingResult.swift modified (provenanceReceipt field added)
- [x] WatermarkEngine.swift modified (provenance param added)
- [x] VideoProcessor.swift modified (provenance param + warning)
- [x] ProvenanceExportTests.swift exists (27 tests)
- [x] Package.swift UNCHANGED (no c2pa-swift dependency — fallback path)
- [x] All 11 task commits present in git log: c29118f, 7634a41, 1d0fdee, 3bb30c2, b66f115, 1ac5357, d2b9f1f, 6a12896, b8532ed, dcd3b70, 026a19a
- [x] Tests pass: 27/27 in ProvenanceExportTests
- [x] Build gate PASSED: WatermarkApp + ShareExtension

---
*Phase: 19-provenance-authorship-protection*
*Plan: 19-02*
*Completed: 2026-06-26*
