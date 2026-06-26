---
phase: 19-provenance-authorship-protection
plan: "03"
subsystem: ui
tags: [swiftui, provenance, c2pa, receipt, rights-metadata, claim-gating]

requires:
  - phase: 19-01
    provides: ProvenanceState, SourceProvenanceAnalyzer, SourceProvenanceReport
  - phase: 19-02
    provides: C2PAProvenanceClient, RightsMetadata, ExportReceipt, ProvenanceExportOptions, C2PASigningIdentityStore
provides:
  - Persisted provenance settings (rightsMetadata, privacyProfile, C2PA sign state, sourceDeclaration)
  - ProvenanceControlsView with source badge, evidence, rights editor, privacy picker, Sign button, and no raw C2PA toggle bypass
  - C2PASigningInfoSheet (Tier-1 honest explainer popup — D-27)
  - ExportReceiptView (source state, signing status, identity caveat — D-19/D-24)
  - More section (ControlsSection.more) in MarkepiPillBar (D-25)
  - Compulsory-author gate for signing (D-26)
  - ViewModel integration — analyze on source load, surface receipt post-export
affects:
  - 19-04 (invisible watermark controls depend on provenance controls + export pipeline)

tech-stack:
  added: []
  patterns:
    - Generic SwiftUI views with ViewModel constrained to WatermarkConfigurable
    - Claim gates delegated to ProvenanceState / SourceProvenanceReport (single source of truth)
    - Runtime state (report, receipt) separate from persisted config
    - Pixel-free metadata analysis via CGImageSourceCreateWithURL + CopyPropertiesAtIndex

key-files:
  created:
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/ProvenanceControlsView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/C2PASigningInfoSheet.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/ExportReceiptView.swift
  modified:
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/MarkepiPillBar.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/ControlsView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/ExtensionRendering.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/UI/ShareExtensionRootView.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Provenance/SourceProvenanceAnalyzer.swift
    - App/ViewModels/WatermarkViewModel.swift
    - App/Views/ContentView.swift
    - ShareExtension/ShareExtensionViewModel.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/SnapshotTestViewModel.swift

key-decisions:
  - "More section houses signing controls, separate from watermark/style/output per D-25"
  - "Creator name is compulsory — Sign button disabled when empty per D-26, with engine-level enforcement as a backstop"
  - "Explainer popup shown before signing with Tier-1 honest wording: device identity, not verified legal identity per D-27"
  - "Pixel-free metadata analysis: CGImageSourceCreateWithURL + CGImageSourceCopyPropertiesAtIndex (no pixel decode)"

patterns-established:
  - "Protocol-additive: WatermarkConfigurable got sourceProvenanceReport with default nil"
  - "Runtime/per-session state (report, receipt) separate from persisted config"
  - "AnalyzeCurrentSource() called from every source-change funnel + index navigation"

requirements-completed:
  - CTRL-01
  - CTRL-02
  - CTRL-03
  - CTRL-04
  - VERIFY-01

tests_added: 1
tests_modified: 1

duration: 55min
completed: 2026-06-26
---

# Plan 19-03: User-facing provenance, rights, privacy, and receipt controls

**Compact provenance section with source badge, rights editor, C2PA signing with explainer popup, and post-export receipt view — shared by app and Share Extension**

## Performance

- **Duration:** 55 min
- **Started:** 2026-06-26T11:37:00+02:00
- **Completed:** 2026-06-26T12:19:00+02:00
- **Tasks:** 6
- **Files modified:** 14

## Accomplishments
- `ProvenanceControlsView` — source badge, evidence summary, rights editor, privacy picker, C2PA status/removal controls, source declaration, invisible protection placeholder, Sign button
- `C2PASigningInfoSheet` — Tier-1 honest explainer popup (D-27): what signing is, the device identity caveat, Tier 2/3 unavailable
- `ExportReceiptView` — source state, evidence, rights added, C2PA signing status with identity type and wording caveat (D-19/D-24)
- `.more` section added to `ControlsSection` (D-25)
- Compulsory-author gate: Sign button disabled when creator name is empty or whitespace-only (D-26), with engine-level enforcement preventing direct config bypass
- ViewModel integration: analyze source on photo load, navigation, and declaration change; surface receipt after export
- Pixel-free metadata analysis via `SourceProvenanceAnalyzer.analyze(imageURL:)` using `CGImageSourceCreateWithURL`
- Migration-safe Codable: old config JSON decodes to safe defaults (provenance fields default off)

## Task Commits

Each task was committed atomically:

1. **Task 1: Persisted Provenance Settings** — `e283969` (feat)
2. **Task 2-6: UI Views + Controls + ViewModel Integration** — `e5e4122` (feat)

## Files Created/Modified
- `ProvenanceControlsView.swift` — Compact provenance section with source badge + all controls
- `C2PASigningInfoSheet.swift` — Explainer popup (D-27)
- `ExportReceiptView.swift` — Read-only receipt (D-19/D-24)
- `WatermarkConfiguration.swift` — Added rightsMetadata, metadataPrivacyProfile, includeC2PAManifest, sourceDeclaration, invisibleProtectionEnabled
- `MarkepiPillBar.swift` — Added `.more` case
- `ControlsView.swift` — Wired `.more` to `ProvenanceControlsView`
- `WatermarkViewModel.swift` — Added analyzeCurrentSource(), provenance options in renderAndPrepareShare(), receipt display
- `ShareExtensionViewModel.swift` — Same provenance integration
- `ContentView.swift` — Added ExportReceiptView sheet
- `ShareExtensionRootView.swift` — Added ExportReceiptView sheet

## Deviations from Plan
None — plan executed exactly as written per reference implementation.

## Issues Encountered
- Duplicate `showExportReceipt` declaration — removed duplicate
- Optional unwrap needed for `report.warnings` (report is Optional)
- `sourceURL` is non-optional `URL` on `PhotoItem` — removed guard let binding
- `$viewModel` not in scope inside `body(content:)` modifier — used `Binding(get:set:)` pattern matching existing sheets
- `showExportReceipt` + `lastExportReceipt` not on protocol — added to `ShareExtensionRendering` and `SnapshotTestViewModel`
- NSCache not Sendable for cert cache (19-02) — used custom `CertCache` class with NSLock
- Post-review: replaced the raw C2PA toggle with an explainer-gated sign flow, wired receipt continuation to sharing, and extended provenance options/receipts through video, Live Photo, batch, app, and Share Extension paths.

## Next Phase Readiness
- Ready for 19-04 (invisible watermark evaluation harness) — provenance controls are in place, export pipeline wires through, `invisibleProtectionEnabled` toggle placeholder exists
- C2PA signing works end-to-end on device (proven in c2pa-spike)

---
*Plan: 19-03*
*Completed: 2026-06-26*
