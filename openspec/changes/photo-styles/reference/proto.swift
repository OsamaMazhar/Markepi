// Prototype of the photo-styles recipes (design D1/D2/D4/D6). Renders tiles for the sample sheets.
// usage: swift proto.swift <outdir> <image>...
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import ImageIO
import UniformTypeIdentifiers

struct Tint { var r, g, b, amt: Double }
struct Recipe {
    var name: String
    var mix: [Double]? = nil          // 3 luma weights for B&W
    var contrast = 0.0, gamma = 1.0, fade = 0.0, shoulder = 0.0
    var rgbGamma = (1.0, 1.0, 1.0)
    var shadow: Tint? = nil, highlight: Tint? = nil
    var saturation = 1.0, vibrance = 0.0, warmth = 0.0
    var skinHue = 0.0, skinSat = 0.0, skinTint = (0.0, 0.0, 0.0)
    var grain = 0.0, grainSize = 1.0, halation = 0.0
    var undertone = false
}

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func sCurve(_ x: Double, _ c: Double) -> Double {
    let s = x * x * (3 - 2 * x)
    return c >= 0 ? x + (s - x) * c : x - (s - x) * (-c)
}
func rgbToHsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
    var h = 0.0
    if d > 1e-6 {
        if mx == r { h = (g - b) / d } else if mx == g { h = 2 + (b - r) / d } else { h = 4 + (r - g) / d }
        h *= 60; if h < 0 { h += 360 }
    }
    return (h, mx == 0 ? 0 : d / mx, mx)
}
func hsvToRgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
    let c = v * s, hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
    let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
    let (r, g, b): (Double, Double, Double)
    switch Int(hh) { case 0: (r, g, b) = (c, x, 0); case 1: (r, g, b) = (x, c, 0); case 2: (r, g, b) = (0, c, x)
    case 3: (r, g, b) = (0, x, c); case 4: (r, g, b) = (x, 0, c); default: (r, g, b) = (c, 0, x) }
    return (r + m, g + m, b + m)
}
/// Weight of "skin-like" hues (orange/red band) — used by undertones and the skin key.
func skinHueWeight(_ h: Double, _ s: Double) -> Double {
    let center = 22.0, width = 28.0
    var d = abs(h - center); if d > 180 { d = 360 - d }
    let hw = max(0, 1 - d / width)
    let sw = clamp((s - 0.08) / 0.12) * clamp((0.75 - s) / 0.2)
    return hw * hw * (3 - 2 * hw) * sw
}

func transform(_ rgb: (Double, Double, Double), _ p: Recipe, skinScale: Double) -> (Double, Double, Double) {
    var (r, g, b) = rgb
    // warmth
    r = clamp(r * (1 + p.warmth)); b = clamp(b * (1 - p.warmth))
    // contrast + midtone gamma
    r = pow(sCurve(r, p.contrast), p.gamma * p.rgbGamma.0)
    g = pow(sCurve(g, p.contrast), p.gamma * p.rgbGamma.1)
    b = pow(sCurve(b, p.contrast), p.gamma * p.rgbGamma.2)
    let L = 0.2126 * r + 0.7152 * g + 0.0722 * b
    // split toning
    if let t = p.shadow { let w = pow(1 - L, 2) * t.amt; r += (t.r - 0.5) * w; g += (t.g - 0.5) * w; b += (t.b - 0.5) * w }
    if let t = p.highlight { let w = L * L * t.amt; r += (t.r - 0.5) * w; g += (t.g - 0.5) * w; b += (t.b - 0.5) * w }
    r = clamp(r); g = clamp(g); b = clamp(b)
    // saturation + vibrance + skin-band hue work
    var (h, s, v) = rgbToHsv(r, g, b)
    let sw = skinHueWeight(h, s) * skinScale
    h += p.skinHue * sw
    s *= 1 + p.skinSat * sw
    s = s * p.saturation
    s += p.vibrance * s * (1 - s)
    (r, g, b) = hsvToRgb(h, clamp(s), v)
    r += p.skinTint.0 * sw; g += p.skinTint.1 * sw; b += p.skinTint.2 * sw
    // B&W channel mix
    if let m = p.mix { let y = clamp(m[0] * r + m[1] * g + m[2] * b); (r, g, b) = (y, y, y) }
    // fade (lifted blacks) + shoulder (soft whites)
    func print(_ x: Double) -> Double { p.fade + clamp(x) * (1 - p.fade - p.shoulder) }
    return (print(r), print(g), print(b))
}

