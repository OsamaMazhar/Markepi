# Phase 05: Extended Engine (ProRAW, EXIF Tokens, Multi-Layer) - Pattern Map

**Mapped:** 2026-06-18
**Files analyzed:** 15 new/modified files
**Analogs found:** 15 / 15

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Utilities/EXIFTokenParser.swift` | utility | transform (string → string) | `Utilities/DeviceMetadataProvider.swift` | **exact** — same dir, static struct, String-keyed EXIF dict access |
| `Processing/ProRAWProcessor.swift` | processing | request-response (load → metadata → CIImage) | `Input/ImageLoader.swift` + `Processing/VideoProcessor.swift` | **role-match** — same CGImageSource metadata extraction + static struct pattern |
| `Engine/WatermarkEngine.swift` | engine | request-response (pipeline orchestrator) | `Engine/WatermarkEngine.swift` (itself) | **exact** — extending existing `buildFilterGraph()` method |
| `Engine/PipelineError.swift` | utility | error enum | `Engine/PipelineError.swift` (itself) | **exact** — extending existing enum |
| `Rendering/TextWatermarkRenderer.swift` | rendering | transform (config → CIImage) | `Rendering/TextWatermarkRenderer.swift` (itself) | **exact** — adding token preprocessing before attributed string |
| `Rendering/WhiteFrameRenderer.swift` | rendering | transform (config + rect → CIImage) | `Rendering/WhiteFrameRenderer.swift` (itself) | **exact** — adding token substitution before text drawing |
| `Rendering/WatermarkRenderer.swift` | rendering | transform (layers → composited CIImage) | `Rendering/WatermarkRenderer.swift` (itself) | **exact** — per-layer opacity passthrough |
| `Rendering/ImageWatermarkRenderer.swift` | rendering | transform (config → CIImage) | `Rendering/ImageWatermarkRenderer.swift` (itself) | **exact** — opacity via `CIFilter.colorMatrix` (already done, reference pattern) |
| `Input/FormatDetector.swift` | input | transform (source → UTI) | `Input/FormatDetector.swift` (itself) | **exact** — extending UTI set + UTI mapping |
| `Input/ImageLoader.swift` | input | CRUD (url → LoadedImage) | `Input/ImageLoader.swift` (itself) | **exact** — extending metadata extraction + DNG validation |
| `Output/ImageWriter.swift` | output | file-I/O (cgImage + metadata → file/data) | `Output/ImageWriter.swift` (itself) | **exact** — extending CGImageDestination write path |
| `Models/MediaMetadata.swift` | model | data (immutable value type) | `Models/MediaMetadata.swift` (itself) | **exact** — adding dngMetadata field |
| `Tests/EXIFTokenParserTests.swift` | test | — | `Tests/TextWatermarkRendererTests.swift` + `Tests/FormatDetectorTests.swift` | **role-match** — same @Suite/@Test pattern |
| `Tests/ProRAWTests.swift` | test | — | `Tests/WatermarkEngineTests.swift` | **role-match** — same E2E pattern, CGImageSource verification |
| `Tests/MultiLayerCompositingTests.swift` | test | — | `Tests/WatermarkEngineTests.swift` (combinedAllFeatures test, line 944) | **role-match** — same combined-layer assertion patterns |
| `Tests/TestHelpers/EXIFMetadataFactory.swift` | utility (test) | — | `Tests/TestHelpers/TestImageFactory.swift` | **role-match** — same factory pattern for synthetic test data |

---

## Pattern Assignments

### `Utilities/EXIFTokenParser.swift` (utility, transform)

**Analog:** `Utilities/DeviceMetadataProvider.swift` (lines 1–67)

**Imports pattern** (DeviceMetadataProvider lines 1–5):
```swift
import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#endif
```

**Struct declaration pattern** (DeviceMetadataProvider lines 17–18):
```swift
/// Doc comment explaining the type's purpose.
/// Stateless utility struct with static methods.
public struct EXIFTokenParser {
```
*Copy from: `DeviceMetadataProvider.swift` line 17 — `public struct` + doc comment header pattern*

**Static String key constants pattern** (DeviceMetadataProvider lines 20–24):
```swift
    /// CFString keys used for EXIF metadata dictionary access.
    /// Using raw string representations for Sendable-compatible lookups.
    private static let tiffDictionaryKey = "{TIFF}"
    private static let tiffModelKey = "Model"
    private static let exifDictionaryKey = "{Exif}"
    private static let exifLensModelKey = "LensModel"
```
*Copy from: `DeviceMetadataProvider.swift` lines 20–24 — String key constants for CFString → String metadata dict access*

**Metadata extraction pattern** (DeviceMetadataProvider lines 36–57):
```swift
    public static func deviceModel(from metadata: [String: Any]) -> String {
        // 1. Try TIFF dictionary
        if let tiff = metadata[tiffDictionaryKey] as? [String: Any],
           let model = tiff[tiffModelKey] as? String,
           !model.isEmpty {
            return model
        }
        // 2. Fallback
        return "Unknown"
    }
```
*Copy from: `DeviceMetadataProvider.swift` lines 38–48 — dictionary chain: `metadata["{TIFF}"]` → `["Model"]` pattern*

**Sendable-compatible pattern:** All static funcs, no stored state, String-keyed dicts. No `@MainActor`, no protocol conformance needed beyond implicit Sendable (struct with only static members).

---

### `Processing/ProRAWProcessor.swift` (processing, request-response)

**Analog 1:** `Input/ImageLoader.swift` (lines 1–131) — CGImageSource metadata extraction + CIImage creation pattern

**Imports pattern** (ImageLoader lines 1–3):
```swift
import CoreImage
import ImageIO
import Foundation
```

**Static struct + availability annotation** (ImageLoader lines 11–12):
```swift
@available(macOS 11.0, *)
public struct ProRAWProcessor {
```

**DNG-specific metadata extraction** (ImageLoader lines 73–84 — general metadata + gain map extraction):
```swift
        // Extract metadata dictionary BEFORE any CIImage creation (Pattern 2)
        let metadata = convertCFDictionary(props)

