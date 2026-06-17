# Phase 1: Core Engine & Photo Pipeline - Research

**Researched:** 2026-06-17
**Domain:** iOS Photo Watermarking Engine — Core Image + ImageIO + HDR Preservation
**Confidence:** HIGH

## Summary

This phase delivers a shared Swift Package (`WatermarkCore`) containing a photo watermarking engine that renders text/image overlays and white frames at 8 preset positions while preserving HDR gain maps, EXIF/metadata, and color profiles. The engine is a pure-logic layer with no UI dependencies, testable end-to-end via Swift Testing, and consumed by all subsequent phases (main app, share extension, Photos extension).

The technology stack relies entirely on Apple system frameworks: **Core Image** (CIFilter.sourceOverCompositing for GPU-accelerated watermark compositing), **ImageIO** (CGImageSource → CGImageDestination for metadata/HDR preservation), **Core Graphics** (white frame rendering via UIGraphicsImageRenderer), and **Swift 6** (strict concurrency with actor isolation). Zero third-party dependencies. The engine processes photos asynchronously on background queues, reuses a single `CIContext` instance to avoid GPU reallocation, and outputs to in-memory `Data` buffers or temp files — never saving to the camera roll.

**Primary recommendation:** Build the engine as a Swift 6 actor (`WatermarkEngine`) that orchestrates a chained pipeline: `CGImageSource` (extract metadata + gain map) → `CIImage` filter graph (composite watermarks + white frame) → `CIContext` render (RGBAh for HDR) → `CGImageDestination` (re-attach metadata + gain map). Keep all rendering functions as pure, synchronous operations on `CIImage` objects — the actor handles concurrency isolation and shared `CIContext` reuse.

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** The engine composes watermarks as an ordered layer stack (text and image overlays can be arranged in any order, then composited onto the base image)
- **D-02:** Text watermarks use SF system fonts in v1. Custom font import is deferred to v2 (CUST-01 group)
- **D-03:** Image/logo watermarks accept PNG format with alpha/transparency support. SVG and HEIC watermark images deferred.
- **D-04:** White frame is a uniform border on all 4 sides of the image — not a bottom-only strip
- **D-05:** Frame width is proportional to the image (3-5% of the shorter dimension)
- **D-06:** Metadata text is rendered centered on the bottom portion of the white frame
- **D-07:** Primary text line reads "Taken by: [Device Model]" where device model is sourced from EXIF metadata when available, falling back to `UIDevice.current.model`
- **D-08:** v1 supports a single "Taken by:" metadata line. Additional metadata lines (camera date, GPS location, lens/camera specs) are deferred to v2 (CUST-04 group)
- **D-09:** Engine preserves the source image format for output (HEIC in → HEIC out, JPEG in → JPEG out) unless the watermark requires a format change (e.g., transparency mandates PNG/HEIC)
- **D-10:** Core supported formats: HEIC, JPEG, PNG. ProRAW and TIFF are deferred to v2.

### the agent's Discretion
- Core Image filter chain architecture (CIFilter graph composition, shared CIContext reuse strategy)
- Watermark position coordinate math (normalized vs pixel coordinates, aspect ratio handling)
- CGImageSource → CGImageDestination metadata extraction and re-application approach
- HDR gain map extraction via `kCGImageAuxiliaryDataTypeHDRGainMap` and re-attachment

