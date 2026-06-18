# Phase 5: Extended Engine (ProRAW, EXIF Tokens, Multi-Layer) - Research

**Researched:** 2026-06-18
**Domain:** Apple ProRAW DNG processing, EXIF metadata token substitution, multi-layer CIImage compositing
**Confidence:** MEDIUM (ProRAW DNG write path has open questions; EXIF token keys are verified)

## Summary

Phase 5 extends the existing WatermarkCore engine with three capabilities that build on Phase 1's foundation: (1) full-resolution Apple ProRAW DNG processing through the Core Image pipeline, (2) dynamic EXIF-based text token substitution for "Shot On" style attribution, and (3) true multi-layer compositing where text, logo, and frame can all render simultaneously.

**ProRAW DNG processing** is largely additive: `CIImage(contentsOf:options:)` already supports DNG files natively. The main work is (a) adding DNG/ProRAW UTI detection to `FormatDetector`, (b) ensuring `expandToHDR: true` is used for DNG loading (the existing `ImageLoader.load()` already passes this flag), (c) preserving DNG-specific metadata via `kCGImagePropertyDNGDictionary` in the write path, and (d) memory-safe 48MP rendering. Apple ProRAW is a Linear DNG (already demosaiced, including computational photography metadata), so no manual RAW Bayer pipeline is needed — Core Image handles it transparently.

**EXIF token parsing** is a pure string substitution function: scan for `{token_name}` patterns in text watermark strings and frame metadata text, extract the corresponding value from the `MediaMetadata.metadata` dictionary, and replace. Each token maps to a well-known `kCGImagePropertyExif*` or `kCGImagePropertyGPS*` key. Missing fields render as `"--"`. This is a stateless function that fits the existing processing pipeline's functional pattern — it operates as a preprocessing step before `TextWatermarkRenderer.render()` and `WhiteFrameRenderer.drawFrame()`.

**Multi-layer compositing** requires almost no new compositing logic — `WatermarkRenderer.composite(layers:onto:)` already handles an ordered array of `(CIImage, CGPoint)` tuples with `CISourceOverCompositing` chaining. The change is removing the implicit assumption that only one watermark type is active, enforcing the correct compositing order per D-12 (text → image/logo → white frame, back-to-front), and feeding per-layer visibility/opacity through to the compositing stage.

**Primary recommendation:** Implement these as three focused additions to the existing engine (new `EXIFTokenParser` utility, DNG support in `FormatDetector` + `ImageLoader` + `ImageWriter`, and order enforcement in `buildFilterGraph()`), plus per-layer opacity passthrough through `CIFilter.colorMatrix`. No model changes to `WatermarkConfiguration` or `WatermarkLayer` — the data structures already support the required semantics.

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Process RAW Bayer data from DNG files (not the embedded JPEG preview). Use `CIImage(imageData:options:)` with `expandToHDR` option. Maintain full 48MP resolution through the pipeline without downsampling.
- **D-02:** DNG metadata handling differs from HEIC/JPEG — use `CGImageSourceCopyPropertiesAtIndex` with DNG-specific keys (`kCGImagePropertyDNGDictionary`, `kCGImagePropertyExifDictionary`, `kCGImagePropertyTIFFDictionary`). Preserve all DNG-specific metadata through `CGImageDestination`.
- **D-03:** ProRAW HDR gain map extraction: DNG stores gain map differently than HEIC. Use `CGImageSourceCopyAuxiliaryDataInfoAtIndex` with `kCGImageAuxiliaryDataTypeHDRGainMap`. If gain map unavailable, process without but log warning.
- **D-04:** Memory safety: 48MP DNG is ~75MB per frame. Use tiled rendering via `CIContext` with workingFormat constraints. Profile with Instruments to validate no jetsam on 6GB devices.
- **D-05:** ProRAW format detection added to `FormatDetector` — recognize `public.camera-raw-image` UTI and DNG file signatures. Supported output format: DNG (preserve source).
- **D-06:** Token syntax: `{camera_model}`, `{lens}`, `{aperture}`, `{focal_length}`, `{shutter_speed}`, `{iso}`, `{date}`, `{gps}` — curly-brace delimited, snake_case keys. Exact keys match REQUIREMENTS.md EXIF-01.
- **D-07:** Token substitution happens at render time as a preprocessing step. Text watermark strings and frame metadata text are scanned for tokens, then substituted with EXIF values before rendering. Token parsing is format-agnostic — works for HEIC, JPEG, PNG, ProRAW, DNG.
- **D-08:** Missing EXIF fields render as "--" (double em dash). Never show empty string or raw token literal.
- **D-09:** GPS token formatting: decimal degrees with 4 decimal places and cardinal direction. Example: `37.7749° N, 122.4194° W`. If GPS is unavailable but location is in other EXIF fields, fall back to those.
- **D-10:** Date token formatting: use EXIF `DateTimeOriginal` → formatted as locale-aware short date. Fallback: `DateTimeDigitized` → `DateTime`.
- **D-11:** Aperture as `f/{value}`, focal length as `{value}mm`, shutter speed as fraction when <1s (`1/120`), decimal when >=1s, ISO as `ISO 400`.
- **D-12:** Fixed compositing order: text watermarks → image/logo watermarks → white frame (back-to-front).
- **D-13:** `WatermarkConfiguration.watermarks: [WatermarkLayer]` already supports an ordered list. No model change needed.
- **D-14:** Each layer has independent: visibility (show/hide), opacity (per-layer alpha), position (WatermarkPosition), scale.
- **D-15:** The existing `WatermarkRenderer.render(layers:onto:)` method already composites ordered CIImage layers onto a base. Multi-layer extends this by accepting the full `[WatermarkLayer]` array.

### the agent's Discretion
- ProRAW CIImage loading options and rendering configuration
- EXIF token parser implementation (regex-based, String extension, or dedicated TokenParser struct)
- Token substitution integration into `TextWatermarkRenderer` and `WhiteFrameRenderer`
- GPS coordinate extraction from EXIF GPS dictionary
- DNG metadata write path
- Memory profiling strategy for 48MP ProRAW pipeline
- `FormatDetector` extension for ProRAW/DNG UTI detection
- Existing `WatermarkRenderer` compositing order enforcement for multi-layer
- Test coverage for each token type, ProRAW round-trip, and multi-layer combinations

