# App Store Connect creative assets: header and search (Oct 2026)

In October 2026 App Store Connect added two new image fields to each version's
localization. They are separate from screenshots and previews, and are set per
version and locale.

| Field | ASC placement type | Where it shows | Size we ship |
|---|---|---|---|
| **Product Page Header** | `PRODUCT_PAGE_HEADER_ASSET` | Wide art at the top of the product page | 3840×1646 PNG (21:9) |
| **Search Results** | `APP_STORE_SEARCH_RESULTS_ASSET` | Card shown in App Store search | 3840×2560 (3:2) |

Apple's guide: https://developer.apple.com/app-store/asset-best-practices/

## Specs

- **Header:** 21:9 at 3840×1646 (JPEG or PNG), or a universal 5244×2950 PNG.
  Upload PNG: our JPEG was rejected with `INVALID_ASSET_FILE_FORMAT`.
- **Search:** 3:2, from 1920×1280 up to 3840×2560.
- **No alpha channel.**
- Keep the focal art and text in the centre. The outer thirds get cropped on
  narrow devices.

## Best practices we follow

- One idea per asset, very little text, real app output only (no fake UI or
  claims).
- **Header:** five different framed photos fanned across the centre. No photo is
  used twice, and the black-haired woman from the screenshots is not used.
  - Headline: "Frame every shot".
  - Subline: "Smart photo looks, frames, watermarks and C2PA signatures that
    protect your work".
- **Search:** headline on the left, real phone screen on the right, two framed
  photos fanned behind the phone.
  - Headline: "Frame & watermark your photos".
  - Subline: "Smart photo looks. Real camera details. Your logo and C2PA
    protection."
  - The phone mask goes on the whole phone, not just the screen rect, or the
    screen looks pasted on.
- Every demo photo has real location metadata, so its frame shows a place:
  - Woman: Montreux, CH
  - Lake: Braies, IT
  - Neon: Tokyo
  - Village: Manarola, IT
  - Cafe: Paris
- Never the developer's real name in demo content.

## Make them

Sources are in `tools/screenshots/`:

- `creative.html` is the layout. `?s=header` or `?s=search` picks the asset.
- It loads its images from `cap/v2/creative/`. Those are real Markepi renders,
  made with the CLI (`--look`, `--border-*`) from Krea-2 synthetic photos.

```sh
cd tools/screenshots
node creative-render.mjs header search   # → out/creative-header.png, out/creative-search.png (needs playwright)
```

Check both outputs at full size before uploading. Shipped copies are in
`~/Projects/Markepi-Assets/v2.0-screenshots/creative/`.

## Upload

```sh
ASC_ISSUER_ID=… python3 tools/screenshots/upload_creative.py 2.1 header out/creative-header.png
ASC_ISSUER_ID=… python3 tools/screenshots/upload_creative.py 2.1 search out/creative-search.png
```

What the script does, through the ASC API:

1. `POST /v1/appAssetLibraryImages`
   - `category: CREATIVE_ASSETS`, plus `fileName` and `fileSize`.
   - Relationship `assetLibrary` → `appAssetLibraries`, where the id is the
     **app id**.
2. Run the returned `uploadOperations`.
3. `PATCH {uploaded: true}`. Unlike screenshots, there is no checksum
   attribute.
4. Poll the image `state` until it leaves `PROCESSING`.
5. Delete the old placement of that type, found under
   `/v1/appStoreVersionLocalizations/{id}/placements`.
6. `POST /v1/appAssetLibraryPlacements` with `placementType`, plus relationships
   `appStoreVersionLocalization` and `image`.
7. The placement goes from `PENDING` to **`ACTIVE`**, which means it is live on
   that version.

The images stay in the app's asset library (`/v1/apps/{id}/assetLibrary`), so a
later version can reuse them by placing the same image id. You don't need to
upload them again.

## Related changes in the same release

- **iPhone 6.1"/6.3" screenshots (`APP_IPHONE_61`, 1206×2622):**
  - ASC now shows this as the medium display size.
  - Without this set, the iPhone screenshots looked faded (scaled down from
    6.9"), so upload this set too.
- **iPhone Duo screenshots** (1398×2034 / 2007×2853) are not required until
  April 2027, so we skipped them.
- **Previews:**
  - iPhone sets: IPHONE_67, IPHONE_65 and IPHONE_61.
  - iPad set: IPAD_PRO_3GEN_129.
  - Length 5–30 s. See `tools/reel/GUIDE.md`.
