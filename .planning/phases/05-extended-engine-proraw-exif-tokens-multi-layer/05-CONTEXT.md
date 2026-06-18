# Phase 5: Extended Engine (ProRAW, EXIF Tokens, Multi-Layer) - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

## Phase Boundary

This phase extends the WatermarkCore engine with three capabilities: (1) Apple ProRAW DNG processing at full 48MP resolution with HDR gain map and DNG metadata preservation, (2) dynamic EXIF-based text tokens for "Shot On" style attribution in watermarks and frame text, and (3) true multi-layer compositing where text watermark, image/logo watermark, and white frame can all be active and rendered simultaneously.

**In scope:** ProRAW DNG pipeline (RAW Bayer → CIImage → compositing → DNG output), EXIF token parsing and substitution in text watermarks and frame metadata, multi-layer compositing with per-layer visibility/opacity/position, HDR gain map preservation through DNG path

**Out of scope:** User-reorderable layer order (v2 CUST-02), format conversion (Phase 6), export quality controls (Phase 6), batch processing (v2), any UI changes

## Implementation Decisions

### ProRAW DNG Processing
- **D-01:** Process RAW Bayer data from DNG files (not the embedded JPEG preview). Use `CIImage(imageData:options:)` with `expandToHDR` option. Maintain full 48MP resolution through the pipeline without downsampling.
- **D-02:** DNG metadata handling differs from HEIC/JPEG — use `CGImageSourceCopyPropertiesAtIndex` with DNG-specific keys (`kCGImagePropertyDNGDictionary`, `kCGImagePropertyExifDictionary`, `kCGImagePropertyTIFFDictionary`). Preserve all DNG-specific metadata through `CGImageDestination`.
- **D-03:** ProRAW HDR gain map extraction: DNG stores gain map differently than HEIC. Use `CGImageSourceCopyAuxiliaryDataInfoAtIndex` with `kCGImageAuxiliaryDataTypeHDRGainMap`. If gain map unavailable, process without but log warning.
- **D-04:** Memory safety: 48MP DNG is ~75MB per frame. Use tiled rendering via `CIContext` with workingFormat constraints. Profile with Instruments to validate no jetsam on 6GB devices.
- **D-05:** ProRAW format detection added to `FormatDetector` — recognize `public.camera-raw-image` UTI and DNG file signatures. Supported output format: DNG (preserve source).

### EXIF Token System
- **D-06:** Token syntax: `{camera_model}`, `{lens}`, `{aperture}`, `{focal_length}`, `{shutter_speed}`, `{iso}`, `{date}`, `{gps}` — curly-brace delimited, snake_case keys. Exact keys match REQUIREMENTS.md EXIF-01.
- **D-07:** Token substitution happens at render time as a preprocessing step. Text watermark strings and frame metadata text are scanned for tokens, then substituted with EXIF values before rendering. Token parsing is format-agnostic — works for HEIC, JPEG, PNG, ProRAW, DNG.
- **D-08:** Missing EXIF fields render as "--" (double em dash). Never show empty string or raw token literal — user needs to see the token didn't resolve. This applies to all tokens regardless of format.
- **D-09:** GPS token formatting: decimal degrees with 4 decimal places and cardinal direction. Example: `37.7749° N, 122.4194° W`. If GPS is unavailable but location is in other EXIF fields, fall back to those.
- **D-10:** Date token formatting: use EXIF `DateTimeOriginal` → formatted as locale-aware short date. Example: `Jun 18, 2026`. If DateTimeOriginal missing, fall back to DateTimeDigitized → DateTime.
- **D-11:** Aperture and focal length formatting: aperture as `f/{value}` (e.g., `f/1.8`), focal length as `{value}mm` (e.g., `24mm`). Shutter speed as fraction when <1s (e.g., `1/120`), decimal when >=1s. ISO as plain number (e.g., `ISO 400`).