let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let cubeN = 33
func bake(_ f: ((Double, Double, Double)) -> (Double, Double, Double)) -> Data {
    var data = [Float](repeating: 0, count: cubeN * cubeN * cubeN * 4)
    var i = 0
    for bi in 0..<cubeN { for gi in 0..<cubeN { for ri in 0..<cubeN {
        let o = f((Double(ri) / Double(cubeN - 1), Double(gi) / Double(cubeN - 1), Double(bi) / Double(cubeN - 1)))
        data[i] = Float(o.0); data[i + 1] = Float(o.1); data[i + 2] = Float(o.2); data[i + 3] = 1; i += 4
    } } }
    return data.withUnsafeBufferPointer { Data(buffer: $0) }
}
func cube(_ img: CIImage, _ data: Data) -> CIImage {
    let f = CIFilter.colorCubeWithColorSpace()
    f.inputImage = img; f.cubeDimension = Float(cubeN); f.cubeData = data; f.colorSpace = p3
    return f.outputImage!.cropped(to: img.extent)
}

// Skin key cube: output gray = skin-likelihood of the input colour.
let skinKeyCube = bake { c in let (h, s, v) = rgbToHsv(c.0, c.1, c.2); let w = skinHueWeight(h, s) * clamp((v - 0.15) / 0.2); return (w, w, w) }

func personMask(_ url: URL, extent: CGRect) -> CIImage? {
    let req = VNGeneratePersonInstanceMaskRequest()
    let handler = VNImageRequestHandler(url: url)
    guard (try? handler.perform([req])) != nil, let obs = req.results?.first, !obs.allInstances.isEmpty,
          let buf = try? obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler) else { return nil }
    let m = CIImage(cvPixelBuffer: buf)
    return m.transformed(by: .init(scaleX: extent.width / m.extent.width, y: extent.height / m.extent.height))
}

func matrix(_ i: CIImage, _ r: CIVector, _ g: CIVector, _ b: CIVector, a: CIVector = CIVector(x: 0, y: 0, z: 0, w: 1), bias: CIVector = CIVector(x: 0, y: 0, z: 0, w: 0)) -> CIImage {
    let f = CIFilter.colorMatrix(); f.inputImage = i; f.rVector = r; f.gVector = g; f.bVector = b; f.aVector = a; f.biasVector = bias
    return f.outputImage!
}
func add(_ top: CIImage, _ bottom: CIImage) -> CIImage {
    let f = CIFilter.additionCompositing(); f.inputImage = top; f.backgroundImage = bottom; return f.outputImage!
}

/// Zero-mean monochrome grain, cell size relative to the short edge (preview == export).
func grain(_ img: CIImage, amount: Double, size: Double) -> CIImage {
    let e = img.extent, short = min(e.width, e.height)
    let s = max(0.5, size * short / 1500)
    let n = CIFilter.randomGenerator().outputImage!.transformed(by: .init(scaleX: s, y: s))
        .applyingGaussianBlur(sigma: Double(s) * 0.35).cropped(to: e)
    let a = CGFloat(amount * 0.22)
    let v = CIVector(x: a, y: 0, z: 0, w: 0)
    let zeroMean = matrix(n, v, v, v, a: CIVector(x: 0, y: 0, z: 0, w: 0), bias: CIVector(x: -a / 2, y: -a / 2, z: -a / 2, w: 0))
    return add(zeroMean, img).applyingFilter("CIColorClamp").cropped(to: e)
}

