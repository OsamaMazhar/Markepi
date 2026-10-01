import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The automatic "Markepi" mark on free exports.
///
/// Drawn by the renderers themselves (photo filter graph, video layer builder)
/// when the export policy asks for it, so it never exists as a user layer: it
/// can't show in the preview, the Layers panel, templates or saved settings.
/// It is placed against the photo's own rect — the same space user layers use
/// — so a frame's mat is never written on.
public enum BrandMark {

    /// Slots in preference order: corners, then centre, then bottom/top middle.
    /// The side middles are deliberately absent — never used.
    public static let slotOrder: [WatermarkPosition] = [
        .bottomRight, .bottomLeft, .topRight, .topLeft, .center, .bottomCenter, .topCenter,
    ]

    /// Height of the rendered text block as a fraction of the shorter side.
    /// A script face sits small in its line box, so this is a little taller
    /// than a sans would need.
    static let heightFraction: CGFloat = 0.06
    /// Cookie: a bundled, heavy-stroked script — readable at small sizes and
    /// distinct from the scripts users typically pick for their own name.
    static let fontName = "Cookie-Regular"
    /// Translucent, so the photo shows through the lockup.
    static let opacity: CGFloat = 0.72

    /// The Markepi app icon in white — the rounded tile with the "M" knocked
    /// out — cut from the app icon artwork.
    private static let icon: CIImage? = {
        guard let url = Bundle.module.url(forResource: "markepi-white", withExtension: "png", subdirectory: "Brand")
        else { return nil }
        return CIImage(contentsOf: url)
    }()

    /// The mark sized for a photo/video frame of `baseSize`: "Markepi" in a
    /// script face with the white Markepi icon on its left, translucent, with
    /// a soft dark shadow so it reads on bright and dark areas alike.
    /// The returned image's extent starts at the origin.
    public static func image(for baseSize: CGSize) -> CIImage {
        FontRegistry.registerBundledFonts()
        let text = TextWatermarkRenderer.render(config: TextWatermarkInput(
            text: "Markepi", fontSize: 96, opacity: 1, fontName: fontName))
        let target = WatermarkScaling.reference(baseSize) * heightFraction
        let k = text.extent.height > 0 ? target / text.extent.height : 1
        var glyphs = text.transformed(by: CGAffineTransform(scaleX: k, y: k))
        glyphs = glyphs.transformed(by: CGAffineTransform(translationX: -glyphs.extent.minX, y: -glyphs.extent.minY))

        // The icon on the left of the word, centred on the line.
        if let icon, icon.extent.height > 0 {
            let side = target * 0.78
            let s = side / icon.extent.height
            let placed = icon
                .transformed(by: CGAffineTransform(scaleX: s, y: s))
                .transformed(by: CGAffineTransform(
                    translationX: -icon.extent.minX * s,
                    y: (target - side) / 2 - icon.extent.minY * s))
            glyphs = placed.composited(over: glyphs.transformed(
                by: CGAffineTransform(translationX: side + target * 0.2, y: 0)))
        }

        // Flatten the small lockup to a bitmap. Left as a lazy graph, Core Image
        // samples the generated text past its crop once the larger shadow ROI
        // renders, streaking a hairline from the "k" and "p" to the frame edge.
        if let cg = CIContextProvider.shared.createCGImage(glyphs, from: glyphs.extent) {
            glyphs = CIImage(cgImage: cg)
        }

        // Shadow: the glyphs' alpha, black, blurred and nudged down.
        let blur = max(1, target * 0.12)
        let black = CIFilter.colorMatrix()
        black.inputImage = glyphs
        black.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        black.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        black.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        black.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.55)
        // Blurred against transparency — clamping would smear the icon's
        // opaque edge outward into a dark box.
        let shadow = (black.outputImage ?? glyphs)
            .applyingGaussianBlur(sigma: blur)
            .cropped(to: glyphs.extent.insetBy(dx: -blur * 3, dy: -blur * 3))
            .transformed(by: CGAffineTransform(translationX: 0, y: -target * 0.04))
        let mark = glyphs.composited(over: shadow)

        let faded = CIFilter.colorMatrix()
        faded.inputImage = mark
        faded.aVector = CIVector(x: 0, y: 0, z: 0, w: opacity)
        let out = faded.outputImage ?? mark
        return out.transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY))
    }

    /// Where the mark goes: the first slot in ``slotOrder`` whose rect touches
    /// none of `occupied`; if all overlap, the one with the least overlap
    /// (ties keep the order). Coordinates are bottom-left origin, like
    /// `PositionCalculator`; `base` is the photo's rect.
    public static func slot(
        mark: CGSize, base: CGRect, padding: CGFloat, occupied: [CGRect]
    ) -> (position: WatermarkPosition, origin: CGPoint) {
        var best: (WatermarkPosition, CGPoint, CGFloat)?
        for slot in slotOrder {
            var p = PositionCalculator.position(
                for: slot, watermarkExtent: CGRect(origin: .zero, size: mark),
                baseExtent: base, padding: padding)
            p.x += base.origin.x
            p.y += base.origin.y
            let rect = CGRect(origin: p, size: mark)
            let overlap = occupied.reduce(CGFloat(0)) { sum, o in
                let i = rect.intersection(o)
                return sum + (i.isNull ? 0 : i.width * i.height)
            }
            if overlap == 0 { return (slot, p) }
            if best == nil || overlap < best!.2 { best = (slot, p, overlap) }
        }
        return (best!.0, best!.1)
    }
}
