# C2PA-Swift Integration Spike — Result

**Date:** 2026-06-26
**Verdict:** **PREFERRED** — c2pa-swift integrates cleanly and signs+reads back manifests.

## Summary

The spike proves `contentauth/c2pa-swift` v0.0.12 works end-to-end:
1. Dependency resolves via SPM (387MB XCFramework, prebuilt for iOS device + simulator + macOS).
2. Sign + read-back roundtrip passes with both bundled test certs and self-generated certs.
3. The Xcode `WatermarkApp` build gate passes with c2pa-swift linked transitively through WatermarkCore.

## What was built

- `tools/c2pa-spike/Package.swift` — standalone macOS executable depending on `c2pa-swift` 0.0.12.
- `tools/c2pa-spike/Sources/c2pa-spike/main.swift` — renders a JPEG, loads PEM certs, builds a manifest, signs via `Builder`/`Signer`/`Stream`, reads back via `C2PA.readFile`.
- `tools/c2pa-spike/Certs/` — self-generated CA + leaf cert chain (P-256, ES256, `digitalSignature` + `emailProtection` EKU). Leaf key converted to PKCS#8 format (`BEGIN PRIVATE KEY`) — c2pa-rs rejects SEC1 (`BEGIN EC PRIVATE KEY`).

## Key findings

### API (verified against resolved v0.0.12 source)
- **Sign:** `Builder(manifestJSON:)` + `Signer(algorithm:certificateChainPEM:tsa:sign:)` (callback-based) + `Stream(readFrom:)`/`Stream(writeTo:)` + `builder.sign(format:source:destination:signer:)`.
- **Convenience `C2PA.signFile`** returns empty errors silently — **do not use**. The Builder/Signer/Stream path surfaces real errors and is the reliable path.
- **Read:** `C2PA.readFile(at:)` returns manifest JSON.
- **Manifest JSON:** use `claim_generator_info: [{name, version}]` (structured array), NOT `claim_generator` (string) — the string form is silently ignored.
- **SignerInfo** (PEM-based) requires PKCS#8 private key format. For Secure Enclave (non-exportable keys), use the callback-based `Signer(algorithm:certificateChainPEM:tsa:sign:)` with `SecKeyCreateSignature` inside the closure.
- **CertificateManager.createSelfSignedCertificateChain(for: SecKey, config:)** generates a full CA→intermediate→leaf PEM chain from a `SecKey` (works with SE-backed keys via their public key).

### Cert format
- c2pa-rs validates the signing cert at sign time. The leaf MUST have `keyUsage=digitalSignature` + an EKU (`emailProtection` works).
- Private key MUST be PKCS#8 (`BEGIN PRIVATE KEY`). Convert SEC1 with: `openssl pkcs8 -topk8 -nocrypt -in leaf-key.pem -out leaf-key-pkcs8.pem`.

### Validation status (self-signed)
- `signingCredential.untrusted` — EXPECTED for a self-signed chain. The manifest is still signed and readable. This satisfies the spike; real trust-list membership is a production concern.
- `assertion.action.malformed: first action must be created or opened` — only affects `c2pa.actions` assertions. Custom metadata assertions (`c2pa.test`, `stds.schema-org.CreativeWork`) work fine.

### Performance
- Sign: ~20–130ms (depending on image size).
- Read: ~1–2ms.

## XCFramework size
- Downloaded artifact: 387MB compressed. The built `.framework` adds to the app bundle — check App Store size impact before shipping to production. For v2.2, the integration is acceptable.

## Secure Enclave signing
- The callback-based `Signer` API supports SE-backed keys: provide the cert chain PEM (generated via `CertificateManager` from the SE key's public key) and a `sign` closure that calls `SecKeyCreateSignature(secKey, .ecdsaSignatureMessageX962SHA256, ...)`.
- This is the path used by the production `C2PASwiftProvenanceClient` in `Packages/WatermarkCore/Sources/WatermarkCore/Provenance/C2PAProvenanceClient.swift`.

## Build gate
- `bash scripts/build-gate.sh` → **BUILD GATE: PASSED** with c2pa-swift linked into WatermarkCore (transitively reaching WatermarkApp + ShareExtension).

## Decision for plan 19-02
- **PREFERRED path taken.** `contentauth/c2pa-swift` is now a dependency of `Packages/WatermarkCore/Package.swift`.
- The concrete `C2PASwiftProvenanceClient` ships behind `#if canImport(C2PA)` and replaces `NoopC2PAProvenanceClient` as the default in `ProvenanceExportOptions`.
- Secure Enclave signing is implemented (not deferred) via the callback-based `Signer`.
