import CoreImage
import Foundation
import Testing
@testable import MarkepiCore

/// Covers the location caption field: the `{gps}` token rendering as a place in
/// a frame caption while still rendering as coordinates in a free text
/// watermark.
///
/// The split is not cosmetic. `TextWatermarkRenderer` draws every glyph white
/// as an alpha mask and applies the real colour through it, so a colour flag
/// pushed down that path comes out as a solid tinted rectangle. The frame
/// caption draws into a context with a real foreground colour and renders the
/// flag properly.
@Suite("Location caption")
struct LocationCaptionTests {

    /// EXIF stores unsigned magnitudes plus a hemisphere ref; this builds that
    /// shape, which is also what the app's own video path writes.
    private func gps(lat: Double, lon: Double) -> [String: Any] {
        ["{GPS}": [
            "Latitude": abs(lat),
            "LatitudeRef": lat >= 0 ? "N" : "S",
            "Longitude": abs(lon),
            "LongitudeRef": lon >= 0 ? "E" : "W",
        ] as [String: Any]]
    }

    // MARK: - Signing

    @Test("A stored magnitude plus its ref becomes a signed coordinate",
          arguments: [
            (48.8566, 2.3522, "north-east"),
            (37.7749, -122.4194, "north-west"),
            (-33.8688, 151.2093, "south-east"),
            (-23.5505, -46.6333, "south-west"),
          ])
    func signing(lat: Double, lon: Double, quadrant: String) throws {
        let signed = try #require(EXIFTokenParser.signedCoordinate(from: gps(lat: lat, lon: lon)))
        #expect(abs(signed.latitude - lat) < 1e-9, "\(quadrant) latitude lost its sign")
        #expect(abs(signed.longitude - lon) < 1e-9, "\(quadrant) longitude lost its sign")
    }

    @Test("With no hemisphere ref the stored sign is used")
    func signingWithoutRefs() throws {
        let metadata: [String: Any] = ["{GPS}": ["Latitude": -33.8688, "Longitude": 151.2093]]
        let signed = try #require(EXIFTokenParser.signedCoordinate(from: metadata))
        #expect(signed.latitude < 0)
        #expect(signed.longitude > 0)
    }

    @Test("No GPS dictionary means no coordinate")
    func signingWithoutGPS() {
        #expect(EXIFTokenParser.signedCoordinate(from: [:]) == nil)
    }