### Multi-Layer Compositing
- **D-12:** Fixed compositing order: text watermarks → image/logo watermarks → white frame (back-to-front). Text renders first (bottom layer), images composite on top of text, white frame is outermost layer. Not user-reorderable in v1.
- **D-13:** `WatermarkConfiguration.watermarks: [WatermarkLayer]` already supports an ordered list. No model change needed — the engine already handles multiple layers via `WatermarkRenderer` ordering. The change is removing any single-layer assumption and allowing both `.text` and `.image` layers simultaneously.
- **D-14:** Each layer has independent: visibility (show/hide), opacity (per-layer alpha), position (WatermarkPosition), scale. Per-layer controls already exist via `WatermarkLayer` properties.
- **D-15:** The existing `WatermarkRenderer.render(layers:onto:)` method already composites ordered CIImage layers onto a base. Multi-layer extends this by accepting the full `[WatermarkLayer]` array and processing each in order.

### Claude's Discretion
- ProRAW CIImage loading options and rendering configuration
- EXIF token parser implementation (regex-based, String extension, or dedicated TokenParser struct)
- Token substitution integration into `TextWatermarkRenderer` and `WhiteFrameRenderer`
- GPS coordinate extraction from EXIF GPS dictionary (latitude/longitude ref + values)
- DNG metadata write path — whether to use CGImageDestination with DNG UTI or specialized DNG writer
- Memory profiling strategy for 48MP ProRAW pipeline
- `FormatDetector` extension for ProRAW/DNG UTI detection
- Existing `WatermarkRenderer` compositing order enforcement for multi-layer
- Test coverage for each token type, ProRAW round-trip, and multi-layer combinations

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Foundation
- `.planning/PROJECT.md` — Core value, constraints
- `.planning/REQUIREMENTS.md` — v1 requirements: PROR-01, PROR-02, EXIF-01, EXIF-02, MULT-01, MULT-02
- `.planning/STATE.md` — Current position

### Phase 1 (Engine Foundation — Primary Dependency)
- `.planning/phases/01-core-engine-photo-pipeline/01-CONTEXT.md` — All Phase 1 decisions: watermark compositing (D-01 through D-10), format handling, font choice, metadata content, HDR pipeline, position enum

