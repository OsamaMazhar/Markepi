import CoreGraphics

/// The colours a modern frame borrows from the photo it surrounds.
///
/// Read from a small copy drawn into a fixed 48×64 bitmap, so the cost is the
/// same for a 48MP photo as for a thumbnail. Read only: nothing here writes
/// back to the photo, which is composited untouched.
struct PhotoPalette: Sendable {
    /// An sRGB colour, 0–1.
    struct RGB: Equatable, Sendable {
        var r: CGFloat, g: CGFloat, b: CGFloat

        var luminance: CGFloat { 0.2126 * r + 0.7152 * g + 0.0722 * b }
        var saturation: CGFloat { max(r, g, b) - min(r, g, b) }

        /// Any colour, converted to sRGB first (a grey `CGColor` has two components).
        init(_ color: CGColor) {
            let c = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent,
                                    options: nil)?.components ?? [0, 0, 0]
            self.init(r: c[0], g: c.count >= 3 ? c[1] : c[0], b: c.count >= 3 ? c[2] : c[0])
        }

        var cgColor: CGColor {
            CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, 1])!
        }

        func mixed(with other: RGB, _ t: CGFloat) -> RGB {
            RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
        }

        static let black = RGB(r: 0, g: 0, b: 0)
        static let white = RGB(r: 1, g: 1, b: 1)
        init(r: CGFloat, g: CGFloat, b: CGFloat) { self.r = r; self.g = g; self.b = b }
        init(_ r: Int, _ g: Int, _ b: Int) {
            self.init(r: CGFloat(r) / 255, g: CGFloat(g) / 255, b: CGFloat(b) / 255)
        }
    }

    /// The photo's dominant colours, most common first.
    let dominant: [RGB]
    /// Average of the top and bottom twelfth of the photo.
    let topEdge: RGB
    let bottomEdge: RGB

    /// What a photo-derived style draws with when it has no photo to read — a
    /// quiet warm grey rather than a failure.
    static let neutral = PhotoPalette(
        dominant: [RGB(52, 54, 62), RGB(120, 116, 110), RGB(200, 196, 188)],
        topEdge: RGB(200, 196, 188), bottomEdge: RGB(84, 86, 94))

    init(dominant: [RGB], topEdge: RGB, bottomEdge: RGB) {
        self.dominant = dominant
        self.topEdge = topEdge
        self.bottomEdge = bottomEdge
    }

    /// Reads a palette from `image`, or nil when it cannot be drawn.
    init?(image: CGImage) {
        let width = 48, height = 64
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        func pixel(_ i: Int) -> RGB {
            RGB(Int(pixels[i * 4]), Int(pixels[i * 4 + 1]), Int(pixels[i * 4 + 2]))
        }
        func average(rows: Range<Int>) -> RGB {
            var sum = RGB.black
            var n: CGFloat = 0
            for y in rows { for x in 0..<width {
                let p = pixel(y * width + x)
                sum.r += p.r; sum.g += p.g; sum.b += p.b; n += 1
            } }
            return RGB(r: sum.r / n, g: sum.g / n, b: sum.b / n)
        }
        // Memory row 0 is the image's top in a bitmap context.
        let band = max(1, height / 12)
        topEdge = average(rows: 0..<band)
        bottomEdge = average(rows: (height - band)..<height)

        // Coarse buckets (4 bits a channel), then each bucket's mean colour.
        var buckets: [Int: (sum: RGB, count: Int)] = [:]
        for i in 0..<(width * height) {
            let key = (Int(pixels[i * 4]) >> 4) << 8 | (Int(pixels[i * 4 + 1]) >> 4) << 4 | Int(pixels[i * 4 + 2]) >> 4
            let p = pixel(i)
            var entry = buckets[key] ?? (RGB.black, 0)
            entry.sum.r += p.r; entry.sum.g += p.g; entry.sum.b += p.b; entry.count += 1
            buckets[key] = entry
        }
        var ranked = buckets.values
            .map { (RGB(r: $0.sum.r / CGFloat($0.count), g: $0.sum.g / CGFloat($0.count),
                        b: $0.sum.b / CGFloat($0.count)), $0.count) }
            .sorted { $0.1 > $1.1 }
        // Merge near neighbours so one soft gradient is one colour, not five.
        var merged: [(RGB, Int)] = []
        while let head = ranked.first {
            ranked.removeFirst()
            var total = head.1
            ranked.removeAll { other in
                let d = abs(other.0.r - head.0.r) + abs(other.0.g - head.0.g) + abs(other.0.b - head.0.b)
                if d < 0.22 { total += other.1; return true }
                return false
            }
            merged.append((head.0, total))
        }
        dominant = merged.sorted { $0.1 > $1.1 }.prefix(8).map(\.0)
    }

    /// The deep, saturated anchor colour — a jacket's navy, a sky's blue.
    var deep: RGB {
        dominant.min { ($0.luminance - 1.5 * $0.saturation) < ($1.luminance - 1.5 * $1.saturation) } ?? Self.neutral.dominant[0]
    }

    /// The warmest colour — skin, sand, a hat's pink.
    var warm: RGB {
        dominant.max { ($0.r - $0.b + $0.luminance / 6) < ($1.r - $1.b + $1.luminance / 6) } ?? Self.neutral.dominant[1]
    }

    // MARK: HLS

    /// `color` with its hue kept and its lightness and saturation replaced.
    static func hls(of color: RGB, lightness: CGFloat, saturation maxS: CGFloat? = nil,
                    saturationTo s: CGFloat? = nil) -> RGB {
        let (h, _, s0) = toHLS(color)
        var sat = s ?? s0
        if let maxS { sat = min(sat, maxS) }
        return fromHLS(h, lightness, sat)
    }

    static func toHLS(_ c: RGB) -> (CGFloat, CGFloat, CGFloat) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let l = (mx + mn) / 2
        guard mx != mn else { return (0, l, 0) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: CGFloat
        if mx == c.r { h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0) }
        else if mx == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        h /= 6
        return (h, l, s)
    }

    static func fromHLS(_ h: CGFloat, _ l: CGFloat, _ s: CGFloat) -> RGB {
        guard s > 0 else { return RGB(r: l, g: l, b: l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func hue(_ t0: CGFloat) -> CGFloat {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return RGB(r: hue(h + 1 / 3), g: hue(h), b: hue(h - 1 / 3))
    }
}
