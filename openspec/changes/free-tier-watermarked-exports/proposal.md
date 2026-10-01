## Why

The free tier today caps exports at 3 photos and 1 video a day with every feature unlocked. That stops free users the moment they want to use the app, which costs us both retention and word of mouth. Markepi will move to the model AutoAlign uses: free users export as much as they like, but the files are smaller and lower in quality than the Pro version and carry a small "Markepi" mark. Pro removes all three limits. Each free export spreads the brand, and when a user exports, a comparison shows what Pro gives them.

## What Changes

- **BREAKING (business model):** remove the free daily export quota (3 photos + 1 video). Free users get unlimited photo, Live Photo and video exports, in the app and in batches.
- Free photo exports are reduced in quality. The pixel size is capped and the compression is lossier, so a 10 MB original exports at about 2 MB, and smaller originals shrink in proportion.
- Free exports drop HDR. Photos lose the gain map and videos are exported as tone-mapped SDR. Pro keeps HDR as it does today.
- Free video exports are capped at 1080p H.264 at a lower bitrate. Pro keeps the source resolution and HDR preset.
- Free exports get an automatic "Markepi" text watermark on the photo area, never on a frame border. It is added **only to the exported file**: the live preview never shows it.
- The automatic mark avoids the user's own elements: text, logos, signatures and the date stamp. It tries the four corners first, then the centre, then the top-middle or bottom-middle of the photo. It never uses the middle of the left or right side.
- On export, free users see a new **comparison sheet**, modelled on AutoAlign's `SaveComparisonSheet`. It shows Pro (full resolution, HDR, no mark) next to Free (reduced resolution, SDR, with the mark), each with spec chips, and offers "Unlock full quality" or "Export free". The sheet covers photos and videos.
- The paywall copy changes from "Unlock Unlimited Exports" to the full-quality pitch: full resolution, HDR, no Markepi mark.
- C2PA / Content Credentials signing stays available to free users. Signed free exports record that a visible watermark was applied.
- Pro users and the DEBUG "Force Premium" override see no change: full quality, HDR, no mark and no comparison sheet.

## Capabilities

### New Capabilities
- `export-tiers`: what a free export and a Pro export each produce for photos, Live Photos, videos and batches (resolution, compression, HDR, codec). It also covers the removal of the daily quota and C2PA staying free.
- `free-tier-watermark`: the automatic "Markepi" mark on free exports, covering export-only application, placement on the photo area, avoiding user layers (corners → centre → top/bottom middle, never side middles) and its size and style.
- `upgrade-comparison`: the Free vs Pro comparison sheet shown when a free user exports. It covers its content, actions and how it resumes the export after a purchase.

### Modified Capabilities
<!-- None: no existing spec (offline-geolocation, photo-frames) covers monetisation or export quality. -->

## Impact

- **MarkepiCore / Premium:**
  - `ExportQuota` is retired.
  - `ExportGate` changes from "may export?" to "which tier is this export?" (`ExportTier`).
  - `PremiumStatusStore` and `StoreManager` are unchanged.
- **MarkepiCore / Engine:**
  - `WatermarkEngine.process`, `processVideo` and `processLivePhoto` take an export tier.
  - Photo path: downscale (the existing `maxPixelDimension`), quality override and gain-map drop.
  - The brand-mark layer is injected after the user's layers are laid out (uses `RenderLayout.layerFrames`).
  - `VideoProcessor`: a free preset with SDR tone mapping and a 1080p cap.
  - `BatchProcessor` passes the tier through.
- **App:**
  - `WatermarkViewModel` export entry points: the paywall gate becomes a comparison gate, and the quota accounting goes.
  - `ContentView` presents the new sheet.
  - `PaywallView` copy and the free/Pro cards change.
  - New `ExportComparisonSheet` view.
- **ShareExtension:** the legacy `ShareExtensionViewModel` still references `ExportGate`. It must keep compiling, but the shipping extension is a handoff bridge and behaves the same.
- **Tests:**
  - `ExportQuota` tests are replaced.
  - New tests for tier output (size, missing gain map, video SDR/1080p), mark placement and preview exclusion.
- **App Store:** the description, What's New and screenshot captions that say "3 free photos a day" must change before release. Existing paid users are unaffected.
