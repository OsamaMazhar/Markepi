import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import os.log

#if DEBUG
private let gainMapLog = Logger(subsystem: "com.watermark.core", category: "GainMap")
#endif

/// The auxiliary gain-map flavor extracted from a source image.
public enum GainMapType: Sendable {
    /// Apple's `kCGImageAuxiliaryDataTypeHDRGainMap` — single-channel, and a
    /// stored sample of 0 means "no boost" (SDR). Safe to zero a frame band.
    case appleHDR
    /// ISO 21496-1 gain map (`kCGImageAuxiliaryDataTypeISOGainMap`, iOS 18+).
    /// The neutral (no-boost) value is metadata-dependent, so we never fabricate
    /// samples for it — geometry-only.
    case iso
}

/// Re-aligns an HDR gain map to the orientation-normalized, optionally
/// white-framed base image before it is re-attached on export.
///
/// The pipeline physically rotates the base pixels upright (via
/// `.applyOrientationProperty` on load + `OrientationNormalizer`) and resets the
/// EXIF orientation tag to 1 on write. The gain map, however, is extracted as an
/// opaque blob still in the source's *stored* orientation. Re-attaching it
/// verbatim leaves the HDR boost rotated / aspect-swapped relative to the pixels
/// for any source whose EXIF orientation wasn't already `.up` (nearly every
/// iPhone photo) — the map's gain lands in the wrong places.
///
/// This type rotates the gain map with the SAME transform the base received,
/// and — when a frame is applied — pads it out to the framed canvas, seating the
/// photo's map exactly where the photo sits and leaving the mat at no boost (an
/// Apple `HDRGainMap` sample of 0 == gain 1.0 == SDR).
///
/// Padding, not merely blanking a border: a viewer stretches the map over
/// whatever image it is attached to, so a photo-shaped map on a framed canvas is
/// re-scaled across the mat as well. The photo's own gain then lands on the
/// border as a shaded rectangle that is invisible in the SDR pixels and obvious
/// on an HDR display.
///
/// Rotation and padding are lossless byte moves, so no resampling or gamma
/// conversion touches the gain values.
public struct GainMapProcessor {

    /// Where the photo sits inside the exported canvas, in pixels, y-down —
    /// exactly the rect the renderer composited it into.
    public struct Placement: Sendable {
        public let canvas: CGSize
        public let photo: CGRect

        public init(canvas: CGSize, photo: CGRect) {
            self.canvas = canvas
            self.photo = photo
        }
    }