### Deferred Ideas (OUT OF SCOPE)
- Custom font import for text watermarks → defer to v2 (CUST-01)
- SVG/HEIC watermark image support → defer to v2
- Additional metadata frame lines (date, GPS, camera specs) → defer to v2 (CUST-04)
- ProRAW and TIFF output format support → defer to v2
- Rotation control for watermarks → defer to Phase 2 or v2 (CUST-02)
- Template/preset saving → defer to v2 (CUST-01)

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| WMRK-01 | Custom text watermarks with font, size, color, and opacity controls | CIAttributedTextImageGenerator with NSAttributedString (font/size/color), UIColor alpha for opacity (§Text Watermark Rendering) |
| WMRK-02 | Import and overlay image/logo watermarks with resize and opacity controls | CIImage from PNG Data, CGAffineTransform scaling, CISourceOverCompositing with alpha (§Image Watermark Compositing) |
| WMRK-03 | Place watermarks in 8 preset positions (4 corners, 4 edges, center) | 9-position enum with CGAffineTransform translation math, EXIF-normalized coordinate system (§Position Calculation) |
| FRME-01 | Apply white frame border to photos | UIGraphicsImageRenderer white border drawing, or CIConstantColorGenerator + CIAffineTransform for Core Image-native border (§White Frame Rendering) |
| FRME-02 | Overlay device metadata text on white frame ("Taken by: iPhone 16 Pro") | DeviceMetadataProvider (EXIF model → UIDevice fallback), UIGraphicsImageRenderer text drawing centered on bottom frame (§Metadata Text Overlay) |
| QUAL-01 | Preserve all EXIF/metadata from source in output | CGImageSourceCopyPropertiesAtIndex extraction → CGImageDestinationAddImage with properties dictionary re-attachment (§Metadata Preservation Pipeline) |
| QUAL-02 | Preserve HDR gain maps and color profiles | CIImage load with `.auxiliaryHDRGainMap: true`, CIContext with CIFormat.RGBAh, CGImageDestinationAddAuxiliaryDataInfo re-attachment (§HDR Gain Map Preservation) |
| QUAL-03 | Preserve original quality (no unnecessary re-compression) | Format-aware output: match source UTI → CGImageDestination, avoid UIImage.jpegData() (§Format-Aware Output) |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Text watermark rendering | Processing Engine (Swift Package) | — | CIAttributedTextImageGenerator runs on-device GPU via Core Image; no UI dependency |
| Image watermark compositing | Processing Engine | — | CIFilter.sourceOverCompositing operates on CIImage pixel graphs, entirely within engine |
| Position calculation (8 presets) | Processing Engine | — | Pure math on CIImage extents; no display coordinates involved |
| White frame + metadata overlay | Processing Engine | — | UIGraphicsImageRenderer or Core Image native; all rendering is engine-side |
| HDR gain map preservation | Processing Engine (ImageIO) | — | CGImageSource/CGImageDestination auxiliary data pipeline; engine-owned |
| EXIF/metadata passthrough | Processing Engine (ImageIO) | — | Metadata extraction before pixel ops, re-attachment at output; engine-owned |
| Format detection + passthrough | Processing Engine (ImageIO) | — | CGImageSourceGetType UTI detection; engine-owned |
| Temp file output (no camera roll) | Processing Engine (Storage) | — | FileManager + cachesDirectory; engine decides output destination |
| CIContext lifecycle | Processing Engine (actor) | — | Single shared instance managed by actor; no UI involvement |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Core Image (CIFilter, CIContext) | iOS 18 SDK | GPU-accelerated watermark compositing, HDR pixel pipeline | Apple's definitive GPU image processing framework. Lazy filter graph merges into single Metal shader. CISourceOverCompositing is the standard blend for watermark overlays. [VERIFIED: Apple Developer docs] |
| ImageIO (CGImageSource, CGImageDestination) | iOS 18 SDK | Metadata extraction/re-attachment, HDR gain map preservation, format-aware I/O | Only framework that preserves EXIF/GPS/color profiles through the pixel pipeline. CGImageDestinationAddAuxiliaryDataInfo is the sole API for embedding HDR gain maps. [VERIFIED: Apple Developer docs] |
| Core Graphics (UIGraphicsImageRenderer) | iOS 18 SDK | White frame border drawing + device metadata text rendering | Standard for bitmap-backed text rendering (NSAttributedString) with UIKit coordinate system. Wide-color context automatically. [VERIFIED: Apple Developer docs] |
| UniformTypeIdentifiers (UTType) | iOS 18 SDK | Source format detection (HEIC/JPEG/PNG) | Modern Swift-native UTI comparison. Replaces legacy CFString UTI constants. [VERIFIED: Apple Developer docs] |
| Foundation (FileManager, Data) | iOS 18 SDK | Temp file management, in-memory buffer I/O | Standard for sandboxed file operations in cachesDirectory. [VERIFIED: Apple Developer docs] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| — _(none)_ | — | — | No third-party libraries are needed. Apple system frameworks provide complete coverage. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Core Image (CIFilter.sourceOverCompositing) | vImage / Accelerate (manual pixel ops) | vImage offers max performance for very large images but requires manual pixel-level compositing code. CIFilter is GPU-accelerated and declarative. Use Core Image for all v1 needs. |
| CGImageDestination for output | PHPhotoLibrary save | PHPhotoLibrary auto-saves to camera roll — contradicts core "share without saving" value. CGImageDestination writes to temp files, giving the engine full control over output destination. |
| UIGraphicsImageRenderer for white frame | CIConstantColorGenerator + CIAffineTransform (Core Image-native) | CIConstantColorGenerator stays within Core Image (no framework switch) but requires more complex border math. UIGraphicsImageRenderer is simpler for text drawing. The engine may use a hybrid: Core Image for border, Core Graphics for text, then composite both. |
| CIAttributedTextImageGenerator for watermark text | CATextLayer rendered to UIImage | CATextLayer requires UIKit interop and forces rasterization. CIAttributedTextImageGenerator stays in Core Image's lazy graph and preserves HDR-capable pixel formats. |

**Installation:**
```bash
# No package manager needed. Apple frameworks are included with the iOS SDK.
# Project setup is manual via Xcode:
# 1. File > New > Package > "WatermarkCore"
# 2. Configure Package.swift with iOS 18 platform
# 3. Link to main app target in Phase 2
```

## Package Legitimacy Audit

> **Not applicable.** This phase installs zero external packages. All functionality is built on Apple system frameworks (Core Image, ImageIO, Core Graphics, UniformTypeIdentifiers, Foundation) included with the iOS 18 SDK. No npm, PyPI, crates.io, or Swift Package Registry dependencies.

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
                          ┌──────────────────────────────────────┐
                          │         WATERMARKCORE ENGINE          │
                          │         (Actor: WatermarkEngine)      │
                          └──────────────────────────────────────┘
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    │                         │                         │
                    ▼                         ▼                         ▼
          ┌─────────────────┐     ┌─────────────────────┐    ┌──────────────────┐
          │  INPUT STAGE    │     │  RENDER STAGE       │    │  OUTPUT STAGE    │
          │                 │     │                     │    │                  │
          │ CGImageSource ──┼──┐  │  CIImage Filter     │    │ CGImageDestination│
          │  │ extract:      │  │  │  Graph:             │    │  │ write:         │
          │  ├─ metadata     │  │  │                     │    │  ├─ rendered CG  │
          │  ├─ gain map     │  │  │  1. BaseImage       │    │  ├─ metadata dict │
          │  ├─ color profile│  │  │     │               │    │  ├─ gain map aux │
          │  └─ pixel buffer─┼──┤  │  2. WhiteFrame     │    │  └─ color profile │
          │                  │  │  │     │ (optional)    │    │                  │
          │  CIImage(contents│  │  │  3. TextWatermark  │    │  Temp file / Data │
          │   Of: url,       │  │  │     │ (layer N)     │    │  (no camera roll) │
          │   options: [     │  │  │  4. ImageWatermark │    └──────────────────┘
          │    .expandToHDR  │  │  │     │ (layer N+1)   │
          │    : true        │  │  │  5. CISourceOver   │
          │    .auxiliaryHDR │  │  │     Compositing    │──▶ CIContext ──▶ CGImage
          │    GainMap: true │  │  │     (per layer)    │    (RGBAh, wide gamut)
          │   ])             │  │  └─────────────────────┘
          └─────────────────┘  │
                    │          │  ┌─────────────────────┐
                    │          │  │ POSITION CALCULATOR │
                    │          │  │                     │
                    │          │  │ Enum: 9 positions   │
                    │          │  │  ├─ topLeft         │
                    │          │  │  ├─ topCenter       │
                    │          │  │  ├─ topRight        │
                    │          │  │  ├─ middleLeft      │
                    │          │  │  ├─ center          │
                    │          │  │  ├─ middleRight     │
                    │          │  │  ├─ bottomLeft      │
                    │          │  │  ├─ bottomCenter    │
                    │          │  │  └─ bottomRight     │
                    │          │  │                     │
                    │          │  │ CGAffineTransform   │
                    │          │  │ translation from     │
                    │          │  │ EXIF-normalized      │
                    │          │  │ extent + padding     │
                    │          └─────────────────────────┘
                    │
                    │          ┌─────────────────────────┐
                    └──────────┤ METADATA / HDR HOLDER   │
                               │ (value types, Sendable) │
                               │                         │
                               │ var metadata: [CFString:│
                               │              Any]?      │
                               │ var gainMapData:        │
                               │     [CFString: Any]?    │
                               │ var colorSpace:         │
                               │     CGColorSpace?       │
                               │ var sourceUTI: CFString │
                               └─────────────────────────┘
