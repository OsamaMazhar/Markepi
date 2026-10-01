## Context

Monetisation today lives in `MarkepiCore/Premium`:

- `PremiumStatusStore` caches the entitlement in the App Group, and `StoreManager` keeps it current.
- `ExportQuota` counts daily exports.
- `ExportGate` combines the two into "may export?".
- `WatermarkViewModel.allowExportOrPaywall` blocks the export and raises `PaywallView`.

Every photo export goes through `WatermarkEngine.process(...)`, which already has two relevant behaviours:

- `maxPixelDimension` downscales the render (built for the live preview).
- When `renderScale < 1` it drops the gain map.

Videos go through `processVideo` → `VideoProcessor` / `VideoLayerBuilder`. The video path picks an HEVC HDR preset or an SDR one, and draws the overlays as CALayers positioned by the same placement maths as photos. Live Photos and batches call the same two entry points.

`buildFilterGraph` records where each user layer lands in `RenderLayout.layerFrames`, keyed by layer index on the rendered canvas. Building the graph is lazy, and nothing is rasterised until `createCGImage`.

The Share Extension is a handoff bridge. Its legacy `ShareExtensionViewModel` still references `ExportGate`, but it does not export in the shipping flow.

## Goals / Non-Goals

**Goals:**
- One place decides the tier and one place applies it, shared by single exports, batches, photos, Live Photos and video.
- The free mark goes through the existing text-layer renderers, so photos and video draw it identically and it uses the same placement maths as the user's own layers.
- The comparison sheet's Free card shows the real slot and size the export will use, built with the same functions.

**Non-Goals:**
- No pricing or product changes. The StoreKit products, IDs and the paywall's plan cards stay as they are.
- No server-side or receipt-based enforcement. The entitlement check stays the cached App Group flag, as it is today.
- No A/B switch between the old quota model and the new one (AutoAlign has a `monetization_mode`; Markepi does not need one).
- No watermark on the in-editor preview, ever, including a "preview as free" toggle.

## Decisions

### 1. `ExportTier` replaces the quota

`ExportGate` becomes the source of `ExportTier { case free, pro }`:

```swift
public struct ExportGate {
    public var tier: ExportTier { status.isPremium ? .pro : .free }
}
```

`ExportQuota` and its App Group keys are deleted. The existing counters are removed from the App Group defaults on first launch, so stale keys don't linger.

**Alternative considered:** keeping `ExportQuota` with an infinite limit. Rejected because it is dead code that still reads like a rule.

### 2. The tier is an engine parameter, and its policy is a value type

Each of `process`, `processVideo` and `processLivePhoto` gains `tier: ExportTier = .pro`. The default keeps every existing caller and test unchanged. The tier resolves to an `ExportPolicy` with these fields:

| Field | Pro | Free |
|---|---|---|
| `maxPixelDimension` | nil | 2048 |
| `lossyQuality` | config value | min(config, 0.7) |
| `keepsGainMap` | true | false |
| `videoPreset` | as today | `AVAssetExportPreset1920x1080` |
| `videoForcesSDR` | false | true |
| `brandMark` | false | true |

Photo:
- Free reuses the existing `maxPixelDimension` downscale, so the gain-map drop already follows.
- Gain-map dropping is made explicit through `policy.keepsGainMap`, because a small source isn't downscaled but must still lose its map.
- Lossless output formats (PNG/TIFF) are written as JPEG for Free, or HEIC when the source is HEIC. Otherwise the "about 2 MB" target fails for PNG users.

Video:
- Free forces the SDR branch: an 8-bit overlay, a composition without HDR colour properties, and Rec. 709 primaries, transfer function and matrix.
- AVFoundation tone-maps HLG/PQ into that composition, and the H.264 1080p preset scales the output down.
- `exportSession.metadata` is still copied, so creation date and location survive.

**Alternative considered:** scaling the photo after writing it with ImageIO thumbnailing. Rejected: it decodes twice, and a second write risks metadata loss.

### 3. The free mark is a synthetic text layer appended at export time

`BrandMark.apply(to config:, canvasSize:, metadata:) -> WatermarkConfiguration` returns a copy of the config with one extra `.text` layer: "Markepi", white, opacity 0.85, with `shadow: true`, and a scale chosen so the cap height is about 4% of the photo's shorter side. The copy exists only inside the export call and is never assigned back to the view model, saved, or added to templates. That is how the spec's "never in preview, layers or saved configuration" holds.

`TextWatermarkInput` gains `shadow: Bool = false`, decoded leniently. `TextWatermarkRenderer` and the video text layer draw a soft dark shadow (blur ≈ 0.08 × font size, 45% black) when it is set. Users don't get a shadow toggle as part of this change.

**Alternative considered:** a separate mark renderer drawn after compositing. Rejected: it would need its own photo and CALayer code and its own coordinate conversions. Appending a layer reuses the code that already handles orientation, frames, padding and video.

### 4. Slot choice from real layer frames

`BrandMarkPlacer` is pure and unit-tested:

```swift
static func slot(mark: CGSize, photo: CGRect, padding: CGFloat,
                 occupied: [CGRect]) -> WatermarkPosition
```

