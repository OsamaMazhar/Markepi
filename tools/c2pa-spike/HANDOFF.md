# C2PA-Swift Integration Spike — Agent Handoff

**Created:** 2026-06-26
**Goal:** De-risk `contentauth/c2pa-swift` for Phase 19 (Provenance & Authorship
Protection) by (1) proving it works in an **isolated tool** and (2) verifying the
**Xcode `WatermarkApp` target still builds, links, and runs** with it. This is the
19-02 "Task 1: C2PA Dependency Decision" go/no-go spike, done standalone BEFORE
touching the real export pipeline.

Do **not** wire C2PA into `WatermarkEngine`/`ImageWriter` yet. This spike only
answers: "does the dependency integrate cleanly, and can we sign + read back a
manifest on-device?" The full pipeline hook is plan 19-02's job afterward.

---

## Context you need (already verified — trust this)

### Environment (verified 2026-06-25/26)
- Swift 6.2.3, **Xcode 26.2**, macOS arm64.
- OpenSSL 3.6.2 present. Network to github.com works. `iPhone 17 Pro` simulator is booted (UDID `6048B4AB-B089-47F5-A4B5-2C2BCEB63405`).
- Repo root: `/Users/osama/Projects/Watermark`. Working branch: `fix/watermark-preview-scale-whiteframe-tests` (dirty tree with unrelated changes — keep spike changes additive, do NOT commit unless the user asks).

### Project structure facts
- Xcode project `Watermark.xcodeproj` has 3 native targets: `WatermarkApp` (app), `ShareExtension` (app-extension), `WatermarkCore` (the SPM package at `Packages/WatermarkCore`).
- **The ShareExtension is a thin handoff bridge only** — it saves the shared photo to the App Group inbox and opens the main app via `watermark://shared`. It does NOT edit/process. Therefore **C2PA only needs to run in `WatermarkApp` (with `WatermarkCore` linked in), never inside the extension.** Ignore extension memory constraints for this feature.
- The build gate is `scripts/build-gate.sh`: it runs `xcodebuild -project Watermark.xcodeproj -scheme WatermarkApp -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`. This is the authoritative "does the app build" check.
- **Tests:** `swift test` does NOT work in this repo (WatermarkCore UI files import UIKit unguarded → "no such module 'UIKit'" on macOS, and no scheme has a test action). To run package tests: `cd Packages/WatermarkCore && xcodebuild test -scheme WatermarkCore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WatermarkCoreTests/<Suite>`.

### c2pa-swift facts (verified from repo + docs, 2026-06-26)
- SPM URL: `https://github.com/contentauth/c2pa-swift.git`
- Module: `import C2PA`. Product name to depend on: `C2PA`.
- Latest version: **v0.0.12** (June 2026). Min iOS **16.0**. Pin to a tag/`from:`, never a branch.
- Ships as a **prebuilt XCFramework** (`C2PAC.xcframework`) inside the package — supports iOS device, iOS simulator, AND macOS. (This is why the isolated macOS tool can link it.)
- Wraps the Rust `c2pa-rs` core via its C API.

### c2pa-swift API surface (from v0.0.12 docs — VERIFY exact names against the resolved package's headers/Swift interface once fetched; minor naming may differ)
- **Read/verify (file):** `let manifestJSON = try C2PA.readFile(at: imageURL)` → returns manifest JSON string. Throws if no manifest.
- **Read (stream):** `Stream(data:)` → `Reader(format: "image/jpeg", stream:)` → `reader.json()`.
- **Sign (file):**
  ```swift
  let signerInfo = SignerInfo(
      algorithm: .es256,
      certificatePEM: certificatePEM,   // leaf + CA chain PEM
      privateKeyPEM: privateKeyPEM,      // leaf private key PEM
      tsaURL: nil)
  try C2PA.signFile(source: inputURL, destination: outputURL,
                    manifestJSON: manifestJSON, signerInfo: signerInfo)
  ```
- Secure Enclave signing is supported by the library but the public docs don't show the API. **Out of scope for this spike** — use PEM cert+key signing here. SE-backed signing is a later refinement (Phase 19 D-24). Note it as "supported, deferred" in your summary.
- **IMPORTANT — confirm the real symbols** after `swift package resolve`: grep the resolved checkout under `.build/checkouts/c2pa-swift/` for `SignerInfo`, `signFile`, `readFile`, `Reader`, `SigningAlg`/`.es256`. The names above are from docs and may need small adjustments. The `c2pa-ios-example` repo (`contentauth/c2pa-ios-example`) is the canonical usage reference if symbols differ.

