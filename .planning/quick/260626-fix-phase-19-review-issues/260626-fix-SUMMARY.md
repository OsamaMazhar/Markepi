---
title: Fix Phase 19 provenance/authorship review issues
date: 2026-06-26
type: quick
requirements-completed: []
---

# Quick Summary: Fix Phase 19 Review Issues

## Outcome

Fixed the Phase 19 review findings across the C2PA signing path, provenance wiring, UI gates, receipts, source analysis, signing identity handling, signing-key guidance, and planning traceability.

## Fixes

- C2PA signing now signs the already-rendered export and moves the signed result back in place, instead of signing the original source over the edited output.
- The source file is attached as a best-effort C2PA ingredient so existing provenance is carried forward.
- Creator-name signing is enforced in the engine, not only in the UI.
- Provenance options and export receipts now flow through photo, video, Live Photo, batch, main app, and Share Extension exports.
- Import-time source analysis reads existing C2PA summaries for still sources.
- Secure Enclave and software signing keys use separate Keychain tags, preventing software keys from being reported as Secure Enclave identities.
- The receipt sheet now has a Continue to Share action and shows rights metadata, privacy actions, and invisible-protection status.
- Phase 19 planning state, requirements, roadmap, and summaries now reflect the preferred `c2pa-swift` integration and 19-03 completion.

## Robustness follow-up

- C2PA replacement now keeps an unsigned backup until the signed file is moved into place, so a file-move failure does not unnecessarily discard the completed render.
- C2PA certificate caching now keys by identity type plus public key material, avoiding a stale cert chain if a signing key is regenerated in the same process.
- The signing explainer trims creator names before display and before enabling confirmation.
- Added regression coverage proving direct-config C2PA signing trims the creator before building the manifest.
- The More section now has a dedicated Content Credentials block with signing-key readiness, a one-tap recheck, and guidance that Markepi creates the local device key automatically.
- The signing UI now explains that the user does not need to fetch a certificate or create an account: Secure Enclave is used when available, with a local Keychain key as fallback.
- The signing sheet and More-section copy now clearly state that this is a local/device signature, not a verified legal identity, while the resulting C2PA manifest remains tamper detectable.
- Signing is blocked when the local key is unavailable, and the UI directs the user to retry signing on their iPhone in Markepi.
- Signing now waits for completed source provenance analysis before enabling the C2PA signing flow.
- Batch signing now discloses that C2PA signing is image-only in this build. Mixed batches continue after user OK: images are signed, videos keep exporting without C2PA signatures, and video non-signing is not treated as a batch error.
- The More section, signing sheet, and batch preflight alert share a tested `BatchC2PASigningDisclosure` model so mixed-batch copy stays consistent.

## Verification

- `git diff --check` on touched files: passed.
- Local AVFoundation metadata identifier typecheck: passed.
- Local c2pa-swift checkout inspection confirmed `Builder.addIngredient(json:format:from:)` exists.
- `bash scripts/build-gate.sh`: passed.
- `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build-for-testing`: passed.
- `xcodebuild -project Watermark.xcodeproj -scheme WatermarkCore -configuration Debug -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build-for-testing`: passed.
- Attempted targeted simulator test run for the new batch disclosure tests, but escalation was rejected by the environment's usage limit. No workaround was attempted.
- `swift test --package-path Packages/WatermarkCore --filter WatermarkEngineProvenanceHookTests`: not a valid verifier in this package layout because SwiftPM builds the package for macOS and the package includes UIKit-only iOS views (`no such module 'UIKit'`). The iOS build gate is the authoritative verifier here.

## Notes

The working tree contains many pre-existing unrelated changes. This quick task only reconciles the Phase 19 provenance/authorship review issues and associated planning artifacts.
