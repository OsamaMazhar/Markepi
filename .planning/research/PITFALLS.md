# Pitfalls Research

**Domain:** iOS Photo/Video Watermarking App
**Researched:** 2026-06-17
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: HDR Gain Map Destruction During Image Processing

**What goes wrong:**
When an iPhone photo with HDR (ISO HDR gain map) passes through any rendering pipeline — `CIImage` → `CGImage` → export — the gain map auxiliary data is silently discarded. The output image loses all HDR "pop," appearing flat and SDR-only. The gain map lives as auxiliary metadata attached to the file container (via Apple's `kCGImageAuxiliaryDataTypeHDRGainMap`), separate from the base pixel buffer. Standard `CIContext.createCGImage()` renders only the base layer and does not automatically carry the gain map through.

**Why it happens:**
- `CIImage(contentsOf:)` loads the base image by default; you must explicitly request auxiliary data via `options: [.auxiliaryHDRGainMap: true]`
- `CIContext` rendering typically produces a single `CGImage` — there is no mechanism to attach auxiliary data to a `CGImage`
- When using `CGImageDestination` to write output, the gain map must be explicitly injected via `CGImageDestinationAddAuxiliaryDataInfo()` or the HEIF-specific `hdrGainMapImage` option on `CIImageRepresentationOption`
- Many developers don't know gain maps exist and only discover the loss when comparing output side-by-side with original

**How to avoid:**
1. Load images with `CIImage(contentsOf: url, options: [.auxiliaryHDRGainMap: true])`
2. Extract gain map via `CIImageOption.auxiliaryHDRGainMap` and store it as a separate `CIImage`
3. When watermarking, apply the same watermark transform to both the base image AND the gain map (or composite watermark onto base, then re-attach the unmodified gain map)
4. When writing output via `CIImage` write methods, use `CIImageRepresentationOption.hdrGainMapImage` to embed the gain map
5. When using `CGImageDestination`, use `CGImageDestinationAddAuxiliaryDataInfo()` with `kCGImageAuxiliaryDataTypeHDRGainMap` to attach gain map data
6. Use 16-bit float pixel formats (`CIFormat.RGBAh`) for the rendering context to preserve dynamic range

**Warning signs:**
- Output image visually identical to original when viewed on SDR display but "flat" on HDR display
- `PHAsset` metadata shows "HDR" for original but output lacks HDR indicator in Photos app
- File size drops dramatically (gain map data can be several MB)
- Inspecting HEIF output with exiftool shows no Apple HDR gain map auxiliary data tracks

**Phase to address:**
Photo watermarking Phase (core image processing pipeline). This MUST be verified with actual HDR photos from iPhone 12+ before shipping.

---

### Pitfall 2: EXIF/Metadata Stripping in Pixel Pipeline

**What goes wrong:**
Every conversion step in the image processing chain strips metadata. `CGImage` is a pure pixel buffer — it has no concept of EXIF, TIFF, GPS, or orientation tags. When you go from `PHAsset` → `CIImage` → `CGImage` → output file, all original metadata (camera model, lens, GPS, timestamp, color profile, orientation) is permanently lost unless explicitly preserved and re-attached during write.

**Why it happens:**
- `CIImage` and `CGImage` are pixel representations only — metadata lives in the file container, not on the image object
- `UIImage` strips orientation when converting to `CGImage` (it "bakes in" the rotation but loses the EXIF orientation flag)
- `UIImage.jpegData(compressionQuality:)` creates a brand new JPEG with fresh (empty) metadata — this is NOT a pass-through of original bytes
- `CGImageDestinationAddImageFromSource()` copies metadata automatically but is unreliable — it carries over unintended tags and can't be used for precisely controlled metadata
- Developers assume metadata "comes along for the ride" because it does in simpler workflows

**How to avoid:**
1. Extract metadata BEFORE any pixel manipulation using `CGImageSourceCopyPropertiesAtIndex()` on the original data/URL
2. Store the properties dictionary separately throughout processing
3. When writing output, use `CGImageDestinationAddImage()` (NOT `AddImageFromSource`) and pass the preserved metadata dictionary as properties
4. For orientation: either "bake in" by rendering with a transform, then set output orientation to `.up`, OR preserve the original orientation tag and ensure output pixels match that orientation
5. Use `CGImagePropertyOrientation` (not `UIImage.Orientation`) when working with ImageIO destinations
6. Preserve color profile by passing source color space to `CIContext` or `CGContext` — never default to `CGColorSpaceCreateDeviceRGB()`
7. For Photos framework outputs, use `PHAssetCreationRequest.addResource(with: .photo, data: dataWithMetadata, options: nil)`

**Warning signs:**
- Output files missing GPS location
- Photos exported as "Unknown" camera model
- Incorrect date/time on output files
- Color shift or "washed out" appearance (color profile stripped)
- Image appears rotated after being viewed on other platforms (EXIF orientation lost but pixels not re-oriented)

**Phase to address:**
Core image processing Phase. This is table-stakes — every image path must include metadata preservation.

---

### Pitfall 3: Video Re-Encoding Quality Degradation

**What goes wrong:**
Any video processing that adds a watermark requires full decode→modify→re-encode. Even with "maximum quality" settings, the output is a generation-loss copy. Common misconfigurations make it dramatically worse: wrong pixel formats cause color shifts, wrong bitrate settings cause blocking artifacts, wrong color primaries cause washed-out output, and hardware encoder quirks introduce visual glitches on certain GOP structures.

**Why it happens:**
- `AVAssetExportPresetPassthrough` cannot be used when visual modifications are applied — it only works for trimming/recontainerization
- `AVOutputSettingsAssistant` chooses "compatible" settings that often under-specify quality to favor broad playback support
- Default encoder settings use variable bitrate that can dip too low on complex frames
- Pixel format mismatch between source (`420YpCbCr8BiPlanarVideoRange`) and output settings causes unnecessary color space conversions
- Failing to specify `AVVideoColorPrimariesKey`, `AVVideoTransferFunctionKey`, and `AVVideoYCbCrMatrixKey` causes the encoder to use default Rec.601 tags even for HD/4K content
- Using `AVAssetExportSession` with `AVAssetExportPresetHighestQuality` is better than nothing but still gives no control over bitrate, profile level, or color metadata

**How to avoid:**
1. Use `AVAssetWriter` (not `AVAssetExportSession`) for full control over encoding parameters
2. Match source pixel format when possible; use `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` for SDR video
3. Explicitly set compression settings:
   - `AVVideoAverageBitRateKey`: target at least 80% of source bitrate
   - `AVVideoProfileLevelKey`: use `AVVideoProfileLevelH264HighAutoLevel` for H.264, or HEVC equivalent
   - Set `AVVideoAllowFrameReorderingKey` to match source GOP structure
4. Explicitly set color properties matching the source:
   - SDR: `AVVideoColorPrimaries_ITU_R_709_2`, `AVVideoTransferFunction_ITU_R_709_2`, `AVVideoYCbCrMatrix_ITU_R_709_2`
   - HDR: `AVVideoColorPrimaries_ITU_R_2020`, `AVVideoTransferFunction_ITU_R_2100_HLG` or `SMPTE_ST_2084_PQ`
5. Read metadata from source asset (`asset.metadata`) and manually copy relevant items to `AVAssetWriter.metadata`
6. Validate output with MediaInfo or ffprobe to confirm bitrate and color tags
7. For development: compare source → intermediate → output PSNR to quantify quality loss

**Warning signs:**
- Output video appears "blocky" in high-motion scenes
- Color looks different from original (desaturated or over-saturated)
- Output file is dramatically smaller than source despite same resolution
- Color primaries tag in output reads "Rec.601" for HD content

**Phase to address:**
Video watermarking Phase. This is the most technically demanding aspect — budget significantly more time for video than photo processing.

---

### Pitfall 4: Share Extension Memory Limit Crashes

**What goes wrong:**
iOS share extensions have a hard memory ceiling of approximately 120 MB. When a user shares a large photo or video through the share sheet, naive code that loads the full-resolution `UIImage` or decodes all frames into memory will trigger a jetsam event. The extension is terminated with `EXC_RESOURCE RESOURCE_TYPE_MEMORY` — no crash log, no error handler, just a silent kill that looks to the user like the extension "didn't work."

**Why it happens:**
- A 12MP photo (4032×3024) as an uncompressed `UIImage` consumes ~48 MB (width×height×4 bytes). Multiple copies (original + preview + processed) easily exceed the limit
- 4K video frames decoded into memory can consume 30+ MB per frame
- Developers test on Simulator which has no memory limit, so crashes only appear on device
- Converting shared attachment to `UIImage` immediately upon receipt is the default approach in most tutorials
- Holding multiple full-resolution images in an array or collection before processing

**How to avoid:**
1. NEVER load shared media as `UIImage` — work with file URLs and `Data` objects instead
2. Use `CGImageSource` with downsampling options (`kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceThumbnailMaxPixelSize`) for previews
3. Process one item at a time; release memory explicitly (`autoreleasepool` blocks)
4. For video: use `AVAsset` which streams from disk; never load video frames into an array
5. Write processed output to App Group shared container as a file (not `UserDefaults`)
6. Configure tight `NSExtensionActivationRule` predicates:
   - `NSExtensionActivationSupportsImageWithMaxCount`: 1
   - `NSExtensionActivationSupportsMovieWithMaxCount`: 1
   - Use `NSPredicate` to prevent attachment types you can't handle
7. Close the extension immediately after writing to shared container — don't keep it alive
8. Test on physical devices only — Simulator memory behavior is irrelevant

**Warning signs:**
- Extension works in Simulator but "crashes" silently on device
- Works with small photos but fails with 48MP ProRAW
- Xcode Organizer shows jetsam events with `reason: per-process-limit`
- Memory graph in Xcode debugger spikes above 100MB during processing

**Phase to address:**
Share Extension Phase. Must be designed with memory budget from day one.

---

### Pitfall 5: CIImage Coordinate System & Double-Rotation Bug

**What goes wrong:**
When applying transforms (crop, overlay placement) to a `CIImage` that has EXIF orientation, the CIImage coordinate system (bottom-left origin, +Y up) conflicts with both the UIKit coordinate system (top-left origin, +Y down) and the EXIF orientation. This produces "double rotation," where applying what looks like a correct crop or overlay position in UIKit coordinates produces a wildly incorrect result in the output. The most common manifestation: a watermark placed in the "top-right corner" via UIKit coordinates appears in the bottom-left of the output image.

**Why it happens:**
- `CIImage` ignores EXIF orientation — it represents the raw sensor data in its stored orientation
- If a photo was shot in portrait but stored as landscape with EXIF rotation=6 (90° CW), the `CIImage` extent represents the landscape orientation
- UIKit views display the EXIF-corrected orientation, but any coordinates from those views are in UIKit space
- Applying `CIImage.cropped(to:)` or `CIImage.transformed(by:)` with UIKit-space coordinates operates on the raw (unrotated) image data
- The Y-axis must be flipped: `ciY = imageHeight - uiKitY - overlayHeight`
- Failure to normalize orientation before applying positional transforms creates compound errors

**How to avoid:**
1. Always normalize orientation BEFORE applying any positional transforms:
   ```swift
   let oriented = ciImage.oriented(forExifOrientation: exifOrientation)
   ```
2. After normalization, the CIImage extent matches the visual display — UIKit coordinates can be directly mapped with Y-axis flip
3. When overlaying watermarks, convert UIKit-space positions to CIImage space:
   ```swift
   let ciY = orientedImage.extent.height - uiKitY - watermarkHeight
   ```
4. Prefer `oriented(forExifOrientation:)` over `imageByApplyingOrientation()` on `CIImage` — the former is more explicit about EXIF handling
5. Use `orientationTransform(forExifOrientation:)` to get the `CGAffineTransform` and combine it with other transforms via `transformed(by:)` for a single-pass operation
6. If you must use Core Graphics for watermark rendering, apply the orientation transform to the `CGContext` CTM before drawing

**Warning signs:**
- Watermark appears in wrong corner of output image
- Cropped output is shifted or has wrong aspect ratio
- "It looks right in the preview but wrong in the saved file"
- Rotating a landscape image that already has EXIF rotation produces portrait output

**Phase to address:**
Photo watermarking Phase (core image processing).

---

### Pitfall 6: PHContentEditingInput Orientation Handling

**What goes wrong:**
When the Photos editing extension receives an image via `PHContentEditingInput`, the `fullSizeImageURL` points to the master file — which may have pixels stored in landscape orientation with EXIF rotation=6 (portrait). If you load this with `CIImage(contentsOf: url)` without applying `input.fullSizeImageOrientation`, your processing operates on the raw pixel layout. The output may have correct EXIF orientation but wrong raster dimensions, or vice versa. Some methods "bake in" orientation by physically rotating pixels, others preserve the EXIF tag — mixing these approaches creates inconsistent results.

**Why it happens:**
- `fullSizeImageOrientation` is an Int32 (not `CGImagePropertyOrientation` or `UIImage.Orientation`), easy to mishandle
- `CIImage(contentsOf:)` does not read EXIF orientation — you must apply it manually
- If you render through `CIContext.createCGImage()` and then create a `UIImage(cgImage:scale:orientation:)`, you need to decide: set orientation to `.up` (pixels already rotated) or preserve the original value (pixels still in raw orientation)
- `PHAdjustmentData` carries no orientation information — it's reconstructible only if your edit format preserves it

**How to avoid:**
1. Always read `contentEditingInput.fullSizeImageOrientation`
2. Convert to `CGImagePropertyOrientation` using the mapping:
   ```swift
   let cgOrientation = CGImagePropertyOrientation(rawValue: UInt32(input.fullSizeImageOrientation)) ?? .up
   ```
3. Normalize the CIImage before processing:
   ```swift
   let oriented = CIImage(contentsOf: url)?.oriented(forExifOrientation: Int32(cgOrientation.rawValue))
   ```
4. When writing output via `CGImageDestination`, set the EXIF orientation to `.up` (1) if you've already baked in the rotation through rendering, OR preserve the original orientation tag if your pixels remain in raw layout
5. Be consistent across the entire pipeline — pick one strategy (bake-in or preserve-tag) and stick with it
6. Verify by testing with photos shot in all four device orientations

**Warning signs:**
- Output image dimensions don't match source after processing
- Image appears rotated when viewed outside Photos app
- Photos edit extension shows different aspect ratio than original
- "adjustment data too large" errors when saving (orientation mismatch causing redundant pixel copies)

**Phase to address:**
Photos Edit Extension Phase.

---

### Pitfall 7: Video HDR (Dolby Vision / HLG) Flattening to SDR

**What goes wrong:**
When a user shares an HDR video (iPhone 12+ Dolby Vision or HLG footage), the processing pipeline — overlay watermark → re-encode — inadvertently flattens the HDR content to SDR. The output is technically playable but loses all HDR luminance range. Highlights that should be 1000+ nits render at SDR 100-nit levels, colors desaturate, and the "HDR" indicator in Photos disappears.

**Why it happens:**
- `AVAssetWriter` defaults to SDR color properties if not explicitly configured
- The watermark overlay (text, logo) is typically authored in SDR (sRGB/Rec.709). Compositing SDR content onto HDR video without HDR-aware blending produces incorrect luminance
- `AVAssetExportSession` with generic presets does not preserve HDR metadata automatically
- One common approach is tone-mapping to SDR — but if your goal is HDR preservation, you must output HDR
- `AVVideoComposition` and `AVVideoCompositionCoreAnimationTool` render in the composition's color space; if the composition defaults to SDR, the HDR signal is clipped

**How to avoid:**
1. Check source video HDR status: inspect `asset.tracks` for HDR metadata; check `CMFormatDescription` for transfer function (HLG, PQ)
2. If source is HDR, configure `AVAssetWriter` output with HDR color properties:
   - HLG: `AVVideoColorPrimaries_ITU_R_2020`, `AVVideoTransferFunction_ITU_R_2100_HLG`
   - Dolby Vision (PQ): `AVVideoColorPrimaries_ITU_R_2020`, `AVVideoTransferFunction_SMPTE_ST_2084_PQ`
   - Matrix: `AVVideoYCbCrMatrix_ITU_R_2020`
3. For `AVVideoComposition`, set `colorPrimaries`, `colorTransferFunction`, `colorYCbCrMatrix` to match source HDR metadata
4. Render watermark in extended range: use `CIFormat.RGBAh` (16-bit float), wide gamut color space
5. If watermark is SDR, apply HDR gain (multiply luminance) before compositing to match the HDR luminance range
6. Use `AVAssetWriterInputPixelBufferAdaptor` with HDR-compatible pixel format (`kCVPixelFormatType_64RGBAHalf` or `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange`)
7. Test with actual Dolby Vision footage from iPhone 12+ — simulator video is often SDR-only

**Warning signs:**
- Output video loses "HDR" badge in Photos app
- Highlights that were bright in original appear clipped at SDR levels
- Colors look desaturated compared to original on XDR display
- Output file is significantly smaller than source (HDR metadata + wider bit depth dropped)

**Phase to address:**
Video processing Phase. Critical for iPhone 12+ users who shoot HDR video by default.

---

### Pitfall 8: AVAssetExportSession Audio Track Drop

**What goes wrong:**
After processing a video (overlaying watermark), the output video is silent — audio track is missing. This happens most commonly when using `AVMutableComposition` with `AVAssetExportSession` and the audio track insertion is incorrect, or when the export session configuration doesn't include the audio mix.

**Why it happens:**
- When creating an `AVMutableComposition`, developers focus on the video track and forget to insert the audio track
- `AVMutableVideoComposition` only governs video — audio handling requires a separate `AVAudioMix` (or simply including the audio track in the composition)
- If you're using `AVAssetExportPresetPassthrough` with a mutable composition that has been modified, the passthrough may fail silently for audio
- Simultaneous playback of the source asset in an `AVPlayer` instance can cause export to fail to access the audio track

**How to avoid:**
1. When creating `AVMutableComposition`, explicitly insert both video AND audio tracks:
   ```swift
   let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
   try compositionAudioTrack?.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
   ```
2. Verify audio track exists before export: `composition.tracks(withMediaType: .audio).count > 0`
3. If using `AVAssetExportSession`, ensure no other object (AVPlayer) is holding the source asset
4. Check export error after completion: `session.error` often surfaces audio format incompatibilities
5. For complex compositions, use `AVAssetWriter` with separate `AVAssetWriterInput` for audio (more control)

**Warning signs:**
- Output video has no sound
- `composition.tracks(withMediaType: .audio).count` returns 0 before export
- "Operation Stopped" error in export session
- Export succeeds but file is suspiciously small

**Phase to address:**
Video processing Phase.

---

### Pitfall 9: UIImage.jpegData() Re-Compression Trap

**What goes wrong:**
Using `uiImage.jpegData(compressionQuality: 1.0)` thinking it will produce a lossless pass-through of the original JPEG bytes. In reality, this fully decompresses the image into pixel buffer → re-compresses to JPEG with quality 1.0. The output is a SECOND-GENERATION lossy JPEG that has accumulated compression artifacts. Even at quality 1.0, the re-encoding is mathematically different from the original JPEG bitstream.

**Why it happens:**
- `UIImage` is a decoded bitmap — it has no memory of the original JPEG compression
- `jpegData(compressionQuality:)` always re-encodes from scratch
- Quality 1.0 in JPEG encoding still applies the DCT quantization tables — it's not visually lossless
- Developers assume "quality 1.0 = same as original" but JPEG encoding is not deterministic

**How to avoid:**
1. For photos that don't need pixel modification: pass through the original `Data` bytes without any decode/re-encode
2. When pixel modification IS required (watermarking):
   - Accept the generation loss BUT use `CGImageDestination` with `kCGImageDestinationLossyCompressionQuality = 1.0`
   - Prefer HEIF output (`public.heic`) which has better compression efficiency and less visible generation loss than JPEG
   - Match the target format to the source format to avoid transcoding between lossy codecs
3. Never use `UIImage.jpegData()` or `UIImage.heicData()` — always use `CGImageDestination` or `CIImage` write methods
4. For HEIF source images, output HEIF to avoid the double-loss of HEIF→decode→JPEG

**Warning signs:**
- Output JPEG is different file size from source even with quality=1.0
- Visible compression artifacts in output that weren't in source
- HEIF source → JPEG output quality noticeably degraded

**Phase to address:**
Core image processing Phase.

---

### Pitfall 10: PHAdjustmentData Size Limit Crashes

**What goes wrong:**
The Photos editing extension's `PHAdjustmentData` has an unpublicized but strict size limit. Storing large data (raw image data, full-resolution PNG overlays, complex filter parameter serializations) in `PHAdjustmentData` causes the extension to be terminated by the system. The `formatIdentifier` and `formatVersion` plus the `data` payload must be very small — Apple intends this for a "recipe" of edit parameters, not actual assets.

**Why it happens:**
- Developers store watermark image data (PNG/HEIF) directly in adjustment data for "self-contained" edits
- Complex serialization of filter parameters produces unexpectedly large payloads
- The limit is not documented by Apple, so it's discovered through crash reports
- Works during development with small test images but fails in production with complex assets

**How to avoid:**
1. `PHAdjustmentData` should contain ONLY a lightweight recipe: watermark position enum, text string, format identifier, maybe a UUID reference
2. Store watermark assets (images, fonts) in the app's shared container or bundle — never in adjustment data
3. Reference external assets by identifier or hash, not by embedding them
4. Keep `formatIdentifier` short (reverse-DNS style) and total payload well under 1KB
5. If you need to store more complex state, write it to a file in App Group container and store only the file URL's bookmark or UUID in adjustment data
6. Test with worst-case: maximum text length, maximum number of watermark placements

**Warning signs:**
- Extension works for simple edits but crashes for edits with multiple watermarks
- Xcode console shows "adjustment data too large" or similar Photos framework warnings
- `canHandle(_:)` returns false for previously saved edits
- Inconsistent behavior between device and simulator (simulator has no size enforcement)

**Phase to address:**
Photos Edit Extension Phase.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Using `UIImage.jpegData()` for output | Simple one-liner, no ImageIO knowledge needed | Irreversible quality loss from re-compression, all metadata stripped | Never for this project (quality preservation is a core requirement) |
| `CIContext()` created per image | No state management | Each context allocates GPU resources; repeated creation causes memory fragmentation and 10-100x slower processing | Only in throwaway prototypes, never in production |
| `AVAssetExportSession` with generic preset | Few lines of code, works for simple cases | No bitrate control, color metadata may default incorrectly, no guarantee of audio passthrough | Quick prototyping only; use `AVAssetWriter` for production |
| Bypassing HDR gain map handling | Works for SDR images, simpler code | All HDR content is silently flattened; impossible to retrofit later without refactoring entire pipeline | Not acceptable — HDR is default for iPhone 12+ |
| UIKit-coordinate overlay placement without CIImage Y-axis flip | Works on square images with EXIF=up | Incorrect watermark placement on all portrait photos and any image with non-zero EXIF orientation | Never |
| Hardcoded color profile (DeviceRGB) | Works on device screen | Output has wrong colors when viewed on other devices/platforms | Never for a sharing app |
| Storing watermark images in `PHAdjustmentData` | Self-contained edit history | Extension crashes on modestly-sized watermarks | Never |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| **Share Extension → Main App** | Trying to call `UIApplication.shared.open()` to bring main app to foreground from extension | Save shared data to App Group container, display "Saved" UI, let user open app manually. Never force-open from extension — it's unsupported and causes infinite launch loops on iOS 16+. |
| **Share Extension → Main App** | Passing large data via `UserDefaults` (shared suite) | Write files to App Group shared container; pass only file paths or UUIDs through `UserDefaults` |
| **Photos Edit Extension** | Assuming extension stays alive between sessions; caching state in memory | Extension process is killed frequently. Serialize all state to disk immediately. Restore from `PHAdjustmentData` + App Group storage on each launch. |
| **NSExtensionActivationRule** | `TRUEPREDICATE` (accepts everything) | Use specific constraints: `NSExtensionActivationSupportsImageWithMaxCount = 1`, `NSExtensionActivationSupportsMovieWithMaxCount = 1`, plus type filtering |
| **App Group Configuration** | Configuring only in main app target | Must be enabled in BOTH main app AND every extension target's Signing & Capabilities. Mismatch = silent failures reading/writing shared data. |
| **Photos Framework Authorization** | Requesting `.readWrite` access in extension | Photos extension gets implicit access to the asset being edited. Don't request authorization — it will prompt user unnecessarily in wrong context. |
| **AVAsset access from Photos** | Using `PHAsset.requestContentEditingInput()` result on main thread | Loading full-resolution video is I/O heavy. Use `PHImageManager.requestAVAsset()` for video, and always on background queue. |
| **Watermark as CALayer** | Adding `CALayer` directly to on-screen `UIView` for watermark, then rendering that view's layer | CALayer hierarchy must be standalone (not attached to any on-screen view) for `AVVideoCompositionCoreAnimationTool`. Create `parentLayer` + `videoLayer` + `watermarkLayer` specifically for export, never reuse UI layers. |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full-resolution `UIImage` decoding in extensions | Silent jetsam crashes on device, works in Simulator | Use `CGImageSource` with downsampling for previews; process full-res only once during final export | Immediately on first real-device test with 12MP+ photos |
| `CIContext` creation per image | Slow processing times, memory churn, GPU resource exhaustion | Create ONE `CIContext` per processing session, store as instance property, reuse across all images | Noticeable at 3+ images; catastrophic at 20+ |
| `AVMutableVideoComposition` + many sublayers | Dropped frames, export glitches, encoder falling back to low-quality | Flatten complex watermark into single pre-rendered `UIImage`/`CIImage`, use as single-layer overlay. Each `CALayer` sublayer adds rendering overhead during export. | At 5+ independent CALayer sublayers |
| Rendering watermark with Core Graphics (`CGContext`) on large images | Single-threaded CPU rendering, 5-10x slower than GPU | Use `CIImage` + `CIContext` (GPU-accelerated). Core Graphics is CPU-bound and single-threaded. | Any image > 4MP (iPhone 6s and later) |
| Unnecessary pixel format conversions in video pipeline | Color shifts, quality loss, slower encoding | Match source pixel format as closely as possible. Use bi-planar YCbCr for video, avoid RGB conversion unless necessary for watermark blending. | Any video with non-trivial color gamut |
| Using `UIImageView` to display full-res image in extension UI | Scrolling lag, memory pressure, eventual crash | Always downsample for display: use `CGImageSourceCreateThumbnailAtIndex()` with `kCGImageSourceThumbnailMaxPixelSize` matching the view's pixel dimensions | Immediate for images > 2MP |
| `PHCachingImageManager` in extension | Misunderstood API — it's for pre-warming, not an in-memory LRU. Attempting to use it for caching leads to unexpected deallocation and redundant fetches. | Manage your own disk-based cache for intermediate processing results; PHCachingImageManager is for pre-fetching in UICollectionView/scroll contexts | When reloading after extension process restart |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Writing to shared container without data validation | Maliciously crafted file from another share extension (if App Group ID is known) could contain path traversal or oversized payload | Validate file types, check file size before processing, use sandboxed file operations |
| Including user's precise GPS coordinates in watermarked output metadata | Users sharing to social media unintentionally broadcasting their home/work location | Offer "Strip Location" option before share, or strip GPS by default when watermarking for social media output |
| Loading arbitrary file formats from share extension | Malicious video file with crafted codec parameters could trigger decoder vulnerability | Validate MIME types, check actual file headers (not just extension), set processing timeouts |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Video processing on main thread | App freezes for seconds/minutes, user force-quits | Process on background queue with determinate progress bar (`Progress` object from AVAssetExportSession/AVAssetWriter) |
| No progress indication for video export | User wonders "is it working?" and may cancel | Show progress bar with time remaining estimate, allow background processing with notification on completion |
| Watermark preview at wrong scale | Watermark looks perfect in preview but enormous/tiny in output | Preview should show watermark at output resolution. Render preview overlay proportionally using same relative coordinates that will be used for output. |
| Deleting original after watermarking | Catastrophic data loss if output is corrupted or user changes mind | Never delete or modify original. Watermark produces new file. |
| "Save" button that saves to camera roll | Clutters camera roll, contradicts core value prop | Only action should be "Share" — output goes to share sheet, never saved unless user explicitly chooses "Save to Photos" from share sheet |
| Extension showing nothing after selecting unsupported file type | Confusion, assumes app is broken | Use `NSExtensionActivationRule` to prevent extension from appearing for unsupported types. In-app picker: show clear "Unsupported format" message. |

---

## "Looks Done But Isn't" Checklist

- [ ] **HDR preservation:** Verified output has gain map auxiliary data when source had it? Tested with iPhone 12+ HDR photo?
- [ ] **EXIF completeness:** GPS, camera model, lens, aperture, ISO, timestamp, color profile all present in output? Checked with exiftool?
- [ ] **Orientation correctness:** Output displays correctly in Photos, Files, and when shared to Instagram/Twitter/WhatsApp? Tested portrait, landscape-left, landscape-right, upside-down?
- [ ] **Video audio:** Output video has audio track, correct duration, no sync drift? Verified on both stereo and spatial audio sources?
- [ ] **Watermark placement accuracy:** All 8 positions (top-left, top-center, top-right, middle-left, center, middle-right, bottom-left, bottom-center, bottom-right) render correctly for both landscape and portrait aspect ratios?
- [ ] **Large image handling:** Tested with 48MP ProRAW? 108MP from third-party camera apps? Panorama (up to 100MP)?
- [ ] **Video memory:** 10-minute 4K60 video processes without jetsam? Peak memory < 200MB during processing?
- [ ] **Share extension on device:** Tested on physical device (not just Simulator)? Verified with Photos app share sheet, Safari image share, Files app share?
- [ ] **Photos edit extension lifecycle:** Extension works after being killed by system and relaunched? `PHAdjustmentData` reconstruction works from stored recipe?
- [ ] **Format fidelity:** HEIF source → HEIF output? JPEG source → JPEG output? No unintended format conversion?
- [ ] **Share without save:** Output appears in share sheet, user can share to any app, no copy saved to camera roll unless explicitly chosen in share sheet?
- [ ] **Cold launch from share extension:** App opens correctly when user returns to it after share extension completes?

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| HDR gain map loss in photo pipeline | HIGH (full pipeline refactor) | Audit every image loading point for `.auxiliaryHDRGainMap` option. Add gain map extraction at input, re-attachment at output. May require switching from `UIImage`-based to `CIImage`-based pipeline. |
| EXIF stripping through CGImage path | MEDIUM | Centralize metadata extraction into a single MetadataPreserver utility. Audit all output paths to pass through preserved metadata dictionary. One-time refactor of output methods. |
| Video re-encode quality settings inadequate | LOW-MEDIUM | Tune `AVAssetWriter` compression settings, re-test. May need per-source-format configuration mapping. |
| Share extension memory crash | MEDIUM | Redesign extension to use streaming/downsampling. Swap `UIImage` for `CGImageSource`. Implement processing queue with memory budget. |
| CIImage coordinate system bugs | LOW | Centralize coordinate conversion into a CoordinateConverter utility with tests for all EXIF orientations. Audit all positional transform code. |
| AVAssetExportSession audio drop | LOW | Swap to `AVAssetWriter` for video exports. Explicitly add audio track to composition. Add preflight check: `composition.tracks(withMediaType: .audio).count > 0`. |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| HDR gain map destruction | Photo watermarking (core pipeline) | Compare original vs output with XDR display; check auxiliary data tracks in output HEIF |
| EXIF/metadata stripping | Photo watermarking (core pipeline) | Exiftool diff of source vs output metadata dictionaries |
| Video re-encoding quality loss | Video watermarking | PSNR comparison; visual inspection at 2x zoom for compression artifacts |
| Share extension memory crash | Share Extension | Test with 48MP photo on oldest supported device; verify memory < 100MB peak |
| CIImage coordinate system | Photo watermarking (core pipeline) | Automated test: watermark in known position, verify pixel coordinates at output |
| PHContentEditingInput orientation | Photos Edit Extension | Test with photos shot in all 4 device orientations |
| Video HDR flattening | Video watermarking | Test with Dolby Vision footage from iPhone 12+; verify HDR badge on output |
| AVAssetExportSession audio drop | Video watermarking | Verify audio track presence in output via AVAssetTrack listing |
| UIImage.jpegData() re-compression | Photo watermarking (core pipeline) | Binary compare source vs output for non-watermarked regions |
| PHAdjustmentData size limit | Photos Edit Extension | Test with maximum-complexity edit (all watermarks, max text length) |

---

## Sources

- Apple Developer Documentation: `CIImage` auxiliary data options, `CGImageSource` metadata, `AVAssetWriter` color properties
- Apple HDR Video WWDC sessions (2020-2024): HDR editing pipeline, gain map specification
- `CGImageDestination` API reference: `AddImageFromSource` vs `AddImage` metadata handling
- `AVFoundation` Programming Guide: video composition, export presets, `AVAssetWriter` configuration
- Apple App Extension Programming Guide: memory limits, `NSExtensionActivationRule`, App Group sharing
- `PHContentEditingController` protocol reference and sample code
- Stack Overflow: HDR gain map preservation threads, EXIF stripping discussions, share extension crash diagnostics
- Community post-mortems: iOS Photo editing app developer forums, known issues with `UIImage` and metadata
- Dolby Vision / HLG developer documentation: metadata signaling, color primaries mappings

---
*Pitfalls research for: iOS Photo/Video Watermarking App*
*Researched: 2026-06-17*
