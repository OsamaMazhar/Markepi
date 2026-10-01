# Screenshot notebook — how the 1.5 store screenshots were made (2026-09-30)

End-to-end record of the pipeline that produced the current App Store
screenshots (9 iPhone 6.9", 9 iPhone 6.5", 9 iPad 13"), so any app — not just
Markepi — can rerun it. Working scripts live in `tools/screenshots/`. Final
JPEGs per release: `~/Projects/<App>-Assets/v<ver>-screenshots/`.

## The shape

```
simulator ──ui.sh/style.sh/tap.sh/cap.sh──▶ cap/NN-*.png (+ .json preview rect)
Remotion iPhone GLB ──phone.mjs──▶ frame.png + screen_mask.png (flat phone)
MarkepiCore CLI ──▶ pop/NN_web.jpg (the framed photo that "lifts out")
            ┌── slide.html (iPhone, 1320x2868) ── render.mjs ──▶ out/setB/NN.png
captures ──┤
            └── ipad.html  (iPad, 2064x2752) ── ipad-render.mjs ─▶ out/setB-ipad/
Playwright headless Chromium ─▶ 2048/1284-wide JPEGs ──▶ tools/aso/screenshots.py ─▶ ASC
```

## 1. Simulator setup (per device)

```sh
xcrun simctl boot <udid>; xcrun simctl bootstatus <udid> -b
xcrun simctl ui <udid> appearance dark
xcrun simctl status_bar <udid> override --time "9:41" --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3
# skip onboarding + force premium (DEBUG), before FIRST launch:
C=$(xcrun simctl get_app_container <udid> <bundle> data)
G=$(xcrun simctl get_app_container <udid> <bundle> group.<group>)
PlistBuddy -c "Add :hasCompletedOnboarding bool true" "$C/Library/Preferences/<bundle>.plist"
PlistBuddy -c "Add :appearancePreference string dark"    "$C/Library/Preferences/<bundle>.plist"
PlistBuddy -c "Add :debug.forcePremium bool true"        "$G/Library/Preferences/group.<group>.plist"
xcrun simctl privacy <udid> grant photos <bundle>
```

English locale for captures: `simctl spawn <udid> defaults write -g AppleLanguages -array en-US`
+ reboot (the sims carry over the last session's language; Arabic was still set once).

## 2. Driving the app (axe)

- `axe tap/drag/swipe/type/key --udid …`. **Tap by fresh coordinates, never by
  `--label`** — label taps resolve against a cached layout and land on the wrong
  element (a "Noir" tap once selected "Sunlight"). The helpers dump the a11y tree
  each time: `ui.sh <udid> <grep>` → `tap.sh <udid> "<exact label>"` reads the
  element's current frame and taps its centre.
- Load photos through the **share inbox**, not the picker:
  `load.sh <udid> file…` stages each file under `PendingShares/<uuid>/` in the
  App Group (the store reads one file per uuid subfolder — a bare file is
  ignored), then relaunch drains it. No permission prompts, no picker driving.
- `style.sh <udid> <Style>` scrolls the frame strip until the style is on screen
  and taps it. On iPad set `SW=1032 K=2` (points width, retina scale) and run
  helpers with those exported.
- Controls panels: the tool re-tap closes a panel ("Hide … controls"), which
  gives the full-bleed preview Osama wants (never cover the phone top).
- Keyboard: `axe key 40` = return, `42` = delete. `axe type` cannot type © —
  type an ASCII substitute or let the app autofill from the creator field.
- Capture + record the preview rect for the compositor: `cap.sh <udid> <dir> <name>`
  writes `NN.png` (full-res) and `NN.json` `{"preview":[x,y,w,h]}` in pixels.
- **C2PA state**: the More-panel toggle ignored taps on iPad. Workaround used:
  the config persists as JSON under `watermarkConfiguration` (+`…SchemaVersion`)
  in the App Group plist — copy both keys from a device/sim where it was set,
  relaunch, done. iPhone accepted `axe tap` on the switch centre; also needed:
  creator name typed first, then "Sign with Content Credentials" → "Sign now".
- Screenshots: `simctl io … screenshot` hung on a wedged sim once; `axe screenshot`
  is the fallback. If `axe` says "Timed out creating the simulator remote
  automation session", retry — it is transient; a wedged sim needs shutdown+boot.

## 3. The flat phone frame (once per model)

`phone.mjs` + `phone.html` render `~/Projects/Remotion-iPhone3D`'s
`iphone17promax.glb` straight-on (orthographic, RoomEnvironment lighting) with
the screen mesh (`Object_49`) painted key green. `phone.json` is the geometry;
then:

1. **Green-screen key** (numpy): greenness = `(G − max(R,B))/200`; despill
   `G = min(G, max(R,B))`; crop to the phone bbox → `frame.png` (hole where the
   screen was) + `screen_mask.png`.
2. **The mask must have real alpha** — browsers mask with the alpha channel; a
   greyscale mask silently does nothing and the capture's square corners poke
   out of the rounded screen. `screen_mask.png` ships as L→alpha already.

`phone.json` = `{"phone":[w,h], "screen":[x,y,w,h]}` in frame pixels. Regenerate
only if the GLB changes (SCREEN_NODE / FACING_ROTATION_Y lore lives in that repo's HANDOFF.md).

## 4. Pop-out renders

Real engine output, one per slide, so the lifted photo shows the exact feature:

```sh
M=$(cd Packages/MarkepiCore && swift build -c release --show-bin-path)/markepi
$M photo.HEIC -o pop/04.jpg --format jpeg --border-style sunlight \
   --text "Northlight Studio" --text-font Pacifico-Regular --text-position bottomRight --text-size 0.05 -f
```

Logo/signature assets: Qwen-Image on the M5 (`ssh llama`, white-on-black, then
`lumakey.py in.png out.png` turns luminance into alpha — the RGBA bg-removal
path keeps the black box on white-on-black art). Never run two M5 jobs at once.
Never use Osama's real name in demo content — "Northlight Studio" is the stand-in.

## 5. Composition (HTML/CSS/JS + Playwright)

- `npm i playwright && npx playwright install chromium` (any scratch dir).
- `slide.html` (iPhone): background = base gradient + blurred blooms + conic
  rays (soft-light, blurred) + SVG grain + vignette — no AI images; colours are
  per-slide art-directed (`P.blue/gold/…`). Caption = chip + 2-line h1 +
  2-line sub. Phone = flat `frame.png` with the capture in the masked screen
  hole. Pop-out = the render at the recorded preview rect, scaled, straight
  (NO rotation/tilt — rejected), deep layered shadows + sheen.
- Controls pop-outs (`crop:` slides): cut the panel from the capture itself
  (pixel-scan for the card edges), place at its own rect scaled 1.2×.
- Layout law: phone starts ~70px under the caption and grows to fill the canvas
  (bleeds off the bottom); every slide has identical 2+2 caption lines so the
  phone sits at the same height on all slides.
- `ipad.html` (iPad): no bezel — the capture is a rounded card (radius 56)
  bleeding off the bottom; pop-outs sized by a **uniform fit rule**
  (`min(1400, 1500·ar)`) rather than from the rect, or they swamp the card.
- Render: `node render.mjs 01 02b …` / `IPAD=1`-style env in `ipad-render.mjs`;
  screenshots at exact ASC pixel sizes. JPEG export: sRGB, quality 95,
  subsampling 0; resize (LANCZOS) to 1284x2778 (6.5") / 2048x2732 (iPad).

## 6. Captions = ASO

Popularity scores came from the **Apple Ads API** keyword suggestions
(`apple_ads_platform` SDK, one seed per call, ~2s pause; popularity 5 = floor =
no volume). What mattered for Markepi (US): photo editor 66, exif metadata 13,
photo editor text 13, add watermark 15, watermark 10–14, white border / border 8,
protect 9, exif viewer 9, photo text editor 11. Apple does **not** index
screenshot text — write for comprehension first, keywords second; avoid terms
dominated by collage apps ("photo frame" → Frameo/collage).

## 7. Upload

```sh
A=<any repo>/tools/aso   # AutoAlign's screenshots.py + asc_api.py (ASC API key auth)
ASC_APP_ID=6782552371 python3 $A/screenshots.py <jpg_dir> en-US \
    APP_IPHONE_67="*iPhone67*" APP_IPHONE_65="*iPhone65*" --replace --dry-run   # then drop --dry-run
```

- Display type is decided by **pixel size**: 1320x2868→67, 1284x2778→65,
  2048x2732→iPad 12.9/13. Filename sort = display order (no reorder API).
- `--replace` empties the set first (otherwise it appends). The commit PATCH
  (checksum) is mandatory — an uncommitted asset silently blocks submission.
- Verify after upload: every screenshot `assetDeliveryState.state == COMPLETE`.

## 8. Slide set that shipped (order matters)

01 hero (Aura) · 02b 12 new photo frames (Noir, panel closed) · 02c Custom photo
borders (Frame panel pops out) · 03 Real EXIF (Readout + EXIF pills) · 04b Add
text · 05b logo & signature · 06 videos · 07c share sheet pop-out · 08c C2PA
signed records pop-out. `b` = photo pops out, `c` = controls pop out; both were
rendered, Osama picked b for text/logo, c for borders/share/C2PA.

## 9. App preview video (reel)

Full runbook: `tools/reel/GUIDE.md`. Shape: record each flow in the simulator
(`tools/reel/rec.sh` + the axe helpers above) → `build.py` converts to CFR 30 and
cuts segments by frame index → `web/reel.html` (deterministic `renderAt(frame)`,
scenes + phone footage in the app-icon palette) → `render.mjs` (Edge + Playwright →
ffmpeg) → Stable Audio music on the M5, picked by energy envelope, loudnorm −14 LUFS
→ `upload_asc.py` (IPHONE_67, poster frame on the logo lock-up). Shipped on 1.5:
29.6 s, chapters frames · text · logo · video · share-in · C2PA · share.

Lessons: read cut times off contact sheets of the CFR video, not wall-clock marks
(~2 s lag); keep under 30 s; show demo marks on a dark frame so white logos read;
the share sheet populates late, so cut around the empty state.
