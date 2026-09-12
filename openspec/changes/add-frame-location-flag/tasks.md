## 1. Offline country boundary dataset

- [ ] 1.1 Pick a public-domain country-boundary source (e.g. Natural Earth admin-0 1:110m) and a simplification level, and record the choice plus provenance in `tools/geo/README.md`, resolving design.md's open question
- [ ] 1.2 Write `tools/geo/build-country-boundaries.*`, a one-time script that emits each country's ISO 3166-1 alpha-2 code, its simplified rings, and a precomputed bounding box as a compact resource, and verify it runs end to end and produces a non-empty output file
- [ ] 1.3 Validate the generated dataset against a fixture list of coordinates that must resolve — including the small territories a coarse approach would have lost (Monaco, Singapore, Vatican City, Liechtenstein, Malta, Bahrain, Andorra) plus a few known border regions — and verify every entry resolves to its correct code
- [ ] 1.4 Add the generated resource to `WatermarkCore`'s `Package.swift` resources alongside the existing `Fonts`/`Logos` entries, and verify `swift build` succeeds and the resource is reachable via `Bundle.module` at runtime
- [ ] 1.5 Record the built app's size before and after the resource is added, and verify the increase matches the dataset's on-disk size with no surprise multiplier

## 2. Country resolution utility

- [ ] 2.1 Add a resolver type in `Packages/WatermarkCore/Sources/WatermarkCore/Utilities/` that loads the bundled boundaries once and resolves **signed** `(latitude, longitude) -> String?` (ISO alpha-2 code, `nil` when the point falls in no country), using a bounding-box prefilter ahead of a ray-casting point-in-polygon test over each ring, and verify a unit test covers a resolvable coordinate, an ocean coordinate, and a coordinate at the dataset's edge (±90 lat / ±180 lon)
- [ ] 2.2 Verify the resolver handles multipolygon countries by asserting a coordinate on a non-mainland part of an archipelago or exclave resolves to the same code as its mainland
- [ ] 2.3 Add flag derivation from an ISO alpha-2 code via Unicode Regional Indicator Symbols, and verify a unit test asserts the emoji produced for a known code (e.g. "FR" → "🇫🇷") matches exactly
- [ ] 2.4 Add localized country name derivation via `Locale.current.localizedString(forRegionCode:)`, falling back to the alpha-2 code itself when the platform returns nil, and verify a unit test asserts a known code resolves to a non-empty name and that the nil path yields the code rather than an empty string
- [ ] 2.5 Combine resolution, name and flag into one entry point returning the formatted caption fragment (pin + name + flag) or `nil`, and verify a unit test covers the resolvable and unresolvable cases

## 3. Sign the coordinates (design.md D6)

- [ ] 3.1 Add the conversion from the `{GPS}` dictionary's unsigned `Latitude`/`Longitude` plus `LatitudeRef`/`LongitudeRef` into signed degrees, negating for "S" and "W" and falling back to the stored sign when a ref is absent, and verify a unit test covers all four hemisphere quadrants
- [ ] 3.2 Verify end to end with a fixture per quadrant that a southern-hemisphere coordinate (e.g. Sydney) and a western-hemisphere coordinate (e.g. São Paulo) each resolve to the correct country, not to the mirrored location an unsigned value would produce

## 4. Wire into the location caption field

- [ ] 4.1 Give `EXIFTokenParser` a place-formatted GPS path reached from the frame caption only, leaving the default `{gps}` substitution returning coordinates, and verify the caption path returns `"--"` when GPS metadata is absent or the coordinate is unresolved
- [ ] 4.2 Verify `TextWatermarkRenderer.render(config:metadata:)` still substitutes `{gps}` to coordinates, with a test asserting a text watermark containing `{gps}` renders the same string it does today — the alpha-mask non-regression required by design.md D7
- [ ] 4.3 Verify end to end that the location field renders the place format as a `classic` caption field (joined with " · ") and as a `gallery` caption slot, with a `CaptionBuilderTests`/`WhiteFrameRendererTests` case for each
- [ ] 4.4 Verify a photo with no GPS metadata, and a photo with GPS metadata that fails to resolve, both cause the location field to be elided from the caption exactly like any other missing field, reusing the existing `resolveSlot` and `DeviceMetadataProvider.caption` "--" handling with no code changes needed there
- [ ] 4.5 Verify the flag and pin render as colour glyphs in a rendered frame caption on both the UIKit and the macOS Core Text paths, not as tofu or a monochrome silhouette

## 5. Full-suite verification

- [ ] 5.1 Run `cd Packages/WatermarkCore && swift test` and verify the full suite passes, including the new resolver, the hemisphere fixtures, and the text-watermark non-regression test
- [ ] 5.2 Build the app (`xcodebuild -scheme WatermarkApp`) and verify it succeeds with the new bundled resource included
- [ ] 5.3 Verify on a real device (not the Simulator, per this project's standing rule) that a photo carrying GPS metadata exports with the place caption rendered correctly, including the flag glyph