### Deferred Ideas (OUT OF SCOPE)
- User-reorderable layer order → v2 CUST-02
- Additional token types (flash status, etc.) → v2 CUST-04
- Custom token format strings → v2 CUST-03
- ProRAW export to HEIC/JPEG with tone mapping → Phase 6 EXPT-03

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PROR-01 | Process Apple ProRAW DNG at 48MP without downsampling | CIImage native DNG support, `expandToHDR: true`, verify CIImage extent dimensions at load |
| PROR-02 | Preserve ProRAW HDR gain maps and DNG metadata | `CGImageSourceCopyAuxiliaryDataInfoAtIndex` with `kCGImageAuxiliaryDataTypeHDRGainMap`, `kCGImagePropertyDNGDictionary` passthrough via `CGImageDestination` |
| EXIF-01 | Dynamic EXIF tokens in watermarks and frame text | `EXIFTokenParser` struct extracting from `CGImageSource` metadata dictionary, token keys §Architecture Patterns |
| EXIF-02 | EXIF tokens work for all supported formats (HEIC, JPEG, ProRAW, DNG) | Format-agnostic: metadata dictionary structure is identical across formats |
| MULT-01 | Text, image, and frame simultaneously in single render pass | `WatermarkRenderer.composite()` already chains ordered layers; enforce D-12 order in `buildFilterGraph()` |
| MULT-02 | Independent position, opacity, visibility per layer | Per-layer `WatermarkLayer` properties; visibility = skip layer in compositing loop; opacity via `CIFilter.colorMatrix` |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| ProRAW DNG loading | API / Backend (ImageLoader) | — | System framework handles RAW decoding; ImageLoader extracts metadata + creates CIImage |
| EXIF token substitution | API / Backend (WatermarkCore/Utilities) | — | Pure string processing, no UI; operates on metadata dictionary |
| Multi-layer compositing | API / Backend (WatermarkRenderer) | — | Core Image filter graph construction; all layers are CIImage objects |
| DNG metadata write | API / Backend (ImageWriter) | — | Same CGImageDestination pattern as existing formats |
| Format detection (ProRAW) | API / Backend (FormatDetector) | — | UTI-based detection, no UI |
| Per-layer opacity | API / Backend (ImageWatermarkRenderer, buildFilterGraph) | — | CIFilter.colorMatrix alpha modulation per layer |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|-------------|
| Core Image (CIImage, CIFilter) | iOS 18 SDK | DNG loading, multi-layer compositing, per-layer opacity | Only framework for DNG RAW processing; GPU-accelerated filter graph |
| ImageIO (CGImageSource, CGImageDestination) | iOS 18 SDK | DNG metadata extraction/write, EXIF/GPS/DNG dictionary access | Only framework for metadata passthrough; DNG metadata in `kCGImagePropertyDNGDictionary` |
| UniformTypeIdentifiers (UTType) | iOS 18 SDK | DNG/ProRAW UTI detection | `UTType.rawImage`, `UTType.dng` for format detection |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Core Image (CIRAWFilter) | iOS 18 SDK | Optional granular RAW processing control | Only if default CIImage loading needs exposure/WB adjustment. Not needed for watermarking — D-01 uses `CIImage(imageData:options:)` |
| Foundation (NSAttributedString) | iOS 18 SDK | Text watermark rendering (unchanged) | Existing pattern in TextWatermarkRenderer — tokens are substituted BEFORE attributed string creation |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `CIImage(contentsOf:options:)` for DNG | `CIRAWFilter(imageData:identifierHint:)` | CIRAWFilter gives exposure/WB control but adds complexity. CIImage direct load is sufficient for watermark overlay — we don't edit RAW development parameters |
| Dedicated `EXIFTokenParser` struct | String extension with regex | Struct is testable, keeps parse logic isolated, matches existing `DeviceMetadataProvider` pattern. Regex-based extension is simpler but harder to test individual token formatters |
| `CIBlendKernel.sourceOver` for compositing | `CIFilter.sourceOverCompositing` | CIBlendKernel is more performant for many layers but changes the existing compositing pattern. For 3-5 layers (typical), CIFilter approach is fine and matches current code |
| Custom DNG writer | Standard `CGImageDestination` with DNG UTI | Custom writer could guarantee DNG version control but adds massive complexity. CGImageDestination with DNG metadata passthrough is the Apple-recommended path |

**Installation:**
```bash
# No package manager needed. All Apple system frameworks included with iOS SDK.
# No third-party dependencies. Phase 5 extends existing WatermarkCore package.
```

**Version verification:** Not applicable — all dependencies are Apple system frameworks bundled with iOS 18 SDK. No npm/pip/cargo packages.

## Package Legitimacy Audit

> Not applicable — Phase 5 uses zero third-party packages. All functionality is built on Apple system frameworks (Core Image, ImageIO, UniformTypeIdentifiers) and the existing WatermarkCore Swift Package. No external packages are installed.

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram (Phase 5 additions)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         EXISTING PIPELINE (Phase 1)                            │
│                                                                                │
│  sourceURL ──→ ImageLoader.load() ──→ OrientationNormalizer ──→ buildFilter   │
│                    │                                                        │
│                    ├── MediaMetadata { metadata, gainMapAuxData, colorSpace } │
│                    │                                                        │
│  ────→ WatermarkRenderer.composite() ──→ CIContext.render() ──→ ImageWriter │
│                                                                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                         PHASE 5 ADDITIONS                                     │
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  1. ProRAW DNG Pipeline                                                  │ │
│  │                                                                          │ │
│  │  sourceURL (.dng)                                                        │ │
│  │     │                                                                    │ │
│  │     ├── FormatDetector.detect() → UTI "com.adobe.raw-image"              │ │
│  │     │   └── NEW: DNG UTI detection (UTType.rawImage, UTType.dng)        │ │
│  │     │                                                                    │ │
│  │     ├── ImageLoader.load() — EXISTING expandToHDR:true handles DNG      │ │
│  │     │   └── CGImageSourceCopyProperties(metadata)                        │ │
│  │     │   └── CGImageSourceCopyAuxiliaryDataInfo(HDRGainMap)               │ │
│  │     │   └── NEW: Extract kCGImagePropertyDNGDictionary                   │ │
│  │     │                                                                    │ │
│  │     ├── CIImage → filter graph → render (same as HEIC/JPEG path)        │ │
│  │     │                                                                    │ │
│  │     └── ImageWriter.write()                                              │ │
│  │         └── NEW: DNG metadata dictionary passthrough                     │ │
│  │         └── NEW: DNG UTI output when source was DNG (preserve format)    │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  2. EXIF Token System                                                    │ │
│  │                                                                          │ │
│  │  User text: "Shot on {camera_model} with {aperture}"                     │ │
│  │     │                                                                    │ │
│  │     ├── EXIFTokenParser.substitute(text, metadata)                       │ │
│  │     │   └── Scan for "{...}" patterns                                    │ │
│  │     │   └── Lookup key → EXIF/GPS/TIFF dictionary                       │ │
│  │     │   └── Format value per token type                                  │ │
│  │     │   └── Replace token with formatted value (or "--" if missing)      │ │
│  │     │                                                                    │ │
│  │     ├── TextWatermarkRenderer.render() — receives pre-substituted text    │ │
│  │     └── WhiteFrameRenderer.drawFrame() — receives pre-substituted text   │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │  3. Multi-Layer Compositing                                              │ │
│  │                                                                          │
│  │  WatermarkConfiguration.watermarks: [WatermarkLayer]                     │ │
│  │     │                                                                    │ │
│  │     ├── buildFilterGraph() processes ALL layers in order (no single-type │ │
│  │     │   assumption — text, image, or both)                               │ │
│  │     │                                                                    │ │
│  │     ├── For each layer:                                                  │ │
│  │     │   ├── Check layer.visibility → skip if hidden (NEW: per-layer)     │ │
│  │     │   ├── Render → CIImage (via TextWatermarkRenderer or               │ │
│  │     │   │   ImageWatermarkRenderer)                                       │ │
│  │     │   ├── Apply per-layer opacity via CIFilter.colorMatrix (NEW)       │ │
│  │     │   ├── Scale + Position                                             │ │
│  │     │   └── Collect into layers array                                    │ │
│  │     │                                                                    │ │
│  │     └── WatermarkRenderer.composite(layers, onto: base)                  │ │
│  │         └── CISourceOverCompositing chain in array order                 │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure (Phase 5 additions — existing structure + new files)

