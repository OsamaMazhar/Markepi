import CoreImage
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The twelve modern styles (`FrameStyle.isModern`).
///
/// Like every style, the result is the frame alone: a canvas-sized image that
/// is transparent where the photo goes, which the caller composites the photo
/// under untouched. The surround — backdrops, light, shade — is built in Core
/// Image; only the caption, the mark and the swatches are drawn in Core
/// Graphics. Effects stay in Core Image for the reason `applyingShadow` gives:
/// a CG shadow offset points opposite ways on the two platform render paths.
extension WhiteFrameRenderer {

    typealias RGB = PhotoPalette.RGB

    // MARK: - Caption

    /// What the shared modern caption says: device and moment on the left,
    /// readings and place on the right.
    struct ResolvedRowCaption {
        var model: String?
        var moment: String?
        /// The readings one by one, for `readout`, which spaces them out.
        var values: [(field: CaptionField, text: String)] = []
        var place: String?
        var mark: BrandMarkArtwork?

        var valuesLine: String? {
            values.isEmpty ? nil : values.map(\.text).joined(separator: runGap)
        }
        var hasText: Bool { model != nil || moment != nil || !values.isEmpty || place != nil }
        var isEmpty: Bool { !hasText && mark == nil }
    }

    static let rowValueFields: [CaptionField] = [.focalLength, .aperture, .shutterSpeed, .iso]
    /// Lens and place only. Pixel size and file format are facts about the
    /// file, not the picture, and on these captions they read as clutter.
    static let rowPlaceFields: [CaptionField] = [.lens, .gps]

    static func resolveRowCaption(config: WhiteFrameConfig, metadata: [String: Any],
                                  withMark: Bool = true) -> ResolvedRowCaption {
        guard config.metadataTextEnabled else { return ResolvedRowCaption() }
        let shown = Set(config.captionFields)
        func value(_ field: CaptionField) -> String? {
            shown.contains(field) ? resolveSlot(.field(field), metadata: metadata, alongside: shown) : nil
        }
        func joined(_ parts: [String?]) -> String? {
            let kept = parts.compactMap { $0 }
            return kept.isEmpty ? nil : kept.joined(separator: runGap)
        }
        let typed = EXIFTokenParser.substitute(config.captionPrefix, metadata: metadata)
            .trimmingCharacters(in: .whitespaces)
        let device = value(.cameraModel) ?? value(.maker)
        let model = joined([typed.isEmpty ? nil : typed, device])
        return ResolvedRowCaption(
            model: model.map { $0.replacingOccurrences(of: runGap, with: " ") },
            moment: joined([value(.date), value(.time)]),
            values: rowValueFields.compactMap { f in value(f).map { (f, $0) } },
            place: joined(rowPlaceFields.map(value)),
            mark: withMark && config.logoEnabled
                ? BrandMarkRegistry.mark(metadata: metadata, variant: .monochrome, matIsLight: true)
                : nil
        )
    }

    /// Swatch's colours sit in the caption band, so like every other style it
    /// keeps the band only while the caption has something to say.
    static func hasModernCaptionContent(config: WhiteFrameConfig, metadata: [String: Any]) -> Bool {
        !resolveRowCaption(config: config, metadata: metadata).isEmpty
    }

    // MARK: - Look

    enum Surround {
        case flat(RGB)
        case graduated(top: RGB, bottom: RGB)
        case ambient
        case aura(deep: RGB, warm: RGB)
        case glow
        case sunlight(wall: RGB)
    }

    /// A soft rounded shadow cast by the photo, in fractions of its short edge.
    struct Shade {
        var color: RGB
        var opacity: CGFloat
        var blur: CGFloat
        /// Image space: +x right, +y down.
        var dx: CGFloat
        var dy: CGFloat
    }

    struct Look {
        var surround: Surround
        var ink: RGB
        var sub: RGB
        var accent: RGB? = nil
        var shades: [Shade] = []
        var debossed = false
    }