        // Extract HDR gain map auxiliary data (Pitfall 1 prevention)
        let gainMapAuxData: [String: Any]? = {
            if let auxData = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source, 0, kCGImageAuxiliaryDataTypeHDRGainMap
            ) as? [CFString: Any] {
                return convertCFDictionary(auxData)
            }
            return nil
        }()

        // NEW: Extract DNG metadata dictionary
        let dngMetadata: [String: Any]? = {
            if let dng = props[kCGImagePropertyDNGDictionary] as? [CFString: Any] {
                return convertCFDictionary(dng)
            }
            return nil
        }()
```
*Copy from: `ImageLoader.swift` lines 73–84 — metadata + gain map extraction pattern; extend with `kCGImagePropertyDNGDictionary`*

**CIImage creation with HDR options** (ImageLoader lines 98–109):
```swift
        // Primary: HDR-enabled load. Fallback: plain load.
        let options: [CIImageOption: Any] = [
            .expandToHDR: true,
            .auxiliaryHDRGainMap: true,
            .applyOrientationProperty: true,
        ]
        var ciImage = CIImage(contentsOf: url, options: options)
        if ciImage == nil {
            ciImage = CIImage(contentsOf: url)
        }
        guard let ciImage = ciImage else {
            throw PipelineError.failedToCreateCIImage
        }
```
*Copy from: `ImageLoader.swift` lines 100–112 — CIImage load pattern with HDR options + fallback*

**Analog 2:** `Processing/VideoProcessor.swift` (lines 1–25) — dedicated processing struct pattern

**Processing struct header pattern** (VideoProcessor lines 25):
```swift
/// Doc comment
/// Uses `public struct` with static method pattern (not actor) —
/// Apple frameworks handle their own threading internally.
public struct ProRAWProcessor {
```

**convertCFDictionary helper** (ImageLoader lines 124–130):
```swift
    /// Converts a [CFString: Any] dictionary to [String: Any] for Sendable conformance.
    private static func convertCFDictionary(_ dict: [CFString: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            result[key as String] = value
        }
        return result
    }
```
*Copy from: `ImageLoader.swift` lines 124–130 — exact pattern reused for DNG metadata conversion*

---

### `Engine/WatermarkEngine.swift` (engine, request-response — EXTEND)

**Analog:** `Engine/WatermarkEngine.swift` (lines 144–230) — `buildFilterGraph()` method

**Core buildFilterGraph loop** (WatermarkEngine lines 198–225):
```swift
        var layers: [(CIImage, CGPoint)] = []
        let extent = composited.extent

        // Build layers in order: bottom layer first, top layer last (D-01)
        for watermark in config.watermarks {
            let watermarkImage: CIImage

            switch watermark {
            case .text(let textConfig, _, _):
                // ** NEW: Token substitution before rendering **
                let substitutedText = EXIFTokenParser.substitute(
                    textConfig.text,
                    metadata: metadata
                )
                let configWithTokens = TextWatermarkInput(
                    text: substitutedText,
                    fontSize: textConfig.fontSize,
                    color: textConfig.color,
                    opacity: textConfig.opacity
                )
                watermarkImage = TextWatermarkRenderer.render(config: configWithTokens)

            case .image(let imageConfig, _, _):
                watermarkImage = try ImageWatermarkRenderer.render(config: imageConfig)
            }

            // Scale watermark relative to base image
            let scaled = watermarkImage.transformed(
                by: CGAffineTransform(scaleX: watermark.scale, y: watermark.scale)
            )

            // Calculate position
            let position = PositionCalculator.position(
                for: watermark.position,
                watermarkExtent: scaled.extent,
                baseExtent: extent,
                padding: config.padding
            )

            layers.append((scaled, position))
        }