```
Packages/WatermarkCore/Sources/WatermarkCore/
├── Engine/
│   ├── PipelineError.swift              # EXTEND: add .proRawGainMapMissing,
│   │                                    #         .tokenSubstitutionFailed
│   └── WatermarkEngine.swift            # EXTEND: buildFilterGraph order
│                                        #         enforcement, per-layer opacity
├── Input/
│   ├── FormatDetector.swift             # EXTEND: add DNG/ProRAW UTIs,
│   │                                    #         public.camera-raw-image
│   └── ImageLoader.swift                # EXTEND: DNG metadata extraction via
│                                        #         kCGImagePropertyDNGDictionary
├── Models/
│   ├── MediaMetadata.swift              # EXTEND: add dngMetadata field
│   └── WatermarkConfiguration.swift     # NO CHANGE (per D-13)
├── Output/
│   └── ImageWriter.swift                # EXTEND: DNG metadata write,
│                                        #         DNG UTI output format
├── Rendering/
│   ├── TextWatermarkRenderer.swift      # EXTEND: token substitution call
│   ├── WatermarkRenderer.swift          # EXTEND: per-layer opacity support
│   └── WhiteFrameRenderer.swift         # EXTEND: token substitution call
└── Utilities/
    ├── DeviceMetadataProvider.swift      # EXISTING (unchanged)
    └── EXIFTokenParser.swift            # NEW: token scanning, substitution,
                                         #       per-token formatters

Packages/WatermarkCore/Tests/WatermarkCoreTests/
├── EXIFTokenParserTests.swift           # NEW: per-token rendering, missing
│                                        #       field fallback, format validation
├── ProRAWTests.swift                    # NEW: DNG round-trip, resolution, metadata
├── MultiLayerCompositingTests.swift     # NEW: text+image+frame combinations
├── TestHelpers/
│   └── EXIFMetadataFactory.swift        # NEW: create metadata dicts with known
│                                        #       EXIF/GPS values for token testing
```

### Pattern 1: EXIF Token Parser (Dedicated Struct)

**What:** A stateless utility struct (`EXIFTokenParser`) with a single static method `substitute(_:metadata:) -> String`. Scans input text for `{token_name}` patterns, extracts the token key, maps it to an EXIF/GPS/TIFF property key, fetches the value from the metadata dictionary, formats it per token type rules, and replaces the token in the string. Missing fields render as `"--"`.

**When to use:** Called before `TextWatermarkRenderer.render()` and `WhiteFrameRenderer.drawFrame()` — token substitution is a preprocessing step per D-07.

**Token-to-Key Mapping:**
| Token | Dictionary | Key | Value Type | Formatter |
|-------|-----------|-----|------------|-----------|
| `{camera_model}` | TIFF `"{TIFF}"` | `"Model"` | String | Passthrough |
| `{lens}` | EXIF `"{Exif}"` | `"LensModel"` | String | Passthrough |
| `{aperture}` | EXIF `"{Exif}"` | `"FNumber"` | NSNumber/Double | `f/{value}` |
| `{focal_length}` | EXIF `"{Exif}"` | `"FocalLength"` | NSNumber/Double | `{value}mm` |
| `{shutter_speed}` | EXIF `"{Exif}"` | `"ShutterSpeedValue"` | NSNumber/Double | Fraction `<1s`, decimal `>=1s` |
| `{iso}` | EXIF `"{Exif}"` | `"ISOSpeedRatings"` | NSNumber/Array | `ISO {value}` |
| `{date}` | EXIF `"{Exif}"` | `"DateTimeOriginal"` | String | Locale-aware short date |
| `{gps}` | GPS `"{GPS}"` | `"Latitude"`/`"LatitudeRef"`/`"Longitude"`/`"LongitudeRef"` | Double, String | `37.7749° N, 122.4194° W` |