    static func look(for style: FrameStyle, palette p: PhotoPalette) -> Look {
        let dark = RGB(28, 28, 30)
        switch style {
        case .float:
            return Look(surround: .flat(RGB(246, 245, 241)), ink: dark, sub: RGB(140, 138, 134),
                        shades: [Shade(color: .black, opacity: 0.22, blur: 0.025, dx: 0, dy: 0.012)])
        case .tone:
            let deep = p.deep
            return Look(surround: .flat(PhotoPalette.hls(of: deep, lightness: 0.20, saturation: 0.45)),
                        ink: PhotoPalette.hls(of: deep, lightness: 0.92, saturationTo: 0.35),
                        sub: PhotoPalette.hls(of: deep, lightness: 0.68, saturationTo: 0.30))
        case .swatch:
            return Look(surround: .flat(.white), ink: dark, sub: RGB(140, 140, 144))
        case .spine:
            return Look(surround: .flat(RGB(250, 250, 248)), ink: dark, sub: RGB(135, 135, 140))
        case .noir:
            return Look(surround: .flat(RGB(10, 10, 11)), ink: RGB(242, 242, 244), sub: RGB(130, 130, 136))
        case .readout:
            return Look(surround: .flat(.white), ink: RGB(20, 20, 20), sub: RGB(20, 20, 20),
                        accent: RGB(245, 166, 35))
        case .ambient:
            return Look(surround: .ambient, ink: .white, sub: RGB(215, 215, 222),
                        shades: [Shade(color: .black, opacity: 0.4, blur: 0.042, dx: 0, dy: 0.018)])
        case .aura:
            let deep = p.deep
            return Look(surround: .aura(deep: deep, warm: p.warm), ink: .white, sub: RGB(220, 220, 232),
                        shades: [Shade(color: deep.mixed(with: .black, 0.7), opacity: 0.5,
                                       blur: 0.058, dx: 0, dy: 0.028)])
        case .glow:
            return Look(surround: .glow, ink: RGB(245, 245, 248), sub: RGB(150, 152, 162))
        case .blend:
            let top = p.topEdge.mixed(with: .white, 0.15)
            let bottom = p.bottomEdge.mixed(with: .black, 0.35)
            // The caption sits on the bottom tone; keep it readable on a pale one.
            let light = bottom.luminance > 0.6
            return Look(surround: .graduated(top: top, bottom: bottom),
                        ink: light ? dark : .white, sub: light ? RGB(90, 90, 96) : RGB(220, 222, 232),
                        shades: [Shade(color: .black, opacity: 0.35, blur: 0.02, dx: 0, dy: 0.008)])
        case .emboss:
            return Look(surround: .flat(RGB(231, 232, 236)), ink: RGB(84, 88, 100), sub: RGB(140, 144, 156),
                        shades: [Shade(color: RGB(120, 124, 140), opacity: 0.30, blur: 0.028, dx: 0.018, dy: 0.022),
                                 Shade(color: .white, opacity: 0.95, blur: 0.028, dx: -0.018, dy: -0.022)],
                        debossed: true)
        case .sunlight:
            return Look(surround: .sunlight(wall: RGB(236, 227, 213)), ink: RGB(48, 40, 32), sub: RGB(130, 116, 100),
                        shades: [Shade(color: RGB(90, 70, 50), opacity: 0.42, blur: 0.025, dx: -0.038, dy: 0.045)])
        case .classic, .gallery, .print, .banner:
            return Look(surround: .flat(.white), ink: dark, sub: RGB(140, 140, 144))
        }
    }

    // MARK: - Render