    @Test("A southern-hemisphere photo captions the country it was taken in",
          arguments: [
            (-33.8688, 151.2093, "AU", "Sydney"),
            (-23.5505, -46.6333, "BR", "São Paulo"),
          ])
    func southernHemisphereEndToEnd(lat: Double, lon: Double, code: String, place: String) {
        // Unsigned, Sydney lands in the open Pacific and São Paulo in central
        // Asia — and nothing crashes to tell you.
        let caption = EXIFTokenParser.substitute("{gps}", metadata: gps(lat: lat, lon: lon),
                                                 gpsFormat: .place)
        #expect(caption.contains(CountryResolver.localizedName(for: code)),
                "\(place) captioned as: \(caption)")
    }

    // MARK: - The two formats

    @Test("A frame caption reads as a place")
    func captionIsAPlace() {
        let caption = EXIFTokenParser.substitute("{gps}", metadata: gps(lat: 48.8566, lon: 2.3522),
                                                 gpsFormat: .place)
        #expect(caption.hasPrefix("📍 "))
        #expect(caption.hasSuffix("🇫🇷"))
        #expect(!caption.contains("°"), "a place caption should carry no raw coordinates")
    }

    @Test("The default format is still coordinates")
    func defaultIsCoordinates() {
        let text = EXIFTokenParser.substitute("{gps}", metadata: gps(lat: 48.8566, lon: 2.3522))
        #expect(text == "48.8566° N, 2.3522° E")
    }

    @Test("A free text watermark still substitutes coordinates, not a flag")
    func textWatermarkIsUnchanged() {
        // The alpha-mask non-regression. This is the entry point
        // `TextWatermarkRenderer.render(config:metadata:)` uses, and it must
        // keep producing exactly what it produced before the place format
        // existed.
        let metadata = gps(lat: -33.8688, lon: 151.2093)
        let rendered = EXIFTokenParser.substitute("Taken at {gps}", metadata: metadata)

        #expect(rendered == "Taken at 33.8688° S, 151.2093° E")
        #expect(!rendered.contains("📍"))
        #expect(!rendered.contains("🇦🇺"))
    }

    // MARK: - Missing and unresolvable

    @Test("A photo with no GPS renders the missing-field placeholder")
    func noGPSIsMissing() {
        #expect(EXIFTokenParser.substitute("{gps}", metadata: [:], gpsFormat: .place) == "--")
    }

    @Test("A coordinate in open ocean is missing, not raw coordinates")
    func unresolvableIsMissing() {
        // Never a fallback to coordinates and never a guessed country.
        let caption = EXIFTokenParser.substitute("{gps}", metadata: gps(lat: 0, lon: -140),
                                                 gpsFormat: .place)
        #expect(caption == "--")
    }

    // MARK: - Through the caption builders

    @Test("The location field is elided from a classic caption when unresolvable")
    func classicCaptionElidesMissingLocation() {
        // A metadata dictionary is `[String: Any]` and so not Sendable, which
        // rules it out as a `@Test` argument; the two cases run inline.
        let cases: [(String, [String: Any])] = [
            ("no GPS at all", [:]),
            ("open ocean", gps(lat: 0, lon: -140)),
        ]
        for (name, metadata) in cases {
            let caption = DeviceMetadataProvider.caption(
                prefix: "", fields: [.gps], metadata: metadata)
            #expect(caption.isEmpty, "\(name) should leave no caption, got: \(caption)")
        }
    }

    @Test("The location field renders as a place in a classic caption")
    func classicCaptionShowsPlace() {
        let caption = DeviceMetadataProvider.caption(
            prefix: "", fields: [.gps], metadata: gps(lat: 48.8566, lon: 2.3522))
        #expect(caption.hasPrefix("📍 "))
        #expect(caption.contains(CountryResolver.localizedName(for: "FR")))
    }

    @Test("A location alongside another field keeps the separator intact")
    func classicCaptionJoinsCleanly() {
        var metadata = gps(lat: 48.8566, lon: 2.3522)
        metadata["{TIFF}"] = ["Model": "iPhone 16 Pro"]
        let caption = DeviceMetadataProvider.caption(
            prefix: "", fields: [.cameraModel, .gps], metadata: metadata)
        #expect(caption.hasPrefix("iPhone 16 Pro · 📍 "))
    }

    @Test("Every style captions the location out of the box",
          arguments: FrameStyle.allCases)
    func everyStyleShowsTheLocationByDefault(style: FrameStyle) throws {
        // Reported as "I can't see the location pin and flag anywhere". It
        // rendered correctly in every style; nothing turned it on. This asserts
        // the default settings, not a hand-built config, which is the only
        // thing that would have caught it.
        var config = WhiteFrameConfig(isEnabled: true, style: style)
        var metadata = gps(lat: 48.8566, lon: 2.3522)
        metadata["{TIFF}"] = ["Make": "Apple", "Model": "iPhone 16 Pro"]

        let caption: String
        switch style {
        case .classic:
            caption = DeviceMetadataProvider.caption(
                prefix: config.captionPrefix, fields: config.captionFields, metadata: metadata)
        case .print:
            caption = WhiteFrameRenderer.resolveCreditCaption(
                config: config, metadata: metadata).details ?? ""
        default:
            let row = WhiteFrameRenderer.resolveRowCaption(config: config, metadata: metadata)
            caption = [row.place, row.details].compactMap { $0 }.joined(separator: " ")
        }
        // Silence the unused-mutation warning while keeping `config` a var for
        // readability above.
        config.isEnabled = true

        #expect(caption.contains("📍"), "\(style.rawValue) caption: \(caption)")
        #expect(caption.contains("🇫🇷"), "\(style.rawValue) caption: \(caption)")
    }

    @Test("A caption field renders the location as a place")
    func gallerySlotShowsPlace() throws {
        let resolved = try #require(WhiteFrameRenderer.resolveField(
            .gps, metadata: gps(lat: 48.8566, lon: 2.3522)))
        #expect(resolved.hasPrefix("📍 "))
        #expect(resolved.hasSuffix("🇫🇷"))
    }

    @Test("A caption field with an unresolvable location resolves to nothing")
    func gallerySlotElidesMissingLocation() {
        #expect(WhiteFrameRenderer.resolveField(.gps, metadata: [:]) == nil)
        #expect(WhiteFrameRenderer.resolveField(
            .gps, metadata: gps(lat: 0, lon: -140)) == nil)
    }

    @Test("Landmark, city and country are each optional and run together as one place")
    func placeFieldsCompose() {
        var metadata = gps(lat: 52.36, lon: 4.885)
        metadata[PlaceNameResolver.landmarkKey] = "Rijksmuseum"
        metadata[PlaceNameResolver.cityKey] = "Amsterdam"
        let country = CountryResolver.localizedName(for: "NL")
        func place(_ fields: Set<CaptionField>) -> String? {
            EXIFTokenParser.placeText(metadata: metadata, fields: fields)
        }
        #expect(place([.landmark, .city, .gps]) == "📍 Rijksmuseum, Amsterdam, \(country) 🇳🇱")
        #expect(place([.city]) == "📍 Amsterdam", "no country, no flag")
        #expect(place([.landmark, .gps]) == "📍 Rijksmuseum, \(country) 🇳🇱")
        #expect(place([.gps]) == "📍 \(country) 🇳🇱")
        #expect(place([.iso]) == nil)
        // The classic line draws the group once, not once per field.
        let line = DeviceMetadataProvider.caption(prefix: "", fields: [.landmark, .city, .gps],
                                                  metadata: metadata)
        #expect(line == "📍 Rijksmuseum, Amsterdam, \(country) 🇳🇱")
    }

    @Test("The place can move to a line of its own under the date")
    func placeOnOwnLine() {
        var config = WhiteFrameConfig(isEnabled: true, captionFields: [.cameraModel, .gps, .format],
                                      style: .float)
        var metadata = gps(lat: 52.36, lon: 4.885)
        metadata["_SourceUTI"] = "public.jpeg"
        let inline = WhiteFrameRenderer.resolveRowCaption(config: config, metadata: metadata)
        #expect(inline.place == nil)
        #expect(inline.details?.hasPrefix("📍") == true)
        config.placeOnOwnLine = true
        let own = WhiteFrameRenderer.resolveRowCaption(config: config, metadata: metadata)
        #expect(own.place?.hasPrefix("📍") == true)
        #expect(own.details == "JPEG")
        config.style = .readout   // a one-line style keeps it inline
        #expect(WhiteFrameRenderer.resolveRowCaption(config: config, metadata: metadata).place == nil)
    }

    @Test("Offline, a ticked city falls back to the country")
    func cityFallsBackToCountry() {
        let country = CountryResolver.localizedName(for: "NL")
        #expect(EXIFTokenParser.placeText(metadata: gps(lat: 52.36, lon: 4.885), fields: [.city])
                == "📍 \(country) 🇳🇱")
    }

    @Test("Only Landmark or City asks the geocoder")
    func countryAloneSkipsLookup() async {
        let frame = WhiteFrameConfig(isEnabled: true, captionFields: [.gps, .date])
        #expect(await PlaceNameResolver.names(for: frame, at: (52.36, 4.885)) == nil)
    }

    @Test("The pin does not get mistaken for a missing-field placeholder")
    func placeSurvivesThePlaceholderFilter() throws {
        // `resolveField` strips "--" words out of a line; a place fragment must
        // pass through it whole, pin and flag included.
        let resolved = try #require(WhiteFrameRenderer.resolveField(
            .gps, metadata: gps(lat: 43.7384, lon: 7.4246)))
        #expect(resolved == "📍 \(CountryResolver.localizedName(for: "MC")) 🇲🇨")
    }
}