**Example:**
```swift
// Source: Apple ImageIO CGImageProperties Reference
// Verified: https://developer.apple.com/documentation/imageio/cgimageproperties
public struct EXIFTokenParser {

    /// Token pattern: matches {snake_case_identifier}
    private static let tokenPattern: String = #"\{([a-z_]+)\}"#

    /// Dictionary key constants (String keys for Sendable conformance)
    private static let exifDictKey = "{Exif}"
    private static let tiffDictKey = "{TIFF}"
    private static let gpsDictKey = "{GPS}"

    // MARK: - Token Definitions

    private enum Token: String, CaseIterable {
        case camera_model, lens, aperture, focal_length
        case shutter_speed, iso, date, gps
    }

    /// Substitutes all EXIF tokens in the input text with formatted values.
    /// - Parameters:
    ///   - text: Input string potentially containing `{token}` patterns
    ///   - metadata: Source image metadata dictionary (String keys)
    /// - Returns: Text with all recognized tokens replaced; unrecognized tokens left as-is;
    ///   missing EXIF fields render as "--" per D-08
    public static func substitute(_ text: String, metadata: [String: Any]) -> String {
        var result = text
        for token in Token.allCases {
            let pattern = "{\(token.rawValue)}"
            guard result.contains(pattern) else { continue }
            let replacement = value(for: token, metadata: metadata)
            result = result.replacingOccurrences(of: pattern, with: replacement)
        }
        return result
    }

    /// Resolves a token to its formatted EXIF value, or "--" if missing.
    private static func value(for token: Token, metadata: [String: Any]) -> String {
        switch token {
        case .camera_model:
            let tiff = metadata[tiffDictKey] as? [String: Any]
            return tiff?["Model"] as? String ?? "--"
        case .lens:
            let exif = metadata[exifDictKey] as? [String: Any]
            return exif?["LensModel"] as? String ?? "--"
        case .aperture:
            let exif = metadata[exifDictKey] as? [String: Any]
            guard let fNumber = exif?["FNumber"] as? Double else { return "--" }
            return String(format: "f/%.1f", fNumber)
        case .focal_length:
            let exif = metadata[exifDictKey] as? [String: Any]
            guard let focal = exif?["FocalLength"] as? Double else { return "--" }
            return String(format: "%.0fmm", focal)
        case .shutter_speed:
            let exif = metadata[exifDictKey] as? [String: Any]
            guard let speed = exif?["ShutterSpeedValue"] as? Double else { return "--" }
            let exposureTime = pow(2.0, -speed)  // APEX to seconds
            if exposureTime < 1.0 {
                let denominator = Int(round(1.0 / exposureTime))
                return "1/\(denominator)"
            } else {
                return String(format: "%.1fs", exposureTime)
            }
        case .iso:
            let exif = metadata[exifDictKey] as? [String: Any]
            let isoValue: Int? = {
                if let ratings = exif?["ISOSpeedRatings"] as? [Int], let first = ratings.first {
                    return first
                }
                if let rating = exif?["ISOSpeedRatings"] as? Int {
                    return rating
                }
                return nil
            }()
            guard let iso = isoValue else { return "--" }
            return "ISO \(iso)"
        case .date:
            let exif = metadata[exifDictKey] as? [String: Any]
            let dateString = (exif?["DateTimeOriginal"] as? String)
                ?? (exif?["DateTimeDigitized"] as? String)
                ?? (exif?["DateTime"] as? String)
            guard let dateString = dateString else { return "--" }
            return formatDate(dateString)
        case .gps:
            return formatGPS(from: metadata)
        }
    }

    // MARK: - Formatters

    private static func formatDate(_ exifDateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let date = formatter.date(from: exifDateString) else { return "--" }
        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .short
        outputFormatter.timeStyle = .none
        return outputFormatter.string(from: date)
    }

    private static func formatGPS(from metadata: [String: Any]) -> String {
        guard let gps = metadata[gpsDictKey] as? [String: Any],
              let lat = gps["Latitude"] as? Double,
              let lon = gps["Longitude"] as? Double else {
            return "--"
        }
        let latRef = gps["LatitudeRef"] as? String ?? (lat >= 0 ? "N" : "S")
        let lonRef = gps["LongitudeRef"] as? String ?? (lon >= 0 ? "E" : "W")
        return String(format: "%.4f° %@, %.4f° %@",
                      abs(lat), latRef, abs(lon), lonRef)
    }
}
```

### Pattern 2: Multi-Layer Compositing with Per-Layer Opacity

**What:** `WatermarkEngine.buildFilterGraph()` processes ALL layers in `config.watermarks` regardless of type (text or image). Before compositing, each layer is checked for visibility (skip if hidden), rendered to a CIImage, and opacity is applied via `CIFilter.colorMatrix` alpha modulation. The existing `WatermarkRenderer.composite(layers:onto:)` chains them via `CISourceOverCompositing`. The white frame, if enabled, is composited as the outermost (top) layer per D-12.

**When to use:** The existing `buildFilterGraph()` method in `WatermarkEngine.swift` — this is where the compositing order is enforced.

**Example:**
```swift
// Inside buildFilterGraph() — per-layer processing with opacity support
var layers: [(CIImage, CGPoint)] = []
let extent = composited.extent

for watermark in config.watermarks {
    // Skip hidden layers (MULT-02: per-layer visibility)
    guard watermark.isVisible else { continue }

    let watermarkImage: CIImage

    switch watermark {
    case .text(let textConfig, _, _):
        // Token substitution before rendering (EXIF-01)
        let substitutedText = EXIFTokenParser.substitute(textConfig.text, metadata: metadata)
        let configWithTokens = textConfig.withText(substitutedText)
        watermarkImage = TextWatermarkRenderer.render(config: configWithTokens)

    case .image(let imageConfig, _, _):
        watermarkImage = try ImageWatermarkRenderer.render(config: imageConfig)
    }

    // Apply per-layer opacity via color matrix (MULT-02)
    let opacityAdjusted: CIImage
    if watermark.opacity < 1.0 {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = watermarkImage
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(watermark.opacity))
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        opacityAdjusted = matrix.outputImage ?? watermarkImage
    } else {
        opacityAdjusted = watermarkImage
    }

    // Scale and position
    let scaled = opacityAdjusted.transformed(
        by: CGAffineTransform(scaleX: watermark.scale, y: watermark.scale)
    )
    let position = PositionCalculator.position(
        for: watermark.position,
        watermarkExtent: scaled.extent,
        baseExtent: extent,
        padding: config.padding
    )

    layers.append((scaled, position))
}

// Composite all layers onto base (with frame below all watermarks if enabled)
return WatermarkRenderer.composite(layers: layers, onto: composited)
```

### Pattern 3: ProRAW DNG Detection & Loading

**What:** `FormatDetector` adds `public.camera-raw-image` and `com.adobe.raw-image` to supported UTIs. `ImageLoader.load()` extracts DNG-specific metadata via `kCGImagePropertyDNGDictionary` in addition to EXIF/TIFF/GPS. Loading uses the existing `expandToHDR: true` flag (already in place). Output format for DNG source is DNG (`.preserveSource` semantics).