        // Composite all layers onto base
        return WatermarkRenderer.composite(layers: layers, onto: composited)
```
*Copy from: `WatermarkEngine.swift` lines 198–228 — the existing for-loop over `config.watermarks`, extend the `.text` case with token substitution*

**White frame compositing pattern** (WatermarkEngine lines 175–193):
```swift
        // White frame rendering (composited below all watermark layers)
        if let frameConfig = config.whiteFrame, frameConfig.isEnabled {
            let frameCIImage = try WhiteFrameRenderer.render(
                config: frameConfig,
                baseExtent: composited.extent,
                metadata: metadata,
                scale: 1.0
            )

            // Composite frame onto base
            let frameFilter = CIFilter.sourceOverCompositing()
            frameFilter.inputImage = frameCIImage
            frameFilter.backgroundImage = composited
            composited = frameFilter.outputImage ?? composited
        }
```
*Copy from: `WatermarkEngine.swift` lines 175–193 — white frame compositing BEFORE watermark layers per D-12 (frame is bottom-most layer)*

**Key change for D-12 (frame compositing order):** Per D-12, the compositing order is text → image/logo → frame (back-to-front). Text renders first (bottom layer), images composite on top of text, white frame is outermost (top) layer. This means the frame compositing should happen AFTER all watermark layers, not before. The existing code composites frame first (below watermarks). The Phase 5 change inverts this: watermark layers composited first onto base, then frame composited on top of watermarked result.

---

### `Engine/PipelineError.swift` (utility, error enum — EXTEND)

**Analog:** `Engine/PipelineError.swift` (lines 1–169)

**New error cases pattern** (lines 9–43 — photo pipeline errors section):
```swift
    // Add these before the `// MARK: - Video Pipeline Errors` comment (before line 45)

    /// ProRAW gain map was expected but not found in DNG file
    case proRawGainMapMissing

    /// Token substitution failed (unexpected — token parser is infallible)
    case tokenSubstitutionFailed(String)

