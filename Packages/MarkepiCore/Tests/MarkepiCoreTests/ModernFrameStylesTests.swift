import CoreImage
import Foundation
import Testing
@testable import MarkepiCore

/// The twelve modern styles: their geometry, the colours they borrow from the
/// photo, and — above all — that none of them ever covers or changes a pixel
/// of the photo outside its rounded corners.
@Suite("Modern frame styles")
struct ModernFrameStylesTests {

    static let modern: [FrameStyle] = FrameStyle.allCases.filter(\.isModern)
    static let portrait = CGSize(width: 600, height: 800)
    static let landscape = CGSize(width: 800, height: 600)

    private func config(_ style: FrameStyle, caption: Bool = true, logo: Bool = true,
                        fields: [CaptionField] = WhiteFrameConfig.defaultCaptionFields) -> WhiteFrameConfig {
        WhiteFrameConfig(isEnabled: true, metadataTextEnabled: caption, captionFields: fields,
                         style: style, logoEnabled: logo)
    }

    private let metadata: [String: Any] = [
        "{TIFF}": ["Make": "Apple", "Model": "iPhone 15 Pro Max"],
        "{Exif}": ["FNumber": 1.78, "ISOSpeedRatings": [64], "FocalLenIn35mmFilm": 24,
                   "DateTimeOriginal": "2026:08:30 15:19:30"],
    ]

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
        TestImageFactory.solidColorImage(color: CGColor(red: r, green: g, blue: b, alpha: 1),
                                         size: CGSize(width: 60, height: 80)).0
    }

    private struct Bitmap {
        let width: Int, height: Int, bytes: [UInt8]
        /// Top-left origin: bitmap memory row 0 is the image's top row.
        func rgba(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let o = 4 * (width * y + x)
            return (bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3])
        }
    }

    private func bitmap(_ image: CIImage) throws -> Bitmap {
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let cg = try #require(context.createCGImage(image, from: image.extent))
        var data = [UInt8](repeating: 0, count: 4 * cg.width * cg.height)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height,
                                bitsPerComponent: 8, bytesPerRow: 4 * cg.width,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return Bitmap(width: cg.width, height: cg.height, bytes: data)
    }

    private func geometry(_ config: WhiteFrameConfig, _ size: CGSize,
                          content: Bool = true) -> FrameGeometry {
        FrameGeometry(config: config, sourceSize: size, dpi: 300, hasCaptionContent: content)
    }

    // MARK: - Model

    @Test("There are sixteen styles, twelve of them modern")
    func styleCount() {
        #expect(FrameStyle.allCases.count == 16)
        #expect(Self.modern.count == 12)
        #expect(Self.modern.allSatisfy { $0.drawsBrandMark && !$0.offersKeyline && !$0.castsShadow })
    }

    @Test("A modern style survives a save and load", arguments: modern)
    func roundTrip(style: FrameStyle) throws {
        let data = try JSONEncoder().encode(config(style))
        #expect(try JSONDecoder().decode(WhiteFrameConfig.self, from: data).style == style)
    }

    // MARK: - Geometry

    @Test("Borders follow the photo's short edge, never a fixed canvas ratio", arguments: modern)
    func proportionalBorders(style: FrameStyle) {
        let p = geometry(config(style), Self.portrait)
        let l = geometry(config(style), Self.landscape)
        #expect(p.photoRect.size == Self.portrait)
        #expect(l.photoRect.size == Self.landscape)
        // Same short edge, same borders: a landscape photo is not padded out.
        #expect(p.left == l.left && p.top == l.top && p.bottom == l.bottom && p.right == l.right)
        if style == .spine {
            #expect(p.right > p.left && p.bottom == p.left)
        } else {
            #expect(p.left == p.top && p.left == p.right && p.bottom > p.left)
        }
    }

    @Test("With nothing to say the caption band collapses", arguments: modern)
    func bandCollapses(style: FrameStyle) {
        let g = geometry(config(style), Self.portrait, content: false)
        #expect(g.bottom == g.left && g.right == g.left)
    }

    // MARK: - The photo is never touched

    @Test("The photo's area is fully transparent in every modern frame", arguments: modern)
    func photoAreaIsClear(style: FrameStyle) throws {
        let cfg = config(style)
        let g = geometry(cfg, Self.portrait)
        let frame = try WhiteFrameRenderer.render(config: cfg, geometry: g, metadata: metadata,
                                                  sourceImage: solid(0.2, 0.3, 0.7))
        let bmp = try bitmap(frame)
        #expect(bmp.width == Int(g.framedSize.width) && bmp.height == Int(g.framedSize.height))

        // Everything inside the photo except its rounded corners is clear, so
        // the photo composited beneath shows through unchanged.
        let inner = g.photoRect.insetBy(dx: g.cornerRadius, dy: 0)
        var covered = 0
        for y in stride(from: Int(inner.minY), to: Int(inner.maxY), by: 3) {
            for x in stride(from: Int(inner.minX), to: Int(inner.maxX), by: 3) where bmp.rgba(x, y).a != 0 {
                covered += 1
            }
        }
        #expect(covered == 0)
        // And the surround is opaque.
        #expect(bmp.rgba(1, 1).a == 255)
        if g.cornerRadius > 0 {
            #expect(bmp.rgba(Int(g.photoRect.minX), Int(g.photoRect.minY)).a > 0,
                    "a rounded style keeps its corners as frame")
        }
    }

    // MARK: - Colour from the photo

    @Test("Tone's border follows the photo's own colour")
    func toneFollowsPhoto() throws {
        let cfg = config(.tone, caption: false)
        let g = geometry(cfg, Self.portrait, content: false)
        let red = try bitmap(WhiteFrameRenderer.render(config: cfg, geometry: g, metadata: [:],
                                                       sourceImage: solid(0.8, 0.1, 0.1))).rgba(2, 2)
        let blue = try bitmap(WhiteFrameRenderer.render(config: cfg, geometry: g, metadata: [:],
                                                        sourceImage: solid(0.1, 0.1, 0.8))).rgba(2, 2)
        #expect(red.r > red.b)
        #expect(blue.b > blue.r)
    }

    @Test("Photo-derived styles fall back to a neutral surround without a sample",
          arguments: modern.filter(\.readsPhoto))
    func neutralFallback(style: FrameStyle) throws {
        let cfg = config(style)
        let frame = try WhiteFrameRenderer.render(config: cfg, geometry: geometry(cfg, Self.portrait),
                                                  metadata: metadata, sourceImage: nil)
        #expect(try bitmap(frame).rgba(1, 1).a == 255)
    }

    @Test("The palette reads the photo's colours and its edges")
    func palette() throws {
        let red = try #require(PhotoPalette(image: solid(0.9, 0.1, 0.1)))
        #expect(red.deep.r > 0.7 && red.deep.b < 0.3)

        // Light top half, dark bottom half.
        let ctx = CIContext()
        let top = CIImage(color: CIColor(red: 0.95, green: 0.95, blue: 0.9)).cropped(to: CGRect(x: 0, y: 40, width: 60, height: 40))
        let bottom = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 60, height: 40))
        let split = try #require(ctx.createCGImage(top.composited(over: bottom), from: CGRect(x: 0, y: 0, width: 60, height: 80)))
        let p = try #require(PhotoPalette(image: split))
        #expect(p.topEdge.luminance > 0.8)
        #expect(p.bottomEdge.luminance < 0.2)
        #expect(p.swatches().first!.luminance < p.swatches().last!.luminance)
    }

    // MARK: - Caption

    @Test("The caption says only what the Include list allows")
    func captionFollowsIncludeList() {
        let full = WhiteFrameRenderer.resolveRowCaption(config: config(.float), metadata: metadata)
        #expect(full.model == "iPhone 15 Pro Max")
        #expect(full.values.contains { $0.field == .aperture })

        let bare = WhiteFrameRenderer.resolveRowCaption(
            config: config(.float, fields: [.iso]), metadata: metadata)
        #expect(bare.model == nil && bare.moment == nil)
        #expect(bare.values.map(\.field) == [.iso])
    }

    @Test("No metadata and no logo means no caption band")
    func emptyCaption() {
        let cfg = config(.noir, logo: false)
        #expect(!WhiteFrameRenderer.hasCaptionContent(config: cfg, metadata: [:]))
        #expect(!WhiteFrameRenderer.hasCaptionContent(config: config(.swatch, logo: false), metadata: [:]))
    }
}