**Example:**
```swift
// FormatDetector extension
private static let supportedUTIs: Set<String> = [
    "public.heic",
    "public.jpeg",
    "public.png",
    "com.adobe.raw-image",       // DNG UTI (primary)
    "public.camera-raw-image",    // Generic raw UTI (conformance check)
]

// DNG file signature verification (extra safety per D-05)
static func isDNG(url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    let header = handle.readData(ofLength: 4)
    // DNG files start with II (little-endian) or MM (big-endian) TIFF header
    let isII = header.starts(with: Data([0x49, 0x49, 0x2A, 0x00]))
    let isMM = header.starts(with: Data([0x4D, 0x4D, 0x00, 0x2A]))
    return isII || isMM
}

// ImageLoader extension — DNG metadata extraction
let dngMetadata: [String: Any]? = {
    if let dng = props[kCGImagePropertyDNGDictionary] as? [CFString: Any] {
        return convertCFDictionary(dng)
    }
    return nil
}()
```

### Anti-Patterns to Avoid

- **Using UIImage for DNG files:** `UIImage` loads only the embedded JPEG preview (typically 12MP or lower), not the full 48MP RAW data. Always use `CIImage(contentsOf:options:)` for ProRAW.
- **Token substitution AFTER attributed string creation:** Tokens must be substituted in the raw text string BEFORE creating `NSAttributedString` — otherwise font/color attributes are applied to the token literal, not the resolved value.
- **Applying per-layer opacity via `CIFilter.sourceOverCompositing` alpha:** The compositor's `sourceOverCompositing` computes blend alpha from the input image's alpha channel. Modulating opacity should happen on the watermark layer BEFORE compositing via `CIFilter.colorMatrix`, not by adjusting the compositor. This is the same pattern already used in `ImageWatermarkRenderer` for PNG watermarks.
- **Creating separate CIContext for 48MP rendering:** The existing `CIContextProvider.shared` with RGBAh + displayP3 is already configured for high-resolution HDR. Creating a second context doubles GPU memory pressure.
- **Assuming DNG metadata is in EXIF dictionary:** DNG files have a separate `kCGImagePropertyDNGDictionary` containing format-specific metadata (DNG version, black/white levels, color matrices, etc.). This must be extracted and re-attached separately from EXIF.
- **Writing DNG as HEIC/JPEG:** Output format for DNG source must be DNG (`.preserveSource`). Converting DNG to HEIC/JPEG would lose all RAW data — this is a separate feature (EXPT-03 in Phase 6).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| RAW Bayer demosaicing | Custom demosaic algorithm | `CIImage(contentsOf:options:)` with DNG | Apple ProRAW is Linear DNG — already demosaiced by the ISP. Core Image handles any remaining rendering transparently |
| DNG file parsing | Custom DNG byte parser | `CGImageSourceCreateWithURL` + `CGImageSourceCopyPropertiesAtIndex` | ImageIO provides full DNG spec compliance, version detection, and metadata extraction |
| Shutter speed APEX conversion | Custom math | Standard `pow(2.0, -apexValue)` formula | APEX to seconds conversion is well-defined; use the standard formula, don't re-derive |
| GPS coordinate math | Custom coordinate conversion | GPS dictionary contains already-computed decimal values | `kCGImagePropertyGPSLatitude` is already a Double in decimal degrees — no conversion needed |
| Date parsing from EXIF string | Custom date formatter | `DateFormatter` with `"yyyy:MM:dd HH:mm:ss"` format | EXIF DateTimeOriginal follows this exact format per spec |
| Token scanning regex | Custom parser combinator | `String.replacingOccurrences(of:with:)` or `NSRegularExpression` | Simple curly-brace pattern matching; full parser combinator is overkill for 8 fixed tokens |
| CIImage opacity modulation | Custom Metal shader | `CIFilter.colorMatrix` with alpha vector | Built-in GPU-accelerated filter; no shader compilation, no Metal code |

**Key insight:** Phase 5 adds ProRAW/EXIF/multi-layer capabilities by extending existing Apple framework APIs, not by introducing custom implementations. The complexity is in correct API usage (right metadata keys, right UTI strings, right compositing order), not in building new algorithms.

## Runtime State Inventory

> Phase 5 is primarily a greenfield engine extension — it adds new capabilities to WatermarkCore without renaming or migrating existing state. No rename/refactor/migration is involved.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — Phase 5 adds DNG handling to the engine; no new persistent state | None |
| Live service config | None — all processing is on-device, stateless | None |
| OS-registered state | None — no Task Scheduler, pm2, or launchd registrations | None |
| Secrets/env vars | None — no API keys or environment variables involved | None |
| Build artifacts | None — Phase 5 extends existing WatermarkCore package without renaming | None |

**Nothing found in any category:** Verified — Phase 5 extends existing files; no state migration needed. The `WatermarkConfiguration` model is unchanged per D-13.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 18 | Building/swift test | ✓ (implicit — project compiles) | 18.x | — |
| iOS 18 SDK | Core Image, ImageIO, UTType | ✓ (implicit — project compiles) | 18.x | — |
| Instruments | Memory profiling for 48MP | ✓ (bundled with Xcode) | Xcode 18 | Manual memory measurement via Xcode debug gauges |
| Device with ProRAW support | Empirical 48MP testing | ✗ (requires iPhone 14 Pro+ device) | — | Test structural correctness with synthetic DNG on simulator; flag for device testing |

**Missing dependencies with no fallback:**
- Physical device with ProRAW support (iPhone 14 Pro or later) — needed for empirical 48MP memory profiling and DNG round-trip validation. Unit tests cover structural correctness; device testing must be done manually before shipping.

**Missing dependencies with fallback:**
- None — all other dependencies are satisfied by the iOS 18 SDK and Xcode toolchain.

## Validation Architecture

> `workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`. Skipping Validation Architecture section.

## Common Pitfalls

### Pitfall 1: DNG Contains Embedded JPEG Preview — Accidentally Processing Low-Res

**What goes wrong:** When loading a ProRAW DNG file, `UIImage(contentsOfFile:)` or `UIImage(data:)` loads only the embedded JPEG preview (typically 12MP binned, not the full 48MP RAW). The watermark looks correct but the output is half-resolution. This is invisible on an iPhone display but obvious when inspecting pixel dimensions.

**Why it happens:** `UIImage` is a display-optimized class that picks the most efficient representation. For DNG files, that's the embedded preview. `CIImage(contentsOf:url:)` with proper options loads the full RAW data.

