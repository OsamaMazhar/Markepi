# Brand marks

Generated. Do not edit by hand — run `tools/logos/build-logos.sh`, which
rebuilds this directory from the artwork in `Packages/WatermarkCore/LogoSources/`.

The `gallery` frame style draws the mark of the manufacturer that took the
photo, read from the image's own metadata. The user never picks a brand — they
only pick colour or monochrome.

Everything here is third-party trademarked artwork, used as factual
attribution: a mark only ever appears on a photo actually taken on that
manufacturer's device.

## What ships

`<brand>-<variant>.<pdf|png>`, flat, where variant is `color`, `black` or
`white`.

- **`color`** — vector PDF, converted from each brand's official SVG. Every
  brand has one.
- **`black` / `white`** — vector PDF where an official mono SVG was supplied
  (Apple), otherwise the official 1024px transparent PNG.

Vector wins wherever a vector exists. The mono rasters are only ever
downscaled: a mark draws at roughly 200–400px even on a 48MP export, so a
1024px master never has to be stretched.

`color` vs mono is the user's choice. Which mono — `black` or `white` — is not:
the renderer picks whichever contrasts with the mat, so `white` only comes up
if a dark mat is ever added.

A brand with no file here resolves to no mark and no divider, which is a valid
state rather than a bug.

## Aspect ratios vary wildly

Most of these are wordmarks, not glyphs: Canon and Sony are ~10:1, Xiaomi is
~1:1, some are taller than wide. The renderer sizes a mark by **height** to fit
the caption band and lets width follow, then caps the width so a long wordmark
cannot crowd out the caption text.

## Brand keys

`Make` is what the manufacturer actually writes into EXIF. Matching case-folds,
trims, and strips corporate suffixes, so every spelling in a row resolves to
the same key.

| Brand key    | Matches `Make`                                                  |
|--------------|-----------------------------------------------------------------|
| `apple`      | Apple                                                            |
| `canon`      | Canon, CANON                                                     |
| `dji`        | DJI, dji                                                         |
| `fujifilm`   | FUJIFILM                                                         |
| `google`     | Google                                                           |
| `gopro`      | GoPro, GOPRO                                                     |
| `hasselblad` | Hasselblad, HASSELBLAD                                           |
| `honor`      | HONOR, Honor                                                     |
| `huawei`     | HUAWEI, Huawei                                                   |
| `insta360`   | Insta360, Arashi Vision                                          |
| `leica`      | LEICA CAMERA AG, Leica Camera AG                                 |
| `motorola`   | motorola, Motorola                                               |
| `nikon`      | NIKON CORPORATION, Nikon                                         |
| `nothing`    | Nothing, Nothing Technology                                      |
| `olympus`    | OLYMPUS CORPORATION, OLYMPUS IMAGING CORP., OM Digital Solutions  |
| `oneplus`    | OnePlus, ONEPLUS                                                 |
| `oppo`       | OPPO, oppo                                                       |
| `panasonic`  | Panasonic, PANASONIC                                             |
| `pentax`     | PENTAX, PENTAX Corporation, RICOH IMAGING COMPANY, LTD.          |
| `realme`     | realme, RealMe                                                   |
| `redmi`      | Xiaomi **with** a `Model` starting "Redmi" — see below            |
| `samsung`    | samsung, SAMSUNG                                                 |
| `sony`       | SONY, Sony                                                       |
| `vivo`       | vivo, VIVO                                                       |
| `xiaomi`     | Xiaomi, xiaomi                                                   |

### Sub-brands need `Model`, not just `Make`

Redmi phones write `Make = Xiaomi` and put the sub-brand in `Model`
(`Redmi Note 13`, …). `Make` alone would give every Redmi the Xiaomi mark, so
resolution checks `Model` for known sub-brands before falling back to the
`Make` match. Honor is the mirror image: current devices write `HONOR`, but
Huawei-era Honors wrote `HUAWEI`, and those correctly get the Huawei mark —
that is what the metadata says.

## Provenance

Artwork supplied by the project owner, 2026-09-02: 25 brands, official
full-colour vectors plus official monochrome renditions. Each brand's original
files are kept verbatim under `LogoSources/<brand>/`.
