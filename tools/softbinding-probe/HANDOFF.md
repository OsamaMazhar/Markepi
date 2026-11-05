# Handoff: invisible watermarking (C2PA soft bindings) for Markepi

**Created:** 2026-11-04
**Status:** research + isolated spike complete. **No production code written, nothing in `App/`, `Packages/`, or `ShareExtension/` was touched.** Everything lives under `tools/softbinding-probe/`.
**Question it answers:** can we carry C2PA-style provenance through platforms that strip metadata (WhatsApp, Instagram, screenshots), and at what cost on a phone?

---

## TL;DR — the decisions

| # | Decision | Evidence |
|---|---|---|
| 1 | **Do not** try to mint or transplant an Apple Reference Image signature | It is a hardware-attested, Apple-CA-signed object; see §2 |
| 2 | Use **Adobe TrustMark variant P** as the durable carrier | MIT (code + weights), on the C2PA approved algorithm list as `com.adobe.trustmark.P`, 48–50 dB PSNR |
| 3 | Watermark payload is a **pointer, not a manifest** — 61-bit ID | C2PA manifest is 2–50 KB; capacity is 7 bytes. See §11 |
| 4 | Manifest lives **in the file (JUMBF) and in a store**, keyed by the ID | Adobe's `c2pa.soft-binding` reference implementation, §10 |
| 5 | Sign **after** watermarking, never before | The hard binding hashes the watermarked bytes |
| 6 | Always pair with a **PDQ fingerprint** | Watermark IDs are copyable (WmForger); crops defeat P |
| 7 | Run inference in **CoreML (decoder int8 24 MB, encoder 17 MB)**, **not MLX** | MLX port doesn't exist; CoreML verified at 1.0 sign agreement |
| 8 | Use a **strip-tiled compositor**, never a full-frame float residual | 192 MP naive peaks at **6.75 GB**; tiled is bounded |
| 9 | Keep the ML work **out of the Share Extension** | 12 MP needs ~180 MB; extension jetsam budget is ~100–200 MB |
| 10 | Never show "verified" from a watermark hit alone | P returns `present=True` with garbage payloads on heavy crops |

---

## 1. Scope

This probe answers five questions, in order:

1. Can a third-party app reproduce Apple's Reference Image signature? (**No** — §2)
2. If not, what is the legitimate equivalent? (C2PA + soft binding)
3. Which open-source watermark actually survives a messaging pipeline? (**TrustMark P**, §5/§7)
4. Does it run on a phone, including 4 GB devices and 48 MP images? (**Yes**, with a tiled compositor — §7.5/§12)
5. How does it combine with the C2PA pipeline Markepi already has? (§10)

What this is **not**: a product spec, an App Store plan, or a licensing review. No code was added to the app targets.

---

## 2. Provenance context (why Apple's signature is out of reach)

### Two different mechanisms

| | C2PA / Content Credentials | Apple Reference Image |
|---|---|---|
| Shape | journal: assertions, ingredients, edit history | seal: one signed artifact, no history |
| Signed object | the final asset (hard binding) | a **hidden inner JPEG** (3024×4032) embedded in the file |
| Signature | COSE, any X.509 chain | composite **ML-DSA-87 + RSA-3072-PSS-SHA512** over SHA-512 of the container split into P‖S‖C |
| Trust | federated trust lists | Apple Prove root only |
| Survives edit | yes (append + re-sign) | no — dies on any re-encode |
| Who can sign | anyone | Apple's camera pipeline / PCC only |

### Verified in this repo (2026-11-04, `tools/refimage-probe/main.swift`)

- ImageIO **drops** the provenance item on any JPEG re-mux — even lossless `CGImageDestinationAddImageFromSource`.
- HEIC: the `uri ` item is never surfaced by `CGImageSourceCopyAuxiliaryDataInfoAtIndex`, and `CGImageDestinationAddAuxiliaryDataInfo` silently ignores the custom type.
- What *does* survive Markepi's writer: EXIF + MakerNote, including the reference-image flag `0x0063 = 8`.
- The verifier itself prints the caveat: the signature **binds the hidden processed image only, not the outer photo's pixels or metadata**.