    /// DNG output write failed — CGImageDestination may not support DNG as destination
    case proRawWriteFailed
```

**LocalizedError description pattern** (lines 76–121):
```swift
        case .proRawGainMapMissing:
            return "The ProRAW DNG file does not contain an HDR gain map. Processing continues without HDR gain map data."
        case .tokenSubstitutionFailed(let token):
            return "Failed to substitute token '\(token)' in watermark text."
        case .proRawWriteFailed:
            return "Failed to write ProRAW DNG output. DNG may not be supported as a write destination on this platform."
```

**Equatable conformance pattern** (lines 130–168 — add to both the `==` override and `_isEqual` helper):
```swift
        case (.proRawGainMapMissing, .proRawGainMapMissing): return true
        case (.tokenSubstitutionFailed(let a), .tokenSubstitutionFailed(let b)): return a == b
        case (.proRawWriteFailed, .proRawWriteFailed): return true
```
*Copy from: `PipelineError.swift` lines 145–168 — add new cases following the exact pattern of existing cases*

---

### `Rendering/TextWatermarkRenderer.swift` (rendering, transform — EXTEND)

**Analog:** `Rendering/TextWatermarkRenderer.swift` (lines 1–64)

**Integration point for token substitution — modify the `render(config:`)` method or add a new overload:**

**Existing render signature** (lines 29–43):
```swift
    public static func render(config: TextWatermarkInput) -> CIImage {
        // Build the attributed string with SF system font (D-02)
        let attributes = buildAttributes(config: config)
        let attributed = NSAttributedString(string: config.text, attributes: attributes)

        // Use CIAttributedTextImageGenerator to create a CIImage
        let filter = CIFilter.attributedTextImageGenerator()
        filter.text = attributed
        filter.scaleFactor = 1.0

        return filter.outputImage!
    }
```

**New render overload with metadata** (add as a new method):
```swift
    /// Renders a text watermark with EXIF token substitution applied to the text string.
    /// Token substitution happens BEFORE NSAttributedString creation per D-07.
    /// - Parameters:
    ///   - config: Text watermark configuration (text may contain {tokens})
    ///   - metadata: Source image metadata dictionary (for token resolution)
    /// - Returns: A CIImage with token-substituted text rendered
    public static func render(config: TextWatermarkInput, metadata: [String: Any]) -> CIImage {
        let substitutedText = EXIFTokenParser.substitute(config.text, metadata: metadata)
        let substitutedConfig = TextWatermarkInput(
            text: substitutedText,
            fontSize: config.fontSize,
            color: config.color,
            opacity: config.opacity
        )
        return render(config: substitutedConfig)
    }
```
*Copy from: `TextWatermarkRenderer.swift` lines 29–37 — NSAttributedString creation from config, inject token substitution before `NSAttributedString(string:)`*

**buildAttributes pattern** (lines 46–63):
```swift
    private static func buildAttributes(config: TextWatermarkInput) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail

        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: config.fontSize, weight: .semibold)
        let foregroundColor = UIColor(cgColor: config.color).withAlphaComponent(config.opacity)
        #elseif canImport(AppKit)
        let font = NSFont.systemFont(ofSize: config.fontSize, weight: .semibold)
        let foregroundColor = NSColor(cgColor: config.color)?.withAlphaComponent(config.opacity) ?? NSColor.white
        #endif

        return [
            .font: font,
            .foregroundColor: foregroundColor,
            .paragraphStyle: paragraphStyle,
        ]
    }
```
*No change needed — buildAttributes unchanged*

---

### `Rendering/WhiteFrameRenderer.swift` (rendering, transform — EXTEND)

**Analog:** `Rendering/WhiteFrameRenderer.swift` (lines 1–252)

**Token substitution integration point — in the `render()` method, the `customAttributionText` path** (lines 51–60):
```swift
        // 2. Determine attribution text (if metadata text is enabled)
        let attributionText: String?
        if config.metadataTextEnabled {
            if let customText = config.customAttributionText {
                // ** NEW: Apply token substitution to custom attribution text **
                attributionText = EXIFTokenParser.substitute(customText, metadata: metadata)
            } else {
                attributionText = DeviceMetadataProvider.attributionText(from: metadata)
            }
        } else {
            attributionText = nil
        }
```
*Copy from: `WhiteFrameRenderer.swift` lines 52–60 — insert `EXIFTokenParser.substitute()` call before line 54 where `customText` is used*

**drawFrame text rendering pattern** (lines 193–231):
```swift
        if let text = attributionText, frameWidth > 0 {
            let fontSize = frameWidth * config.textFontSizeRatio
            let textColor = platformColor(from: config.textColor)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: platformFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: textColor,
            ]

            let attributed = NSAttributedString(
                string: text,
                attributes: attributes
            )
            // ...
```
*No change needed — `attributionText` is already token-substituted by this point*

---

### `Rendering/WatermarkRenderer.swift` (rendering, transform — EXTEND)

**Analog:** `Rendering/WatermarkRenderer.swift` (lines 1–51)

**Existing composite signature** (lines 27–51):
```swift
    public static func composite(
        layers: [(CIImage, CGPoint)],
        onto base: CIImage
    ) -> CIImage {
        var composited = base
        let baseExtent = base.extent

        for (layer, position) in layers {
            let transform = CGAffineTransform(translationX: position.x, y: position.y)
            let positioned = layer.transformed(by: transform)

            let filter = CIFilter.sourceOverCompositing()
            filter.inputImage = positioned
            filter.backgroundImage = composited

            composited = filter.outputImage ?? composited
        }

        return composited.cropped(to: baseExtent)
    }
```

**Minimal change:** The `WatermarkRenderer.composite()` already handles ordered arrays of `(CIImage, CGPoint)` tuples. Multi-layer requires no changes to this method — the engine (buildFilterGraph) simply passes all layers in the correct order. The compositor chains them via `CISourceOverCompositing` in array order, which is the correct behavior per D-12.

**Per-layer opacity:** Applied in `buildFilterGraph()` via `CIFilter.colorMatrix` (following the `ImageWatermarkRenderer` pattern lines 43–57) BEFORE passing to `composite()`:
```swift
        // Apply per-layer opacity via color matrix (following ImageWatermarkRenderer pattern)
        if watermark.opacity < 1.0 {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = scaled
            matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(watermark.opacity))
            matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            opacityAdjusted = matrix.outputImage ?? scaled
        }
```
*Copy from: `ImageWatermarkRenderer.swift` lines 43–57 — exact `CIFilter.colorMatrix()` alpha modulation pattern*

---

### `Rendering/ImageWatermarkRenderer.swift` (rendering, transform — REFERENCE ONLY)

**Analog:** `Rendering/ImageWatermarkRenderer.swift` (lines 1–61)

This file is NOT modified in Phase 5 but serves as the reference pattern for per-layer opacity.

**Opacity via CIFilter.colorMatrix** (lines 43–57):
```swift
        if config.opacity < 1.0 {
            let opacity = CGFloat(config.opacity)
            let colorMatrix = CIFilter.colorMatrix()
            colorMatrix.inputImage = scaled
            colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: opacity)
            colorMatrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)

            guard let output = colorMatrix.outputImage else {
                return scaled
            }
            return output
        }
        return scaled
```

---

### `Input/FormatDetector.swift` (input, transform — EXTEND)

**Analog:** `Input/FormatDetector.swift` (lines 1–56)

**Add DNG UTIs to supportedUTIs set** (line 13–17):
```swift
    /// Supported source UTIs per D-10 (using String keys for Swift 6 Sendable conformance).
    private static let supportedUTIs: Set<String> = [
        "public.heic",
        "public.jpeg",
        "public.png",
        "com.adobe.raw-image",       // ** NEW: DNG UTI (primary) **
    ]
```

**Add DNG case to detect() switch** (lines 32–41):
```swift
        switch utiString {
        case "public.heic": type = .heic
        case "public.jpeg": type = .jpeg
        case "public.png":  type = .png
        case "com.adobe.raw-image": type = .rawImage  // ** NEW **
        default:
            throw PipelineError.unsupportedFormat(utiString)
        }
```

**Add DNG fileExtension** (lines 47–55):
```swift
        switch utiString {
        case "public.heic": return "heic"
        case "public.jpeg": return "jpg"
        case "public.png":  return "png"
        case "com.adobe.raw-image": return "dng"  // ** NEW **
        default:            return "jpg"
        }
```

**DNG file signature verification** (NEW method — extra safety per D-05):
```swift
    /// Verifies a file is a valid DNG/TIFF by checking the byte-order marker.
    /// DNG files start with "II" (little-endian) or "MM" (big-endian) TIFF header.
    /// - Parameter url: File URL to verify
    /// - Returns: `true` if the file begins with a valid TIFF/DNG byte-order marker
    public static func isDNG(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 4)
        let isII = header.starts(with: Data([0x49, 0x49, 0x2A, 0x00]))
        let isMM = header.starts(with: Data([0x4D, 0x4D, 0x00, 0x2A]))
        return isII || isMM
    }
```
*Copy from: RESEARCH.md Pattern 3 (lines 437–444)*

---

### `Input/ImageLoader.swift` (input, CRUD — EXTEND)

**Analog:** `Input/ImageLoader.swift` (lines 1–131)

**Add DNG metadata extraction** — after the gain map extraction (line 84), add DNG metadata block:
```swift
        // Extract DNG-specific metadata dictionary (ProRAW support per D-02)
        let dngMetadata: [String: Any]? = {
            if let dng = props[kCGImagePropertyDNGDictionary] as? [CFString: Any] {
                return convertCFDictionary(dng)
            }
            return nil
        }()
```

**DNG resolution validation** — after pixel dimension check (line 69), add DNG-specific assertion:
```swift
        // DNG resolution validation: ProRAW photos should be >= 4000px on the short side
        // (prevents accidentally processing the embedded JPEG preview instead of RAW)
        let minDimension = min(width, height)
        if sourceUTIString == "com.adobe.raw-image" && minDimension < 4000 {
            // Log a warning: may have loaded the embedded JPEG preview instead of RAW
            // (Pitfall 1 prevention per RESEARCH.md §Common Pitfalls #1)
        }
```

**Extend LoadedImage struct** (lines 14–30) — add `dngMetadata` field:
```swift
    public struct LoadedImage: @unchecked Sendable {
        public let ciImage: CIImage
        public let metadata: [String: Any]
        public let gainMapAuxData: [String: Any]?
        public let dngMetadata: [String: Any]?     // ** NEW **
        public let colorSpace: CGColorSpace?
        public let sourceUTI: String
    }
```

**Return with dngMetadata** (lines 114–120):
```swift
        return LoadedImage(
            ciImage: ciImage,
            metadata: metadata,
            gainMapAuxData: gainMapAuxData,
            dngMetadata: dngMetadata,     // ** NEW **
            colorSpace: colorSpace,
            sourceUTI: sourceUTIString
        )
```

---

### `Output/ImageWriter.swift` (output, file-I/O — EXTEND)

**Analog:** `Output/ImageWriter.swift` (lines 1–90)

**Extend write() signatures** — add `dngMetadata` parameter to both overloads:

**File URL variant** (lines 26–54):
```swift
    public static func write(
        cgImage: CGImage,
        metadata: [String: Any],
        gainMapAuxData: [String: Any]?,
        dngMetadata: [String: Any]?,     // ** NEW **
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

        // Re-attach metadata (Pattern 2)
        CGImageDestinationAddImage(destination, cgImage, combinedMetadata as CFDictionary)

        // Re-attach HDR gain map if present (Pitfall 1 prevention)
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

**Data variant** (lines 61–89) — same addition of `dngMetadata` parameter and combined metadata dictionary.

---

### `Models/MediaMetadata.swift` (model, data — EXTEND)

**Analog:** `Models/MediaMetadata.swift` (lines 1–46)

**Add dngMetadata field** (after line 27):
```swift
    /// DNG-specific metadata dictionary (kCGImagePropertyDNGDictionary).
    /// Non-nil only for ProRAW/DNG source images.
    /// Dictionary keys are `String` representations of the original CFString keys.
    public let dngMetadata: [String: Any]?
```

**Update init** (lines 35–45):
```swift
    public init(
        metadata: [String: Any],
        gainMapAuxData: [String: Any]?,
        dngMetadata: [String: Any]?,     // ** NEW **
        colorSpace: CGColorSpace?,
        sourceUTI: String
    ) {
        self.metadata = metadata
        self.gainMapAuxData = gainMapAuxData
        self.dngMetadata = dngMetadata    // ** NEW **
        self.colorSpace = colorSpace
        self.sourceUTI = sourceUTI
    }
```

---

### `Tests/EXIFTokenParserTests.swift` (test — NEW)

**Analog:** `Tests/TextWatermarkRendererTests.swift` (lines 1–59) + `Tests/FormatDetectorTests.swift` (lines 1–73)

**Test file structure pattern** (TextWatermarkRendererTests lines 1–8):
```swift
import Testing
import CoreImage
@testable import WatermarkCore

/// Tests EXIFTokenParser for token substitution, formatting, and missing-field fallback.
@Suite("EXIFTokenParser")
struct EXIFTokenParserTests {
```

**Individual test pattern** (FormatDetectorTests lines 10–22):
```swift
    @Test("Detects JPEG format from JPEG data")
    func detectsJPEG() throws {
        // Setup: create test data
        let (_, jpegData) = TestImageFactory.solidColorImage(...)
        // Act
        // Assert
        #expect(type == UTType.jpeg)
    }
```

**Token test examples using pattern from TextWatermarkRendererTests:**
- Test each of the 8 tokens with known metadata values
- Test missing fields render as `"--"` per D-08
- Test format validation: `f/1.8`, `24mm`, `ISO 400`, `1/120`, GPS coordinate format
- Test multiple tokens in same string
- Test unrecognized tokens left as-is

---

### `Tests/ProRAWTests.swift` (test — NEW)

**Analog:** `Tests/WatermarkEngineTests.swift` (lines 1–1018) — E2E test pattern

**Test file structure pattern** (WatermarkEngineTests lines 1–15):
```swift
import Testing
import ImageIO
import CoreImage
import Foundation
@testable import WatermarkCore

/// End-to-end tests for ProRAW DNG processing pipeline.
@Suite("ProRAW Processing")
struct ProRAWTests {
```

**Test patterns from WatermarkEngineTests:**
- `processReturnsResult` (lines 34–63) — full pipeline test pattern
- `outputPreservesDimensions` (lines 66–108) — dimension verification via `CGImageSourceCopyPropertiesAtIndex`
- `outputPreservesFormat` (lines 110–139) — UTI preservation check
- `metadataRoundTrip` (lines 177–221) — metadata key verification

**ProRAW-specific tests needed:**
- DNG resolution validation (≥ 4000px short side)
- DNG metadata dictionary preservation
- HDR gain map extraction from DNG
- DNG output format preservation (`.dng` output for `.dng` input)
- Memory safety: 48MP DNG processed without crash (structural test)

---

### `Tests/MultiLayerCompositingTests.swift` (test — NEW)

**Analog:** `Tests/WatermarkEngineTests.swift` — `combinedAllFeatures` test (lines 944–1017)

**Multi-layer test pattern from combinedAllFeatures** (lines 944–1017):
```swift
    @Test("Combined: text watermark + image watermark + white frame — all visible")
    func combinedAllFeatures() async throws {
        // Setup: text + image + frame config
        let config = WatermarkConfiguration(
            watermarks: [
                .text(..., position: .topLeft, scale: 0.12),
                .image(..., position: .bottomRight, scale: 0.3),
            ],
            whiteFrame: WhiteFrameConfig(isEnabled: true, ...)
        )
        // Process
        // Verify: all layers visible in output pixels
    }
```

**Multi-layer test cases needed:**
- Text + image layers simultaneously (line 256 — already implemented as `mixedTextAndImageLayers`)
- Text + image + frame (line 944 — already implemented as `combinedAllFeatures`)
- Per-layer visibility (hidden layer = no pixel effect)
- Per-layer opacity (different opacity per layer)
- Multiple text layers at different positions
- Multiple image layers at different positions

---

### `Tests/TestHelpers/EXIFMetadataFactory.swift` (utility, test — NEW)

**Analog:** `Tests/TestHelpers/TestImageFactory.swift` (lines 1–90)

**Factory struct pattern** (TestImageFactory lines 12–13):
```swift
/// Test helper for creating in-memory test images.
public struct TestImageFactory {
```

**EXIFMetadataFactory should follow the same pattern:**
```swift
import Foundation
import ImageIO
import CoreImage

/// Test helper for creating metadata dictionaries with known EXIF/GPS/TIFF values.
/// Used by EXIFTokenParserTests to verify token substitution with controlled inputs.
public struct EXIFMetadataFactory {

    /// Creates a metadata dictionary with realistic iPhone EXIF values for all
    /// supported token fields.
    ///
    /// - Parameters:
    ///   - model: Camera model string (default: "iPhone 16 Pro")
    ///   - lens: Lens model string (default: "iPhone 16 Pro back triple camera 6.86mm f/1.78")
    ///   - aperture: F-number (default: 1.78)
    ///   - focalLength: Focal length in mm (default: 6.86)
    ///   - shutterSpeed: ShutterSpeedValue in APEX (default: 6.906 → 1/120s)
    ///   - iso: ISO speed rating (default: 400)
    ///   - dateTime: EXIF DateTimeOriginal string (default: "2026:06:18 14:30:00")
    ///   - lat: GPS latitude in decimal degrees (default: 37.7749)
    ///   - lon: GPS longitude in decimal degrees (default: -122.4194)
    /// - Returns: A [String: Any] metadata dictionary with EXIF, TIFF, and GPS dictionaries
    public static func realisticMetadata(...) -> [String: Any] { ... }
}
```

**CGImageSource pattern from TestImageFactory** (lines 40–51 for CGImageDestination usage):
- Use `CGImageDestinationCreateWithData` to create test images with metadata
- Use `CGImageSourceCopyPropertiesAtIndex` to read back for verification

---

## Shared Patterns

### Metadata Dictionary Access (String-keyed CFString dictionaries)

**Source:** `Utilities/DeviceMetadataProvider.swift` lines 20–24
**Apply to:** `EXIFTokenParser.swift`, `ProRAWProcessor.swift`, `ImageLoader.swift` (DNG extension)

```swift
// All metadata dictionaries use String keys for Sendable-compatible access.
// CFString keys are converted at the ImageIO boundary via convertCFDictionary().
private static let exifDictKey = "{Exif}"      // kCGImagePropertyExifDictionary → "{Exif}"
private static let tiffDictKey = "{TIFF}"      // kCGImagePropertyTIFFDictionary → "{TIFF}"
private static let gpsDictKey = "{GPS}"        // kCGImagePropertyGPSDictionary → "{GPS}"
```

### Static Struct Pattern (stateless utilities)

**Source:** `DeviceMetadataProvider.swift` line 17, `CIContextProvider.swift` line 10, `ImageLoader.swift` line 12
**Apply to:** `EXIFTokenParser.swift`, `ProRAWProcessor.swift`

```swift
/// Doc comment
public struct StructName {
    // Static methods only — no stored state
    public static func methodName(...) -> ReturnType { ... }
}
```

### CGImageSource → CIImage → CIContext.render → CGImage → CGImageDestination Pipeline

**Source:** `ImageLoader.swift` + `WatermarkEngine.swift` + `ImageWriter.swift`
**Apply to:** `ProRAWProcessor.swift` (DNG-specific pipeline)

```swift
// Step 1: CGImageSourceCreateWithURL(url, nil)
// Step 2: CGImageSourceCopyPropertiesAtIndex(source, 0, nil) → metadata dict
// Step 3: CIImage(contentsOf: url, options: [.expandToHDR: true, ...])
// Step 4: CIContextProvider.shared.createCGImage(ciImage, from: extent, format: .RGBAh, colorSpace: ...)
// Step 5: CGImageDestinationCreateWithURL(url, uti, 1, nil) → addImage → finalize
```

### Swift Testing (@Suite/@Test) Pattern

**Source:** `Tests/TextWatermarkRendererTests.swift` lines 1–8, `Tests/FormatDetectorTests.swift` lines 1–8
**Apply to:** All new test files

```swift
import Testing
import CoreImage
@testable import WatermarkCore

@Suite("SuiteName")
struct StructNameTests {

    @Test("Test description")
    func testName() throws {
        // Setup → Act → Assert
        #expect(condition)
    }
}
```

### PipelineError Throwing Pattern

**Source:** `ImageLoader.swift` lines 49–111 (multiple `guard` + `throw` patterns)
**Apply to:** `ProRAWProcessor.swift`, `ImageWriter.swift` DNG extension

```swift
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
    throw PipelineError.invalidSource
}

guard CGImageDestinationFinalize(destination) else {
    throw PipelineError.failedToFinalize
}
```

### convertCFDictionary Helper (CFString → String bridging)

**Source:** `ImageLoader.swift` lines 124–130
**Apply to:** `ProRAWProcessor.swift`, anywhere DNG metadata dicts are converted

```swift
private static func convertCFDictionary(_ dict: [CFString: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, value) in dict {
        result[key as String] = value
    }
    return result
}
```

### CIFilter.colorMatrix Opacity Pattern

**Source:** `ImageWatermarkRenderer.swift` lines 43–57
**Apply to:** `WatermarkEngine.swift` `buildFilterGraph()` — per-layer opacity for text and image layers

```swift
if opacity < 1.0 {
    let colorMatrix = CIFilter.colorMatrix()
    colorMatrix.inputImage = image
    colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))
    colorMatrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    return colorMatrix.outputImage ?? image
}
```

### CIFilter.sourceOverCompositing Compositing Pattern

**Source:** `WatermarkRenderer.swift` lines 39–44, `WatermarkEngine.swift` lines 189–192
**Apply to:** `WatermarkEngine.swift` `buildFilterGraph()` — frame compositing, all layer compositing

```swift
let filter = CIFilter.sourceOverCompositing()
filter.inputImage = foregroundLayer
filter.backgroundImage = backgroundBase
composited = filter.outputImage ?? composited
```

---

## No Analog Found

Files with no close match in the codebase (planner should use RESEARCH.md patterns instead):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | — | — | All Phase 5 files have exact or role-matched analogs in the existing WatermarkCore codebase |

---

## Integration Notes

### buildFilterGraph Changes Summary

The `buildFilterGraph()` method in `WatermarkEngine.swift` (lines 165–229) requires these changes:

1. **Token substitution** — In the `.text` case (line 203), call `EXIFTokenParser.substitute(textConfig.text, metadata: metadata)` before rendering
2. **Per-layer opacity** — After scaling (line 211), apply `CIFilter.colorMatrix` for layers with opacity < 1.0 (following `ImageWatermarkRenderer` pattern lines 43–57)
3. **Multi-layer order enforcement per D-12** — The white frame should composite as the TOP (outermost) layer, not the bottom layer. Reverse the existing frame compositing to happen AFTER watermark layers, or change to: watermark layers composite onto base, then frame composites on top of watermarked result.
4. **Per-layer visibility** — Skip layers that aren't visible (requires adding `isVisible` property to `WatermarkLayer`, or checking existing opacity == 0 as proxy)

### EXIFTokenParser Design (from RESEARCH.md Pattern 1)

- Token-to-key mapping: `{camera_model}` → `"{TIFF}"."Model"`, `{lens}` → `"{Exif}"."LensModel"`, `{aperture}` → `"{Exif}"."FNumber"`, `{focal_length}` → `"{Exif}"."FocalLength"`, `{shutter_speed}` → `"{Exif}"."ShutterSpeedValue"`, `{iso}` → `"{Exif}"."ISOSpeedRatings"`, `{date}` → `"{Exif}"."DateTimeOriginal"`, `{gps}` → `"{GPS}"."Latitude/Longitude"`
- Aperture APEX to seconds: `pow(2.0, -apexValue)`
- ISOSpeedRatings can be `[Int]` or `Int` — handle both
- GPS dictionary keys: `"Latitude"`, `"LatitudeRef"`, `"Longitude"`, `"LongitudeRef"`
- Date format: EXIF `"yyyy:MM:dd HH:mm:ss"` → locale-aware short date

---

## Metadata

**Analog search scope:** `Packages/WatermarkCore/Sources/WatermarkCore/` (all subdirectories) + `Packages/WatermarkCore/Tests/WatermarkCoreTests/`
**Files scanned:** 34 source files, 11 test files
**Pattern extraction date:** 2026-06-18
**Confidence:** HIGH — all files have existing analogs with extractable patterns; no structural unknowns beyond Open Question #1 (DNG write path support)
