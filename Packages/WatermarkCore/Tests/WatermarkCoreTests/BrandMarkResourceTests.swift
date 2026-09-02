import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import WatermarkCore

/// Checks the shipped brand marks are loadable artwork of the expected shape.
///
/// The `gallery` frame draws these at full export resolution, so a mark that
/// does not open, or that ships at a size it would have to be stretched from,
/// is a visible defect. These tests run over whatever `Resources/Logos`
/// contains, so they keep covering brands as artwork changes without needing a
/// new test per brand.
@Suite("Brand mark resources")
struct BrandMarkResourceTests {

    static let variants = ["color", "black", "white"]

    /// Every mark currently shipped, vector and raster alike.
    static func shippedMarkURLs() -> [URL] {
        let pdfs = Bundle.module.urls(forResourcesWithExtension: "pdf", subdirectory: "Logos") ?? []
        let pngs = Bundle.module.urls(forResourcesWithExtension: "png", subdirectory: "Logos") ?? []
        return pdfs + pngs
    }

    static func brandKeys() -> Set<String> {
        Set(shippedMarkURLs().compactMap { url in
            let stem = url.deletingPathExtension().lastPathComponent
            guard let dash = stem.lastIndex(of: "-") else { return nil }
            return String(stem[stem.startIndex..<dash])
        })
    }

    @Test("Logos resource directory is bundled and reachable")
    func logosDirectoryIsBundled() throws {
        let readme = Bundle.module.url(forResource: "README", withExtension: "md", subdirectory: "Logos")
        #expect(readme != nil, "Resources/Logos is not in the bundle; check the .copy entry in Package.swift")
    }

    @Test("Marks are shipped for every supplied brand")
    func everyBrandShips() throws {
        // 25 brands were supplied. A drop in this number means the build step
        // silently skipped artwork.
        #expect(Self.brandKeys().count == 25, "expected 25 brands, found \(Self.brandKeys().count)")
    }

    @Test("Every brand has a colour mark and a black mark")
    func everyBrandHasColourAndBlack() throws {
        for brand in Self.brandKeys().sorted() {
            let hasColour = Self.shippedMarkURLs().contains {
                $0.deletingPathExtension().lastPathComponent == "\(brand)-color"
            }
            let hasBlack = Self.shippedMarkURLs().contains {
                $0.deletingPathExtension().lastPathComponent == "\(brand)-black"
            }
            #expect(hasColour, "\(brand) has no colour mark")
            // Black is the mono the light mat actually uses, so its absence is
            // a real gap in a way a missing white mark is not.
            #expect(hasBlack, "\(brand) has no black mark")
        }
    }

    @Test("Colour marks are vectors, so they cannot soften at export size")
    func colourMarksAreVectors() throws {
        for brand in Self.brandKeys().sorted() {
            let pdf = Bundle.module.url(forResource: "\(brand)-color", withExtension: "pdf", subdirectory: "Logos")
            #expect(pdf != nil, "\(brand)-color should be a vector PDF")
        }
    }

    @Test("Every shipped PDF opens as a single page with a non-zero media box")
    func shippedPDFsAreUsable() throws {
        let pdfs = Bundle.module.urls(forResourcesWithExtension: "pdf", subdirectory: "Logos") ?? []
        #expect(!pdfs.isEmpty, "no PDFs shipped at all")
        for url in pdfs {
            let name = url.lastPathComponent
            guard let doc = CGPDFDocument(url as CFURL) else {
                Issue.record("\(name) is not a readable PDF"); continue
            }
            #expect(doc.numberOfPages == 1, "\(name) should have exactly 1 page, has \(doc.numberOfPages)")
            guard let page = doc.page(at: 1) else { Issue.record("\(name) has no page 1"); continue }
            let box = page.getBoxRect(.mediaBox)
            #expect(box.width > 0 && box.height > 0, "\(name) has an empty media box")
        }
    }

    @Test("Every shipped raster is large enough that it is only ever downscaled")
    func shippedRastersAreLargeEnough() throws {
        // A mark draws at roughly 200-400px even on a 48MP export. 512px on the
        // long edge leaves headroom; below that a mark would start being
        // stretched on large photos.
        let minimumLongEdge = 512
        for url in Bundle.module.urls(forResourcesWithExtension: "png", subdirectory: "Logos") ?? [] {
            let name = url.lastPathComponent
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int,
                  let h = props[kCGImagePropertyPixelHeight] as? Int else {
                Issue.record("\(name) is not a readable image"); continue
            }
            #expect(max(w, h) >= minimumLongEdge, "\(name) is \(w)x\(h), too small to downscale from")
        }
    }

    @Test("Shipped marks follow the <brand>-<variant> naming convention")
    func shippedMarksAreNamedCorrectly() throws {
        for url in Self.shippedMarkURLs() {
            let stem = url.deletingPathExtension().lastPathComponent
            guard let dash = stem.lastIndex(of: "-") else {
                Issue.record("\(stem) should be named <brand-key>-<variant>"); continue
            }
            let variant = String(stem[stem.index(after: dash)...])
            #expect(Self.variants.contains(variant),
                    "\(stem) variant should be one of \(Self.variants), got '\(variant)'")
        }
    }
}

