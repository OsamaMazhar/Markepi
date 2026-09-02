import CoreGraphics
import Foundation
import Testing
@testable import WatermarkCore

/// Checks the shipped brand marks are loadable vector artwork.
///
/// The `gallery` frame draws these at full export resolution, so a mark that
/// is not a readable single-page PDF would either fail to draw or — worse, if
/// someone dropped in a raster — draw soft on a 48MP photo. These tests run
/// over whatever is in `Resources/Logos`, so they keep covering each brand as
/// it lands without needing a new test per brand.
@Suite("Brand mark resources")
struct BrandMarkResourceTests {

    /// Every `<brand>-<variant>.pdf` currently shipped.
    static func shippedMarkURLs() -> [URL] {
        Bundle.module.urls(forResourcesWithExtension: "pdf", subdirectory: "Logos") ?? []
    }

    @Test("Logos resource directory is bundled and reachable")
    func logosDirectoryIsBundled() throws {
        // The README always ships, so this asserts the directory itself made it
        // into the bundle — the thing that breaks if Package.swift stops
        // copying it — independently of how many brands have been supplied.
        let readme = Bundle.module.url(forResource: "README", withExtension: "md", subdirectory: "Logos")
        #expect(readme != nil, "Resources/Logos is not in the bundle; check the .copy entry in Package.swift")
    }

    @Test("Every shipped mark opens as a single-page PDF with a non-zero media box")
    func shippedMarksAreUsablePDFs() throws {
        for url in Self.shippedMarkURLs() {
            let name = url.lastPathComponent
            guard let doc = CGPDFDocument(url as CFURL) else {
                Issue.record("\(name) is not a readable PDF")
                continue
            }
            #expect(doc.numberOfPages == 1, "\(name) should have exactly 1 page, has \(doc.numberOfPages)")
            guard let page = doc.page(at: 1) else {
                Issue.record("\(name) has no page 1")
                continue
            }
            let box = page.getBoxRect(.mediaBox)
            #expect(box.width > 0 && box.height > 0, "\(name) has an empty media box")
        }
    }

    @Test("Shipped marks follow the <brand>-<variant> naming convention")
    func shippedMarksAreNamedCorrectly() throws {
        // The registry looks marks up by this name, so a typo here is a brand
        // that silently never resolves.
        for url in Self.shippedMarkURLs() {
            let stem = url.deletingPathExtension().lastPathComponent
            let parts = stem.split(separator: "-")
            #expect(parts.count == 2, "\(stem) should be named <brand-key>-<variant>")
            if parts.count == 2 {
                #expect(["color", "mono"].contains(String(parts[1])),
                        "\(stem) variant should be 'color' or 'mono'")
            }
        }
    }
}
