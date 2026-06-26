---
phase: 19-provenance-authorship-protection
plan: "01"
subsystem: provenance
tags: [source-provenance, metadata, c2pa, iptc, claim-gating, swift-testing]

requires: []
provides:
  - Five-state ProvenanceState enum with claim-gating API
  - ProvenanceEvidence model with kind/strength/source semantics
  - SourceProvenanceReport for final analyzer verdict
  - SourceProvenanceAnalyzer service using ImageIO metadata dictionaries
  - C2PASummary bridge for Plan 19-02 injection
  - 16 Swift Testing tests covering all product rules
affects:
  - 19-02 (C2PA integration reads ProvenanceState and C2PASummary)
  - 19-03 (UI controls consume ProvenanceState display labels and claim gates)
  - 19-04 (invisible watermark eval references provenance report)

tech-stack:
  added: []
  patterns:
    - Conservative provenance: absence of evidence is NOT proof of camera capture
    - Claim gating delegates to ProvenanceState as single source of truth
    - Evidence modeled as items with kind/source/strength, never truth on its own
    - User declarations recorded as declarations, never verified language

key-files:
  created:
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/ProvenanceState.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Models/SourceProvenanceReport.swift
    - Packages/WatermarkCore/Sources/WatermarkCore/Provenance/SourceProvenanceAnalyzer.swift
    - Packages/WatermarkCore/Tests/WatermarkCoreTests/SourceProvenanceAnalyzerTests.swift
  modified: []

key-decisions:
  - "C2PA is modeled as injectable C2PASummary (nil in 19-01) since ImageIO cannot surface JUMBF manifests"
  - "allowsNoAIClaim is always false — no detector can prove a negative (D-05)"
  - "allowsRightsProtection is true for all states because copyright/creator protection is separate from source authenticity (D-16, CTRL-03)"

patterns-established:
  - "Conservative analyzer pattern: structured evidence → weighted rules → conservative state"
  - "Claim gating via computed properties on ProvenanceState (single source of truth)"
  - "Test-by-product-rule: each test encodes a product rule that must never regress"

requirements-completed:
  - PROV-01
  - PROV-02
  - PROV-03
  - VERIFY-02

tests_added: 1
tests_modified: 0

duration: 8min
completed: 2026-06-26
---

# Plan 19-01: Conservative source-provenance model and analyzer

**Five-state provenance taxonomy with claim gates, evidence modeling, and ImageIO metadata analyzer — 16 tests enforce product rules**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-26T09:58:00+02:00
- **Completed:** 2026-06-26T10:00:00+02:00
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- `ProvenanceState` with five durable cases: verifiedCameraCapture, markedAI, userDeclared, unknown, suspectedAI
- `ProvenanceEvidence` with kind/strength/source/user-supplied semantics — evidence as evidence, not truth
- `SourceProvenanceAnalyzer` reads ImageIO metadata dicts, applies conservative rules, emits `SourceProvenanceReport`
- C2PA bridge: `C2PASummary` struct for Plan 19-02 injection (nil in 19-01)
- Claim-gating API: `allowsVerifiedCameraClaim`, `allowsNoAIClaim`, `allowsRightsProtection`
- 16 Swift Testing tests covering all product rules (D-01 through D-20)

## Task Commits

1. **Task 1: Provenance Model Types** - ProvenanceState.swift and SourceProvenanceReport.swift
2. **Task 2: Metadata Evidence Scanner** - SourceProvenanceAnalyzer.swift and tests
3. **Task 3: Claim Gate Tests** - 10 additional tests encoding product rules that must never regress

## Files Created
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/ProvenanceState.swift` - Five-state enum with claim gates and display labels
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/SourceProvenanceReport.swift` - Evidence model, user declaration, report with claim-gating delegation
- `Packages/WatermarkCore/Sources/WatermarkCore/Provenance/SourceProvenanceAnalyzer.swift` - ImageIO metadata scanner with conservative rules
- `Packages/WatermarkCore/Tests/WatermarkCoreTests/SourceProvenanceAnalyzerTests.swift` - 16 product-rule tests

## Decisions Made
- Followed reference implementation exactly — state/evidence semantics and claim gates kept as specified
- Test file required explicit `import Foundation` for `JSONEncoder`/`JSONDecoder` (plan's reference code omitted it)

## Deviations from Plan
None — plan executed exactly as written.

## Issues Encountered
- Test compilation failed due to missing `import Foundation` — fixed by adding the import

## Next Phase Readiness
- Ready for 19-02 (C2PA integration) — `C2PASummary` bridge and `ProvenanceState` are in place
- Ready for 19-03 (UI controls) — display labels and claim gates are implemented
- Ready for 19-04 (invisible watermark) — `SourceProvenanceReport` provides the source context

---
*Plan: 19-01*
*Completed: 2026-06-26*
