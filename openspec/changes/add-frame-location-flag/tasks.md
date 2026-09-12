## 1. Offline country dataset

- [ ] 1.1 Pick a public-domain country-boundary source (e.g. Natural Earth admin-0) and a grid resolution, and record the choice plus provenance in `tools/geo/README.md`, resolving design.md's open question
- [ ] 1.2 Write `tools/geo/build-country-grid.*`, a one-time script that samples the source boundaries on the chosen grid and emits a compact coordinate→ISO-3166-1-alpha-2 resource, and verify it runs end to end and produces a non-empty output file
- [ ] 1.3 Validate the generated grid against a fixture list of coordinates spanning small territories, city-states, and a few known border regions, and verify every populated country in the fixture list resolves to its correct code
- [ ] 1.4 Add the generated resource to `WatermarkCore`'s `Package.swift` resources, and verify `swift build` succeeds and the resource is reachable via `Bundle.module` at runtime

## 2. Country resolution utility

- [ ] 2.1 Add a resolver type in `Packages/WatermarkCore/Sources/WatermarkCore/Utilities/` that loads the bundled grid once and resolves `(latitude, longitude) -> String?` (ISO alpha-2 code, `nil` when unresolved), and verify a unit test covers a resolvable coordinate, an ocean coordinate, and a coordinate at the grid's edge (±90 lat / ±180 lon)
- [ ] 2.2 Add flag derivation from an ISO alpha-2 code via Unicode Regional Indicator Symbols, and verify a unit test asserts the emoji produced for a known code (e.g. "FR" → "🇫🇷") matches exactly
- [ ] 2.3 Add localized country name derivation via `Locale.localizedString(forRegionCode:)`, and verify a unit test asserts a known code resolves to a non-empty name
- [ ] 2.4 Combine resolution, name and flag into one entry point returning the formatted caption fragment (pin + name + flag) or `nil`, and verify a unit test covers the resolvable and unresolvable cases

## 3. Wire into the location caption field

- [ ] 3.1 Change `EXIFTokenParser.formatGPS` to resolve through the new utility instead of formatting raw coordinates, returning `"--"` when GPS metadata is absent or the coordinate is unresolved, and verify existing `EXIFTokenParserTests` GPS cases are updated to assert the new format
- [ ] 3.2 Verify end to end that the location field renders correctly as a `classic` caption field (joined with " · ") and as a `gallery` caption slot, with a `CaptionBuilderTests`/`WhiteFrameRendererTests` case for each
- [ ] 3.3 Verify a photo with no GPS metadata, and a photo with GPS metadata that fails to resolve, both cause the location field to be elided from the caption exactly like any other missing field, reusing the existing `resolveSlot` "--"-elision behavior with no code changes needed there

## 4. Full-suite verification

- [ ] 4.1 Run `cd Packages/WatermarkCore && swift test` and verify the full suite passes, including the new resolver and updated GPS caption tests
- [ ] 4.2 Build the app (`xcodebuild -scheme WatermarkApp`) and verify it succeeds with the new bundled resource included