    /// Returns a gain-map auxiliary dictionary aligned to the exported base
    /// image, or `nil` when there is no gain map / it can't be safely aligned.
    ///
    /// Fallback policy: when the map can't be parsed but a transform is required
    /// (rotation or frame neutralization), the map is DROPPED rather than
    /// re-attached stale. A missing gain map exports as SDR — correct-looking,
    /// just without the HDR boost — whereas a misaligned one is visibly corrupt.
    ///
    /// - Parameters:
    ///   - auxData: The source gain-map aux dict (String keys, as stored by
    ///     `ImageLoader`). `nil` ⇒ no gain map ⇒ returns `nil`.
    ///   - type: Which gain-map flavor `auxData` came from.
    ///   - sourceOrientation: The source image's EXIF orientation (the transform
    ///     the base pixels received to become upright).
    ///   - placement: Where the photo sits in the exported canvas when a frame
    ///     enlarged it. `nil` ⇒ the canvas IS the photo ⇒ nothing to pad.
    /// - Returns: A rebuilt aux dict ready for `CGImageDestinationAddAuxiliaryDataInfo`,
    ///   the original dict unchanged (fast path), or `nil`.
    public static func aligned(
        auxData: [String: Any]?,
        type: GainMapType,
        sourceOrientation: CGImagePropertyOrientation,
        placement: Placement?
    ) -> [String: Any]? {
        guard let auxData else { return nil }

        let needsRotation = sourceOrientation != .up
        let needsNeutralization = placement != nil

        // Fast path: base wasn't rotated and no frame band to clear — the stored
        // gain map already aligns with the exported pixels. Return it untouched.
        if !needsRotation && !needsNeutralization {
            return auxData
        }

        // ISO gain maps: geometry is type-agnostic (safe to rotate) but the
        // neutral value depends on the map's own metadata, so we can't fabricate
        // "no boost" samples for the mat. When a frame is applied to an ISO map,
        // drop it (clean SDR frame) rather than risk a glowing border.
        if type == .iso && needsNeutralization {
            #if DEBUG
            gainMapLog.debug("ISO gain map + white frame: dropping map to keep frame flat")
            #endif
            return nil
        }

        guard let parsed = parse(auxData) else {
            // Unparseable/unsupported format and a transform is required → drop.
            #if DEBUG
            gainMapLog.debug("gain map unparseable while transform required — dropping (SDR export)")
            #endif
            return nil
        }

        // Rotate (and tightly repack) into upright orientation. Passing `.up`
        // here is a plain stride-normalizing copy, so this also fixes any input
        // that carried row padding.
        let rotated = rotate(
            pixels: parsed.pixels,
            width: parsed.width,
            height: parsed.height,
            bytesPerSample: parsed.bytesPerSample,
            srcBytesPerRow: parsed.bytesPerRow,
            orientation: sourceOrientation
        )
        var buffer = rotated.pixels
        var width = rotated.width
        var height = rotated.height

        if let placement {
            // Guaranteed `.appleHDR` here (ISO + frame returned above): the mat
            // is filled with 0, which is gain 1.0 — no boost.
            guard let padded = padded(
                buffer,
                width: width,
                height: height,
                bytesPerSample: parsed.bytesPerSample,
                into: placement
            ) else {
                #if DEBUG
                gainMapLog.debug("gain map cannot be seated in the framed canvas — dropping (SDR export)")
                #endif
                return nil
            }
            buffer = padded.pixels
            width = padded.width
            height = padded.height
        }
        let tightBytesPerRow = width * parsed.bytesPerSample

        var description: [String: Any] = [
            "Width": width,
            "Height": height,
            "BytesPerRow": tightBytesPerRow,
            "PixelFormat": parsed.pixelFormat,
        ]
        // Preserve any extra description keys ImageIO wrote (e.g. color primaries)
        // that aren't geometry-dependent.
        for (key, value) in parsed.extraDescriptionKeys where description[key] == nil {
            description[key] = value
        }

        var result: [String: Any] = [
            kCGImageAuxiliaryDataInfoData as String: Data(buffer) as CFData,
            kCGImageAuxiliaryDataInfoDataDescription as String: description,
        ]
        // The gain-map metadata (headroom / version) is orientation-independent —
        // carry it through unchanged so peak-brightness mapping is preserved.
        if let metadata = parsed.metadata {
            result[kCGImageAuxiliaryDataInfoMetadata as String] = metadata
        }

        #if DEBUG
        gainMapLog.debug(
            "aligned gain map: orient=\(sourceOrientation.rawValue) out=\(width)x\(height) bps=\(parsed.bytesPerSample) frame=\(needsNeutralization)"
        )
        #endif

        return result
    }

    // MARK: - Parsing

    private struct Parsed {
        var pixels: [UInt8]
        var width: Int
        var height: Int
        var bytesPerRow: Int
        var bytesPerSample: Int
        var pixelFormat: Int
        var metadata: Any?
        var extraDescriptionKeys: [String: Any]
    }

    private static func parse(_ aux: [String: Any]) -> Parsed? {
        guard let data = aux[kCGImageAuxiliaryDataInfoData as String] as? Data else { return nil }
        guard let desc = descriptionDict(aux[kCGImageAuxiliaryDataInfoDataDescription as String]) else {
            return nil
        }
        guard
            let width = intValue(desc["Width"]),
            let height = intValue(desc["Height"]),
            let bytesPerRow = intValue(desc["BytesPerRow"])
        else { return nil }

        let pixelFormat = intValue(desc["PixelFormat"]) ?? Int(kCVPixelFormatType_OneComponent8)
        let bytesPerSample: Int
        switch pixelFormat {
        case Int(kCVPixelFormatType_OneComponent8):
            bytesPerSample = 1
        case Int(kCVPixelFormatType_OneComponent16Half):
            bytesPerSample = 2
        default:
            // Multi-channel / unknown layouts (e.g. some ISO maps) — not safely
            // rotatable as a raw single-channel buffer. Caller drops the map.
            return nil
        }

        guard width > 0, height > 0,
              bytesPerRow >= width * bytesPerSample,
              data.count >= bytesPerRow * height
        else { return nil }

        var extras = desc
        for key in ["Width", "Height", "BytesPerRow", "PixelFormat"] {
            extras.removeValue(forKey: key)
        }

        return Parsed(
            pixels: [UInt8](data),
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            bytesPerSample: bytesPerSample,
            pixelFormat: pixelFormat,
            metadata: aux[kCGImageAuxiliaryDataInfoMetadata as String],
            extraDescriptionKeys: extras
        )
    }