---

## What is already done

1. Created directory skeleton:
   - `tools/c2pa-spike/Sources/c2pa-spike/` (empty — needs `main.swift`)
   - `tools/c2pa-spike/Certs/`
2. **Cert generation was IN PROGRESS but interrupted** — the openssl command to build the ES256 chain had not confirmed completion. Re-run it (Step 1 below) and verify the PEM files exist before proceeding. The intended chain:
   - `ca-key.pem` / `ca.pem` — P-256 self-signed root CA (CA:TRUE, keyCertSign).
   - `leaf-key.pem` / `leaf.pem` — P-256 leaf, `keyUsage=critical,digitalSignature`, `extendedKeyUsage=emailProtection` (required by the C2PA cert profile), signed by the CA.
   - `chain.pem` — `leaf.pem` + `ca.pem` concatenated (this is `certificatePEM`).
   - `leaf-key.pem` is `privateKeyPEM`.

---

## Plan — execute in order

### Step 1 — (Re)generate the signing chain
```bash
cd /Users/osama/Projects/Watermark/tools/c2pa-spike/Certs
openssl ecparam -name prime256v1 -genkey -noout -out ca-key.pem
openssl req -new -x509 -key ca-key.pem -out ca.pem -days 3650 \
  -subj "/CN=Markepi Dev Root CA/O=Markepi" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
openssl ecparam -name prime256v1 -genkey -noout -out leaf-key.pem
openssl req -new -key leaf-key.pem -out leaf.csr -subj "/CN=Markepi Device Signer/O=Markepi"
cat > leaf-ext.cnf <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=emailProtection
EOF
openssl x509 -req -in leaf.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
  -out leaf.pem -days 3650 -extfile leaf-ext.cnf
cat leaf.pem ca.pem > chain.pem
openssl x509 -in leaf.pem -noout -text | grep -A1 -E "Key Usage|Extended Key Usage"
```
Acceptance: `chain.pem` and `leaf-key.pem` exist; leaf shows `Digital Signature` + `E-mail Protection`.

### Step 2 — Create the SwiftPM executable package
`tools/c2pa-spike/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "c2pa-spike",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/contentauth/c2pa-swift.git", from: "0.0.12"),
    ],
    targets: [
        .executableTarget(
            name: "c2pa-spike",
            dependencies: [.product(name: "C2PA", package: "c2pa-swift")]
        ),
    ]
)
```
Then resolve and inspect real symbols:
```bash
cd /Users/osama/Projects/Watermark/tools/c2pa-spike
swift package resolve         # may need network; if sandboxed, request unsandboxed run
ls .build/checkouts/c2pa-swift
grep -rE "struct SignerInfo|func signFile|func readFile|enum SigningAlg|case es256" .build/checkouts/c2pa-swift/Sources 2>/dev/null | head
```
Adjust the API calls in Step 3 to match whatever the grep shows.

### Step 3 — Write `Sources/c2pa-spike/main.swift`
It must, end to end:
1. Render a solid-color **JPEG** test image to a temp file using CoreGraphics/ImageIO (self-contained; do not depend on external fixtures).
2. Load `chain.pem` (as `certificatePEM`) and `leaf-key.pem` (as `privateKeyPEM`) from `../Certs/` (resolve a path relative to `#filePath` or take CLI args).
3. Build a minimal manifest JSON (claim generator `"Markepi"`, one action e.g. `c2pa.edited` / `c2pa.watermark`).
4. Call the sign API → write a signed output JPEG.
5. Call the read API on the output → print the returned manifest JSON.
6. Print a clear PASS/FAIL line. PASS = signed file written AND manifest reads back with our claim generator present. Print any validation_status entries verbatim (a self-signed chain will likely report `signingCredential.untrusted` — that is EXPECTED and still counts as "signed and readable"; call it out honestly).

Keep it small and defensive — print the actual thrown error if any step fails.

