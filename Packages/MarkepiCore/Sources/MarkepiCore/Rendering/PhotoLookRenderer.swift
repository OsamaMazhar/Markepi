import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Applies a `PhotoLook` to the photo's pixels.
///
/// Pure CIImage graph building, like the rest of the filter graph: no context,
/// no rendering. Each look is a `Recipe` (numbers, not code) baked once into a
/// 33³ colour cube; the user's tone/colour pad, film grain, halation, the skin
/// mask and intensity are cheap live filters layered on top.
///
/// The look approved in review lives in `openspec/changes/photo-styles/reference/`
/// (`proto.swift` renders the same recipes on macOS for contact sheets).
public enum PhotoLookRenderer {

    /// - Parameters:
    ///   - settings: The look and its tuning. Inactive settings return `image` itself.
    ///   - image: The upright photo (origin anywhere).
    ///   - masks: Where the skin and sky are (upright, any size). Undertones read
    ///     the skin mask — without one they apply only their light global shift;
    ///     looks with a sky treatment read the sky mask — without one, none.
    public static func apply(_ settings: PhotoLookSettings, to image: CIImage, masks: SceneMasks = .none) -> CIImage {
        guard settings.isActive, let recipe = Recipe.catalog[settings.look] else { return image }
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else { return image }

        var styled: CIImage
        if recipe.undertone {
            let skin = CubeCache.shared.apply(settings.look, recipe, skinScale: 1, to: image)
            let global = CubeCache.shared.apply(settings.look, recipe, skinScale: Recipe.undertoneGlobalShare, to: image)
            if let mask = masks.skin.map({ fitted($0, to: extent) }) {
                let blend = CIFilter.blendWithMask()
                blend.inputImage = skin
                blend.backgroundImage = global
                blend.maskImage = mask
                styled = blend.outputImage ?? global
            } else {
                styled = global
            }
        } else {
            styled = CubeCache.shared.apply(settings.look, recipe, skinScale: 1, to: image)
        }

        styled = pad(styled, tone: settings.tone, color: settings.color)
        if recipe.hasSkyTreatment, let sky = masks.sky.map({ fitted($0, to: extent) }) {
            styled = skyTreated(styled, recipe: recipe, mask: sky)
        }
        if recipe.halation > 0 { styled = halation(styled, strength: recipe.halation) }
        let grainAmount = settings.grain ?? recipe.grain
        if recipe.grain > 0 || settings.grain != nil, grainAmount > 0 {
            styled = grain(styled, amount: grainAmount, size: recipe.grainSize)
        }

        if settings.intensity < 1 {
            let mix = CIFilter.dissolveTransition()
            mix.inputImage = image
            mix.targetImage = styled
            mix.time = Float(settings.intensity)
            styled = mix.outputImage ?? styled
        }
        return styled.cropped(to: extent)
    }

    /// The film's own grain amount (what the Grain slider starts at), or nil.
    public static func defaultGrain(for look: PhotoLook) -> Double? {
        Recipe.catalog[look].flatMap { $0.grain > 0 ? $0.grain : nil }
    }

    /// Whether rendering `settings` reads the skin or sky mask.
    public static func needsMasks(_ settings: PhotoLookSettings) -> Bool {
        guard settings.isActive, let recipe = Recipe.catalog[settings.look] else { return false }
        return recipe.undertone || recipe.hasSkyTreatment
    }

    // MARK: - Live controls

    /// Tone lifts or drops the midtones with the endpoints pinned; colour warms or
    /// cools by scaling red against blue. Centre (0, 0) is a no-op.
    static func pad(_ image: CIImage, tone: Double, color: Double) -> CIImage {
        var out = image
        if tone != 0 {
            let t = CGFloat(tone) * 0.1
            let curve = CIFilter.toneCurve()
            curve.inputImage = out
            curve.point0 = CGPoint(x: 0, y: 0)
            curve.point1 = CGPoint(x: 0.25, y: 0.25 + t * 0.8)
            curve.point2 = CGPoint(x: 0.5, y: 0.5 + t)
            curve.point3 = CGPoint(x: 0.75, y: 0.75 + t * 0.6)
            curve.point4 = CGPoint(x: 1, y: 1)
            out = (curve.outputImage ?? out).applyingFilter("CIColorClamp")
        }
        if color != 0 {
            let w = CGFloat(color) * 0.08
            out = matrix(out,
                         r: CIVector(x: 1 + w, y: 0, z: 0, w: 0),
                         g: CIVector(x: 0, y: 1 + w * 0.2, z: 0, w: 0),
                         b: CIVector(x: 0, y: 0, z: 1 - w, w: 0))
                .applyingFilter("CIColorClamp")
        }
        return out
    }