/// Resolving a photo's manufacturer to a brand mark. The user never picks the
/// brand — a photo can only carry the mark of the device that took it.
@Suite("Brand resolution")
struct BrandResolutionTests {

    @Test("Every shipped brand resolves from the way it writes itself into EXIF")
    func realWorldMakeStrings() {
        let cases: [(String, String)] = [
            ("Apple", "apple"),
            ("Canon", "canon"), ("CANON", "canon"),
            ("NIKON CORPORATION", "nikon"), ("Nikon", "nikon"),
            ("SONY", "sony"),
            ("FUJIFILM", "fujifilm"),
            ("LEICA CAMERA AG", "leica"),
            ("OLYMPUS CORPORATION", "olympus"),
            ("OLYMPUS IMAGING CORP.", "olympus"),
            ("OM Digital Solutions", "olympus"),
            ("Panasonic", "panasonic"),
            ("PENTAX Corporation", "pentax"),
            ("RICOH IMAGING COMPANY, LTD.", "pentax"),
            ("samsung", "samsung"), ("SAMSUNG", "samsung"),
            ("Google", "google"),
            ("Xiaomi", "xiaomi"),
            ("HUAWEI", "huawei"),
            ("HONOR", "honor"),
            ("OnePlus", "oneplus"),
            ("OPPO", "oppo"), ("vivo", "vivo"),
            ("realme", "realme"),
            ("motorola", "motorola"),
            ("Nothing Technology", "nothing"),
            ("DJI", "dji"), ("GoPro", "gopro"),
            ("Hasselblad", "hasselblad"),
            ("Arashi Vision", "insta360"),
        ]
        for (make, expected) in cases {
            #expect(BrandMarkRegistry.brandKey(make: make, model: nil) == expected,
                    "\(make) should resolve to \(expected)")
        }
    }

    @Test("A sub-brand is told apart by its model, not its make")
    func subBrandNeedsTheModel() {
        // Redmi phones write Make=Xiaomi; make alone would give every Redmi the
        // Xiaomi mark.
        #expect(BrandMarkRegistry.brandKey(make: "Xiaomi", model: "Redmi Note 13") == "redmi")
        #expect(BrandMarkRegistry.brandKey(make: "Xiaomi", model: "Mi 11") == "xiaomi")
    }

    @Test("Unknown or absent manufacturers resolve to no mark")
    func unknownMakesResolveToNothing() {
        #expect(BrandMarkRegistry.brandKey(make: nil, model: nil) == nil)
        #expect(BrandMarkRegistry.brandKey(make: "", model: nil) == nil)
        #expect(BrandMarkRegistry.brandKey(make: "Kodak", model: nil) == nil)
    }

    @Test("Resolution reads the TIFF dictionary the pipeline actually carries")
    func resolvesFromMetadataDictionary() {
        let metadata: [String: Any] = ["{TIFF}": ["Make": "Apple", "Model": "iPhone 6s"]]
        #expect(BrandMarkRegistry.brandKey(metadata: metadata) == "apple")
        #expect(BrandMarkRegistry.brandKey(metadata: [:]) == nil)
    }

    @Test("A resolved brand loads drawable artwork")
    func resolvedBrandLoadsArtwork() throws {
        let metadata: [String: Any] = ["{TIFF}": ["Make": "Apple"]]
        let mark = BrandMarkRegistry.mark(metadata: metadata, variant: .color, matIsLight: true)
        #expect(mark != nil, "Apple should have artwork")
        #expect((mark?.aspectRatio ?? 0) > 0)
    }

    @Test("Monochrome picks the rendition that contrasts with the mat")
    func monochromeContrastsWithTheMat() {
        // Not a user choice: dark mark on a light mat, light on a dark one.
        #expect(BrandMarkRegistry.variantNames(for: .monochrome, matIsLight: true).first == "black")
        #expect(BrandMarkRegistry.variantNames(for: .monochrome, matIsLight: false).first == "white")
        #expect(BrandMarkRegistry.variantNames(for: .color, matIsLight: true).first == "color")
    }

    @Test("Colour falls back to a mono rendition for a brand shipping no colour mark")
    func colourFallsBack() {
        // Order matters more than the first entry: a brand with only one
        // rendition still draws something.
        let order = BrandMarkRegistry.variantNames(for: .color, matIsLight: true)
        #expect(order.count > 1, "colour should have a fallback")
    }

    @Test("Every brand key in the registry has artwork on disk")
    func registryMatchesShippedArtwork() {
        for key in BrandMarkRegistry.brandKeys {
            let mark = BrandMarkRegistry.artwork(brandKey: key, variant: .color, matIsLight: true)
            #expect(mark != nil, "\(key) is in the registry but ships no artwork")
        }
    }
}