### Engine API (WatermarkCore)
- `Packages/WatermarkCore/Sources/WatermarkCore/Engine/WatermarkEngine.swift` — `process(sourceURL:config:)` entry point, `buildFilterGraph()` compositing logic
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift` — `WatermarkConfiguration`, `WatermarkLayer` enum, `OutputFormat`
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/TextWatermarkInput.swift` — Text watermark input model
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/WhiteFrameConfig.swift` — White frame config with metadata text
- `Packages/WatermarkCore/Sources/WatermarkCore/Rendering/WatermarkRenderer.swift` — Ordered layer compositing
- `Packages/WatermarkCore/Sources/WatermarkCore/Rendering/TextWatermarkRenderer.swift` — Text rendering
- `Packages/WatermarkCore/Sources/WatermarkCore/Rendering/WhiteFrameRenderer.swift` — Frame rendering with metadata text
- `Packages/WatermarkCore/Sources/WatermarkCore/Input/FormatDetector.swift` — Format detection (to extend)
- `Packages/WatermarkCore/Sources/WatermarkCore/Input/ImageLoader.swift` — Image loading (to extend for DNG)
- `Packages/WatermarkCore/Sources/WatermarkCore/Models/MediaMetadata.swift` — Metadata model
- `Packages/WatermarkCore/Sources/WatermarkCore/Utilities/DeviceMetadataProvider.swift` — Device metadata extraction (reference for EXIF reading)

### Research
- `.planning/research/STACK.md` — Technology stack: Core Image, ImageIO, CGImageSource/Destination, DNG
- `.planning/research/ARCHITECTURE.md` — MVVM + @Observable, shared WatermarkCore package
- `.planning/research/PITFALLS.md` — Critical pitfalls for metadata and quality

### Phase Tracking
- `.planning/ROADMAP.md` Phase 5 — Goal, requirements, success criteria
- `.planning/STATE.md` — Current position, Phase 5 blocker notes

## Existing Code Insights

### Reusable Assets
- **WatermarkRenderer** — Already composites ordered CIImage layers. Multi-layer extends this by processing the full `[WatermarkLayer]` array.
- **TextWatermarkRenderer** — Text rendering with SF system fonts. Token substitution is a preprocessing step before rendering.
- **WhiteFrameRenderer** — Frame metadata text. Token substitution applies to `metadataText` string before frame compositing.
- **ImageLoader** — CGImageSource-based loading with HDR options. Extend with DNG-specific loading path and `expandToHDR`.
- **ImageWriter** — CGImageDestination write with metadata attachment. Extend with DNG metadata dictionary keys.
- **FormatDetector** — UTI-based format detection. Add `public.camera-raw-image` and DNG signature detection.
- **DeviceMetadataProvider** — Pattern for extracting EXIF fields. Token system follows the same CGImageSource property extraction pattern.

### Established Patterns
- **CGImageSource → CIImage → CIFilter → CIContext.render → CGImage → CGImageDestination** — The standard photo pipeline. ProRAW follows this same chain but with DNG-specific source/destination settings.
- **Static processing pipeline** — Functional pattern with static methods. Token parser follows this as a stateless utility struct.
- **Actor isolation** — WatermarkEngine is an actor. Token parsing is a pure function (no state), no actor changes needed.
- **Sendable models** — WatermarkConfiguration and all models are Sendable. No new non-Sendable types.
- **PipelineError enum** — Add ProRAW-specific and token-specific error cases.

### Integration Points
- **WatermarkEngine.buildFilterGraph()** — Multi-layer compositing changes the filter graph construction. Currently iterates over watermarks in order; this logic extends naturally.
- **TextWatermarkRenderer** — Token substitution injected as a preprocessing step before `CIFilter.attributedTextImageGenerator`.
- **WhiteFrameRenderer.drawFrame()** — Token substitution applied to `metadataText` before `NSAttributedString` creation.
- **FormatDetector** — New DNG/ProRAW detection path.
- **ImageLoader** — New ProRAW loading path with memory-safety constraints.

## Specific Ideas

- Token parser should be a dedicated `EXIFTokenParser` struct with a static `func substitute(_ text: String, metadata: MediaMetadata) -> String` method. Scan for `{...}` patterns, extract key, map to EXIF value, replace.
- GPS formatting: extract `kCGImagePropertyGPSLatitude`, `kCGImagePropertyGPSLatitudeRef`, `kCGImagePropertyGPSLongitude`, `kCGImagePropertyGPSLongitudeRef`. Format as `{lat}° {ref}, {lon}° {ref}` with 4 decimal places.
- ProRAW DNG should be detected via both UTI (`public.camera-raw-image`) and DNG file signature check (first 4 bytes = "II*" or "MM*" + "DNG" at offset). Both checks for safety.
- Multi-layer should just work: the engine already iterates `config.watermarks` in order. The change is removing any assumption that only one type can be active. Each layer gets composited via `CIFilter.sourceOverCompositing` in sequence.
- Memory for 48MP: use `CIContext` with `workingFormat: CIFormat.RGBAh` and `outputColorSpace: CGColorSpace.displayP3`. Render in tiles if needed for very large images.

## Deferred Ideas

- User-reorderable layer order via drag-and-drop in UI → v2 CUST-02
- Additional token types (flash status, white balance, exposure bias) → v2 CUST-04
- Custom token format strings (e.g., date formatting options) → v2 CUST-03
- ProRAW export to HEIC/JPEG with tone mapping → Phase 6 EXPT-03

---

*Phase: 5-Extended Engine (ProRAW, EXIF Tokens, Multi-Layer)*
*Context gathered: 2026-06-18*