func halation(_ img: CIImage, strength: Double) -> CIImage {
    let e = img.extent
    let y = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
    let tc = CIFilter.toneCurve(); tc.inputImage = matrix(img, y, y, y)
    tc.point0 = .init(x: 0, y: 0); tc.point1 = .init(x: 0.55, y: 0); tc.point2 = .init(x: 0.75, y: 0.15)
    tc.point3 = .init(x: 0.9, y: 0.7); tc.point4 = .init(x: 1, y: 1)
    let glow = tc.outputImage!.applyingFilter("CIColorClamp").clampedToExtent()
        .applyingGaussianBlur(sigma: min(e.width, e.height) * 0.012).cropped(to: e)
    let k = CGFloat(strength)
    let tinted = matrix(glow, CIVector(x: k, y: 0, z: 0, w: 0), CIVector(x: 0.3 * k, y: 0, z: 0, w: 0), CIVector(x: 0.1 * k, y: 0, z: 0, w: 0),
                        a: CIVector(x: 0, y: 0, z: 0, w: 0))
    return add(tinted, img).applyingFilter("CIColorClamp").cropped(to: e)
}

let recipes: [Recipe] = [
    // Moods
    Recipe(name: "Vibrant", contrast: 0.15, saturation: 1.22, vibrance: 0.3),
    Recipe(name: "Natural", contrast: 0.06, saturation: 1.04, warmth: 0.02),
    Recipe(name: "Luminous", contrast: -0.06, gamma: 0.84, shoulder: 0.02, highlight: Tint(r: 1, g: 0.92, b: 0.8, amt: 0.08), saturation: 1.05),
    Recipe(name: "Dramatic", contrast: 0.5, gamma: 1.12, shadow: Tint(r: 0.4, g: 0.5, b: 0.62, amt: 0.1), saturation: 0.85),
    Recipe(name: "Quiet", contrast: -0.28, gamma: 0.95, fade: 0.06, saturation: 0.68),
    Recipe(name: "Cozy", contrast: -0.05, shadow: Tint(r: 0.62, g: 0.48, b: 0.4, amt: 0.12), highlight: Tint(r: 1, g: 0.8, b: 0.5, amt: 0.14), saturation: 0.95, warmth: 0.05),
    Recipe(name: "Ethereal", contrast: -0.22, gamma: 0.88, fade: 0.12, shadow: Tint(r: 0.62, g: 0.45, b: 0.8, amt: 0.16), highlight: Tint(r: 1, g: 0.9, b: 0.95, amt: 0.08), saturation: 0.8),
    Recipe(name: "Muted B&W", mix: [0.2126, 0.7152, 0.0722], contrast: -0.15, fade: 0.08),
    Recipe(name: "Stark B&W", mix: [0.5, 0.42, 0.08], contrast: 0.65, gamma: 1.05),
    // Undertones (skin params; global = 0.3×)
    Recipe(name: "Neutral", skinHue: 3, skinSat: -0.28, undertone: true),
    Recipe(name: "Cool Rose", skinHue: -12, skinSat: -0.08, skinTint: (0.03, -0.035, 0.05), undertone: true),
    Recipe(name: "Rose Gold", skinHue: -6, skinSat: 0.16, skinTint: (0.05, 0.0, 0.02), undertone: true),
    Recipe(name: "Gold", skinHue: 9, skinSat: 0.2, skinTint: (0.03, 0.03, -0.05), undertone: true),
    Recipe(name: "Amber", skinHue: 1, skinSat: 0.32, skinTint: (0.065, 0.012, -0.065), undertone: true),
    // Film
    Recipe(name: "Portrait 400", contrast: -0.12, fade: 0.03, shadow: Tint(r: 0.35, g: 0.5, b: 0.6, amt: 0.08), highlight: Tint(r: 1, g: 0.88, b: 0.75, amt: 0.06), saturation: 0.85, warmth: 0.03, skinSat: 0.06, grain: 0.25, grainSize: 1.0),
    Recipe(name: "Golden 200", contrast: 0.12, fade: 0.02, highlight: Tint(r: 1, g: 0.82, b: 0.35, amt: 0.14), saturation: 1.1, warmth: 0.07, grain: 0.4, grainSize: 1.3),
    Recipe(name: "Chrome 100", contrast: 0.38, gamma: 1.08, shadow: Tint(r: 0.2, g: 0.45, b: 0.65, amt: 0.14), saturation: 1.14, grain: 0.15, grainSize: 0.8),
    Recipe(name: "Velvet 50", contrast: 0.3, gamma: 1.05, rgbGamma: (1.0, 0.97, 1.0), saturation: 1.45, vibrance: 0.2, grain: 0.1, grainSize: 0.7),
    Recipe(name: "Classic Neg", contrast: 0.22, fade: 0.04, shadow: Tint(r: 0.2, g: 0.6, b: 0.55, amt: 0.18), highlight: Tint(r: 1, g: 0.85, b: 0.9, amt: 0.08), saturation: 0.8, grain: 0.35, grainSize: 1.1),
    Recipe(name: "Tungsten 800", contrast: 0.1, rgbGamma: (1.04, 1.0, 0.94), shadow: Tint(r: 0.2, g: 0.5, b: 0.6, amt: 0.14), saturation: 0.95, warmth: -0.08, grain: 0.5, grainSize: 1.4, halation: 0.55),
    Recipe(name: "Silver 400", mix: [0.45, 0.45, 0.1], contrast: 0.42, fade: 0.02, grain: 0.75, grainSize: 1.5),
    Recipe(name: "Faded", contrast: -0.15, fade: 0.14, shadow: Tint(r: 0.5, g: 0.42, b: 0.6, amt: 0.1), highlight: Tint(r: 1, g: 0.88, b: 0.68, amt: 0.1), saturation: 0.7, warmth: 0.05, grain: 0.35, grainSize: 1.2),
]