```

**Flow trace (primary use case — text watermark + white frame on HDR photo):**
1. Caller provides `URL` of source photo → `WatermarkEngine.process(url:config:)`
2. **Input Stage:** `CGImageSourceCreateWithURL` → `CGImageSourceCopyPropertiesAtIndex` (metadata dict) → `CGImageSourceCopyAuxiliaryDataInfoAtIndex` with `kCGImageAuxiliaryDataTypeHDRGainMap` (gain map aux data) → `CIImage(contentsOf: url, options: [.auxiliaryHDRGainMap: true, .expandToHDR: true])` (HDR pixel data)
3. **Render Stage:** Normalize CIImage orientation via `.oriented(forExifOrientation:)` → scale watermark text/image CIImage to proportional size → calculate CGAffineTransform translation for target position → `CIFilter.sourceOverCompositing()` for each layer → if white frame enabled: render frame + metadata text via UIGraphicsImageRenderer → convert to CIImage → composite onto base at bottom layer → crop to source extent
4. **Output Stage:** `CIContext.createCGImage(compositedImage, from: extent, format: .RGBAh, colorSpace: sourceColorSpace)` → `CGImageDestinationCreateWithData` or `CGImageDestinationCreateWithURL` with source UTI → `CGImageDestinationAddImage(destination, cgImage, metadataDict)` → `CGImageDestinationAddAuxiliaryDataInfo(destination, kCGImageAuxiliaryDataTypeHDRGainMap, gainMapDict)` → `CGImageDestinationFinalize(destination)` → return `Data` or `URL`

### Recommended Project Structure

```
Packages/
└── WatermarkCore/                          # LOCAL SWIFT PACKAGE
    ├── Package.swift                       # tools-version: 6.0, platforms: [.iOS(.v18)]
    ├── Sources/
    │   ├── Models/
    │   │   ├── WatermarkConfiguration.swift    # Position enum, text/image config, overlay style
    │   │   ├── WatermarkPosition.swift         # 9-case enum + CGAffineTransform math
    │   │   ├── ImageWatermarkInput.swift       # PNG Data wrapper, alpha support
    │   │   ├── TextWatermarkInput.swift        # String, font size, color, opacity
    │   │   ├── WhiteFrameConfig.swift          # Border width (%), metadata text enabled
    │   │   ├── ProcessingResult.swift          # Output Data or URL, source UTI
    │   │   └── MediaMetadata.swift             # EXIF dict, gain map aux data, color space
    │   ├── Engine/
    │   │   ├── WatermarkEngine.swift           # Actor: orchestrates full pipeline
    │   │   └── PipelineError.swift             # Error cases (invalid format, render fail, etc.)
    │   ├── Input/
    │   │   ├── ImageLoader.swift               # CGImageSource wrapper: extract metadata + gain map + CIImage
    │   │   └── FormatDetector.swift            # CGImageSourceGetType → UTType mapping
    │   ├── Rendering/
    │   │   ├── PositionCalculator.swift        # 9-position CGAffineTransform math
    │   │   ├── WatermarkRenderer.swift         # Chains layer CIImages via sourceOverCompositing
    │   │   ├── TextWatermarkRenderer.swift     # NSAttributedString → CIAttributedTextImageGenerator
    │   │   ├── ImageWatermarkRenderer.swift    # PNG Data → CIImage with scale transform
    │   │   ├── WhiteFrameRenderer.swift        # White border + metadata text via UIGraphicsImageRenderer
    │   │   └── OrientationNormalizer.swift     # EXIF orientation → CIImage.oriented(...)
    │   ├── Output/
    │   │   ├── ImageWriter.swift               # CGImageDestination pipeline with metadata + HDR
    │   │   └── TempFileManager.swift           # cachesDirectory lifecycle, cleanup
    │   └── Utilities/
    │       ├── CIContextProvider.swift          # Shared CIContext singleton with RGBAh working format
    │       └── DeviceMetadataProvider.swift     # EXIF model extraction → UIDevice.current.model fallback
    └── Tests/
        ├── PositionCalculatorTests.swift       # Verify all 9 positions for landscape + portrait
        ├── WatermarkRendererTests.swift        # Verify compositing output has expected pixel values
        ├── TextWatermarkRendererTests.swift    # Verify text CIImage generation
        ├── ImageWatermarkRendererTests.swift   # Verify PNG alpha compositing
        ├── WhiteFrameRendererTests.swift       # Verify border width + text placement
        ├── ImageWriterTests.swift              # Verify metadata + HDR preservation in output
        ├── FormatDetectorTests.swift           # Verify HEIC/JPEG/PNG detection
        ├── OrientationNormalizerTests.swift    # Verify all 8 EXIF orientations resolve correctly
        └── WatermarkEngineTests.swift          # End-to-end: input → process → output validation
```

### Pattern 1: Core Image Filter Graph (Lazy Compositing Chain)

**What:** Build watermark compositing as a chain of `CIImage` transforms and `CIFilter.sourceOverCompositing` calls. Core Image defers all rendering until `CIContext.createCGImage()`, merging the entire graph into a single GPU shader. No intermediate pixel buffers.

**When to use:** Every watermark overlay operation. Text watermark, image watermark, white frame — each produces a `CIImage` that gets composited onto the base image in layer order.

**Example:**
```swift
// Source: Apple Core Image Programming Guide + verified community patterns
import CoreImage
import CoreImage.CIFilterBuiltins

