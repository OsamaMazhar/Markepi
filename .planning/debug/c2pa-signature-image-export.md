---
status: resolved
trigger: "suddenlty C2PA signature stops working. Verify that that the C2PA MUST WORK when image is exported"
created: "2026-07-05T14:15:55Z"
updated: "2026-07-05T15:18:13Z"
---

# Debug Session: c2pa-signature-image-export

## Symptoms

- expected_behavior: "Exported images must contain a working C2PA signature."
- actual_behavior: "C2PA signature suddenly stopped working for exported images."
- error_messages: "Not provided."
- timeline: "Sudden regression reported on 2026-07-05."
- reproduction: "Export an image with C2PA signing enabled and verify the exported file."

## Current Focus

- hypothesis: "Image export can report signed even when post-sign C2PA read-back verification fails."
- test: "Sign/read JPEG and HEIC through the C2PA spike; compile app/extension through build gate; add engine regression coverage for unverified signed results."
- expecting: "C2PA image export is only treated as signed after read-back proves an intact claim signature."
- next_action: "Ship the fail-closed signing guard."
- reasoning_checkpoint: "C2PA library signs JPEG and HEIC; app integration needed a stronger read-back gate."
- tdd_checkpoint: "Added regression test for a fake `.signed` result without intact verification."

## Evidence

- `swift run c2pa-spike` signs and reads back JPEG successfully.
- Extended temp spike confirmed HEIC signs and reads back with both `image/heic` and `image/heif`.
- App-shaped manifest probe (`c2pa.created` first action + `c2pa.markepi.provenance`) signs/reads back for JPEG and HEIC and does not report `assertion.action.malformed`.
- Previous production client signed to a temp file, replaced the export, then returned `status: .signed` even when `C2PA.readFile` failed and `verification == nil`.
- `ExportReceiptView` treats `status == .signed` as protected, so a nil/failed verification could still be presented as signed.

## Eliminated

- C2PA library total failure: eliminated by successful JPEG and HEIC spike signing/read-back.
- HEIC unsupported format: eliminated by successful `image/heic` and `image/heif` read-back.
- Video regression scope: video path already reports C2PA as unsupported; this fix targets image export.

## Resolution

- root_cause: "The image export path did not fail closed when post-sign C2PA read-back verification was missing or not intact."
- fix: "Verify the signed temporary file before replacing the rendered export; require an intact claim signature in both the concrete C2PA client and `WatermarkEngine` before returning `.signed`."
- verification: "`bash scripts/build-gate.sh` passed; `xcodebuild build-for-testing -scheme WatermarkCore -destination 'platform=iOS Simulator,name=iPhone 17'` passed; `swift run c2pa-spike` passed for app-shaped JPEG and HEIC manifests. `swift test --filter ProvenanceExport` remains blocked by the package's macOS SwiftPM/UIKit mismatch."
- files_changed: "C2PAProvenanceClient.swift, WatermarkEngine.swift, PipelineError.swift, ProvenanceExportTests.swift"
