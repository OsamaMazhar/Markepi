# markepi — command-line watermarking

`markepi` is a macOS CLI front end for the same `WatermarkCore` pipeline the
Markepi iOS app uses. Text watermarks, logos, the white frame with an EXIF
caption, and the retro film date stamp — scriptable, batchable, no simulator.

Metadata (EXIF, GPS, HDR gain map, colour profile) is preserved unless you ask
otherwise with `--privacy`.

## Build & run

```sh
cd Packages/WatermarkCore
swift build                 # first build downloads the c2pa binary artifact (large)
swift run markepi --help
```

The binary lands at `.build/debug/markepi`. Put it on your `PATH` if you use it
often:

```sh
sudo ln -sf "$PWD/.build/release/markepi" /usr/local/bin/markepi   # after: swift build -c release
```

The target has no product, so Xcode never builds it — `scripts/build-gate.sh`
and the app builds are unaffected.

## Quick start

```sh
markepi photo.jpg -o out.jpg --text "© Osama Mazhar"
```

Everything else is optional. Each feature turns on when you pass one of its
flags, so `--border-caption "Shot on"` implies `--border`, and `--date-size 0.04`
implies `--date-stamp`.

## The four features

### Text watermark

```sh
markepi photo.jpg -o out.jpg \
  --text "LUCERNE · 2026" \
  --text-font montserrat \
  --text-position topLeft \
  --text-size 0.022 \
  --text-color "#FFFFFFCC"
```

`--text-size` is a fraction of the **image height** (0.01–0.90, default 0.045).
`--text-color` takes `#RRGGBB` or `#RRGGBBAA`; `--text-opacity` multiplies on
top of the alpha channel.

EXIF tokens are substituted into the string:

| Token | Token | Token |
|---|---|---|
| `{camera_model}` | `{lens}` | `{aperture}` |
| `{focal_length}` | `{shutter_speed}` | `{iso}` |
| `{date}` | `{gps}` | `{dimensions}` |
| `{format}` | | |

Missing values render as `--`, so check your source has the EXIF before
building a caption out of tokens.

```sh
markepi photo.jpg -o out.jpg --text "{camera_model} · {focal_length} · ISO {iso}"
```

### Logo

```sh
markepi photo.jpg -o out.png --format png \
  --logo brand.png \
  --logo-position topRight \
  --logo-size 0.20 \
  --logo-opacity 0.75 \
  --logo-rotation -8
```

`--logo-size` is a fraction of the **image width**. PNG keeps transparency.
A white logo on a bright sky disappears — place it over a darker region or
raise the opacity.

### White frame

```sh
markepi photo.jpg -o out.jpg \
  --border \
  --border-caption "Lake Lucerne, Switzerland" \
  --border-fields cameraModel,focalLength,aperture,iso
```

`--border-caption` is free text (tokens work here too) printed before the
metadata fields. `--border-fields` picks which fields follow it; they always
print in this canonical order regardless of how you list them:

`cameraModel, lens, focalLength, aperture, shutterSpeed, iso, date, dimensions, format, gps`

`--border-no-text` gives you a clean frame with nothing written in it.
`--border-width` (0.03–0.05) and `--border-text-size` (0.005–0.05) are
fractions of the **short edge**.

### Date stamp

```sh
markepi photo.jpg -o out.jpg --date-stamp --date-format classicShortYear
```

Burns in the orange film-databack date read from the photo's capture date.
Formats: `dayMonthYear` (default), `dayMonthYearDash`, `yearMonthDay`,
`monthDayYear`, `classicShortYear`, `dayMonthText`. `--date-size` is a fraction
of the image height (0.015–0.12). Film cameras stamped the lower corners, so
`--date-position` defaults to `bottomLeft`.

## Positions

All nine positions apply to `--text-position`, `--logo-position` and
`--date-position`:

```
topLeft       topCenter       topRight
middleLeft    center          middleRight
bottomLeft    bottomCenter    bottomRight
```

## Layer order

Text → logo → border → date stamp. With a border on, the text and logo are
inset so they stay inside the frame rather than under it.

## Fonts

```sh
markepi --list-fonts
```

29 bundled faces in four groups (serif, sans-serif, script, monospace). Pass
either the short id (`great-vibes`) or any PostScript name installed on this
Mac (`HelveticaNeue-Bold`).

> An unrecognised `--text-font` value is passed through to the renderer as a
> PostScript name rather than rejected — that's what makes system fonts work,
> but it also means a typo silently falls back to the system face instead of
> erroring.

## Output & metadata

| Flag | Meaning |
|---|---|
| `-o, --output <path>` | Required. Refuses to overwrite without `-f`. |
| `-f, --force` | Overwrite an existing output file. |
| `--format <fmt>` | `preserve` (default) · `heic` · `jpeg` · `png` · `tiff` |
| `--quality <0–1>` | Lossy-format quality, default `1.0` |
| `--padding <points>` | Minimum edge padding; the engine uses `max(padding, 4% of short edge)` |
| `--privacy <profile>` | `preserveAll` (default) · `stripSensitive` · `minimalPublic` |

`stripSensitive` drops GPS and body serial numbers but keeps camera model, ISO
and capture date. `minimalPublic` keeps only the essentials.

```sh
markepi photo.jpg -o share.jpg --text "©" --privacy stripSensitive
```

## Batching

Nothing special — it's a normal CLI:

```sh
mkdir -p out
for f in ~/Photos/*.jpg; do
  markepi "$f" -o "out/$(basename "$f")" -f \
    --border --border-caption "Shot on" --border-fields cameraModel,focalLength,iso
done
```

## Exit codes

`0` on success, `1` on any error with a message on stderr:

```
markepi: no such file: /path/to/missing.jpg
markepi: /path/to/out.jpg already exists — pass --force to overwrite
markepi: invalid value "middle" for --text-position. Expected one of: topLeft, topCenter, …
markepi: nothing to apply — pass --text, --logo, --border or --date-stamp
```

On success it prints the written path and its UTI:

```
/Users/you/out.jpg  [public.jpeg]
```

## Not covered

Videos, Live Photos, hand-drawn signatures and C2PA Content Credentials are
app-only. The CLI signs nothing and writes no manifest.