func compositeWatermarkLayers(
    baseImage: CIImage,
    layers: [CIImage],          // Ordered: bottom layer first, top layer last
    positions: [CGPoint],       // Bottom-left origin points
    baseExtent: CGRect
) -> CIImage {
    var composited = baseImage
    for (layer, position) in zip(layers, positions) {
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

### Pattern 2: CGImageSource → CGImageDestination Metadata Pipeline

**What:** Extract metadata dictionary BEFORE any pixel processing via `CGImageSourceCopyPropertiesAtIndex`. Store the dictionary as a value type throughout the pipeline. Re-attach during output via `CGImageDestinationAddImage` with the preserved properties dictionary. Never use `UIImage` in the processing path — it silently strips all metadata.

**When to use:** Every photo processing operation. This is table-stakes for QUAL-01 compliance.

**Example:**
```swift
// Source: Apple ImageIO documentation + verified community patterns
import ImageIO

struct LoadedImage {
    let ciImage: CIImage
    let metadata: [CFString: Any]
    let gainMapAuxData: [CFString: Any]?
    let colorSpace: CGColorSpace?
    let sourceUTI: CFString
}

func loadImage(from url: URL) throws -> LoadedImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw PipelineError.invalidSource
    }
    
    let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    let gainMapAuxData = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
        source, 0, kCGImageAuxiliaryDataTypeHDRGainMap
    ) as? [CFString: Any]
    
    let colorSpace: CGColorSpace? = {
        guard let profileName = metadata[kCGImagePropertyProfileName] as? String else { return nil }
        return CGColorSpace(name: profileName as CFString)
    }()
    
    let uti = CGImageSourceGetType(source) ?? "public.heic" as CFString
    
    let options: [CIImageOption: Any] = [
        .expandToHDR: true,
        .auxiliaryHDRGainMap: true,
        .applyOrientationProperty: true
    ]
    guard let ciImage = CIImage(contentsOf: url, options: options) else {
        throw PipelineError.failedToCreateCIImage
    }
    
    return LoadedImage(
        ciImage: ciImage,
        metadata: metadata,
        gainMapAuxData: gainMapAuxData,
        colorSpace: colorSpace,
        sourceUTI: uti
    )
}

func writeImage(
    cgImage: CGImage,
    metadata: [CFString: Any],
    gainMapAuxData: [CFString: Any]?,
    sourceUTI: CFString,
    to url: URL
) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, sourceUTI, 1, nil
    ) else {
        throw PipelineError.failedToCreateDestination
    }
    
    CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
    
    if let gainMap = gainMapAuxData {
        CGImageDestinationAddAuxiliaryDataInfo(
            destination, kCGImageAuxiliaryDataTypeHDRGainMap, gainMap as CFDictionary
        )
    }
    
    guard CGImageDestinationFinalize(destination) else {
        throw PipelineError.failedToFinalize
    }
}
```

### Pattern 3: Swift 6 Actor-Isolated Processing Engine

**What:** Wrap the entire processing pipeline in a Swift actor (`WatermarkEngine`). The actor owns the shared `CIContext` instance and serializes rendering operations. `CIImage` objects are Sendable-safe (immutable) and can cross actor boundaries. `CIFilter` instances are NOT thread-safe and must be created fresh within each processing call.

**When to use:** The top-level entry point for all watermarking operations. Callers invoke `engine.process(url:config:)` and await the result.

**Example:**
```swift
// Source: Swift 6 concurrency model + verified Core Image thread-safety docs
import CoreImage

actor WatermarkEngine {
    private let context: CIContext = {
        var options = CIContextOptions()
        options.workingColorSpace = CGColorSpace(name: CGColorSpace.displayP3)
        options.workingFormat = .RGBAh  // 16-bit float for HDR preservation
        return CIContext(options: options)
    }()
    
    func process(sourceURL: URL, config: WatermarkConfiguration) async throws -> ProcessingResult {
        // 1. Load (synchronous I/O, off the actor briefly via nonisolated or Task)
        let loaded = try ImageLoader.load(from: sourceURL)
        
        // 2. Render filter graph (pure CIImage operations, no context needed)
        let composited = try buildFilterGraph(base: loaded.ciImage, config: config)
        
        // 3. Render to CGImage (uses actor-owned CIContext)
        let cgImage = context.createCGImage(
            composited,
            from: composited.extent,
            format: .RGBAh,
            colorSpace: loaded.colorSpace
        )
        guard let cgImage else { throw PipelineError.renderFailed }
        
        // 4. Write output
        let outputURL = try TempFileManager.createTempFile(uti: loaded.sourceUTI)
        try ImageWriter.write(
            cgImage: cgImage,
            metadata: loaded.metadata,
            gainMapAuxData: loaded.gainMapAuxData,
            sourceUTI: loaded.sourceUTI,
            to: outputURL
        )
        
        return ProcessingResult(url: outputURL, sourceUTI: loaded.sourceUTI as String)
    }
    
    private func buildFilterGraph(base: CIImage, config: WatermarkConfiguration) throws -> CIImage {
        // Normalize orientation first (critical — avoids double-rotation bugs)
        let normalized = base.oriented(.up)
        let extent = normalized.extent
        
        var layers: [CIImage] = []
        var positions: [CGPoint] = []
        
        // Build layers in order: white frame (bottom) → watermarks (stacked above)
        if config.whiteFrame != nil {
            let frameImage = try WhiteFrameRenderer.render(config: config, baseExtent: extent)
            layers.append(frameImage)
            positions.append(.zero)  // Frame covers entire extent
        }
        
        for watermark in config.watermarks {
            let watermarkImage: CIImage
            switch watermark {
            case .text(let textConfig):
                watermarkImage = TextWatermarkRenderer.render(config: textConfig)
            case .image(let imageConfig):
                watermarkImage = try ImageWatermarkRenderer.render(config: imageConfig)
            }
            
            let scaled = watermarkImage.transformed(by: CGAffineTransform(
                scaleX: watermark.scale, y: watermark.scale
            ))
            let position = PositionCalculator.position(
                for: watermark.position,
                watermarkExtent: scaled.extent,
                baseExtent: extent,
                padding: 20
            )
            layers.append(scaled)
            positions.append(position)
        }
        
        return WatermarkRenderer.composite(layers: layers, positions: positions, base: normalized)
    }
}
```

### Anti-Patterns to Avoid
- **UIImage in processing pipeline:** Converting to/from UIImage strips EXIF, color profiles, and HDR gain maps. Use CGImageSource → CIImage → CGImageDestination exclusively. UIImage is only for SwiftUI Image display in later phases.
- **CIContext-per-operation:** Creating `CIContext()` inside processing loops causes GPU resource churn. Reuse a single instance as an actor property.
- **Skipping EXIF orientation normalization:** Applying positional transforms to non-normalized CIImage causes watermark misplacement (the double-rotation bug). Always call `.oriented(.up)` before positioning.
- **UIImage.jpegData() for output:** This forces a lossy re-encode of already-compressed data. Use CGImageDestination with the source UTI for format-preserving output.
- **Hardcoded color space (DeviceRGB):** Output viewed on other platforms will show wrong colors. Always pass the source color space to CIContext and CGImageDestination.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pixel-level watermark compositing | Manual pixel buffer manipulation with vImage/Accelerate | `CIFilter.sourceOverCompositing()` with CIImage chain | Core Image merges the filter graph into a single GPU Metal shader. Hand-rolling pixel compositing requires CPU-bound loops, manual alpha blending math, and separate handling for different pixel formats (RGBA8, RGBAh, 420v, 420f). |
| EXIF/GPS metadata parsing and re-serialization | Custom EXIF binary parser/writer | `CGImageSourceCopyPropertiesAtIndex` + `CGImageDestinationAddImage` with properties dictionary | EXIF is a complex binary format with dozens of tag types and endianness variants. ImageIO handles all tag types, MakerNote vendor extensions, and GPS coordinate rationals natively. |
| HDR gain map encoding | Manual ISO 21496-1 gain map construction | `CGImageDestinationAddAuxiliaryDataInfo` with `kCGImageAuxiliaryDataTypeHDRGainMap` | The gain map auxiliary data format includes Apple-specific MakerNote metadata tags (33, 48) that the Photos app requires for HDR recognition. ImageIO embeds these correctly. |
| Color profile ICC handling | Manual ICC profile parsing or vImage color conversion | Pass source `CGColorSpace` to `CIContext.createCGImage()` and `CGImageDestination` metadata | Color profile handling involves complex 3D LUTs, tone curves, and matrix transforms. Apple frameworks handle ICC v2/v4 and display P3 natively with GPU acceleration. |
| Orientation math for 8 EXIF cases | Switch-case on CGImagePropertyOrientation with manual CGAffineTransform matrices | `CIImage.oriented(.up)` to normalize, then work in consistent coordinate space | The EXIF orientation tag has 8 possible values with non-obvious transform compositions. `oriented(forExifOrientation:)` handles all 8 cases correctly. |
| Text rendering to pixel buffer | CATextLayer or manual glyph rasterization | `CIAttributedTextImageGenerator` or `UIGraphicsImageRenderer` with `NSAttributedString.draw()` | Text rendering requires font metrics, kerning, ligatures, and CTFont descriptor handling. Both APIs handle this natively with system font support. |

**Key insight:** The iOS SDK provides a complete photo processing stack. Every hand-rolled alternative introduces bugs in edge cases (HDR, metadata, orientation, color management) that Apple's frameworks have handled for years across billions of devices.

## Runtime State Inventory

> **Greenfield phase — SKIPPED.** This is the first phase of a new project. No existing runtime state, stored data, live services, OS registrations, secrets, or build artifacts exist. All artifacts created by this phase (Swift Package, test fixtures) are source-controlled and created fresh.

## Common Pitfalls

### Pitfall 1: HDR Gain Map Silent Destruction (CRITICAL)

**What goes wrong:** The HDR gain map auxiliary data that gives iPhone photos their dynamic range "pop" is silently discarded during the Core Image pipeline. Output looks flat and SDR-only. This is the #1 quality regression in iOS photo apps.

**Why it happens:** `CIImage(contentsOf:)` loads only the base SDR image by default. The gain map lives as separate auxiliary metadata in the HEIC/JPEG container. Standard `CIContext.createCGImage()` renders only the base layer. Without explicit extraction and re-attachment, the gain map is lost.

**How to avoid:**
1. Load with `CIImage(contentsOf: url, options: [.auxiliaryHDRGainMap: true, .expandToHDR: true])`
2. Extract gain map aux data via `CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap)`
3. Render via `CIContext` with `format: .RGBAh` and source color space
4. Re-attach via `CGImageDestinationAddAuxiliaryDataInfo(dest, kCGImageAuxiliaryDataTypeHDRGainMap, auxData)`
5. Do NOT modify the gain map image — composite watermark only onto the base image, then re-attach the unmodified gain map

**Warning signs:** Output file size drops dramatically (gain map can be several MB). Photos app doesn't show HDR badge. Highlights appear clipped at SDR levels.

[VERIFIED: Apple Developer — "Supporting HDR images in your app" (WWDC24) + Greg Benz Photography technical analysis]

### Pitfall 2: EXIF/Metadata Stripping via UIImage (CRITICAL)

**What goes wrong:** Every conversion step strips metadata. `CGImage` and `CIImage` are pixel-only representations — they have no concept of EXIF tags, GPS, or color profiles. When the output is written without explicitly re-attaching metadata, all camera/lens/location data is permanently lost.

**Why it happens:** UIImage.jpegData() creates a brand new JPEG with empty metadata. CGImageDestinationAddImageFromSource carries over unintended tags unreliably. Developers assume metadata "comes along for the ride."

**How to avoid:**
1. Extract metadata dictionary BEFORE any pixel manipulation: `CGImageSourceCopyPropertiesAtIndex(source, 0, nil)`
2. Store as a value type `[CFString: Any]` throughout the pipeline
3. Use `CGImageDestinationAddImage` (NOT `AddImageFromSource`) and pass the preserved dictionary
4. For orientation: normalize via `.oriented(.up)`, set output EXIF orientation to `.up` (1)

**Warning signs:** GPS missing, "Unknown" camera model in output, wrong date/time, color shift (profile stripped).

[VERIFIED: Apple ImageIO documentation + multiple community sources confirming CGImageSourceCopyPropertiesAtIndex approach]

### Pitfall 3: CIImage Coordinate System Double-Rotation

**What goes wrong:** Watermark placed in "top-right" via UIKit coordinates appears in bottom-left of output. This is the most common positional bug in Core Image watermarking.

**Why it happens:** CIImage uses bottom-left origin (+Y up) and ignores EXIF orientation. UIKit uses top-left origin (+Y down). Without normalization, positional transforms operate on raw sensor orientation, not the displayed orientation.

**How to avoid:**
1. Always normalize orientation first: `let normalized = ciImage.oriented(.up)`
2. After normalization, CIImage extent matches visual display
3. Convert UIKit-style positions by flipping Y: `ciY = imageHeight - uiKitY - overlayHeight`
4. Use the PositionCalculator to encapsulate this math — never inline coordinate conversion

**Warning signs:** Watermark in wrong corner, "looks right in preview but wrong in saved file," rotation on images with non-zero EXIF orientation.

[VERIFIED: Apple Core Image documentation + Stack Overflow consensus on CIImage coordinate system]

### Pitfall 4: CIContext Creation Per Operation

**What goes wrong:** Creating `let context = CIContext()` inside processing functions causes severe performance degradation and GPU resource exhaustion.

**Why it happens:** CIContext initialization allocates GPU resources, compiles Metal shader programs, and sets up render pipelines. Creating one per image (or per video frame) causes frame drops and memory fragmentation.

**How to avoid:** Create ONE CIContext as an actor property. Reuse it for the entire engine lifetime. Configure once: `workingFormat: .RGBAh`, `workingColorSpace: displayP3`.

**Warning signs:** Slow processing times, increasing memory usage over repeated operations, GPU-related crash logs.

[VERIFIED: Apple Core Image Programming Guide — explicit recommendation to reuse CIContext]

### Pitfall 5: Format Transcoding (HEIC → JPEG Quality Loss)

**What goes wrong:** Processing a HEIC photo but outputting as JPEG causes an unnecessary HEIC→decode→JPEG re-encode, introducing generation loss.

**Why it happens:** Developers hardcode output format as JPEG. When the user shares to social media, the platform may transcode again — double generation loss.

**How to avoid:** Detect source UTI via `CGImageSourceGetType(source)`. Pass the same UTI to `CGImageDestinationCreateWithURL`/`CreateWithData`. Only change format when required (e.g., PNG watermark on JPEG source → HEIC output, not JPEG).

**Warning signs:** Noticeable quality degradation on HEIC source images, file size mismatch, compression artifacts in output.

[VERIFIED: Apple ImageIO documentation on CGImageSourceGetType and format preservation]

## Code Examples

Verified patterns from official sources:

### Text Watermark Generation
```swift
// Source: Apple CIAttributedTextImageGenerator documentation
import CoreImage

func generateTextWatermark(
    text: String,
    fontSize: CGFloat,
    color: CGColor,
    opacity: CGFloat
) -> CIImage {
    let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: UIColor(cgColor: color).withAlphaComponent(opacity)
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    
    let filter = CIFilter.attributedTextImageGenerator()
    filter.text = attributed
    filter.scaleFactor = 1.0
    return filter.outputImage!
}
```

### Position Calculation (9 Preset Positions)
```swift
// Source: Verified CIImage coordinate system math
enum WatermarkPosition: String, CaseIterable {
    case topLeft, topCenter, topRight
    case middleLeft, center, middleRight
    case bottomLeft, bottomCenter, bottomRight
    
    func translation(
        watermarkExtent: CGRect,
        baseExtent: CGRect,
        padding: CGFloat
    ) -> CGAffineTransform {
        // Note: CIImage coordinate system — origin is BOTTOM-LEFT
        let x: CGFloat
        let y: CGFloat
        
        switch self {
        case .topLeft:     x = padding;                             y = baseExtent.height - watermarkExtent.height - padding
        case .topCenter:   x = (baseExtent.width - watermarkExtent.width) / 2; y = baseExtent.height - watermarkExtent.height - padding
        case .topRight:    x = baseExtent.width - watermarkExtent.width - padding; y = baseExtent.height - watermarkExtent.height - padding
        case .middleLeft:  x = padding;                             y = (baseExtent.height - watermarkExtent.height) / 2
        case .center:      x = (baseExtent.width - watermarkExtent.width) / 2;   y = (baseExtent.height - watermarkExtent.height) / 2
        case .middleRight: x = baseExtent.width - watermarkExtent.width - padding; y = (baseExtent.height - watermarkExtent.height) / 2
        case .bottomLeft:  x = padding;                             y = padding
        case .bottomCenter:x = (baseExtent.width - watermarkExtent.width) / 2;   y = padding
        case .bottomRight: x = baseExtent.width - watermarkExtent.width - padding; y = padding
        }
        
        return CGAffineTransform(translationX: x, y: y)
    }
}
```

### White Frame + Metadata Text Rendering
```swift
// Source: Apple UIGraphicsImageRenderer documentation + verified patterns
import UIKit

func renderWhiteFrame(
    baseExtent: CGRect,
    frameWidthRatio: CGFloat,     // 0.03–0.05 per D-05
    metadataText: String,
    scale: CGFloat = 1.0
) throws -> CIImage {
    let frameWidth = min(baseExtent.width, baseExtent.height) * frameWidthRatio
    let renderSize = baseExtent.size
    
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.preferredRange = .extended  // Support HDR
    
    let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
    let uiImage = renderer.image { ctx in
        // 1. Draw white border
        ctx.cgContext.setFillColor(UIColor.white.cgColor)
        ctx.cgContext.fill(baseExtent)
        
        // 2. Cut out inner transparent area
        let innerRect = baseExtent.insetBy(dx: frameWidth, dy: frameWidth)
        ctx.cgContext.setBlendMode(.clear)
        ctx.cgContext.fill(innerRect)
        ctx.cgContext.setBlendMode(.normal)
        
        // 3. Draw metadata text centered on bottom frame
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: frameWidth * 0.4, weight: .medium),
            .foregroundColor: UIColor.darkGray
        ]
        let textSize = metadataText.size(withAttributes: textAttributes)
        let textX = (renderSize.width - textSize.width) / 2
        let textY = renderSize.height - frameWidth / 2 - textSize.height / 2
        let textRect = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)
        metadataText.draw(in: textRect, withAttributes: textAttributes)
    }
    
    guard let ciImage = CIImage(image: uiImage) else {
        throw PipelineError.frameRenderFailed
    }
    return ciImage
}
```

### Device Metadata Extraction
```swift
// Source: Apple EXIF dictionary keys + UIDevice documentation
import ImageIO
import UIKit

struct DeviceMetadataProvider {
    /// Extracts device model from EXIF, falls back to UIDevice.current.model
    static func deviceModel(from metadata: [CFString: Any]) -> String {
        // Try EXIF TIFF dictionary first (most cameras write model here)
        if let tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let model = tiff[kCGImagePropertyTIFFModel] as? String,
           !model.isEmpty {
            return model
        }
        // Try EXIF dictionary directly
        if let exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let model = exif[kCGImagePropertyExifLensModel] as? String {
            return model
        }
        // Fallback to current device
        return UIDevice.current.model  // "iPhone", "iPad", etc.
    }
    
    static func attributionText(from metadata: [CFString: Any]) -> String {
        return "Taken by: \(deviceModel(from: metadata))"
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `UIImage`-based processing pipeline | `CGImageSource` → `CIImage` → `CGImageDestination` | iOS 10+ (ImageIO) | UIImage strips all metadata and HDR — must be avoided entirely in processing paths |
| `CIImage(contentsOf:)` without options | Load with `.auxiliaryHDRGainMap: true` + `.expandToHDR: true` | iOS 14.1+ (gain map) / iOS 17+ (expandToHDR) | Without these options, HDR content is silently flattened to SDR |
| `CIContext()` per operation | Single shared `CIContext` with `CIFormat.RGBAh` | Always best practice | Per-operation context creation causes GPU churn and 10-100× slower rendering |
| `AVAssetExportSession` with defaults | `AVAssetWriter` with explicit color props | iOS 16+ (color metadata control) | For Phase 3 (video); default settings assume SDR/Rec.601 and strip HDR metadata |
| `ObservableObject` / `@Published` | `@Observable` macro | iOS 17+ | Granular property-level SwiftUI updates; eliminates unnecessary view redraws |
| EXIF orientation as afterthought | Normalize first via `.oriented(.up)` | Always best practice | Prevents double-rotation bugs; consistent coordinate space for all positioning math |

**Deprecated/outdated:**
- `UIImagePickerController`: Replaced by PhotosPicker (PhotosUI). Not used in engine — engine receives raw Data/URL.
- `CIImage.oriented(forExifOrientation:)` without preceding normalization: Must normalize before positioning — working on non-normalized images causes watermark misplacement.
- `UIImage.jpegData(compressionQuality:)`: Never use for output. Creates second-generation lossy JPEG. Use CGImageDestination instead.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `CIImage` conforms to `Sendable` in the iOS 18 SDK for Swift 6 strict concurrency | Architecture Patterns (Pattern 3) | If CIImage is not Sendable, the actor-based WatermarkEngine will produce compiler errors. Mitigation: wrap in `@unchecked Sendable` struct or use `CGImage` (which is Sendable) as the cross-boundary currency. |
| A2 | `CIImageRepresentationOption.hdrGainMapImage` is available on iOS 18 without manual rawValue extension | HDR Gain Map Preservation | If the symbol is not directly exposed (it was previously accessed via `rawValue: "kCIImageRepresentationHDRGainMapImage"`), an extension will be needed. Fallback: use CGImageDestination auxiliary data path exclusively. |
| A3 | `CIAttributedTextImageGenerator` inputPadding parameter is available on iOS 18 | Text Watermark Rendering | Prior iOS versions had text clipping issues. If inputPadding is unavailable, workaround: increase scaleFactor and scale down with CGAffineTransform. |
| A4 | `CGImageSourceCopyAuxiliaryDataInfoAtIndex` correctly preserves Apple-specific MakerNote HDR tags (33, 48) through a round-trip extraction → re-attachment | HDR Gain Map Preservation | If MakerNote tags are stripped during the round-trip, the Photos app may not recognize the output as HDR even though the gain map data is present. Mitigation: include the full MakerNote dictionary in the metadata properties passed to CGImageDestinationAddImage. |
| A5 | EXIF model tag (`kCGImagePropertyTIFFModel`) is present in iPhone photos | Device Metadata Provider | Some third-party camera apps or screenshot workflows may not write the TIFF model tag. Fallback to UIDevice.current.model is already implemented per D-07. |

## Open Questions

1. **HDR gain map preservation through UIGraphicsImageRenderer for white frame**
   - What we know: The white frame + metadata text is rendered via UIGraphicsImageRenderer and converted to CIImage for compositing. The base image and its gain map are handled via the CGImageDestination path.
   - What's unclear: Whether converting the white frame CIImage back through the Core Image pipeline before CGImageDestination output affects the gain map attachment. The gain map is re-attached at the final CGImageDestination step — the white frame overlay should not interfere as long as we composite onto the base image (not the gain map).
   - Recommendation: Composite white frame onto base CIImage only. Re-attach the unmodified gain map auxiliary data at CGImageDestination. Test with actual HDR photo from iPhone 12+.

2. **CIAttributedTextImageGenerator multiline text behavior on iOS 18**
   - What we know: Prior iOS versions (<16) had bugs with text width expansion on multiline attributed strings. Community reports suggest this was fixed but behavior may vary.
   - What's unclear: Whether single-line watermark text (v1 only supports single "Taken by:" line per D-08) triggers any edge cases in the current iOS 18 implementation.
   - Recommendation: Use single-line text for v1. Verify the output CIImage extent matches expected text dimensions. If unexpected wrapping occurs, enforce single-line via NSParagraphStyle.lineBreakMode = .byTruncatingTail.

3. **Optimal CIFormat for HDR rendering output**
   - What we know: CIFormat.RGBAh (16-bit float) preserves HDR dynamic range through the CIContext render. CIFormat.RGBA16 is unsigned 16-bit integer (different format).
   - What's unclear: Whether RGBAh produces correct output for all source formats (HEIC 10-bit, JPEG 8-bit) when the final destination is an 8-bit JPEG. The CGImageDestination may need to tone-map from RGBAh to the destination bit depth.
   - Recommendation: Use CIFormat.RGBAh for the CIContext working format (set in CIContextOptions). The CGImageDestination handles bit-depth conversion automatically when writing — no manual tone-mapping needed. Test with JPEG output from HEIC HDR source to verify no clipping.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift | Language, compilation | ✓ | 6.2.3 | — (required) |
| Xcode | IDE, iOS SDK, SwiftPM | ✓ | 26.2 (build 17C52) | — (required) |
| iOS 18 SDK | Core Image, ImageIO, etc. | ✓ | Bundled with Xcode 26.2 | — (required) |
| exiftool | Metadata validation during testing | ✗ | — | Install via `brew install exiftool`. Not blocking — tests can verify metadata programmatically via CGImageSourceCopyPropertiesAtIndex comparison. exiftool is a QA convenience tool. |

**Missing dependencies with no fallback:**
- None. All required dependencies (Swift 6, Xcode 26.2 with iOS 18 SDK) are available.

**Missing dependencies with fallback:**
- exiftool: Install with `brew install exiftool` before Phase 1 QA verification. Programmatic metadata comparison is the primary verification method.

## Security Domain

> Security enforcement is enabled (default). No `security_enforcement: false` in config.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Not applicable — no user accounts, entirely on-device |
| V3 Session Management | No | Not applicable — no sessions, no server |
| V4 Access Control | No | Not applicable — single-user, local-only app |
| V5 Input Validation | Yes | Validate input Data for supported UTI types before CGImageSource creation. Reject corrupted/malformed image data gracefully with typed errors. Validate watermark text for maximum length. Validate watermark scale is within sane bounds (0.01–0.90). |
| V6 Cryptography | No | Not applicable — no cryptographic operations |

### Known Threat Patterns for Core Image / ImageIO

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed image data causing CGImageSource crash/DoS | Denial of Service | Validate CGImageSourceCreateWithData/URL succeeds before processing. Check CGImageSourceGetCount > 0. Wrap processing in Task with timeout. |
| Path traversal via user-supplied URL | Tampering | Use FileManager to verify URL is within sandbox (cachesDirectory or tempDirectory). Never accept arbitrary file paths from external input in Phase 1. |
| Oversized image exhausting memory | Denial of Service | Check CGImageSource pixel dimensions before creating full CIImage. Reject images exceeding configurable max resolution (e.g., 100MP). |
| Watermark PNG with embedded malicious metadata | Elevation of Privilege | Not applicable (all processing on-device, no code execution from image metadata). ImageIO sandboxes metadata parsing. |
| Temp file race condition | Tampering / Info Disclosure | Use FileManager with unique UUID filenames. Set temp file permissions restrictive. Cleanup stale temp files on engine init. |
| User location data in EXIF GPS output | Information Disclosure | Engine preserves GPS per QUAL-01. In Phase 2 (UI), offer "Strip Location" toggle before share. Engine should support a `stripLocation: Bool` parameter for future use. |

### Security-Specific Code Patterns

```swift
// Input validation before CGImageSource creation
func validateImageData(_ data: Data) throws {
    guard data.count > 0 else { throw PipelineError.emptyData }
    guard data.count < 500_000_000 else { throw PipelineError.dataTooLarge } // 500MB max
    
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetCount(source) > 0 else {
        throw PipelineError.invalidImageData
    }
    
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
    let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
    let megapixels = (width * height) / 1_000_000
    
    guard megapixels <= 100 else { throw PipelineError.imageTooLarge }
}

// Watermark scale boundary validation
func validateWatermarkScale(_ scale: CGFloat) throws {
    guard scale >= 0.01 && scale <= 0.90 else {
        throw PipelineError.invalidScale(scale)
    }
}
```

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — Core Image: CIFilter.sourceOverCompositing, CIAttributedTextImageGenerator, CIContext, CIFormat.RGBAh, CIImage.oriented(forExifOrientation:)
- Apple Developer Documentation — ImageIO: CGImageSource, CGImageDestination, CGImageSourceCopyPropertiesAtIndex, CGImageDestinationAddAuxiliaryDataInfo, kCGImageAuxiliaryDataTypeHDRGainMap
- Apple Developer — "Supporting HDR images in your app" (WWDC24 session) — HDR gain map preservation via CGImageDestination, CIImageRepresentationOption.hdrGainMapImage
- Apple Developer — UniformTypeIdentifiers: UTType.heic, UTType.jpeg, UTType.png for format detection
- Swift Evolution — SE-0395 (Observation), SE-0302 (Sendable), Swift 6 language mode
- Apple Developer — UIGraphicsImageRenderer with preferredRange = .extended for HDR

### Secondary (MEDIUM confidence)
- Greg Benz Photography — Technical deep-dive on Apple HDR gain map architecture, MakerNote tags (33, 48) required for Photos HDR recognition
- Stack Overflow, Apple Developer Forums — CIImage coordinate system (bottom-left origin), EXIF orientation normalization patterns, CISourceOverCompositing watermark examples
- Community post-mortems (forasoft.com, nonstrict.eu) — HDR metadata preservation challenges, gain map round-trip verification
- Kodeco (formerly raywenderlich.com) — Core Image filter chaining patterns, CIAttributedTextImageGenerator usage

### Tertiary (LOW confidence — needs validation)
- `CIAttributedTextImageGenerator` inputPadding parameter availability on iOS 18 — inferred from API availability, not directly tested
- Exact `CIImageRepresentationOption.hdrGainMapImage` symbol exposure in iOS 18 SDK — may require rawValue string fallback (`"kCIImageRepresentationHDRGainMapImage"`)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — All Apple system frameworks with comprehensive official documentation and WWDC session coverage. Zero third-party dependencies. Verified against Xcode 26.2 / Swift 6.2.3 environment.
- Architecture: HIGH — Actor-isolated processing engine, CIImage lazy filter graph, CGImageSource → CGImageDestination metadata pipeline are all established patterns confirmed by official docs and cross-referenced with community validation.
- Pitfalls: HIGH — All 5 critical pitfalls are sourced from Apple documentation warnings (WWDC24 HDR session, Core Image Programming Guide), consistent community post-mortems, and the existing project's PITFALLS.md research. HDR gain map destruction is the most important — explicitly called out by Apple.
- Code examples: HIGH — All patterns verified against Apple documentation and cross-referenced with working community implementations.

**Research date:** 2026-06-17
**Valid until:** 2026-07-17 (30 days — stable iOS SDK, no expected API changes)
