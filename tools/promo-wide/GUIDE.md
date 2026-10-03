# Wide promo (Reddit / 16:9)

24 s, 1920×1080, 30 fps promo with narrator, cut to the music's beat. Shipped
as `markepi_reddit-wide_24s_v03_20261003.mp4` (r/AppHookup, lifetime sale).

```sh
cd tools/promo-wide && npm i          # gsap + playwright (chromium: npx playwright install chromium)
node render.mjs 45,335,512            # stills -> stills/  (check before a full render)
node render.mjs                       # film -> $MARKEPI_MV/out/markepi_reddit-wide_<len>s_v03_<date>.mp4 (~75 s)
node render.mjs --audio-only          # remix audio only (~10 s)
```

## Inputs (not in git)

| What | Where |
|---|---|
| App Store slides `0N-iPhone67.jpg` | `~/Projects/Markepi-Assets/v1.5-screenshots` (`MARKEPI_SLIDES`) |
| App screen recordings `frames/st_*` | `../reel/web/frames` (run `tools/reel/build.py`) |
| Music, SFX, narrator WAVs, `out/` | `~/Projects/Markepi-Assets/marketing-videos` (`MARKEPI_MV`) |

`render.mjs` symlinks `slides`, `frames` and `icon.png` here on first run.

## Shape (beat grid: music-stolen-128bpm, beat k at 0.459 + k·0.46875 s)

| Beats | Scene |
|---|---|
| 0–8 | Tilted 3D wall of slides + "Watermark. Frame. Share." one word per two beats |
| 8–16 | Orange phone playing real frame-style footage, one style per beat, ticker on the left |
| 16–32 | Coverflow of slides 03–09, one per two beats, headline reveal + counter |
| 32–40 | Drop: fanned slides pan across, one big word per beat with a camera punch |
| 40–50 | Endcard: icon, wordmark, tagline, "Download now on the App Store" |

`promo.html` is deterministic: `renderAt(frame)` seeks a paused GSAP timeline, then
draws the procedural layer (background blobs, wall scroll, phone frames, coverflow,
fan, grain) from `t`. Same frame in, same pixels out.

## Narrator

`lines.json` holds the five lines. Generate them in the approved voice with
`python3 tools/vo_make.py <this>/lines.json` from the marketing-videos folder (M5,
one job at a time). Placement is the `vo` list in `render.mjs`; music ducks under
the voice (sidechaincompress). Whisper scoring rejects "twelve" and "Markepi":
keep both out of the lines.

`beat.py <audio> <bpm>` prints a track's beat phase and 2 s energy envelope — use it
to find the first beat and the drop before laying out a new grid.

## Pitfalls

- A GSAP `fromTo` paints its *from* state before it starts when you seek. Use
  `set` + `to` for flashes (else the whole film turns milky), and start hidden
  text at `opacity: 0` / `yPercent: 160` (blur and scale spill past the line clip).
- Cards that have passed in the coverflow must fade fast or they sit under the copy.
- The VO mix must be padded to the film length (`apad,atrim`), or the ducking
  filter ends with the last line and cuts the endcard.