**How to avoid:** Always use `CIImage(contentsOf: url, options: [.expandToHDR: true])` for DNG files — never `UIImage`. Verify loaded CIImage extent dimensions match expected 48MP resolution (8064×6048 for iPhone 14/15/16 Pro main camera). Add a debug assertion in `ImageLoader` for DNG files: `assert(ciImage.extent.width >= 4000, "DNG loaded at sub-48MP resolution")`.

**Warning signs:** Loaded CIImage extent is ~4032×3024 (12MP) instead of ~8064×6048 (48MP). Output file is smaller than source DNG.

### Pitfall 2: DNG Metadata Dictionary Structure Mismatch

**What goes wrong:** DNG files have metadata spread across multiple dictionaries — `kCGImagePropertyDNGDictionary` (DNG-specific), `kCGImagePropertyExifDictionary` (EXIF), `kCGImagePropertyTIFFDictionary` (TIFF). Assuming EXIF keys like camera model are in the main EXIF dictionary when they're actually in the TIFF dictionary causes token substitution to return "--" for all values on DNG files.

**Why it happens:** DNG follows TIFF/EP structure where camera make/model live in the TIFF IFD, not the EXIF IFD. Developers familiar with HEIC/JPEG metadata (where camera model can appear in multiple places) don't check the DNG-specific layout.

**How to avoid:** The `EXIFTokenParser` must look up `{camera_model}` in the TIFF dictionary (`"{TIFF}"` → `"Model"`), not the EXIF dictionary. This is already correct in the Pattern 1 example above. Cross-verify with actual ProRAW DNG metadata from iPhone using exiftool: `exiftool -G -t photo.dng` to see which groups contain which tags.

**Warning signs:** EXIF tokens render as "--" on DNG files but work correctly on HEIC/JPEG. `exiftool -G -t` shows TIFF group for camera model, not EXIF group.

### Pitfall 3: 48MP Memory Pressure Jetsam

**What goes wrong:** A 48MP DNG loaded as a CIImage consumes ~75MB for the base image. Adding multiple watermark layers, a white frame render, and the `CIContext.createCGImage()` render target can push peak memory above 250MB. On 6GB devices (iPhone 14/15 base models) with other apps running, this triggers a jetsam event — the app is silently killed with no crash log.

**Why it happens:** Each CIImage in the filter graph holds a reference to the source pixel data. The `createCGImage()` call renders a full-resolution output buffer. Multiple intermediate CIImage instances (base + watermark layers + frame) accumulate references.

**How to avoid:**
1. Use the shared `CIContextProvider.shared` (already RGBAh + displayP3) — don't create a second context
2. Render to CGImage promptly after building the filter graph — don't hold the filter graph in memory
3. Consider `CIContext` tiled rendering for very large images (though 48MP is within the normal range for modern devices)
4. Profile with Instruments Allocations template on a device, not simulator
5. The existing `ImageLoader` validates file size ≤ 500MB and pixel count ≤ 100MP — 48MP DNGs pass both checks

**Warning signs:** App silently terminates during DNG processing on 6GB devices. Xcode Organizer shows jetsam events with `reason: per-process-limit`. Memory gauge in Xcode debugger spikes above 200MB.

### Pitfall 4: Token Substitution Order Dependency

**What goes wrong:** If `{camera_model}` is substituted before `{model}`, or tokens share substrings, the substitution can cascade incorrectly. For example, if a token key is a substring of another token, a naive `replacingOccurrences` loop could produce garbled output.

**Why it happens:** Simple string replacement without ordering guarantees can cause partial matches. For example, a hypothetical `{gps}` and `{gps_altitude}` would conflict if replaced in wrong order.

**How to avoid:** The 8 tokens defined in D-06 have no substring overlap — `camera_model`, `lens`, `aperture`, `focal_length`, `shutter_speed`, `iso`, `date`, `gps` are all unique. A simple iteration over all tokens and `replacingOccurrences(of: "{\(token)}", with: value)` works without ordering issues. However, the parser should still use a single-pass scan rather than iterative replacement to be robust against future token additions.

**Warning signs:** Output text contains partially substituted tokens (e.g., `f/1.8cal_length` instead of `f/1.8` and `24mm`).

### Pitfall 5: Shutter Speed APEX Value Misinterpretation

**What goes wrong:** The EXIF `ShutterSpeedValue` tag stores the shutter speed in APEX (Additive System of Photographic Exposure) units, not seconds. A value of `6.906` means `2^(-6.906) = 1/120` seconds, not 6.9 seconds. Using the raw APEX value as seconds produces absurd output like "6.9s" for a fast shutter.

**Why it happens:** Many developers assume EXIF values are in human-readable units. ShutterSpeedValue is one of the few EXIF tags that uses APEX encoding.

**How to avoid:** Always convert APEX to seconds: `exposureTime = pow(2.0, -apexValue)`. Then format: if exposureTime < 1.0, display as fraction `1/{denominator}`; if >= 1.0, display as decimal with seconds suffix. This is implemented in Pattern 1.

**Warning signs:** Shutter speed displays as large numbers like "6.9s" for photos shot at 1/120s. Exiftool shows `ShutterSpeedValue: 6.906` but `ExposureTime: 1/120`.

### Pitfall 6: DNG Gain Map Extraction Differences from HEIC

**What goes wrong:** The DNG gain map may be stored in a different auxiliary data type or embedded within the DNG dictionary rather than as a separate `kCGImageAuxiliaryDataTypeHDRGainMap` auxiliary image. If `CGImageSourceCopyAuxiliaryDataInfoAtIndex` returns nil for the gain map, the code should log a warning and continue — not fail.

**Why it happens:** Apple ProRAW DNG encodes computational photography metadata differently than HEIC container files. The gain map may be embedded in DNG tags rather than as a separate auxiliary data track per the HEIF specification.

**How to avoid:** Per D-03: attempt `CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap)`. If nil, log a warning via `os_log` (not `print`) and continue processing without the gain map. The DNG metadata contains tone curve information in the DNG dictionary that provides some HDR rendering instructions even without the explicit gain map.

**Warning signs:** Gain map extraction returns nil for DNG files but works for HEIC files. This is expected behavior — DNG uses a different HDR encoding. The output should still be visually correct because Core Image renders with `expandToHDR: true`.

## Code Examples

### EXIF Token Substitution in Text Watermark Rendering