- It walks `[.bottomRight, .bottomLeft, .topRight, .topLeft, .center, .bottomCenter, .topCenter]`.
- For each slot it builds the mark's candidate rect inside `photo` using `WatermarkPosition.translation`, the same maths the renderers use.
- It returns the first slot with zero intersection with `occupied`. If every slot intersects, it returns the slot with the smallest intersection area, and ties keep list order.
- Side middles are absent from the list by construction.

`occupied` comes from a layout pass:

- `buildFilterGraph` runs once on a clear `CIImage` of the export's canvas size; nothing is rendered, the graph is lazy.
- It returns `RenderLayout.layerFrames` for the visible user layers. The date stamp's frame is now recorded there too, under a reserved key.
- The same pass gives `photoRect`, so on framed exports the mark stays on the photo, never on the mat.

Video calls the same pass with the video's natural size, so its slot is fixed for the whole clip. Batches call it per item, because aspect ratios differ.

**Alternative considered:** using the preset `position` fields only. Rejected because dragged (`.custom`) layers and the date stamp would be ignored, which the spec forbids. The reverse, deriving occupancy from the last preview's layout, was also rejected: batches and videos have no matching preview.

### 5. The comparison sheet is an App-level view that gates export entry points

`WatermarkViewModel.allowExportOrPaywall` becomes `beginExport(_ request: ExportRequest)`:

- Pro: `perform(request, tier: .pro)` runs immediately.
- Free: it stores `pendingExport = request` and sets `showExportComparison = true`.

`ExportRequest` is `.photo`, `.livePhoto`, `.video` or `.batch`. It captures what the existing `renderAndPrepareShare` branches already decide, so the batch C2PA notice ordering is kept.

`ExportComparisonSheet` is modelled on AutoAlign's `SaveComparisonSheet`, using Markepi design tokens:

- Two cards stacked in portrait, side by side in landscape.
- Pro gets a gold stroke and star; Free is plain.
- Spec chips per card, and buttons "Unlock full quality" (prominent) and "Export free".
- A card tap triggers the same action as its button.

Card images:
- Both come from one preview-size render of the current item, made with `engine.process(maxPixelDimension: ~1200, tier:)`.
- Pro is rendered with `.pro`. Free is rendered with `.free`, so it includes the real mark slot and size, then shown SDR. Pro uses `.allowedDynamicRange(.high)` when the source has a gain map.
- For video, the existing preview frame is used.
- The specs (pixel sizes, HDR, 1080p) come from source metadata and `ExportPolicy`, never from guesses.

Actions:
- "Export free" runs `perform(request, tier: .free)`.
- "Unlock full quality" sets `awaitingPurchaseResume = true` and presents the paywall.
- `onChange(of: store.isPremium)` to true while `awaitingPurchaseResume` runs `perform(request, tier: .pro)`.
- Closing the paywall while still free re-presents the comparison, as AutoAlign's `SaveFlowCoordinator` does.
- Dismissing the comparison clears `pendingExport`.

**Alternative considered:** a banner in the share sheet after a free export. Rejected because it never shows the user the difference.

### 6. Content Credentials

Signing is untouched. Because the mark is a real layer, the existing `visibleWatermarkApplied: !config.watermarks.isEmpty` in the C2PA manifest request becomes true for Free exports without extra code. The receipt view will list "Markepi" among the watermarks, which is accurate.

### 7. Paywall copy

Only the copy and the free/Pro cards change:

- Headline: "Export in Full Quality".
- Benefits: "Full resolution", "HDR photos & videos", "No Markepi watermark".
- The free card says "Free: unlimited exports up to 2048 px, SDR, with a small Markepi mark."

The plans section, purchase flow and legal footer are unchanged.

## Risks / Trade-offs

- **[Simulator cannot verify video export]** (CoreMedia XPC fault) → verify the free 1080p SDR path and the mark on a device before release, as for every video change.
- **[A 30% size bound depends on content]** Very noisy photos compress worse → the test uses a representative fixture, and the spec states the bound for "typical" camera photos. Quality 0.7 at 2048 px lands near 15–20% on the reference set.
- **[Users dislike a watermark they didn't add]** → the mark avoids their elements, stays small and is shown before export in the comparison, so it is never a surprise.
- **[Cached entitlement can be stale in the extension]** → irrelevant: the extension does not export. The app refreshes `StoreManager` on launch, as today.
- **[Legacy `ShareExtensionViewModel` compile break]** → its quota calls switch to `ExportGate.tier`, with no behaviour change. Deleting the dead file is a separate cleanup.
- **[Marketing copy still says "3 free photos a day"]** → a release-checklist task updates the ASC description and What's New. Screenshots don't mention the limit.

## Migration Plan

1. Ship the engine policy and the mark behind the tier parameter, defaulting to `.pro`, so nothing changes yet. Tests land with it.
2. Switch the app entry points to `beginExport` and the comparison sheet, delete `ExportQuota`, and clean up its App Group keys.
3. Update the paywall copy and the ASC description, What's New and promo text for the release. Ship as 1.6.

Rollback: revert step 2. The engine tier code is inert at `.pro`.
