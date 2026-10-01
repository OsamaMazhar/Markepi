# App Store reel (app preview video)

Builds the 29.6 s, 886×1920, 30 fps iPhone app preview from real simulator
recordings, adds music, and uploads it to App Store Connect (IPHONE_67, en-US).
Shipped on 1.5: `out/Markepi-Reel.mp4` (with music) and `out/Markepi-Reel-silent.mp4`.
Adapted from AutoAlign's reel (`~/.superset/worktrees/AutoAlign/magnificent-nylon/tools/reel/`).

## Pipeline

| Step | Command | Makes |
|---|---|---|
| 1. Record | `rec.sh start <udid> rec/<name>.mp4` … drive the app … `rec.sh stop` | `rec/<name>.mp4` (gitignored) |
| 2. Frames | `python3 build.py` | `rec/<name>_cfr.mp4`, then `web/frames/<segment>/0001.jpg…` |
| 3. Music | see below | `music/zimmer_s7.flac` |
| 4. Render | `cd web && npm i playwright-core --no-save && node render.mjs reel` | `~/Desktop/Markepi-Reel.mp4` (silent track) |
| 5. Add music | see below | `~/Desktop/Markepi-Reel.mp4` |
| 6. Upload | `ASC_ISSUER_ID=… python3 upload_asc.py 1.5` | replaces the en-US IPHONE_67 preview, waits for COMPLETE |

Spot-check frames: `node render.mjs reel 315,345,405` → PNGs in `web/out-reel-en/`.

## Files

- `rec.sh` – background `simctl io recordVideo`. Drive the app with
  `../screenshots/{ui,tap,style,load}.sh` (fresh-coordinate taps; `load.sh` stages
  photos through the App Group share inbox).
- `rec/` – raw recordings of each flow: `frames` (style cycling), `text`, `logo`,
  `video`, `sharein` (Photos share sheet → Markepi), `c2pa`, `share`, `drag` (unused).
- `build.py` – `SEGMENTS`: `name: (recording, start s, end s, speed)`. Times are
  **video time of the CFR copy** — read them off a contact sheet
  (`ffmpeg -ss T -i rec/x_cfr.mp4 -vf "fps=2,scale=150:-2,tile=12x3"`), never from
  `.marks` wall-clock stamps (they lag the video by ~2 s).
- `web/reel.html` – the reel. `T` holds every on-screen word; scenes are
  `S(dur, draw)`, phone footage is `footage(parts, meta)` with parts
  `{clip, n, from, step, last, sub}` (`n` frames played, `last` holds the final
  frame). `window.renderAt(frame)` is deterministic. Palette from the app icon
  (`--brand #2f62d6`, navy `#06102a`, ice `#cfe0ff`); `web/icon.png` = app icon.
- `web/render.mjs` – Playwright drives Microsoft Edge at 886×1920, pipes PNGs to ffmpeg.
- `assets/northlight-logo.png` – the demo logo (white, alpha) used in the logo chapter;
  add it to the sim with `xcrun simctl addmedia`. Demo identity is "Northlight Studio",
  never a real name.
- `upload_asc.py` – app 6782552371; deletes old previews in the set, uploads in chunks,
  commits with MD5, poster frame 00:00:28:00 (the logo lock-up).

## Music (Stable Audio on the M5, one job at a time)

```sh
cd ~/.superset/worktrees/AutoAlign-Video/helix-buttercup
for s in 7 21 42; do python3 image/qwen_m5.py "Epic cinematic hybrid orchestral trailer music in the style of Hans Zimmer, 128 BPM, driving high-energy percussion, huge taiko drums and punchy electronic kick, pulsing staccato strings ostinato, deep braaam brass hits, rising synth arpeggios, big risers and impacts, heroic and triumphant, modern polished trailer mix, instrumental, no vocals" \
  -o <this dir>/music/zimmer_s$s.flac --audio music --seconds 32 --seed $s; done
```

Pick by the energy envelope (2 s RMS windows): s42 died at 18 s, s21 at 29 s, s7 held
to 30 s and peaks 22–28 s → shipped. Mux:

```sh
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 silent.mp4)
ffmpeg -i silent.mp4 -i music/zimmer_s7.flac -map 0:v -map 1:a -c:v copy \
  -af "atrim=0:$D,loudnorm=I=-14:TP=-1.5:LRA=11,afade=t=in:d=0.08,afade=t=out:st=$(echo "$D-0.9"|bc):d=0.9,aresample=48000" \
  -c:a aac -b:a 256k -shortest -movflags +faststart Markepi-Reel.mp4
```

## Landmines

- Simulator recordings are VFR: convert to CFR 30 first, cut by frame index
  (`select=between(n,…)`), or segment lengths drift.
- Slow UI: each `tap.sh` dumps the a11y tree (~2.5 s). For tight takes, look the
  coordinates up once and `axe tap -x -y` directly.
- The share sheet's app icons load ~4 s after it opens: cut the tap, then jump to the
  populated sheet (`share_out` parts in reel.html).
- White logo on a white border is invisible — use a dark frame (Noir) for the logo take,
  size ≥ 90. The size stepper has no auto-repeat on long-press; tap it (0.5 per tap).
- The logo picker is out-of-process (no a11y tree): tap tiles by coordinates.
- App Store preview limit is 30 s; the render prints the frame total, check it.