    // MARK: - Sky

    /// The look's own sky: deeper or paler, more or less saturated, blended in
    /// through the sky mask so the horizon stays soft.
    static func skyTreated(_ image: CIImage, recipe: Recipe, mask: CIImage) -> CIImage {
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = Float(1 + recipe.skySaturation)
        controls.brightness = 0
        controls.contrast = 1
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = controls.outputImage ?? image
        exposure.ev = Float(recipe.skyExposure)
        let treated = (exposure.outputImage ?? image).applyingFilter("CIColorClamp")
        let blend = CIFilter.blendWithMask()
        blend.inputImage = treated
        blend.backgroundImage = image
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: image.extent)
    }

    // MARK: - Film character

    /// Zero-mean monochrome grain. The grain cell is a fixed fraction of the
    /// short edge, so a preview and a full-size export look alike; below one
    /// pixel the amplitude drops as a downsample of real grain would.
    /// `CIRandomGenerator` is a fixed noise field, so renders are repeatable.
    static func grain(_ image: CIImage, amount: Double, size: Double) -> CIImage {
        let e = image.extent
        let cell = size * Double(min(e.width, e.height)) / 1500
        let s = CGFloat(max(cell, 0.5))
        let noise = CIFilter.randomGenerator().outputImage!
            .transformed(by: CGAffineTransform(scaleX: s, y: s))
            .transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY))
            .applyingGaussianBlur(sigma: Double(s) * 0.35)
            .cropped(to: e)
            // CIRandomGenerator's alpha is random too; un-premultiplying by it
            // would blow the noise up. Take its channels as opaque colour.
            .settingAlphaOne(in: e)
        let a = CGFloat(amount * 0.22 * min(1, cell))
        // Zero-mean noise split into its bright and dark halves (both opaque,
        // non-negative), added and subtracted so alpha stays exactly 1.
        let up = CIVector(x: a, y: 0, z: 0, w: 0), down = CIVector(x: -a, y: 0, z: 0, w: 0)
        let opaque = CIVector(x: 0, y: 0, z: 0, w: 0)
        let bright = matrix(noise, r: up, g: up, b: up, a: opaque,
                            bias: CIVector(x: -a / 2, y: -a / 2, z: -a / 2, w: 1)).applyingFilter("CIColorClamp")
        let dark = matrix(noise, r: down, g: down, b: down, a: opaque,
                          bias: CIVector(x: a / 2, y: a / 2, z: a / 2, w: 1)).applyingFilter("CIColorClamp")
        return subtract(dark, from: add(bright, over: image)).cropped(to: e)
    }

    /// A soft red-orange glow bleeding from bright highlights, as on film
    /// without an anti-halation layer. Radius is a fraction of the short edge.
    static func halation(_ image: CIImage, strength: Double) -> CIImage {
        let e = image.extent
        // Linear ramp from luminance 0.6 (no glow) to 1 (full glow). A tone
        // curve was used first; its spline bulged above zero in the midtones.
        let ramp = 1 / (1 - 0.6)
        let y = CIVector(x: 0.2126 * ramp, y: 0.7152 * ramp, z: 0.0722 * ramp, w: 0)
        let highlights = matrix(image, r: y, g: y, b: y,
                                bias: CIVector(x: -0.6 * ramp, y: -0.6 * ramp, z: -0.6 * ramp, w: 0))
        let glow = highlights.applyingFilter("CIColorClamp").clampedToExtent()
            .applyingGaussianBlur(sigma: Double(min(e.width, e.height)) * 0.012)
            .cropped(to: e)
        let k = CGFloat(strength)
        let tinted = matrix(glow,
                            r: CIVector(x: k, y: 0, z: 0, w: 0),
                            g: CIVector(x: 0.3 * k, y: 0, z: 0, w: 0),
                            b: CIVector(x: 0.1 * k, y: 0, z: 0, w: 0))
        return add(tinted.cropped(to: e), over: image).cropped(to: e)
    }

    // MARK: - Helpers

    /// Typed builders only: string-keyed `CIColorMatrix` vectors were silently
    /// ignored in the prototype.
    static func matrix(_ image: CIImage, r: CIVector, g: CIVector, b: CIVector,
                       a: CIVector = CIVector(x: 0, y: 0, z: 0, w: 1),
                       bias: CIVector = CIVector(x: 0, y: 0, z: 0, w: 0)) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = r; f.gVector = g; f.bVector = b; f.aVector = a; f.biasVector = bias
        return f.outputImage ?? image
    }

    /// `bottom + top` per channel, alpha kept at 1 (both inputs opaque).
    /// `CIAdditionCompositing` sums alpha too, which then halves the colour
    /// when un-premultiplied; an alpha-0 top adds nothing at all.
    static func add(_ top: CIImage, over bottom: CIImage) -> CIImage {
        let f = CIFilter.linearDodgeBlendMode()
        f.inputImage = top
        f.backgroundImage = bottom
        return (f.outputImage ?? bottom).applyingFilter("CIColorClamp")
    }

    /// `bottom − top` per channel, alpha kept at 1.
    static func subtract(_ top: CIImage, from bottom: CIImage) -> CIImage {
        let f = CIFilter.subtractBlendMode()
        f.inputImage = top
        f.backgroundImage = bottom
        return (f.outputImage ?? bottom).applyingFilter("CIColorClamp")
    }

    /// Stretches a mask of any size and origin onto `extent`.
    static func fitted(_ mask: CIImage, to extent: CGRect) -> CIImage {
        let m = mask.extent
        guard m.width > 0, m.height > 0, m.width.isFinite, m.height.isFinite else { return mask }
        return mask
            .transformed(by: CGAffineTransform(translationX: -m.minX, y: -m.minY))
            .transformed(by: CGAffineTransform(scaleX: extent.width / m.width, y: extent.height / m.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }
}

// MARK: - Recipes

extension PhotoLookRenderer {

    /// One look, as numbers. Colour work happens in gamma-encoded Display P3.
    struct Recipe: Sendable {
        struct Tint: Sendable { var r, g, b, amount: Double }

        /// Luma weights; non-nil makes the look black-and-white (still RGB).
        var mix: [Double]? = nil
        var contrast = 0.0, gamma = 1.0, fade = 0.0, shoulder = 0.0
        var rgbGamma = (1.0, 1.0, 1.0)
        var shadow: Tint? = nil, highlight: Tint? = nil
        var saturation = 1.0, vibrance = 0.0, warmth = 0.0
        var skinHue = 0.0, skinSat = 0.0, skinTint = (0.0, 0.0, 0.0)
        var grain = 0.0, grainSize = 1.0, halation = 0.0
        var undertone = false
        /// Sky only (through the sky mask): saturation change and exposure in EV.
        var skySaturation = 0.0, skyExposure = 0.0

        var hasSkyTreatment: Bool { skySaturation != 0 || skyExposure != 0 }

        /// How much of an undertone's skin shift reaches the rest of the photo.
        static let undertoneGlobalShare = 0.3

        static let catalog: [PhotoLook: Recipe] = base.reduce(into: [:]) { out, entry in
            var recipe = entry.value
            if let sky = skyTreatments[entry.key] {
                recipe.skySaturation = sky.saturation
                recipe.skyExposure = sky.exposure
            }
            out[entry.key] = recipe
        }

        private static let base: [PhotoLook: Recipe] = [
            // Moods
            .vibrant: Recipe(contrast: 0.15, saturation: 1.22, vibrance: 0.3),
            .natural: Recipe(contrast: 0.06, saturation: 1.04, warmth: 0.02),
            .luminous: Recipe(contrast: -0.06, gamma: 0.84, shoulder: 0.02,
                              highlight: Tint(r: 1, g: 0.92, b: 0.8, amount: 0.08), saturation: 1.05),
            .dramatic: Recipe(contrast: 0.5, gamma: 1.12,
                              shadow: Tint(r: 0.4, g: 0.5, b: 0.62, amount: 0.1), saturation: 0.85),
            .quiet: Recipe(contrast: -0.28, gamma: 0.95, fade: 0.06, saturation: 0.68),
            .cozy: Recipe(contrast: -0.05, shadow: Tint(r: 0.62, g: 0.48, b: 0.4, amount: 0.12),
                          highlight: Tint(r: 1, g: 0.8, b: 0.5, amount: 0.14), saturation: 0.95, warmth: 0.05),
            .ethereal: Recipe(contrast: -0.22, gamma: 0.88, fade: 0.12,
                              shadow: Tint(r: 0.62, g: 0.45, b: 0.8, amount: 0.16),
                              highlight: Tint(r: 1, g: 0.9, b: 0.95, amount: 0.08), saturation: 0.8),
            .mutedBW: Recipe(mix: [0.2126, 0.7152, 0.0722], contrast: -0.15, fade: 0.08),
            .starkBW: Recipe(mix: [0.5, 0.42, 0.08], contrast: 0.65, gamma: 1.05),
            // Undertones (skin strength; the rest of the photo gets `undertoneGlobalShare` of it)
            .neutral: Recipe(skinHue: 3, skinSat: -0.28, undertone: true),
            .coolRose: Recipe(skinHue: -12, skinSat: -0.08, skinTint: (0.03, -0.035, 0.05), undertone: true),
            .roseGold: Recipe(skinHue: -6, skinSat: 0.16, skinTint: (0.05, 0.0, 0.02), undertone: true),
            .gold: Recipe(skinHue: 9, skinSat: 0.2, skinTint: (0.03, 0.03, -0.05), undertone: true),
            .amber: Recipe(skinHue: 1, skinSat: 0.32, skinTint: (0.065, 0.012, -0.065), undertone: true),
            // Film
            .pastel400: Recipe(contrast: -0.12, fade: 0.03, shadow: Tint(r: 0.35, g: 0.5, b: 0.6, amount: 0.08),
                                 highlight: Tint(r: 1, g: 0.88, b: 0.75, amount: 0.06), saturation: 0.85, warmth: 0.03,
                                 skinSat: 0.06, grain: 0.25, grainSize: 1.0),
            .golden200: Recipe(contrast: 0.12, fade: 0.02, highlight: Tint(r: 1, g: 0.82, b: 0.35, amount: 0.14),
                               saturation: 1.1, warmth: 0.07, grain: 0.4, grainSize: 1.3),
            .chrome100: Recipe(contrast: 0.38, gamma: 1.08, shadow: Tint(r: 0.2, g: 0.45, b: 0.65, amount: 0.14),
                               saturation: 1.14, grain: 0.15, grainSize: 0.8),
            .velvet50: Recipe(contrast: 0.3, gamma: 1.05, rgbGamma: (1.0, 0.97, 1.0), saturation: 1.45, vibrance: 0.2,
                              grain: 0.1, grainSize: 0.7),
            .classicNeg: Recipe(contrast: 0.22, fade: 0.04, shadow: Tint(r: 0.2, g: 0.6, b: 0.55, amount: 0.18),
                                highlight: Tint(r: 1, g: 0.85, b: 0.9, amount: 0.08), saturation: 0.8,
                                grain: 0.35, grainSize: 1.1),
            .tungsten800: Recipe(contrast: 0.1, rgbGamma: (1.04, 1.0, 0.94), shadow: Tint(r: 0.2, g: 0.5, b: 0.6, amount: 0.14),
                                 saturation: 0.95, warmth: -0.08, grain: 0.5, grainSize: 1.4, halation: 0.55),
            .silver400: Recipe(mix: [0.45, 0.45, 0.1], contrast: 0.42, fade: 0.02, grain: 0.75, grainSize: 1.5),
            .faded: Recipe(contrast: -0.15, fade: 0.14, shadow: Tint(r: 0.5, g: 0.42, b: 0.6, amount: 0.1),
                           highlight: Tint(r: 1, g: 0.88, b: 0.68, amount: 0.1), saturation: 0.7, warmth: 0.05,
                           grain: 0.35, grainSize: 1.2),
        ]

        /// How each look treats the sky, applied over `base`.
        static let skyTreatments: [PhotoLook: (saturation: Double, exposure: Double)] = [
            .vibrant: (0.18, -0.15), .natural: (0.06, -0.05), .luminous: (0, 0.08), .dramatic: (0.1, -0.35),
            .ethereal: (-0.1, 0.1), .starkBW: (0, -0.5),
            .golden200: (0.05, -0.05), .chrome100: (0.15, -0.2), .velvet50: (0.2, -0.2),
            .classicNeg: (-0.05, 0), .silver400: (0, -0.3),
        ]

        /// The identity recipe: bakes to an identity cube.
        static let identity = Recipe()

        /// Maps one gamma-encoded P3 colour through the recipe.
        func transform(_ rgb: (Double, Double, Double), skinScale: Double) -> (Double, Double, Double) {
            var (r, g, b) = rgb
            r = clamp(r * (1 + warmth)); b = clamp(b * (1 - warmth))
            r = pow(sCurve(r, contrast), gamma * rgbGamma.0)
            g = pow(sCurve(g, contrast), gamma * rgbGamma.1)
            b = pow(sCurve(b, contrast), gamma * rgbGamma.2)
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if let t = shadow {
                let w = pow(1 - luma, 2) * t.amount
                r += (t.r - 0.5) * w; g += (t.g - 0.5) * w; b += (t.b - 0.5) * w
            }
            if let t = highlight {
                let w = luma * luma * t.amount
                r += (t.r - 0.5) * w; g += (t.g - 0.5) * w; b += (t.b - 0.5) * w
            }
            r = clamp(r); g = clamp(g); b = clamp(b)
            if saturation != 1 || vibrance != 0 || skinHue != 0 || skinSat != 0 || skinTint != (0, 0, 0) {
                var (h, s, v) = Self.hsv(r, g, b)
                let sw = Self.skinHueWeight(h, s) * skinScale
                h += skinHue * sw
                s *= 1 + skinSat * sw
                s *= saturation
                s += vibrance * s * (1 - s)
                (r, g, b) = Self.rgb(h, clamp(s), v)
                r += skinTint.0 * sw; g += skinTint.1 * sw; b += skinTint.2 * sw
            }
            if let m = mix {
                let y = clamp(m[0] * r + m[1] * g + m[2] * b)
                (r, g, b) = (y, y, y)
            }
            func print(_ x: Double) -> Double { fade + clamp(x) * (1 - fade - shoulder) }
            return (print(r), print(g), print(b))
        }

        // MARK: Colour maths

        private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

        /// Smoothstep-based S-curve; negative contrast flattens.
        private func sCurve(_ x: Double, _ c: Double) -> Double {
            guard c != 0 else { return x }
            let s = x * x * (3 - 2 * x)
            return c >= 0 ? x + (s - x) * c : x - (s - x) * (-c)
        }

        static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
            let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
            var h = 0.0
            if d > 1e-6 {
                if mx == r { h = (g - b) / d } else if mx == g { h = 2 + (b - r) / d } else { h = 4 + (r - g) / d }
                h *= 60
                if h < 0 { h += 360 }
            }
            return (h, mx == 0 ? 0 : d / mx, mx)
        }

        static func rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
            let c = v * s
            let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
            let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
            let (r, g, b): (Double, Double, Double)
            switch Int(hh) {
            case 0: (r, g, b) = (c, x, 0)
            case 1: (r, g, b) = (x, c, 0)
            case 2: (r, g, b) = (0, c, x)
            case 3: (r, g, b) = (0, x, c)
            case 4: (r, g, b) = (x, 0, c)
            default: (r, g, b) = (c, 0, x)
            }
            return (r + m, g + m, b + m)
        }

        /// Weight of skin-like hues (the orange-red band at mid saturation).
        /// Used by undertones and by the fallback skin key.
        static func skinHueWeight(_ h: Double, _ s: Double) -> Double {
            var d = abs(h - 22)
            if d > 180 { d = 360 - d }
            let hw = max(0, 1 - d / 28)
            let lowS = min(max((s - 0.08) / 0.12, 0), 1)
            let highS = min(max((0.75 - s) / 0.2, 0), 1)
            return hw * hw * (3 - 2 * hw) * lowS * highS
        }
    }
}