    static func renderModern(config: WhiteFrameConfig, geometry: FrameGeometry,
                             metadata: [String: Any], sourceImage: CGImage?) throws -> CIImage {
        let palette = config.style.readsPhoto
            ? (sourceImage.flatMap(PhotoPalette.init(image:)) ?? .neutral)
            : .neutral
        let look = look(for: config.style, palette: palette)
        let caption = resolveRowCaption(config: config, metadata: metadata)
        let size = geometry.framedSize
        let canvas = CGRect(origin: .zero, size: size)
        let photo = geometry.photoRect
        let s = min(photo.width, photo.height)
        // Core Image is y-up; the photo rect is y-down.
        let photoCI = CGRect(x: photo.minX, y: size.height - photo.maxY, width: photo.width, height: photo.height)

        var image = surround(look.surround, canvas: canvas, photoCI: photoCI, s: s,
                             sample: config.style.readsPhoto ? sourceImage : nil)
        for shade in look.shades {
            let rect = photoCI.offsetBy(dx: shade.dx * s, dy: -shade.dy * s)
            let shape = roundedRect(rect, radius: geometry.cornerRadius,
                                    color: shade.color, alpha: shade.opacity)
            image = shape.applyingGaussianBlur(sigma: Double(shade.blur * s)).composited(over: image)
        }

        let ink = try rasterize(size: size) { ctx in
            drawModernCaption(ctx, style: config.style, geometry: geometry, caption: caption,
                              look: look, palette: palette)
        }
        image = ink.composited(over: image).cropped(to: canvas)

        // Cut the photo's place out — rounded where the style rounds it. The
        // corners stay frame, which is all the rounding ever does to a photo.
        let hole = try rasterize(size: size) { ctx in
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(canvas)
            ctx.setBlendMode(.clear)
            ctx.addPath(CGPath(roundedRect: photo, cornerWidth: geometry.cornerRadius,
                               cornerHeight: geometry.cornerRadius, transform: nil))
            ctx.fillPath()
        }
        return image.applyingFilter("CISourceInCompositing",
                                    parameters: [kCIInputBackgroundImageKey: hole]).cropped(to: canvas)
    }

    // MARK: Surround

