import CoreGraphics
import Foundation
import ImageIO

/// A brand mark ready to draw, whether it came from a vector or a raster.
///
/// Colour marks are vector PDFs; most monochrome renditions are the
/// manufacturer's official 1024px artwork, since only Apple supplied mono
/// vectors. One type with one `draw` keeps the caption code from caring.
public enum BrandMarkArtwork {
    case vector(CGPDFPage)
    case raster(CGImage)

    /// Width-to-height ratio. These marks range from ~10:1 wordmarks to square
    /// glyphs, so callers size by height and use this to find the width.
    public var aspectRatio: CGFloat {
        switch self {
        case .vector(let page):
            let box = page.getBoxRect(.mediaBox)
            return box.height > 0 ? box.width / box.height : 1
        case .raster(let image):
            return image.height > 0 ? CGFloat(image.width) / CGFloat(image.height) : 1
        }
    }

    /// Draws the mark to fill `rect`, which callers derive from a height.
    public func draw(in rect: CGRect, context: CGContext) {
        context.saveGState()
        switch self {
        case .vector(let page):
            let box = page.getBoxRect(.mediaBox)
            guard box.width > 0, box.height > 0 else { context.restoreGState(); return }
            // The context is flipped to a top-left origin for frame drawing;
            // PDF pages are y-up, so flip back over the target rect.
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: rect.width / box.width, y: -(rect.height / box.height))
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
        case .raster(let image):
            // Same flip: CGContext draws images bottom-up relative to a
            // top-left-origin context.
            context.translateBy(x: 0, y: rect.maxY + rect.minY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: rect)
        }
        context.restoreGState()
    }
}

/// Maps the manufacturer recorded in a photo's metadata to that brand's mark.
///
/// The brand is never configured by the user: a photo can only ever carry the
/// mark of the device that took it. A manufacturer with no shipped artwork
/// resolves to nothing, and the caption then draws neither mark nor divider —
/// which is what lets brands land one at a time.
public enum BrandMarkRegistry {

    /// Brand keys, matching the filenames in `Resources/Logos`.
    public static let brandKeys: [String] = [
        "apple", "canon", "dji", "fujifilm", "google", "gopro", "hasselblad",
        "honor", "huawei", "insta360", "leica", "motorola", "nikon", "nothing",
        "olympus", "oneplus", "oppo", "panasonic", "pentax", "realme", "redmi",
        "samsung", "sony", "vivo", "xiaomi",
    ]

    /// Manufacturers whose EXIF name does not contain their brand key.
    ///
    /// Every other brand is found by substring, which already absorbs the
    /// usual "NIKON CORPORATION" / "LEICA CAMERA AG" noise.
    private static let aliases: [String: String] = [
        "om digital solutions": "olympus",   // Olympus's camera arm, renamed
        "om system": "olympus",
        "arashi vision": "insta360",         // Insta360's company name
        "ricoh imaging": "pentax",           // Pentax bodies report Ricoh
        "ricoh": "pentax",
    ]

    /// Sub-brands that record their parent as the manufacturer, and so can
    /// only be told apart by the model.
    ///
    /// Redmi phones write `Make = Xiaomi`; matching on make alone would give
    /// every Redmi the Xiaomi mark. Honor needs no entry: current devices
    /// write HONOR, and Huawei-era ones wrote HUAWEI and correctly get the
    /// Huawei mark, because that is what the metadata says.
    private static let subBrandsByModel: [String: String] = [
        "redmi": "redmi",
    ]

    // MARK: - Resolving

    /// Normalises a manufacturer string for matching: case-folded, trimmed of
    /// whitespace and punctuation.
    static func normalise(_ raw: String) -> String {
        raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// The brand key for a photo, or nil when the metadata names no
    /// manufacturer or one with no shipped mark.
    public static func brandKey(make: String?, model: String?) -> String? {
        // A sub-brand in the model wins: it is more specific than the parent
        // company in the make.
        if let model {
            let normalisedModel = normalise(model)
            for (needle, key) in subBrandsByModel where normalisedModel.contains(needle) {
                return brandKeys.contains(key) ? key : nil
            }
        }

        guard let make, !make.isEmpty else { return nil }
        let normalisedMake = normalise(make)
        guard !normalisedMake.isEmpty else { return nil }

        for (needle, key) in aliases where normalisedMake.contains(needle) {
            return key
        }
        // Substring rather than equality, so corporate suffixes do not defeat
        // the match.
        for key in brandKeys where normalisedMake.contains(key) {
            return key
        }
        return nil
    }

    /// The brand key for a photo's metadata dictionary.
    public static func brandKey(metadata: [String: Any]) -> String? {
        let tiff = metadata["{TIFF}"] as? [String: Any]
        let make = (tiff?["Make"] as? String) ?? (metadata["Make"] as? String)
        let model = (tiff?["Model"] as? String) ?? (metadata["Model"] as? String)
        return brandKey(make: make, model: model)
    }

    // MARK: - Loading artwork

    /// Which file to use for a brand, honouring the user's colour/monochrome
    /// preference and falling back when a brand ships only one rendition.
    ///
    /// Which *monochrome* is not a user choice: the rendition that contrasts
    /// with the mat is used, so the light one only comes up on a dark mat.
    static func variantNames(for variant: LogoVariant, matIsLight: Bool) -> [String] {
        switch variant {
        case .color:
            return ["color", matIsLight ? "black" : "white"]
        case .monochrome:
            let mono = matIsLight ? "black" : "white"
            let other = matIsLight ? "white" : "black"
            return [mono, other, "color"]
        }
    }

    /// Loads a brand's mark, or nil when nothing is shipped for it.
    public static func artwork(
        brandKey: String,
        variant: LogoVariant,
        matIsLight: Bool,
        bundle: Bundle? = nil
    ) -> BrandMarkArtwork? {
        let bundle = bundle ?? .module
        for name in variantNames(for: variant, matIsLight: matIsLight) {
            let stem = "\(brandKey)-\(name)"
            if let url = bundle.url(forResource: stem, withExtension: "pdf", subdirectory: "Logos"),
               let doc = CGPDFDocument(url as CFURL), let page = doc.page(at: 1) {
                return .vector(page)
            }
            if let url = bundle.url(forResource: stem, withExtension: "png", subdirectory: "Logos"),
               let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                return .raster(image)
            }
        }
        return nil
    }

    /// The mark for a photo, resolved end to end from its metadata.
    public static func mark(
        metadata: [String: Any],
        variant: LogoVariant,
        matIsLight: Bool
    ) -> BrandMarkArtwork? {
        guard let key = brandKey(metadata: metadata) else { return nil }
        return artwork(brandKey: key, variant: variant, matIsLight: matIsLight)
    }
}