```swift
// Source: Integration point in WatermarkEngine.buildFilterGraph()
// Verified: Apple ImageIO CGImageProperties + existing TextWatermarkRenderer pattern
case .text(let textConfig, _, _):
    // Token substitution happens BEFORE rendering (D-07)
    let substitutedText = EXIFTokenParser.substitute(
        textConfig.text,
        metadata: loaded.metadata.metadata
    )
    let configWithTokens = TextWatermarkInput(
        text: substitutedText,
        fontSize: textConfig.fontSize,
        color: textConfig.color,
        opacity: textConfig.opacity
    )
    watermarkImage = TextWatermarkRenderer.render(config: configWithTokens)
```

### EXIF Token Substitution in White Frame Text

```swift
// Source: Integration in WhiteFrameRenderer.render() — attribution text path
// The metadataText string from WhiteFrameConfig.customAttributionText
// passes through token substitution before NSAttributedString creation
if let rawText = attributionText {
    let substituted = EXIFTokenParser.substitute(rawText, metadata: metadata)
    // ... use substituted text for NSAttributedString rendering ...
}
```

### DNG UTI Detection in FormatDetector

```swift
// Source: Apple UTType documentation + existing FormatDetector pattern
// [CITED: developer.apple.com/documentation/uniformtypeidentifiers/utype]
private static let supportedUTIs: Set<String> = [
    "public.heic",
    "public.jpeg",
    "public.png",
    "com.adobe.raw-image",       // DNG UTI
]

// UTI to UTType mapping
case "com.adobe.raw-image": type = .dng  // or .rawImage

// File extension for DNG
case "com.adobe.raw-image": return "dng"
```

### DNG Metadata Preservation in ImageWriter