/// The flag has to actually render as a colour flag.
///
/// This is the failure the whole `GPSFormat` split exists to avoid, just in the
/// other direction: a colour emoji drawn through the wrong path comes out as a
/// flat silhouette, and a missing glyph comes out as tofu. Both look like
/// "text" to any assertion that only counts dark pixels, so this one looks for
/// *saturation* — caption text is grey, a flag is not.
@Suite("Location caption renders in colour")
struct LocationFlagRenderingTests {

    /// How many pixels in the caption band are actually coloured.
    ///
    /// Saturation rather than darkness: caption text is grey, so a flag that
    /// rendered as a flat silhouette or as a tofu box would still register as
    /// "text" to anything that merely counts dark pixels.
    private func colouredCaptionPixels(fields: [CaptionField],
                                       metadata: [String: Any]) throws -> Int {
        var config = WhiteFrameConfig(
            isEnabled: true, metadataTextEnabled: true, captionFields: fields,
            style: .classic, outputDPI: 300)
        config.captionTextMillimetres = 6   // large enough to sample reliably

        let source = CGSize(width: 600, height: 400)
        let image = try WhiteFrameRenderer.render(
            config: config, sourceSize: source, metadata: metadata)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let cgImage = try #require(context.createCGImage(image, from: image.extent))

        let bytesPerRow = 4 * cgImage.width
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * cgImage.height)
        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }

        let band = FrameGeometry(config: config, sourceSize: source,
                                 dpi: 300, hasCaptionContent: true).captionBand
        var saturated = 0
        for y in Int(band.minY)..<min(Int(band.maxY), cgImage.height) {
            for x in 0..<cgImage.width {
                let offset = bytesPerRow * y + 4 * x
                guard pixels[offset + 3] > 0 else { continue }
                let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
                if max(r, max(g, b)) - min(r, min(g, b)) > 60 { saturated += 1 }
            }
        }
        return saturated
    }

    @Test("A resolved location draws colour glyphs inside the caption band")
    func flagDrawsInColour() throws {
        let metadata: [String: Any] = ["{GPS}": [
            "Latitude": 48.8566, "LatitudeRef": "N",
            "Longitude": 2.3522, "LongitudeRef": "E",
        ] as [String: Any]]
        let coloured = try colouredCaptionPixels(fields: [.gps], metadata: metadata)
        // A concatenation cannot become a `Comment`, so this stays one literal.
        #expect(coloured > 20,
                "expected colour flag pixels in the caption band, found \(coloured); a flat silhouette or a tofu box would look like this")
    }

    @Test("A photo with no location draws no colour in the band")
    func noLocationNoColour() throws {
        // The control: without a flag the same band is grey text on a white
        // mat, which is what makes the test above meaningful.
        let coloured = try colouredCaptionPixels(
            fields: [.cameraModel], metadata: ["{TIFF}": ["Model": "iPhone 16 Pro"]])
        #expect(coloured == 0, "a caption with no flag should be grey, found \(coloured) colour pixels")
    }
}