Full notes: `~/.claude/projects/-Users-osama-Projects-Markepi/memory/apple-reference-image-imageio-drops-it.md`.
Samples (ephemeral, `/tmp/refimage-sample/`): `IMG_0104.jpeg`, `elephant-ref-img.HEIC`.

### Why we won't chase it further

A transplant has only three outcomes: fails verification (hash binding), verifies but visibly contradicts the embedded original (the hidden capture ships inside the payload), or is a fake MakerNote flag that only fools naive detectors. Only one of those is a product, and it isn't one you can ship. Decision: **read/preserve is legitimate, minting is not, and preserve isn't worth the HEIC item surgery yet.**

---

## 3. Why a watermark at all

Measured on the real WhatsApp pipeline assumptions (long edge ~1600 px, JPEG q55–60, metadata stripped, file 80–500 KB):

- A C2PA manifest in the file: **gone**.
- If a platform kept the bytes but re-encoded: `c2pa.hash.data` mismatch → the verifier reports **"modified"**, which is worse than absent.
- A TrustMark watermark in the pixels: **survives all of it** (§7.3).

So the watermark is not a replacement for C2PA — it is the recovery channel that makes C2PA *durable*, which is exactly what CAI calls [Durable Content Credentials](https://opensource.contentauthenticity.org/docs/durable-cr/).

---

## 4. Candidate landscape (why P)

The C2PA Soft Binding Algorithm List (`c2pa-org/softbinding-algorithm-list`) has **57 entries** as of 2026-11-04. Only a handful are open source:

| Project | License | Payload | Quality | Notes |
|---|---|---|---|---|
| **Adobe TrustMark** (B/C/P/Q/F) | **MIT incl. weights** | 100 raw bits → 40–75 protected | Q 43–45 dB, **P 48–50 dB**, C 38–39 dB | On the list: `com.adobe.trustmark.{Q,C,P,F}`; ONNX + Rust/C++/JS runners; removal net shipped |
| **Meta PixelSeal / VideoSeal / ChunkySeal** | MIT | 256 / 1024 bits | SOTA | Best for video (temporal pooling); heavier |
| **Meta WAM** (Watermark Anything) | MIT weights | 32 bits | good | **Localizes tampering**; TPR 99.5–100 under splicing vs TrustMark 1.5–39; 256² inference, CPU-hostile |
| **Microsoft InvisMark** | MIT | 256 bits | ~51 dB | On the list; AI-image oriented, less independent replication |
| blind_watermark (DWT-DCT-SVD) | MIT | arbitrary | 39 dB | **0.61 bit accuracy** in TrustMark's noise suite — not provenance-grade |
| invisible-watermark (dwtDct / RivaGAN) | MIT/Apache | arbitrary | — | Legacy; RivaGAN ~0.77 bit acc |
| EditGuard / OmniGuard | research | bits + recovery | — | Semi-fragile: **detects tampering**, robust only to JPEG q70–95 |
| Stable Signature / SSL / StegaStamp / HiDDeN | MIT-ish | 48–256 bits | — | Superseded (SSL: 0.1 % TPR under crop) |

Benchmarks worth knowing: **WAVES** (UMD) — distortions survivable, regeneration/adversarial attacks wipe everything out; **WmForger** (Meta, NeurIPS 2025) — one-shot black-box forging makes *any* watermark ID copyable; **JPEG Trust Part 3 / ISO 21617** — 100-bit payload benchmark, ICIP 2026 grand challenge.

**Choice: P.** Highest imperceptibility of the variants (48–50 dB), on the approved list, MIT, ONNX published. Cost: it decodes from a **centre square** (§8.1), so it is weaker under crops than Q.

---

## 5. What was implemented and tested

Everything is a standalone Python script; nothing imports the app.

| File | What it does |
|---|---|
| `scripts/wmtest_p.py` | Encodes P at two strengths on a 3024×2268 sample, applies 8 messaging-style attacks, decodes each, reports PSNR + coverage |
| `scripts/lean2.py` | **Memory-lean reference embedder** (strip-streamed bilinear, no full-frame float buffer) + 12/24/48 MP runs with a WhatsApp pass |
| `scripts/memrun.py` | One-size-per-process peak-RSS measurement for 12→100 MP |
| `scripts/wmtest_large.py` | Naive-implementation timing/memory at 24/48/100 MP, including a 192 MP manual run |
| `scripts/coreml_p.py`, `coreml_p2.py` | PyTorch→TorchScript→CoreML conversion, numeric parity vs PyTorch, int8/palettization, end-to-end decode of attacked files |
| `results/*.json` | The raw outputs of the runs quoted below |

Environment: macOS arm64, 16 GB, Python 3.12, torch 2.8.0, coremltools 9.0, mlx + mlx_lm 0.28.4, `trustmark` **0.9.2** from PyPI.

---

## 6. Models

Source: `https://cai-watermark.adobe.net/watermarking/trustmark-models/` (MIT, per repo LICENSE, covers the model files too).

| File | Size | md5 (verified) |
|---|---|---|
| `encoder_P.ckpt` | 17,301,306 B | `0a18f6de6d57c6ef7dda30ce6154a775` |
| `decoder_P.ckpt` | 47,647,180 B | `9450972bc0c3c217cb7b8220dd2f7a3c` |
| `encoder_P.onnx` | 17,312,208 B | — |
| `decoder_P.onnx` | 47,400,467 B | — |

Model facts that matter:

- Encoder always runs at **256²**; decoder at **224²** (Q uses 245²). Encode/decode cost is therefore **independent of image size**; only the residual compositing scales.
- Variant P sets `aspect_ratio_lim = 0` → **centre square only**. Q uses 2.0 → whole frame for 4:3/3:2/16:9.
- Python and Rust both multiply strength by **1.25** for P internally.
- Payload: 100 raw bits; BCH levels → 40 (SUPER, 8 flips), 61 (BCH_5, 5 flips), 68 (BCH_4, 4), 75 (BCH_3, 3).

---

## 7. Results

### 7.1 Quality and coverage — 3024×2268, payload `MKP7F3A`

| Strength | PSNR | mean abs delta inside square | outside square | pixels touched | encode |
|---|---|---|---|---|---|
| 1.0 (effective 1.25) | **47.25 dB** | 2.471 | **0.000** | 61.0 % | 0.4 s |
| 0.8 (effective 1.00) | 48.71 dB | 2.090 | **0.000** | 59.9 % | 0.3 s |

The zero outside the square is the single most important number in this document: **P does not touch the side margins** of a 4:3 frame.

### 7.2 Messaging-pipeline survival — 3024×2268

| Attack | output | 1.0 (eff 1.25) | 0.8 (eff 1.00) |
|---|---|---|---|
| q95 re-save | 4.3 MB | ✅ | ✅ |
| **WhatsApp 1600, q60** | 469 KB | ✅ | ✅ |
| WhatsApp 1080, q55 | 191 KB | ✅ | ✅ |
| "HD" 1600, q80 | 707 KB | ✅ | ✅ |
| heavy 1600, q40 | 348 KB | ❌ | ❌ |
| screenshot 1179, q80 | 381 KB | ✅ | ✅ |
| crop 10 % → 1600 q60 | 480 KB | ✅ | ✅ |
| crop 25 % → 1600 q60 | 498 KB | ❌ | ❌ **and returns garbage with `present=True`** |

Decode is 0.04 s.

### 7.3 Resolution scaling — same attacks, four image sizes

Strength parameter 1.0 (= effective 1.25); result identical at 1.25 (= 1.56):

| Size | wa1600 q60 | wa1600 q80 | wa1080 q55 | wa2048 q60 | crop 10 % | crop 25 % |
|---|---|---|---|---|---|---|
| 6048×4032 (24 MP) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 8064×6048 (48 MP) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 12288×8192 (100 MP) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 16000×12000 (192 MP) | ✅ | — | — | — | — | — |

**But** at effective strength 1.0 (parameter 0.8) the 48 MP case **fails** wa1600/q60, while 24 MP passes. So robustness is not purely resolution-independent — do not lower the strength as images get bigger.

### 7.4 Time and memory

Naive (reference) implementation, peak RSS includes a ~0.8–1.3 GB Python/torch floor:

| Image | encode | peak RSS | stego JPEG q95 |
|---|---|---|---|
| 24 MP | 1.0 s | 1.80 GB | 11.7 MB |
| 48 MP | 2.2 s | 2.73 GB | 18.8 MB |
| 100 MP | 4.6 s | 3.79 GB | 30.9 MB |
| 192 MP | 12.0 s | **6.75 GB** | 48.6 MB |

Strip-tiled compositor (`lean2.py`, validated — decodes both directly and after a WhatsApp pass):

| Image | encode | peak delta vs. runtime baseline |
|---|---|---|
| 12 MP | 0.4 s | +344 MB |
| 24 MP | 0.6 s | +191 MB |
| 48 MP | 1.3 s | +336 MB |
| 100 MP | 2.2 s | +923 MB |

The deltas are inflated by CPython/PIL/torch allocator behaviour; the iOS budget is just buffers + weights (§12).

### 7.5 CoreML conversion (coremltools 9.0, target iOS 18, `mlprogram`)

| Model | Parity vs PyTorch | Size on disk |
|---|---|---|
| Decoder, fp32 | **sign agreement 1.0000**, max\|Δ\| 0.0013 | 47.5 MB |
| Decoder, fp16 | **sign agreement 1.0000**, max\|Δ\| 0.0024 | 47.5 MB (no auto-shrink) |
| Decoder, **int8 linear** | sign agreement 0.95, **6/8 attacks pass = baseline** | **23.9 MB** |
| Decoder, 6-bit k-means palettize | **5/8 attacks** (worse — reject) | 17.9 MB |
| Encoder, fp32 | corr 0.99998, residual error ≈ 56.5 dB | 17.3 MB |

End-to-end: the CoreML decoder was fed the **real WhatsApp-mangled JPEGs** and returned `MKP7F3A` correctly for every one it should (4/4 sampled).

Total shipping estimate: **17.3 + 23.9 ≈ 41 MB**.

### 7.6 MLX

- GitHub repos `trustmark + mlx`: **0**. `trustmark + coreml`: **0**.
- Hugging Face: 3 TrustMark repos, **all variant Q**, none MLX.
- MLX (installed) *does* have every op the architecture needs: `Conv2d`, `ConvTranspose2d`, `InstanceNorm`, `BatchNorm`, `PReLU`, `Upsample`, `mx.conv2d`. No `pixel_shuffle`, but TrustMark uses `Upsample`, so that doesn't matter.
- Verdict: a faithful MLX-Swift port is ~1 day + a state-dict converter, for zero benefit over CoreML. **Don't.**

---

## 8. Findings that change the design

1. **P is centre-square only.** Side margins of a 4:3 photo carry *exactly zero* watermark. If the user crops to a wide frame or reframes, coverage collapses. Decide: accept it (and always pair with a fingerprint), switch to Q for whole-frame coverage, or re-watermark after a crop.
2. **`present=True` is not trust.** At strength 0.8 with a 25 % crop, P returned `"M\x0bP?'?A\x00\x13\x12"` with `present=True`. Every decoded payload needs a namespace byte + CRC, or you will show a badge on noise.
3. **Strength must not scale down with resolution.** 48 MP at effective 1.0 failed q60; effective 1.25 passed everything up to 192 MP.
4. **File size is irrelevant; pixels are not.** A 40 MB JPEG ≈ 100 MP ≈ 880 MB on device. 40 MB is fine; 100 MP needs the region cap.
5. **Watermarking must happen before signing.** The hard binding hashes the watermarked bytes. Markepi's `signExport(outputURL:)` already takes a rendered file — the watermark just has to be applied first, and one assertion added.
6. **The ID is not a signature.** WmForger copies IDs black-box. The manifest + PDQ fingerprint is what makes the ID meaningful.
7. **Heavy crops are the failure mode, not platform compression.** q60/q55/q40 all behave like the published benchmarks; 25 % crop kills P at every size.
8. **No MLX, and Core AI is iOS 27+.** Deployment target is iOS 18 → CoreML (verified) or ONNX Runtime (published artifacts). Add Core AI later behind availability.
9. **Share Extension memory is the real constraint**, not compute. 12 MP ≈ 180 MB is fine in-app, borderline in an extension.
10. **HDR is untouched by this probe.** P composites in 8-bit sRGB; applying it to an HDR base without care will flatten the gain map. Open item (§14).

---

## 9. Payload layout (61 bits, BCH_5)

```
[8]  namespace   0x4D ('M')             — rejects foreign/garbage decodes
[32] asset id    store-assigned         — uniqueness enforced by the store, NOT random
[16] crc-16      over namespace+id      — catches the "present but garbage" case
[5]  epoch       day count               — bounds store retention
```

Why store-assigned: random 32-bit IDs hit a 50 % birthday collision at ~65 k assets; a store that checks-and-retries never collides. Encoded in **binary mode**, not text — text mode is ASCII, 8 bits/char, and silently truncates at `payload_len − ecc − version` bits (7 chars at BCH_5). That truncation cost me a test cycle; don't repeat it.

---

## 10. C2PA integration (the actual design)

Adobe ships the reference flow in `adobe/trustmark/c2pa/c2pa_watermark_example.py`. Reproduced here in Markepi terms:

### Order of operations

```
1. render          visible watermark / white frame            (existing pipeline)
2. watermark       TrustMark P, 61-bit ID                     (new)
3. fingerprint     PDQ of the final pixels                    (new, cheap)
4. manifest        actions + c2pa.soft-binding + ingredient   (extend existing builder)
5. sign            C2PASwiftProvenanceClient.signExport       (existing)
6. publish         ID → {manifest, pdq, created_at} to store  (new, opt-in)
7. verify          re-decode ID from the signed file          (new, cheap assert in export)
```

Step 7 is in Adobe's own example: they decode the watermark *from the signed file* to prove signing didn't destroy it. Do the same in the export receipt.

### The assertion

```json
{
  "label": "c2pa.soft-binding",
  "data": {
    "alg": "com.adobe.trustmark.P",
    "blocks": [ { "scope": {}, "value": "1*0000001001010000010000111101101101001110…" } ]
  }
}
```
Plus `"action": "c2pa.watermarked"` in `c2pa.actions`. The `value` is `"<encoding_type>*<bit string>"` — Adobe's example uses `2*…` (BCH_4); ours is `1*…` (BCH_5).

### What a verifier can say

| Incoming | Check | Honest wording |
|---|---|---|
| untouched file | JUMBF + hard binding | "Signed by Markepi; unmodified since signing" |
| WhatsApp-mangled | ID → store → PDQ compare | "Re-encoded copy of an asset signed by Markepi on <date>; fingerprint match 0.94; edited since signing" |
| mangled + cropped | ID found, PDQ mismatch | "Watermark present; no matching signed asset — provenance lost" |
| screenshot | usually nothing | "No provenance" (never imply "fake") |

### Store schema (minimum)

```
id            uint32   primary key
manifest      bytes    the signed manifest store (not the image)
pdq           bytes    32-byte PDQ hash of the signed asset
created_at    timestamp
expires_at    timestamp  from the epoch field
```

Privacy: IDs must be random per asset with no user/device bits, or lookups become a tracking oracle. Publishing must be **opt-in** and stated in the manifest; the app's no-network promise stays true for users who don't opt in.

### If you need more than 7 bytes in pixels

Only one robust channel has the capacity: a **QR/DataMatrix burned into the white frame** (0.5–2 KB, survives screenshots, visible by design). Steganography (KB capacity) does not survive JPEG. So the three-channel model is: manifest in file → ID in pixels → optional URL+hash in the frame.

---

## 11. Why the manifest cannot live in the watermark

- **Capacity:** 61 bits vs 2–50 KB. Short by ~2000×.
- **Circular hashing:** `c2pa.hash.data` covers the file bytes; a manifest inside those bytes has to hash itself. No fixed point.
- **Bearer token:** anything embedded in pixels is copyable; a signature must live where modification is detectable — a store.

Hence: watermark = *pointer*, manifest = *proof*, fingerprint = *binding between them*.

---

## 12. Recommended setups

### Per device / resolution

| Device class | Max capture | Setup | Expected peak |
|---|---|---|---|
| 4 GB (SE 2/3, XR, 11, 12 mini) | 12 MP | P @ effective 1.25, tiled, in-app | **~150–200 MB**, 0.4 s |
| 6 GB (13/14/14 Pro) | 12 MP, 48 MP ProRAW | same | ~200 MB / ~500 MB |
| 8 GB (15/16/17 Pro) | 48 MP | same | ~500 MB, ~1.2 s |
| Panoramas 48–100 MP | up to ~100 MP | cap the **region** at 4096², upsample residual, tile | ~250 MB regardless of source |
| Share Extension (any) | — | **don't** run the ML; hand off to the app | jetsam risk |

### Inference stack

- **CoreML**, decoder int8 (23.9 MB) + encoder fp32 (17.3 MB) ≈ 41 MB.
- Alternative: **ONNX Runtime Mobile** with Adobe's published `encoder_P.onnx` / `decoder_P.onnx`.
- Not MLX. Core AI later (iOS 27+), gated on availability.

### Compositor

- Strip-tile the residual (256 rows is plenty), add into one uint8 canvas, never materialise a full-frame float array.
- If `min(W,H) > 4096`, watermark a 4096² proxy of the square and upsample the residual — visually and decodably equivalent.

---

## 13. Implementation traps (all hit during this spike)

1. **Aspect first, then resize.** The 256² encoder view must be the *centre square cropped*, not the whole frame squashed. Getting this wrong produces a watermark that never decodes.
2. **Residual units.** The encoder works in [−1, 1]; compositing into 0–255 pixels requires `× 127.5`, not `× 255`.
3. **Strip mapping must use global output coordinates.** Per-strip `resize(source_crop → strip)` without the global offset makes every strip repeat the whole pattern.
4. **`WM_STRENGTH` for P is multiplied by 1.25 internally.** "1.0" in the API is 1.25 on the pixels.
5. **Text payload truncates silently** at 61 bits (7 ASCII chars). Use binary mode.
6. **PIL refuses >89 MP by default** (`DecompressionBombWarning`); set `Image.MAX_IMAGE_PIXELS = None` for panoramas. ImageIO has its own limits — check before promising 100 MP.
7. **Don't trust `present`** — validate namespace + CRC (§8.2).
8. **Install the models by hand if the downloader stalls.** The SDK's `urllib` fetch can sit at a partial file; `curl` + md5 check (§6) is reliable.

---

## 14. Not tested / open questions

- **HDR + gain map.** P composites 8-bit sRGB. Needs: apply residual to the SDR base only, leave the gain map untouched, verify with `exiftool` and a real HDR photo.
- **HEIC.** All tests were JPEG. HEIC round-trip (ImageIO → CIImage → HEIC) needs its own pass, plus 10-bit.
- **Video.** Not attempted. If video matters, evaluate VideoSeal/PixelSeal (256-bit, temporal pooling) rather than per-frame TrustMark.
- **Real-device timing.** All numbers are macOS CPU. A-series ANE/GPU numbers need a device run.
- **Share Extension jetsam.** Assumed limit ~100–200 MB; measure on a 4 GB device before committing to in-extension processing.
- **PDQ integration.** Not exercised. Need a Swift PDQ implementation (C/WASM reference exists) and a distance threshold calibrated on WhatsApp-mangled samples.
- **Store + resolver.** Design only; no service, no API.
- **CAI conformance / trust list.** Getting the cert recognized by third-party verifiers requires the CAI conformance program; self-signed = "unrecognized signer".
- **App Attest** as an identity upgrade for `C2PASigningIdentityStore` (attests the app, not the sensor — must be worded accordingly).
- **Q vs P for photos.** Not measured head-to-head on the same attacks; Q would fix the centre-square gap at 43–45 dB.

---

## 15. Reproduce

```bash
# models (md5 in §6)
cd /tmp && python3 -m venv --system-site-packages wmvenv
./wmvenv/bin/pip install trustmark blind-watermark pywavelets coremltools

# robustness + quality at 3024 wide
./wmvenv/bin/python tools/softbinding-probe/scripts/wmtest_p.py

# 12/24/48 MP, tiled compositor, with a WhatsApp pass
./wmvenv/bin/python tools/softbinding-probe/scripts/lean2.py

# per-size peak memory (one process each)
for d in 4032x3024 6048x4032 8064x6048 12288x8192; do
  ./wmvenv/bin/python tools/softbinding-probe/scripts/memrun.py $d
done

# CoreML conversion + parity + end-to-end decode of attacked files
./wmvenv/bin/python tools/softbinding-probe/scripts/coreml_p.py
./wmvenv/bin/python tools/softbinding-probe/scripts/coreml_p2.py
```

Scripts reference `/tmp/refimage-sample/IMG_0104.jpeg` (the pps-lab Reference Image sample) and write to `/tmp/wmrunP`, `/tmp/wmlarge`, `/tmp/coremlP`. All of those vanish on reboot; re-download the sample with `curl -o IMG_0104.jpeg https://vari.pps-lab.com/assets/samples/IMG_0104.jpeg`.

Raw results: `results/trustmark_p_3024.json`, `results/large_images.json`, `results/coreml_conversion.json`.

---

## 16. Sources

- TrustMark repo + FAQ + `python/CONFIG.md` + `c2pa/c2pa_watermark_example.py` — https://github.com/adobe/trustmark
- TrustMark, ICCV 2025 — Bui, Agarwal, Collomosse — https://collomosse.com/pubs/Bui-ICCV-2025.pdf
- C2PA Soft Binding Algorithm List — https://github.com/c2pa-org/softbinding-algorithm-list (57 entries on 2026-11-04)
- C2PA 2.1 spec (`c2pa.soft-binding`, `c2pa.hash.data`, `c2pa.hash.boxes`) and 2.4 Implementation Guidance §4.2 (manifest repositories, soft binding lookup)
- CAI Durable Content Credentials — https://opensource.contentauthenticity.org/docs/durable-cr/
- CAI Soft Binding Resolution API — https://developer.adobe.com/cai-soft-binding-api/
- Watermark Anything (WAM), ICLR 2025 — https://arxiv.org/abs/2411.07231 (robustness/localization tables)
- Pixel Seal — https://arxiv.org/abs/2512.16874 · VideoSeal — https://arxiv.org/abs/2412.09492
- WmForger, NeurIPS 2025 — https://arxiv.org/abs/2510.20468
- WAVES benchmark — https://wavesbench.github.io/
- JPEG Trust / ISO 21617 Part 3, ICIP 2026 grand challenge — https://jpeg-trust-community.github.io/watermarking/benchmark/
- pps-lab Reference Image verifier — https://github.com/pps-lab/reference-image-verifier-js
- In-repo prior art: `tools/c2pa-spike/HANDOFF.md`, `tools/refimage-probe/main.swift`, `Packages/MarkepiCore/Sources/MarkepiCore/Provenance/`

---

## 17. Suggested next step

One isolated spike, same shape as this one: a Swift executable that (1) loads `decoder_P_int8.mlpackage`, (2) decodes the ID from the three WhatsApp-mangled JPEGs in `/tmp/wmrunP`, (3) prints payload + CRC status, (4) runs the tiled compositor over a 48 MP image on a **4 GB device** while logging `os_proc_available_memory()`. That answers the two remaining production questions — real-device memory headroom and whether the CoreML path matches the Python results outside the simulator — before anything is wired into `MarkepiCore`.