```swift
// Source: Apple ImageIO CGImageDestination documentation
// [CITED: developer.apple.com/documentation/imageio/cgimagedestination]
public static func write(
    cgImage: CGImage,
    metadata: [String: Any],
    dngMetadata: [String: Any]?,     // NEW: DNG-specific metadata
    gainMapAuxData: [String: Any]?,
    sourceUTI: String,
    to url: URL
) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, sourceUTI as CFString, 1, nil
    ) else {
        throw PipelineError.failedToCreateDestination
    }

    // Build combined metadata dictionary
    var combinedMetadata = metadata
    if let dng = dngMetadata {
        combinedMetadata[kCGImagePropertyDNGDictionary as String] = dng
    }

    CGImageDestinationAddImage(destination, cgImage, combinedMetadata as CFDictionary)

    if let gainMap = gainMapAuxData {
        CGImageDestinationAddAuxiliaryDataInfo(
            destination,
            kCGImageAuxiliaryDataTypeHDRGainMap,
            gainMap as CFDictionary
        )
    }

    guard CGImageDestinationFinalize(destination) else {
        throw PipelineError.failedToFinalize
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| DNG unsupported (Phase 1 D-10: ProRAW deferred) | Native DNG via `CIImage(contentsOf:options:)` + `CGImageDestination` with DNG UTI | Phase 5 | ProRAW users can watermark without quality loss |
| Static "Taken by: Device" text only | Dynamic `{token}` substitution in any text field | Phase 5 | Users can add camera specs to watermarks and frames |
| Single watermark + frame (implied) | Any combination of text, image, and frame layers | Phase 5 | "Shot on iPhone" style multi-element overlays |
| CGImageSource metadata = EXIF only | Metadata includes DNG dictionary for DNG files | Phase 5 | DNG-specific color matrices and tone curves preserved |

**Deprecated/outdated:**
- **Phase 1 D-10 "ProRAW and TIFF deferred to v2":** Rescoped — ProRAW is now Phase 5 (v1), TIFF remains deferred to v2
- **`FormatDetector.supportedUTIs` hardcoded to HEIC/JPEG/PNG:** Extended to include DNG UTIs
- **Single-layer opacity assumption:** The `ImageWatermarkRenderer` applies opacity per-layer already (via `colorMatrix`), but text watermarks did not have per-layer opacity in the compositing step. Phase 5 adds consistent per-layer opacity for all layer types.

## Assumptions Log

> All claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this
> section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Apple ProRAW DNG files are always Linear DNG (already demosaiced) — no manual Bayer pipeline needed | Standard Stack | HIGH: Would need `CIRAWFilter` with custom debayer if files are not Linear DNG |
| A2 | `kCGImageAuxiliaryDataTypeHDRGainMap` works for DNG files the same way as HEIC (D-03 says "DNG stores gain map differently" but uses the same API) | Pitfalls §6 | MEDIUM: DNG may use a different auxiliary type or embed gain map in DNG dictionary tags |
| A3 | `CGImageDestination` with DNG UTI properly preserves all `kCGImagePropertyDNGDictionary` metadata when writing | DNG Write Path | HIGH: Apple's ImageIO may strip or reject certain DNG dictionary keys on write |
| A4 | ISOSpeedRatings is an array `[Int]` in the CGImageSource metadata dictionary (matching the EXIF spec) | Pattern 1 | LOW: Some cameras store it as a single Int — code handles both cases |
| A5 | GPS dictionary keys `"Latitude"`, `"LatitudeRef"`, `"Longitude"`, `"LongitudeRef"` are the correct string-keyed forms for `[String: Any]` metadata dictionaries after `convertCFDictionary` | Pattern 1 | MEDIUM: String representations of CFString keys in metadata dicts follow these exact names per existing `DeviceMetadataProvider` pattern |

## Open Questions

1. **DNG Write Path — Does CGImageDestination support DNG output?**
   - What we know: `CGImageDestinationCreateWithURL` accepts any UTI; DNG UTI (`com.adobe.raw-image`) is a valid image UTI. `CGImageDestinationAddImage` attaches metadata.
   - What's unclear: Whether Apple's ImageIO implementation supports DNG as a DESTINATION format (it supports it as a SOURCE). Some ImageIO types are read-only. If DNG write is unsupported, the DNG output would need to fall back to HEIC with a warning, or use `CIRAWFilter` output.
   - Recommendation: Spike this during planning Wave 0 — create a CGImageDestination with DNG UTI, write a test CGImage, and check if `CGImageDestinationFinalize` succeeds. If DNG write fails, the `OutputFormat` for DNG source should be `.heic` with HDR gain map preservation and a logged warning.

2. **DNG Gain Map — Separate auxiliary data or embedded in DNG dictionary?**
   - What we know: D-03 says "DNG stores gain map differently than HEIC." Apple ProRAW DNG is a Linear DNG — it contains computational photography metadata that may encode HDR information differently than the HEIF gain map auxiliary track.
   - What's unclear: Whether `kCGImageAuxiliaryDataTypeHDRGainMap` returns data for DNG files, or if the HDR information is embedded in DNG tags like `kCGImagePropertyDNGAsShotNeutral`, `kCGImagePropertyDNGLinearizationTable`, etc.
   - Recommendation: Test with a real ProRAW DNG from an iPhone — call `CGImageSourceCopyAuxiliaryDataInfoAtIndex` with `kCGImageAuxiliaryDataTypeHDRGainMap` and log the result. If nil, the HDR rendering is handled by Core Image's `expandToHDR: true` flag during CIImage creation rather than a separate gain map re-attachment step.

3. **Per-layer visibility property — Does WatermarkLayer need a new field?**
   - What we know: D-14 says "Each layer has independent: visibility (show/hide), opacity (per-layer alpha), position (WatermarkPosition), scale." The current `WatermarkLayer` enum has cases like `.text(TextWatermarkInput, position: WatermarkPosition, scale: CGFloat)` — no visibility or opacity field on the layer itself.
   - What's unclear: Whether visibility and per-layer opacity should be added as `WatermarkLayer` associated values, or derived from properties already on `TextWatermarkInput`/`ImageWatermarkInput`.
   - Recommendation: `TextWatermarkInput.opacity` already exists but is used for the text rendering alpha, not the compositing opacity. Per-layer opacity for compositing should be on `WatermarkLayer` as an additional associated value: e.g., `.text(TextWatermarkInput, position: WatermarkPosition, scale: CGFloat, opacity: CGFloat, isVisible: Bool)`. This requires a minor model change despite D-13 saying "No model change needed" — D-13 refers to the layer LIST structure, not the individual layer properties.

4. **What is the correct CGImageSource metadata dictionary key for ISOSpeedRatings in String-keyed format?**
   - What we know: The CFString constant is `kCGImagePropertyExifISOSpeedRatings`. After `convertCFDictionary` (CFString → String), this becomes the string representation of that constant. The existing `DeviceMetadataProvider` uses: `tiffDictionaryKey = "{TIFF}"`, `tiffModelKey = "Model"`, etc.
   - What's unclear: The exact String representation of CFString constants like `kCGImagePropertyExifFNumber`, `kCGImagePropertyExifFocalLength`, etc. after `CFString → String` bridging.
   - Recommendation: Log the actual dictionary keys from a test image during Wave 0 to confirm exact String representations. The codebase already uses this pattern in DeviceMetadataProvider — test by printing all keys from a known image's metadata dictionary.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — `CGImageSourceCopyPropertiesAtIndex`: [developer.apple.com/documentation/imageio/cgimagesource](https://developer.apple.com/documentation/imageio/cgimagesource) — EXIF, TIFF, GPS, DNG dictionary access [VERIFIED: official docs]
- Apple Developer Documentation — `CGImageDestination`: [developer.apple.com/documentation/imageio/cgimagedestination](https://developer.apple.com/documentation/imageio/cgimagedestination) — Metadata passthrough, auxiliary data attachment [VERIFIED: official docs]
- Apple Developer Documentation — `UTType.rawImage`, `UTType.dng`: [developer.apple.com/documentation/uniformtypeidentifiers/utype](https://developer.apple.com/documentation/uniformtypeidentifiers/utype) — DNG UTI detection [VERIFIED: official docs]
- Apple Developer Documentation — `CIImage(contentsOf:options:)`: [developer.apple.com/documentation/coreimage/ciimage](https://developer.apple.com/documentation/coreimage/ciimage) — DNG loading, `expandToHDR` option [VERIFIED: official docs]
- Apple Developer Documentation — `kCGImagePropertyExifDictionary`, `kCGImagePropertyTIFFDictionary`, `kCGImagePropertyGPSDictionary`: CGImageProperties.h header — Exact key names and value types [VERIFIED: official docs]
- Existing WatermarkCore codebase (Phase 1-4) — `DeviceMetadataProvider`, `ImageLoader`, `FormatDetector`, `ImageWriter`, `WatermarkRenderer`, `WatermarkEngine` [VERIFIED: local codebase grep]
- Phase 1 CONTEXT.md — Watermark compositing decisions (D-01 through D-10), HDR pipeline, CGImageSource→CGImageDestination pattern [VERIFIED: project docs]
- Phase 5 CONTEXT.md — All locked decisions (D-01 through D-15) [VERIFIED: project docs]

### Secondary (MEDIUM confidence)
- WebSearch: "CGImageSource DNG metadata kCGImagePropertyDNGDictionary" — DNG dictionary structure and key names [CITED: developer.apple.com]
- WebSearch: "CIImage expandToHDR ProRAW DNG Bayer raw data" — Confirmed ProRAW is Linear DNG, already demosaiced [CITED: multiple Apple documentation sources]
- WebSearch: "CGImageSource EXIF dictionary keys Swift" — ISOSpeedRatings type (array vs scalar), FNumber type (Double) [CITED: stackoverflow.com, ikyle.me]
- WebSearch: "CGImageDestination DNG write preserve metadata" — DNG output format support caveats [CITED: stackoverflow.com, medium.com]
- WebSearch: "public.camera-raw-image UTI DNG UTType iOS" — DNG UTIs and conformance hierarchy [CITED: developer.apple.com]
- WebSearch: "CIImage sourceOverCompositing multi-layer order" — Confirmed chaining pattern matches existing WatermarkRenderer implementation [CITED: developer.apple.com, stackoverflow.com]

### Tertiary (LOW confidence)
- [ASSUMED] CGImageDestination supports DNG as a write destination format — needs Spike verification (see Open Question #1)
- [ASSUMED] String representations of CFString EXIF keys follow the exact names used in Pattern 1 — needs empirical verification per Open Question #4
- [ASSUMED] `kCGImageAuxiliaryDataTypeHDRGainMap` works for DNG files — needs empirical testing with real ProRAW DNG (see Open Question #2)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All Apple system frameworks; no third-party dependencies; ProRAW DNG loading via CIImage is verified in Apple docs
- Architecture: HIGH — Patterns extend existing Phase 1 architecture; EXIFTokenParser follows DeviceMetadataProvider pattern; multi-layer compositing extends existing WatermarkRenderer
- Pitfalls: MEDIUM — Two open questions about DNG write path and gain map extraction could change implementation approach

**Research date:** 2026-06-18
**Valid until:** 2026-07-18 (stable domain — Apple framework APIs change only at WWDC annually; next changes June 2027)
