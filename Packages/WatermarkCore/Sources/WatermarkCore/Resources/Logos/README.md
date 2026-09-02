# Brand marks

The `gallery` frame style draws the mark of the manufacturer that took the
photo, read from the image's own metadata. The user never picks a brand — they
only pick colour or monochrome, and only where a brand ships both.

Everything in this directory is third-party trademarked artwork. It is used as
factual attribution: a mark only ever appears on a photo actually taken on that
manufacturer's device.

## Drop convention

One file per brand and variant, named `<brand-key>-<variant>.pdf`:

```
apple-color.pdf     apple-mono.pdf
samsung-color.pdf   samsung-mono.pdf
```

- `<brand-key>` is the lowercase key from the table below.
- `<variant>` is `color` or `mono`.
- Both variants are optional. Ship `mono` only, `color` only, or both — the
  variant control appears in the UI only for brands that have both.
- A brand with no file here resolves to no mark and no divider. A missing brand
  is a valid state, not a broken one, so brands can land one at a time.

## Supplying artwork

Hand over SVG (preferred), PDF, or EPS. SVG is converted with:

```sh
tools/logos/import-logo.sh <brand-key> <color|mono> path/to/artwork.svg
```

That converts to a single-page PDF, drops it here under the right name, and
checks the result opens as one page with a non-zero media box. A PDF handed over
directly is copied and checked the same way.

Vector only. A PNG would soften on a 48MP export, which is the whole reason
these are PDFs.

Artwork should be the plain mark on a transparent background — no wordmark
lockup, no padding, no background plate. The renderer scales it to the caption
band and centres it against the two text lines, so any baked-in margin shows up
as the mark sitting too small or off-centre.

## Brand keys

The `Make` column lists what the manufacturer actually writes into EXIF.
Matching case-folds, trims, and strips corporate suffixes, so every spelling in
a row resolves to the same key.

| Brand key   | Matches `Make`                                    |
|-------------|---------------------------------------------------|
| `apple`     | Apple                                             |
| `samsung`   | samsung, SAMSUNG                                  |
| `google`    | Google                                            |
| `canon`     | Canon, CANON                                      |
| `nikon`     | NIKON CORPORATION, Nikon                          |
| `sony`      | SONY, Sony                                        |
| `fujifilm`  | FUJIFILM                                          |
| `leica`     | LEICA CAMERA AG, Leica Camera AG                  |
| `panasonic` | Panasonic, PANASONIC                              |
| `olympus`   | OLYMPUS CORPORATION, OM Digital Solutions         |
| `xiaomi`    | Xiaomi, xiaomi                                    |
| `huawei`    | HUAWEI, Huawei                                    |
| `oneplus`   | OnePlus, ONEPLUS                                  |
| `dji`       | DJI, dji                                          |
| `gopro`     | GoPro, GOPRO                                      |

## Provenance

Record every file as it lands: where the artwork came from, and the licence or
usage terms it arrived under.

| File | Source | Licence / terms |
|------|--------|-----------------|
| _(none yet)_ | | |
