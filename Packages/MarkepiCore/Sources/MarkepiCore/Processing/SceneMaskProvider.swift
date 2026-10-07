import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Vision

/// Where the skin and the sky are in a photo, for looks that treat them apart
/// from the rest. Both are upright (EXIF orientation applied), single-channel
/// in RGB, and any size — the renderer stretches them onto the photo.
public struct SceneMasks: @unchecked Sendable {
    public var skin: CIImage?
    public var sky: CIImage?
    public init(skin: CIImage? = nil, sky: CIImage? = nil) {
        self.skin = skin
        self.sky = sky
    }
    public static let none = SceneMasks()
}

/// Builds and caches `SceneMasks` per source file.
///
/// **Skin:** the skin matte Portrait-mode photos embed (iPhone XS and later)
/// minus the embedded hair matte; otherwise Vision's person matte times a
/// skin-colour key, so skin-coloured walls outside a person are ignored.
///
/// **Sky:** the sky matte some iPhone photos embed; otherwise — iOS has no
/// public sky segmentation — only when Vision's scene classifier says the photo
/// shows sky, a sky-colour key weighted toward the top of the frame, with
/// people cut out.
///
/// Computed once per source at a fixed working size and cached, so the preview
/// and the full-size export use the very same masks. Everything runs on device.
public actor SceneMaskProvider {
    public static let shared = SceneMaskProvider()

    /// Long edge of the working decode the Vision fallbacks run on.
    static let workingSize: CGFloat = 1024
    private let capacity = 8
    private var cache: [(key: String, masks: Stored)] = []
    private(set) var computeCount = 0

    /// Linear so mask values survive the CGImage round trip unchanged.
    private static let maskColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CIContextProvider.workingColorSpace

    private struct Stored: @unchecked Sendable {
        var skin: CGImage?
        var sky: CGImage?
        var masks: SceneMasks { SceneMasks(skin: skin.map { CIImage(cgImage: $0) }, sky: sky.map { CIImage(cgImage: $0) }) }
    }

    public init() {}

    /// The masks for `url`. Either may be nil (no person / no sky).
    public func masks(for url: URL) -> SceneMasks {
        let key = Self.cacheKey(url)
        if let i = cache.firstIndex(where: { $0.key == key }) {
            let hit = cache.remove(at: i)
            cache.append(hit)
            return hit.masks.masks
        }
        computeCount += 1
        let made = Self.make(url)
        cache.append((key, made))
        if cache.count > capacity { cache.removeFirst(cache.count - capacity) }
        return made.masks
    }

    /// Number of cached sources (tests).
    var cachedCount: Int { cache.count }

    static func cacheKey(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "\(url.standardizedFileURL.path)|\(values?.fileSize ?? -1)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    // MARK: - Building

    private static func make(_ url: URL) -> Stored {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { return Stored() }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = CGImagePropertyOrientation(
            rawValue: (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1) ?? .up

        let embeddedSkin = embeddedSkinMask(source, orientation: orientation)
        let embeddedSky = matte(source, kCGImageAuxiliaryDataTypeSemanticSegmentationSkyMatte, orientation)

        var skin = embeddedSkin, sky = embeddedSky
        if skin == nil || sky == nil, let work = workingDecode(source) {
            let photo = CIImage(cgImage: work)
            let handler = VNImageRequestHandler(cgImage: work)
            let person = personMatte(handler).map { PhotoLookRenderer.fitted($0, to: photo.extent) }
            if skin == nil, let person {
                skin = multiply(PhotoLookRenderer.applyCube(PhotoLookRenderer.skinKeyCube, to: photo), person)
            }
            if sky == nil, showsSky(handler) {
                sky = keyedSky(photo, excluding: person)
            }
        }
        return Stored(skin: skin.flatMap { render($0, feather: 0.004) },
                      sky: sky.flatMap { render($0, feather: 0.01) })
    }

    private static func workingDecode(_ source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(workingSize),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func render(_ mask: CIImage, feather: Double) -> CGImage? {
        let e = mask.extent
        guard e.width > 0, e.height > 0, e.width.isFinite, e.height.isFinite else { return nil }
        let soft = mask.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(min(e.width, e.height)) * feather)
            .cropped(to: e)
            .applyingFilter("CIColorClamp")
        guard hasContent(soft) else { return nil }
        return CIContextProvider.shared.createCGImage(soft, from: e, format: .RGBA8, colorSpace: maskColorSpace)
    }

    // MARK: Embedded mattes

    /// Portrait-mode skin matte minus hair, upright.
    static func embeddedSkinMask(_ source: CGImageSource, orientation: CGImagePropertyOrientation) -> CIImage? {
        guard let skin = matte(source, kCGImageAuxiliaryDataTypeSemanticSegmentationSkinMatte, orientation) else { return nil }
        guard let hair = matte(source, kCGImageAuxiliaryDataTypeSemanticSegmentationHairMatte, orientation) else { return skin }
        return multiply(skin, PhotoLookRenderer.fitted(hair, to: skin.extent).applyingFilter("CIColorInvert"))
    }

    static func matte(_ source: CGImageSource, _ type: CFString, _ orientation: CGImagePropertyOrientation) -> CIImage? {
        guard let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) as? [AnyHashable: Any],
              let matte = try? AVSemanticSegmentationMatte(fromImageSourceAuxiliaryDataType: type, dictionaryRepresentation: info)
        else { return nil }
        let image = CIImage(cvPixelBuffer: matte.mattingImage).oriented(orientation)
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    // MARK: Vision fallbacks

    private static func personMatte(_ handler: VNImageRequestHandler) -> CIImage? {
        let instances = VNGeneratePersonInstanceMaskRequest()
        if (try? handler.perform([instances])) != nil,
           let result = instances.results?.first, !result.allInstances.isEmpty,
           let buffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) {
            return CIImage(cvPixelBuffer: buffer)
        }
        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = .balanced
        guard (try? handler.perform([segmentation])) != nil, let result = segmentation.results?.first else { return nil }
        let matte = CIImage(cvPixelBuffer: result.pixelBuffer)
        return hasContent(matte) ? matte : nil
    }

    /// Vision's scene classifier, so a blue wall indoors is never treated as sky.
    static func showsSky(_ handler: VNImageRequestHandler) -> Bool {
        let classify = VNClassifyImageRequest()
        guard (try? handler.perform([classify])) != nil else { return false }
        return (classify.results ?? []).contains { $0.identifier == "sky" && $0.confidence >= 0.25 }
    }

    /// Sky-coloured pixels, weighted toward the top of the frame, minus people.
    // ponytail: colour + position heuristic, because iOS has no public sky
    // segmentation; swap in a segmentation model if one becomes available.
    static func keyedSky(_ photo: CIImage, excluding person: CIImage?) -> CIImage {
        let e = photo.extent
        let key = PhotoLookRenderer.applyCube(PhotoLookRenderer.skyKeyCube, to: photo)
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: e.midX, y: e.maxY)
        gradient.point1 = CGPoint(x: e.midX, y: e.maxY - e.height * 0.75)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0)
        var sky = multiply(key, gradient.outputImage!.cropped(to: e))
        if let person { sky = multiply(sky, person.applyingFilter("CIColorInvert")) }
        return sky
    }

    // MARK: Helpers

    /// True when any pixel of a mask is meaningfully on.
    private static func hasContent(_ mask: CIImage) -> Bool {
        let maxima = CIFilter.areaMaximum()
        maxima.inputImage = mask
        maxima.extent = mask.extent
        guard let out = maxima.outputImage else { return false }
        var px = [UInt8](repeating: 0, count: 4)
        CIContextProvider.shared.render(out, toBitmap: &px, rowBytes: 4,
                                        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                        format: .RGBA8, colorSpace: nil)
        return px[0] > 25
    }

    private static func multiply(_ a: CIImage, _ b: CIImage) -> CIImage {
        let f = CIFilter.multiplyCompositing()
        f.inputImage = a
        f.backgroundImage = b
        return (f.outputImage ?? a).cropped(to: a.extent)
    }
}