    private static func surround(_ kind: Surround, canvas: CGRect, photoCI: CGRect, s: CGFloat,
                                 sample: CGImage?) -> CIImage {
        func solid(_ c: RGB) -> CIImage { CIImage(color: ciColor(c)).cropped(to: canvas) }
        switch kind {
        case .flat(let c):
            return solid(c)
        case .graduated(let top, let bottom):
            return CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: canvas.maxY), "inputColor0": ciColor(top),
                "inputPoint1": CIVector(x: 0, y: 0), "inputColor1": ciColor(bottom),
            ])!.outputImage!.cropped(to: canvas)
        case .ambient:
            guard let sample else { return solid(RGB(52, 54, 62)) }
            let src = CIImage(cgImage: sample)
            let scale = max(canvas.width / src.extent.width, canvas.height / src.extent.height)
            let fill = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let placed = fill.transformed(by: CGAffineTransform(
                translationX: (canvas.width - fill.extent.width) / 2 - fill.extent.minX,
                y: (canvas.height - fill.extent.height) / 2 - fill.extent.minY))
            return darkened(placed.clampedToExtent().applyingGaussianBlur(sigma: Double(0.067 * s)), by: 0.72)
                .cropped(to: canvas)
        case .aura(let deep, let warm):
            var image = solid(deep.mixed(with: RGB(10, 14, 30), 0.5))
            let w = canvas.width, h = canvas.height
            let blobs: [(CGFloat, CGFloat, CGFloat, RGB)] = [
                (0.05, 0.0, 0.7, warm),
                (1.0, 0.45, 0.55, deep),
                (0.15, 1.0, 0.6, deep.mixed(with: RGB(130, 160, 255), 0.35)),
            ]
            for (x, y, r, c) in blobs {
                let clear = CIColor(red: c.r, green: c.g, blue: c.b, alpha: 0)
                let blob = CIFilter(name: "CIRadialGradient", parameters: [
                    "inputCenter": CIVector(x: x * w, y: h - y * h),
                    "inputRadius0": r * w * 0.35, "inputRadius1": r * w * 1.25,
                    "inputColor0": ciColor(c), "inputColor1": clear,
                ])!.outputImage!.cropped(to: canvas)
                image = blob.composited(over: image)
            }
            return image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.4])
                .cropped(to: canvas)
        case .glow:
            let ground = solid(RGB(12, 12, 15))
            guard let sample else { return ground }
            let src = CIImage(cgImage: sample)
            let halo = src
                .transformed(by: CGAffineTransform(scaleX: photoCI.width / src.extent.width,
                                                   y: photoCI.height / src.extent.height))
            let placed = halo.transformed(by: CGAffineTransform(
                translationX: photoCI.minX - halo.extent.minX, y: photoCI.minY - halo.extent.minY))
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.6])
                .applyingGaussianBlur(sigma: Double(0.075 * s))
            return darkened(placed, by: 0.75)
                .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: ground])
                .cropped(to: canvas)
        case .sunlight(let wall):
            let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
                "inputColor0": CIColor(red: 1, green: 1, blue: 1), "inputColor1": CIColor(red: 0, green: 0, blue: 0),
                "inputWidth": 0.05 * s, "inputCenter": CIVector(x: 0, y: 0),
            ])!.outputImage!
                .transformed(by: CGAffineTransform(rotationAngle: -28 * .pi / 180))
                .cropped(to: canvas.insetBy(dx: -s, dy: -s))
                .applyingGaussianBlur(sigma: Double(0.012 * s))
            let light = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: canvas.width * 0.8, y: canvas.height * 0.8),
                "inputRadius0": 0, "inputRadius1": 1.5 * s,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1), "inputColor1": CIColor(red: 0, green: 0, blue: 0),
            ])!.outputImage!
            let mask = darkened(stripes.applyingFilter("CIMultiplyCompositing",
                                                       parameters: [kCIInputBackgroundImageKey: light]), by: 0.55)
            return solid(RGB(150, 128, 104)).applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: solid(wall), kCIInputMaskImageKey: mask,
            ]).cropped(to: canvas)
        }
    }

    private static func darkened(_ image: CIImage, by k: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
        ])
    }

    private static func roundedRect(_ rect: CGRect, radius: CGFloat, color: RGB, alpha: CGFloat) -> CIImage {
        CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: rect), "inputRadius": radius,
            "inputColor": CIColor(red: color.r, green: color.g, blue: color.b, alpha: alpha),
        ])!.outputImage!
    }

    /// sRGB, always — an achromatic colour left in a grey space desaturates
    /// whatever it is composited with.
    private static func ciColor(_ c: RGB) -> CIColor {
        CIColor(red: c.r, green: c.g, blue: c.b, alpha: 1, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    }

    // MARK: - Drawing the caption

    private static func drawModernCaption(_ ctx: CGContext, style: FrameStyle, geometry: FrameGeometry,
                                          caption: ResolvedRowCaption, look: Look, palette: PhotoPalette) {
        let photo = geometry.photoRect
        let f = geometry.captionFontSize
        switch style {
        case .spine:
            let rail = CGRect(x: photo.maxX, y: photo.minY,
                              width: geometry.framedSize.width - photo.maxX, height: photo.height)
            drawSpine(ctx, rail: rail, font: f, caption: caption, look: look)
        default:
            let band = CGRect(x: photo.minX, y: photo.maxY, width: photo.width,
                              height: geometry.framedSize.height - photo.maxY - geometry.left)
            guard band.height > 0 else { return }
            if style == .readout {
                drawReadout(ctx, band: band, font: f, caption: caption, look: look)
            } else if style == .swatch {
                drawSwatch(ctx, band: band, font: f, caption: caption, look: look, colours: palette.swatches())
            } else {
                if look.debossed {
                    var lift = look
                    lift.ink = .white; lift.sub = .white
                    drawRow(ctx, band: band.offsetBy(dx: 0, dy: max(1, f * 0.07)), font: f,
                            caption: caption, look: lift)
                }
                drawRow(ctx, band: band, font: f, caption: caption, look: look)
            }
        }
    }

    private static func text(_ s: String, _ size: CGFloat, _ weight: CaptionWeight, _ c: RGB,
                             mono: Bool = false) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: mono ? monoFont(ofSize: size) : platformFont(ofSize: size, weight: weight),
            .foregroundColor: platformColor(from: c.cgColor),
        ])
    }

    /// The mark drawn as a silhouette in `color`, so it always matches the ink.
    private static func drawMark(_ mark: BrandMarkArtwork, in rect: CGRect, color: RGB, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        mark.draw(in: rect, context: ctx)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private static func markSize(_ mark: BrandMarkArtwork?, height: CGFloat) -> CGSize {
        guard let mark else { return .zero }
        let h = height, w = min(h * mark.aspectRatio, h * 4)
        return CGSize(width: w, height: w / mark.aspectRatio)
    }

    /// Mark + model / moment on the left; readings / place on the right.
    private static func drawRow(_ ctx: CGContext, band: CGRect, font f0: CGFloat,
                                caption: ResolvedRowCaption, look: Look) {
        func layout(_ f: CGFloat) -> (left: [NSAttributedString], right: [NSAttributedString], mark: CGSize, width: CGFloat) {
            let h = f * ModernFrameLayout.blockToFont
            let left = [caption.model.map { text($0, f, .semibold, look.ink) },
                        caption.moment.map { text($0, f * 0.76, .regular, look.sub) }]
            let right = [caption.valuesLine.map { text($0, f, .semibold, look.ink) },
                         caption.place.map { text($0, f * 0.76, .regular, look.sub) }]
            let mark = markSize(caption.mark, height: h * 0.62)
            let lw = left.compactMap { $0?.size().width }.max() ?? 0
            let rw = right.compactMap { $0?.size().width }.max() ?? 0
            let markSpace = mark.width > 0 ? mark.width + h * 0.32 : 0
            return (left.compactMap { $0 }, right.compactMap { $0 }, mark, markSpace + lw + rw + h * 0.8)
        }
        var f = f0
        var l = layout(f)
        if l.width > band.width, l.width > 0 { f *= band.width / l.width; l = layout(f) }
        let h = f * ModernFrameLayout.blockToFont
        let top = band.midY - h / 2

        var x = band.minX
        if let mark = caption.mark, l.mark.width > 0 {
            drawMark(mark, in: CGRect(x: x, y: top + (h - l.mark.height) / 2, width: l.mark.width,
                                      height: l.mark.height), color: look.ink, ctx)
            x += l.mark.width + h * 0.32
        }
        func stack(_ lines: [NSAttributedString], at x: (NSAttributedString) -> CGFloat) {
            let offsets: [CGFloat] = lines.count == 2 ? [0, h * 0.56] : [(h - (lines.first?.size().height ?? 0)) / 2]
            for (line, dy) in zip(lines, offsets) { drawLine(line, at: CGPoint(x: x(line), y: top + dy), in: ctx) }
        }
        stack(l.left) { _ in x }
        stack(l.right) { band.maxX - $0.size().width }
    }

    private static func drawSwatch(_ ctx: CGContext, band: CGRect, font f: CGFloat,
                                   caption: ResolvedRowCaption, look: Look, colours: [RGB]) {
        let r = f * 0.95
        for (i, c) in colours.enumerated() {
            let cx = band.minX + r + CGFloat(i) * r * 2.35
            ctx.setFillColor(c.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - r, y: band.midY - r, width: r * 2, height: r * 2))
        }
        let dotsEnd = band.minX + CGFloat(max(colours.count, 1)) * r * 2.35
        let h = f * ModernFrameLayout.blockToFont
        var lines = [caption.model.map { text($0, f, .semibold, look.ink) },
                     caption.valuesLine.map { text($0, f * 0.76, .regular, look.sub) }].compactMap { $0 }
        let room = band.maxX - dotsEnd - h
        let widest = lines.map { $0.size().width }.max() ?? 0
        var k: CGFloat = 1
        if widest > room, widest > 0 {
            k = room / widest
            lines = [caption.model.map { text($0, f * k, .semibold, look.ink) },
                     caption.valuesLine.map { text($0, f * 0.76 * k, .regular, look.sub) }].compactMap { $0 }
        }
        let top = band.midY - h * k / 2
        for (i, line) in lines.enumerated() {
            let dy = lines.count == 2 ? CGFloat(i) * h * k * 0.56 : (h * k - line.size().height) / 2
            drawLine(line, at: CGPoint(x: band.maxX - line.size().width, y: top + dy), in: ctx)
        }
        if let mark = caption.mark {
            let m = markSize(mark, height: h * k * 0.62)
            let blockWidth = lines.map { $0.size().width }.max() ?? 0
            drawMark(mark, in: CGRect(x: band.maxX - blockWidth - h * k * 0.35 - m.width,
                                      y: band.midY - m.height / 2, width: m.width, height: m.height),
                     color: look.ink, ctx)
        }
    }

    private static func drawReadout(_ ctx: CGContext, band: CGRect, font f0: CGFloat,
                                    caption: ResolvedRowCaption, look: Look) {
        func parts(_ f: CGFloat) -> (model: NSAttributedString?, values: [NSAttributedString], mark: CGSize, width: CGFloat) {
            let model = caption.model.map { text($0.uppercased(), f, .regular, look.ink, mono: true) }
            let values = caption.values.map { v in
                text(v.text, f, .regular, v.field == .aperture ? (look.accent ?? look.ink) : look.ink, mono: true)
            }
            let mark = markSize(caption.mark, height: f * 0.95)
            let width = (mark.width > 0 ? mark.width + f * 0.6 : 0) + (model?.size().width ?? 0)
                + values.reduce(0) { $0 + $1.size().width } + f * 1.3 * CGFloat(values.count)
            return (model, values, mark, width)
        }
        var f = f0
        var p = parts(f)
        if p.width > band.width, p.width > 0 { f *= band.width / p.width; p = parts(f) }
        let lineH = (p.model ?? p.values.first)?.size().height ?? f
        let top = band.midY - lineH / 2
        var x = band.minX
        if let mark = caption.mark, p.mark.width > 0 {
            drawMark(mark, in: CGRect(x: x, y: band.midY - p.mark.height / 2 - f * 0.05,
                                      width: p.mark.width, height: p.mark.height), color: look.ink, ctx)
            x += p.mark.width + f * 0.6
        }
        if let model = p.model { drawLine(model, at: CGPoint(x: x, y: top), in: ctx) }
        var right = band.maxX
        for value in p.values.reversed() {
            right -= value.size().width
            drawLine(value, at: CGPoint(x: right, y: top), in: ctx)
            right -= f * 1.3
        }
    }

    /// One line up the rail, read bottom to top, with the mark upright on top.
    private static func drawSpine(_ ctx: CGContext, rail: CGRect, font f0: CGFloat,
                                  caption: ResolvedRowCaption, look: Look) {
        guard rail.width > 0 else { return }
        var markHeight: CGFloat = 0
        if let mark = caption.mark {
            let m = markSize(mark, height: min(rail.width * 0.3, f0 * 1.48))
            drawMark(mark, in: CGRect(x: rail.midX - m.width / 2, y: rail.minY, width: m.width, height: m.height),
                     color: look.ink, ctx)
            markHeight = m.height
        }
        func line(_ f: CGFloat) -> NSAttributedString {
            let out = NSMutableAttributedString()
            if let model = caption.model { out.append(text(model, f, .semibold, look.ink)) }
            for part in [caption.valuesLine, caption.moment].compactMap({ $0 }) {
                out.append(text((out.length > 0 ? "     " : "") + part, f, .regular, look.sub))
            }
            return out
        }
        var f = min(f0, rail.width * 0.28)
        var run = line(f)
        let room = rail.height - markHeight - f * 1.5
        if run.size().width > room, run.size().width > 0 { f *= room / run.size().width; run = line(f) }
        guard run.length > 0 else { return }
        ctx.saveGState()
        ctx.translateBy(x: rail.midX - run.size().height / 2, y: rail.maxY)
        ctx.rotate(by: -.pi / 2)
        drawLine(run, at: .zero, in: ctx)
        ctx.restoreGState()
    }

    // MARK: - Platform

    #if canImport(UIKit)
    static func monoFont(ofSize size: CGFloat) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }
    #else
    static func monoFont(ofSize size: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }
    #endif

    /// Draws into a transparent, top-left-origin canvas and returns it as a
    /// `CIImage`, on either platform render path.
    static func rasterize(size: CGSize, _ draw: (CGContext) -> Void) throws -> CIImage {
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .extended
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
        guard let cg = image.cgImage else { throw PipelineError.frameRenderFailed }
        return CIImage(cgImage: cg)
        #else
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 4 * width, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw PipelineError.frameRenderFailed }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        draw(ctx)
        guard let cg = ctx.makeImage() else { throw PipelineError.frameRenderFailed }
        return CIImage(cgImage: cg)
        #endif
    }
}
