## 1. Tier model (MarkepiCore/Premium)

- [ ] 1.1 Add `ExportTier { free, pro }` and `ExportPolicy` (maxPixelDimension 2048 / lossyQuality ≤ 0.7 / keepsGainMap / videoPreset 1920x1080 / videoForcesSDR / brandMark) with `ExportPolicy(tier:)`; verify with a unit test asserting both policies' fields
- [ ] 1.2 Change `ExportGate` to expose `tier` (premium → `.pro`) and drop `canExport/record/remaining*`; verify a test flipping `PremiumStatusStore` (and the DEBUG override) switches the tier
- [ ] 1.3 Delete `ExportQuota` + `ExportQuotaTests`; add a one-time cleanup of the `exportQuota.*` App Group keys on app launch; verify `swift test --skip ExtensionSnapshotTests --skip C2PARealSigningIntegrationTests` passes and grep finds no `ExportQuota` references
- [ ] 1.4 Point the legacy `ShareExtensionViewModel` at `ExportGate.tier` (no quota calls) so it compiles unchanged in behaviour; verify `bash scripts/build-gate.sh` builds both targets

## 2. Free photo output (engine)

- [ ] 2.1 Add `tier: ExportTier = .pro` to `WatermarkEngine.process`; Free applies `maxPixelDimension: 2048`, `min(outputQuality, 0.7)`, and maps PNG/TIFF output to JPEG (HEIC when the source is HEIC); verify a test exporting a 4032×3024 fixture yields 2048×1536 and ≤ 30% of the Pro file size
- [ ] 2.2 Make gain-map dropping follow `policy.keepsGainMap` (not only `renderScale < 1`); verify a test with a small HDR fixture (no downscale) has no gain map on Free and keeps it on Pro
- [ ] 2.3 Verify Free photo metadata: test that EXIF camera/lens/date/GPS survive and PixelWidth/PixelHeight match the reduced image
- [ ] 2.4 Pass `tier` through `processLivePhoto` (still → photo rules, motion → video rules) and `BatchProcessor`; verify a batch test where every item honours the tier

## 3. Free video output (engine)

- [ ] 3.1 Add `tier` to `processVideo`/`VideoProcessor.process`; Free forces the SDR branch (8-bit overlays, Rec. 709 primaries/transfer/matrix on the composition) and prefers `AVAssetExportPreset1920x1080`, keeping audio and `exportSession.metadata`; verify by unit-testing preset/colour selection for HDR and SDR inputs
- [ ] 3.2 Device check: export a 4K HDR clip as Free and Pro on a real iPhone; verify with `ffprobe`/exiftool that Free is 1920×1080 H.264 bt709 with audio + creation date, Pro is unchanged (Simulator cannot export video)

## 4. Markepi mark

- [ ] 4.1 Add `shadow: Bool = false` (lenient decode) to `TextWatermarkInput`; draw the soft shadow in `TextWatermarkRenderer` and the video text layer; verify a render test that a white mark on a white image has dark pixels around the glyphs only when `shadow` is on, and that old configs decode
- [ ] 4.2 Record the date stamp's rendered frame in `RenderLayout.layerFrames` under a reserved key; verify with a layout test that a date stamp at bottom-left reports its rect
- [ ] 4.3 Implement `BrandMarkPlacer.slot(mark:photo:padding:occupied:)` with order BR, BL, TR, TL, centre, bottom-middle, top-middle and least-overlap fallback; verify table tests for: empty, BR taken, four corners, corners+centre, corners+centre+bottom-middle, everything taken, dragged rect over BR, and that middle-left/right are never returned
- [ ] 4.4 Implement `BrandMark.apply(to:canvasSize:metadata:)`: lazy layout pass on a clear canvas → visible user layer frames + date stamp → slot within `photoRect` → returns a config copy with the "Markepi" text layer (white, 0.85 opacity, shadow, cap height ≈ 4% of the shorter side); verify a test that a framed config puts the mark inside `photoRect` and that the input config is unchanged
- [ ] 4.5 Apply the mark in `process`/`processVideo`/`processLivePhoto` when `policy.brandMark`; verify tests that Free output contains the mark (pixel diff vs Pro in the expected slot) and Pro does not, and that the preview path (`maxPixelDimension` render from the view model) never includes it
- [ ] 4.6 Verify C2PA: a signed Free export's manifest reports `visibleWatermarkApplied` and signing still succeeds for free users (existing provenance test extended with `tier: .free`)

## 5. Export flow + comparison sheet (App)

- [ ] 5.1 Introduce `ExportRequest` (.photo/.livePhoto/.video/.batch) and `beginExport(_:)` in `WatermarkViewModel`; Pro → `perform(request, tier: .pro)`, Free → `pendingExport` + `showExportComparison`; remove `allowExportOrPaywall`, `pendingQuota`, `recordCompletedExport`; keep the batch C2PA notice ordering; verify `build-gate.sh` passes and a Pro export still opens the share sheet in the Simulator
- [ ] 5.2 Build `ExportComparisonSheet` (Pro card gold stroke + star, Free card plain, spec chips, "Unlock full quality" / "Export free", no "Don't show again" or suppression state, card taps = actions, portrait stack / landscape side-by-side, no scrolling) with previews rendered via `engine.process(maxPixelDimension: 1200, tier:)` and specs from source metadata + `ExportPolicy`; verify Simulator screenshots on iPhone 17 Pro Max and iPad Pro 13 portrait + landscape
- [ ] 5.3 Wire actions: Export free → `perform(.free)`; Unlock → paywall with `awaitingPurchaseResume`; purchase/restore (`store.isPremium` true) resumes `perform(.pro)`; paywall closed while free → comparison re-shown; sheet dismissed → nothing rendered; verify in the Simulator with the DEBUG Force Premium toggle standing in for a purchase
- [ ] 5.4 Video and batch comparison content (video frame + 1080p/SDR vs source/HDR chips; batch first item + item count); verify Simulator screenshots for a video and a 5-item batch
- [ ] 5.5 Update `PaywallView` copy and free/Pro cards to full resolution / HDR / no watermark, remove every daily-limit string; verify `grep -rn "per day\|daily\|3 photos" App` returns nothing user-facing and a screenshot of the paywall

## 6. Release

- [ ] 6.1 Run `bash scripts/build-gate.sh` and the MarkepiCore suite (with the known `--skip`s); verify both are green
- [ ] 6.2 Device pass on Osama's iPhone: free photo (size, no HDR, mark placement with text in corners), free video, free Live Photo, Pro unchanged, purchase-resume from the comparison; verify by inspecting exported files with exiftool
- [ ] 6.3 Update ASC description, promo text and What's New for 1.6 to the new model (no "3 free photos a day"); verify via the ASC API that the en-US localization text no longer mentions daily limits