// MARK: - Cube baking

extension PhotoLookRenderer {

    static let cubeDimension = 33
    static let cubeColorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CIContextProvider.workingColorSpace

    /// Bakes `f` (gamma-encoded RGB in, RGB out) into RGBA float cube data.
    static func bake(_ f: ((Double, Double, Double)) -> (Double, Double, Double)) -> Data {
        let n = cubeDimension
        var data = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        let step = 1 / Double(n - 1)
        for bi in 0..<n {
            for gi in 0..<n {
                for ri in 0..<n {
                    let o = f((Double(ri) * step, Double(gi) * step, Double(bi) * step))
                    data[i] = Float(o.0); data[i + 1] = Float(o.1); data[i + 2] = Float(o.2); data[i + 3] = 1
                    i += 4
                }
            }
        }
        return data.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func applyCube(_ data: Data, to image: CIImage) -> CIImage {
        let f = CIFilter.colorCubeWithColorSpace()
        f.inputImage = image
        f.cubeDimension = Float(cubeDimension)
        f.cubeData = data
        f.colorSpace = cubeColorSpace
        return (f.outputImage ?? image).cropped(to: image.extent)
    }

    /// Baked cubes, most recently used last. A 33³ float cube is ~575 KB, so
    /// only a handful are kept.
    final class CubeCache: @unchecked Sendable {
        static let shared = CubeCache()
        private let lock = NSLock()
        private var entries: [(key: String, data: Data)] = []
        private let capacity = 6

        func data(for look: PhotoLook, recipe: Recipe, skinScale: Double) -> Data {
            let key = "\(look.rawValue)@\(skinScale)"
            lock.lock()
            if let i = entries.firstIndex(where: { $0.key == key }) {
                let hit = entries.remove(at: i)
                entries.append(hit)
                lock.unlock()
                return hit.data
            }
            lock.unlock()
            let baked = PhotoLookRenderer.bake { recipe.transform($0, skinScale: skinScale) }
            lock.lock()
            entries.append((key, baked))
            if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
            lock.unlock()
            return baked
        }

        func apply(_ look: PhotoLook, _ recipe: Recipe, skinScale: Double, to image: CIImage) -> CIImage {
            PhotoLookRenderer.applyCube(data(for: look, recipe: recipe, skinScale: skinScale), to: image)
        }

        var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
    }
}

/// Key cubes: output gray = how skin-like / sky-like the input colour is.
extension PhotoLookRenderer {
    /// Blue sky, plus pale overcast at half weight.
    static let skyKeyCube: Data = bake { c in
        let (h, s, v) = Recipe.hsv(c.0, c.1, c.2)
        var d = abs(h - 215)
        if d > 180 { d = 360 - d }
        let hue = max(0, 1 - d / 35)
        let blue = hue * hue * (3 - 2 * hue) * min(max((s - 0.12) / 0.15, 0), 1) * min(max((v - 0.3) / 0.25, 0), 1)
        let overcast = 0.5 * min(max((0.14 - s) / 0.08, 0), 1) * min(max((v - 0.72) / 0.15, 0), 1)
        let w = max(blue, overcast)
        return (w, w, w)
    }

    static let skinKeyCube: Data = bake { c in
        let (h, s, v) = Recipe.hsv(c.0, c.1, c.2)
        let w = Recipe.skinHueWeight(h, s) * min(max((v - 0.15) / 0.2, 0), 1)
        return (w, w, w)
    }
}
