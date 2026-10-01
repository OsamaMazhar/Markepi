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

### 3. The free mark is drawn by the renderers, not added as a user layer

`BrandMark` (MarkepiCore/Rendering) produces the mark and picks its slot:

- `BrandMark.image(for:)` makes a lockup: the white Markepi app-icon tile (`Resources/Brand/markepi-white.png`, the "M" knocked out) on the left of "Markepi" in the bundled Cookie script, 6% of the frame's shorter side tall, with a blurred 55% black shadow, at 72% opacity. The lockup is flattened to a bitmap before the shadow, since a lazy graph streaks the text past its crop.
- `buildFilterGraph(brandMark:)` for photos and `VideoLayerBuilder.buildLayers(brandMark:)` for video add it after the user's layers and the date stamp. Both already know where each of those landed (`layerRects`, the CALayer frames) in the photo's own coordinates. These are the same coordinates user layers are positioned in, so the mark can never land on a frame's mat.
- The mark never enters `WatermarkConfiguration`, so it can't reach the preview, the Layers panel, templates or saved settings. `renderPreview` has no `brandMark` input at all.

**Alternative considered:** append a synthetic `.text` layer to a config copy, as the first draft planned. Rejected for these reasons:
- It needed a new `shadow` field on `TextWatermarkInput`.
- It needed a separate layout pass to find occupied space.
- The renderers already hold the exact rects, which makes the in-renderer version smaller and exact.

### 4. Slot choice

`BrandMark.slot(mark:base:padding:occupied:)` is pure and unit-tested:

- It walks `slotOrder = [.bottomRight, .bottomLeft, .topRight, .topLeft, .center, .bottomCenter, .topCenter]`.
- Each candidate rect is built with `PositionCalculator`, the same maths the renderers use.
- It returns the first slot with zero overlap, or else the least-overlap slot; ties keep the order.
- Side middles are absent by construction.

`occupied` is the visible user layers plus the date stamp. Dragged (`.custom`) layers count wherever they actually render. A video's slot is chosen once in the layer builder, so it is fixed for the whole clip.

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

Signing is untouched. The manifest's `visibleWatermarkApplied` becomes `!config.watermarks.isEmpty || policy.brandMark`, so a signed Free export says a visible watermark was applied even when the user added none.

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