let ctx = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!])
func write(_ img: CIImage, _ url: URL) {
    let cg = ctx.createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: p3)!
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    CGImageDestinationFinalize(d)
}

func render(_ r: Recipe, _ img: CIImage, skinMask: CIImage?) -> CIImage {
    var out: CIImage
    if r.undertone {
        let skin = cube(img, bake { transform($0, r, skinScale: 1) })
        let global = cube(img, bake { transform($0, r, skinScale: 0.3) })
        out = skinMask.map { skin.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: global, kCIInputMaskImageKey: $0]) } ?? global
    } else {
        out = cube(img, bake { transform($0, r, skinScale: 1) })
    }
    if r.halation > 0 { out = halation(out, strength: r.halation) }
    if r.grain > 0 { out = grain(out, amount: r.grain, size: r.grainSize) }
    return out.cropped(to: img.extent)
}

let args = CommandLine.arguments.dropFirst()
let outDir = URL(fileURLWithPath: args.first!)
let maxSide = Double(ProcessInfo.processInfo.environment["MAXSIDE"] ?? "900")!
for path in args.dropFirst() {
    let url = URL(fileURLWithPath: path)
    var img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])!
    let k = maxSide / max(img.extent.width, img.extent.height)
    img = img.transformed(by: .init(scaleX: k, y: k)).cropped(to: CGRect(x: 0, y: 0, width: (img.extent.width * k).rounded(.down), height: (img.extent.height * k).rounded(.down)))
    img = img.transformed(by: .init(translationX: -img.extent.minX, y: -img.extent.minY))
    // Skin mask = person mask × skin-colour key, feathered.
    var mask: CIImage? = nil
    if let pm = personMask(url, extent: img.extent) {
        let key = cube(img, skinKeyCube)
        let m = key.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: pm.cropped(to: img.extent)])
        mask = m.clampedToExtent().applyingGaussianBlur(sigma: min(img.extent.width, img.extent.height) * 0.004).cropped(to: img.extent)
        write(mask!, outDir.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)__mask.jpg"))
    }
    let base = url.deletingPathExtension().lastPathComponent
    write(img, outDir.appendingPathComponent("\(base)__Original.jpg"))
    for r in recipes { write(render(r, img, skinMask: mask), outDir.appendingPathComponent("\(base)__\(r.name).jpg")) }
    print("done", base, "mask:", mask != nil)
}