    /// Normalizes the nested data-description into a `[String: Any]`. ImageIO may
    /// hand it back as a Swift dictionary or a toll-free-bridged NSDictionary.
    private static func descriptionDict(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        if let ns = value as? NSDictionary {
            var out: [String: Any] = [:]
            for (key, val) in ns {
                if let k = key as? String { out[k] = val }
            }
            return out
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let u as UInt32: return Int(u)
        default: return nil
        }
    }

    // MARK: - Rotation

    /// True for EXIF orientations that swap width and height (the 90° family).
    private static func swapsAxes(_ orientation: CGImagePropertyOrientation) -> Bool {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            return true
        default:
            return false
        }
    }

    /// Maps a source pixel (top-left origin) to its upright destination pixel for
    /// the given EXIF orientation. Pure permutation — exact, no interpolation.
    private static func destinationCoordinate(
        _ orientation: CGImagePropertyOrientation,
        sx: Int, sy: Int, width w: Int, height h: Int
    ) -> (x: Int, y: Int) {
        switch orientation {
        case .up:            return (sx, sy)
        case .upMirrored:    return (w - 1 - sx, sy)
        case .down:          return (w - 1 - sx, h - 1 - sy)
        case .downMirrored:  return (sx, h - 1 - sy)
        case .leftMirrored:  return (sy, sx)
        case .right:         return (h - 1 - sy, sx)
        case .rightMirrored: return (h - 1 - sy, w - 1 - sx)
        case .left:          return (sy, w - 1 - sx)
        @unknown default:    return (sx, sy)
        }
    }

    /// Rotates a raw single-channel buffer into upright orientation, returning a
    /// tightly packed buffer (`bytesPerRow == width * bytesPerSample`).
    private static func rotate(
        pixels: [UInt8],
        width: Int,
        height: Int,
        bytesPerSample bps: Int,
        srcBytesPerRow: Int,
        orientation: CGImagePropertyOrientation
    ) -> (pixels: [UInt8], width: Int, height: Int) {
        let swap = swapsAxes(orientation)
        let dstWidth = swap ? height : width
        let dstHeight = swap ? width : height
        let dstBytesPerRow = dstWidth * bps
        var out = [UInt8](repeating: 0, count: dstBytesPerRow * dstHeight)

        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for sy in 0..<height {
                    let srcRowStart = sy * srcBytesPerRow
                    for sx in 0..<width {
                        let d = destinationCoordinate(orientation, sx: sx, sy: sy, width: width, height: height)
                        let srcIndex = srcRowStart + sx * bps
                        let dstIndex = d.y * dstBytesPerRow + d.x * bps
                        for b in 0..<bps {
                            dst[dstIndex + b] = src[srcIndex + b]
                        }
                    }
                }
            }
        }
        return (out, dstWidth, dstHeight)
    }

    // MARK: - Framed canvas

    /// Seats the photo's gain map in a neutral canvas of the framed image's
    /// shape, so a viewer's stretch puts every sample back over the pixel it
    /// was measured from and the mat stays at no boost.
    ///
    /// The map is a uniformly downscaled copy of the photo, so its own scale
    /// against `placement.photo` is the scale the whole canvas is built at.
    private static func padded(
        _ buffer: [UInt8],
        width: Int,
        height: Int,
        bytesPerSample bps: Int,
        into placement: Placement
    ) -> (pixels: [UInt8], width: Int, height: Int)? {
        let photo = placement.photo
        let canvas = placement.canvas
        guard photo.width > 0, photo.height > 0, canvas.width > 0, canvas.height > 0 else { return nil }

        let scaleX = CGFloat(width) / photo.width
        let scaleY = CGFloat(height) / photo.height
        let outWidth = max(width, Int((canvas.width * scaleX).rounded()))
        let outHeight = max(height, Int((canvas.height * scaleY).rounded()))
        let originX = min(max(Int((photo.minX * scaleX).rounded()), 0), outWidth - width)
        let originY = min(max(Int((photo.minY * scaleY).rounded()), 0), outHeight - height)

        var out = [UInt8](repeating: 0, count: outWidth * outHeight * bps)
        let sourceRow = width * bps
        let destinationRow = outWidth * bps
        buffer.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<height {
                    let s = y * sourceRow
                    let d = (y + originY) * destinationRow + originX * bps
                    for i in 0..<sourceRow { dst[d + i] = src[s + i] }
                }
            }
        }
        return (out, outWidth, outHeight)
    }
}