### Step 4 — Run the isolated spike
```bash
cd /Users/osama/Projects/Watermark/tools/c2pa-spike
swift run c2pa-spike
```
Acceptance: prints PASS, shows the manifest JSON containing the Markepi claim
generator. Record runtime + any validation_status notes.

> If `swift run`/`swift package resolve` fails due to the sandbox blocking
> network, re-run the Bash call with the sandbox disabled (the harness exposes a
> `dangerouslyDisableSandbox` option). Resolution writes only into the package's
> `.build/`.

### Step 5 — Verify in the Xcode app (the real risk)
Before editing the project, **invoke the Axiom build skill** (`axiom-ios-build`,
which routes to SPM/build-debugging guidance) — this step is exactly an
SPM-into-xcodeproj integration and the repo mandates Axiom for iOS build work.

Then:
1. Add the `c2pa-swift` package dependency so it reaches the **`WatermarkApp`** target. Two viable routes — prefer (a):
   - **(a)** Add it to `Packages/WatermarkCore/Package.swift` as a dependency of the `WatermarkCore` target (`.product(name: "C2PA", package: "c2pa-swift")`). Since the app links WatermarkCore, SPM resolves it transitively. This matches plan 19-02's intended shape.
   - **(b)** Add the package directly to the Xcode project and link it on `WatermarkApp` only.
2. Add a tiny, compiled-in smoke call so we prove it LINKS (not just resolves) for `arm64-apple-ios`. e.g. a `C2PASmokeTest.run()` in WatermarkCore that calls `C2PA.readFile(at:)` inside a do/catch (it can throw "no manifest" — that's fine; we only need it to link and execute). Reference it from app startup behind a debug flag, or from a unit test.
3. Run the build gate:
   ```bash
   bash scripts/build-gate.sh
   ```
   Acceptance: `BUILD GATE: PASSED`. This proves the XCFramework links for iOS in BOTH the app and the (still-built) ShareExtension target.
4. (Optional but recommended) Run the smoke test on the booted simulator to confirm the XCFramework loads at runtime, not just links:
   ```bash
   cd Packages/WatermarkCore && xcodebuild test -scheme WatermarkCore \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -only-testing:WatermarkCoreTests/C2PASmokeTests
   ```

### Step 6 — Write the decision summary
Create `tools/c2pa-spike/RESULT.md` answering plan 19-02 Task 1:
- Did the dependency resolve? Did it LINK for iOS in the app build gate? XCFramework size added to the app (check the built `.app`/framework size — relevant for App Store).
- Did sign + read-back roundtrip pass? Validation status of a self-signed chain.
- **Verdict:** `PREFERRED` (c2pa-swift integrates cleanly → 19-02 proceeds with the concrete `C2PASwiftProvenanceClient`) OR `FALLBACK` (integration blocked → keep `NoopC2PAProvenanceClient` + adapter, document the blocker). Per the plan, NEVER hand-roll C2PA serialization to fill a gap — an invalid manifest is worse than none.
- Note Secure Enclave signing as "library-supported, deferred to Phase 19 D-24 implementation."

---

## Gotchas / decisions already made
- **Cert profile matters:** c2pa-rs validates the signing cert at sign time. The leaf MUST have `keyUsage=digitalSignature` and an EKU (we use `emailProtection`). A bare self-signed leaf with no EKU may be rejected — that's why we build a CA+leaf chain.
- **Self-signed = untrusted, not invalid:** reading back will likely show `signingCredential.untrusted`. That satisfies the spike ("signed and readable"); real trust-list membership is a production concern, not this spike's.
- **Keep it isolated:** everything lives under `tools/c2pa-spike/` except the minimal Step-5 smoke hook. Don't touch the export pipeline.
- **Don't commit** unless the user asks. If committing, add `tools/c2pa-spike/.build/` and `tools/c2pa-spike/Certs/*key*.pem` to `.gitignore` (never commit private keys).
- **Verify API symbols** against the resolved checkout before trusting the doc-sourced names in Step 2/3.

---

## Definition of done
1. `swift run c2pa-spike` prints PASS with a read-back Markepi manifest.
2. `bash scripts/build-gate.sh` prints `BUILD GATE: PASSED` with c2pa-swift linked into `WatermarkApp`.
3. `tools/c2pa-spike/RESULT.md` records a clear PREFERRED/FALLBACK verdict + XCFramework size + validation notes, ready to feed plan 19-02.
