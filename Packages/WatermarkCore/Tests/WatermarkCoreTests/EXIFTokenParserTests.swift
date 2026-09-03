import Testing
import Foundation
@testable import WatermarkCore

/// Tests EXIFTokenParser for all 8 token types, missing-field fallback ("--"),
/// multi-token substitution, unrecognized token passthrough, ISO dual-type
/// handling (array vs scalar), and empty input.
@Suite("EXIFTokenParser")
struct EXIFTokenParserTests {

    // MARK: - Per-Token Resolution Tests (Tests 1–8)

    @Test("substitute({camera_model}) resolves TIFF Model tag")
    func resolvesCameraModel() {
        let metadata = EXIFMetadataFactory.realisticMetadata(model: "iPhone 16 Pro")
        let result = EXIFTokenParser.substitute("{camera_model}", metadata: metadata)
        #expect(result == "iPhone 16 Pro",
                "Expected 'iPhone 16 Pro' but got '\(result)'")
    }

    @Test("substitute({lens}) resolves EXIF LensModel tag")
    func resolvesLensModel() {
        let metadata = EXIFMetadataFactory.realisticMetadata(
            lens: "iPhone 16 Pro back triple camera 6.86mm f/1.78"
        )
        let result = EXIFTokenParser.substitute("{lens}", metadata: metadata)
        // The lens keeps its name; only the focal is restated as the 35mm
        // equivalent, which is the number the Photos app shows for this module.
        #expect(result == "iPhone 16 Pro back triple camera 24mm f/1.78",
                "Expected lens model but got '\(result)'")
    }

    @Test("substitute({aperture}) resolves EXIF FNumber → f/1.8 format")
    func resolvesAperture() {
        let metadata = EXIFMetadataFactory.realisticMetadata(aperture: 1.78)
        let result = EXIFTokenParser.substitute("{aperture}", metadata: metadata)
        #expect(result == "f/1.8",
                "Expected 'f/1.8' but got '\(result)'")
    }

    @Test("substitute({focal_length}) gives the 35mm equivalent, not the optical focal")
    func resolvesFocalLength() {
        // 6.86mm is the optical focal of a known Apple module; its equivalent
        // is 24mm, which is what the Photos app shows and what a reader of the
        // caption expects. Rounding the optical to "7mm" named a focal length
        // no camera has.
        let metadata = EXIFMetadataFactory.realisticMetadata(focalLength: 6.86)
        let result = EXIFTokenParser.substitute("{focal_length}", metadata: metadata)
        #expect(result == "24mm",
                "Expected '24mm' but got '\(result)'")
    }

    @Test("substitute({shutter_speed}) resolves APEX 6.906 → 1/120")
    func resolvesShutterSpeedFraction() {
        // APEX 6.906 → exposureTime = 2^-6.906 ≈ 1/120
        let metadata = EXIFMetadataFactory.realisticMetadata(shutterSpeedAPEX: 6.906)
        let result = EXIFTokenParser.substitute("{shutter_speed}", metadata: metadata)
        #expect(result == "1/120",
                "Expected '1/120' but got '\(result)'")
    }

    @Test("substitute({shutter_speed}) resolves slow shutter as decimal seconds")
    func resolvesShutterSpeedDecimal() {
        // APEX 0 → exposureTime = 1.0s
        let metadata = EXIFMetadataFactory.realisticMetadata(shutterSpeedAPEX: 0.0)
        let result = EXIFTokenParser.substitute("{shutter_speed}", metadata: metadata)
        #expect(result == "1.0s",
                "Expected '1.0s' but got '\(result)'")
    }

    @Test("substitute({iso}) resolves EXIF ISOSpeedRatings → ISO 400")
    func resolvesISO() {
        let metadata = EXIFMetadataFactory.realisticMetadata(iso: 400)
        let result = EXIFTokenParser.substitute("{iso}", metadata: metadata)
        #expect(result == "ISO 400",
                "Expected 'ISO 400' but got '\(result)'")
    }

    @Test("substitute({date}) resolves DateTimeOriginal → locale-aware date and time")
    func resolvesDate() {
        let metadata = EXIFMetadataFactory.realisticMetadata(dateTime: "2026:06:18 14:30:00")
        let result = EXIFTokenParser.substitute("{date}", metadata: metadata)
        // Formatted, not the raw EXIF string. The time now carries a colon, so
        // the tell is the date part: EXIF writes "2026:06:18", a formatter never does.
        #expect(!result.hasPrefix("2026:06:18"),
                "Date should be formatted, not raw EXIF 'yyyy:MM:dd HH:mm:ss'. Got: '\(result)'")
        #expect(result.contains("2026"), "Date should carry the year. Got: '\(result)'")
        // Time to the minute, never seconds.
        #expect(result.filter { $0 == ":" }.count == 1,
                "Time should be hours and minutes only, no seconds. Got: '\(result)'")
        #expect(!result.isEmpty && result != "--",
                "Date should resolve to formatted date, not fallback. Got: '\(result)'")
    }

    @Test("substitute({gps}) resolves GPS Lat/Lon → decimal degrees with cardinal")
    func resolvesGPS() {
        let metadata = EXIFMetadataFactory.realisticMetadata(lat: 37.7749, lon: -122.4194)
        let result = EXIFTokenParser.substitute("{gps}", metadata: metadata)
        #expect(result.contains("37.7749"),
                "Expected latitude 37.7749° in GPS output, got: '\(result)'")
        #expect(result.contains("N"),
                "Expected 'N' for northern hemisphere, got: '\(result)'")
        #expect(result.contains("W"),
                "Expected 'W' for western hemisphere, got: '\(result)'")
        #expect(result.contains("122.4194"),
                "Expected longitude 122.4194° in GPS output, got: '\(result)'")
    }

    // MARK: - Missing Field Fallback Tests

    @Test("Missing field renders as '--' (double em dash per D-08)")
    func missingFieldRendersDoubleEmDash() {
        let metadata = EXIFMetadataFactory.minimalMetadata()
        let result = EXIFTokenParser.substitute("{lens}", metadata: metadata)
        #expect(result == "--",
                "Missing field should render as '--', got: '\(result)'")
    }

    @Test("All tokens render as '--' with empty metadata")
    func allTokensFallbackWithEmptyMetadata() {
        let metadata = EXIFMetadataFactory.minimalMetadata()
        let tokens = ["{camera_model}", "{lens}", "{aperture}", "{focal_length}",
                       "{shutter_speed}", "{iso}", "{date}", "{gps}"]
        for token in tokens {
            let result = EXIFTokenParser.substitute(token, metadata: metadata)
            #expect(result == "--",
                    "Token \(token) should render as '--' with empty metadata, got: '\(result)'")
        }
    }

    @Test("Partially missing metadata — present tokens resolve, missing fall back")
    func partialMetadataResolution() {
        // Only TIFF model present, no EXIF or GPS
        let metadata = EXIFMetadataFactory.tiffOnlyMetadata(model: "iPhone 16 Pro")
        let cameraResult = EXIFTokenParser.substitute("{camera_model}", metadata: metadata)
        #expect(cameraResult == "iPhone 16 Pro",
                "camera_model should resolve from TIFF, got: '\(cameraResult)'")

        let apertureResult = EXIFTokenParser.substitute("{aperture}", metadata: metadata)
        #expect(apertureResult == "--",
                "aperture should fallback to '--' when EXIF missing, got: '\(apertureResult)'")
    }

    // MARK: - Multi-Token Substitution

    @Test("Multiple tokens in one string all substituted correctly")
    func multiTokenSubstitution() {
        let metadata = EXIFMetadataFactory.realisticMetadata(
            model: "iPhone 16 Pro",
            aperture: 1.78,
            focalLength: 6.86,
            iso: 400
        )
        let input = "Shot on {camera_model}, {aperture}, {focal_length}, {iso}"
        let result = EXIFTokenParser.substitute(input, metadata: metadata)
        #expect(result == "Shot on iPhone 16 Pro, f/1.8, 24mm, ISO 400",
                "Multi-token substitution failed. Got: '\(result)'")
    }

    @Test("Tokens with no substring overlap substitute independently")
    func tokensNoSubstringOverlap() {
        // All 8 tokens have unique identifiers — no substring risk.
        // Verify replacing one doesn't affect others.
        let metadata = EXIFMetadataFactory.realisticMetadata(
            model: "TestCam", iso: 200
        )
        let result = EXIFTokenParser.substitute(
            "{camera_model} {iso}", metadata: metadata
        )
        #expect(result == "TestCam ISO 200",
                "Independent token substitution failed. Got: '\(result)'")
    }

    // MARK: - Unrecognized Token Passthrough

    @Test("Unrecognized token {unknown} left as-is in output")
    func unrecognizedTokenPassthrough() {
        let metadata = EXIFMetadataFactory.realisticMetadata()
        let result = EXIFTokenParser.substitute("{unknown}", metadata: metadata)
        #expect(result == "{unknown}",
                "Unrecognized tokens should be left as-is, got: '\(result)'")
    }

    @Test("Mix of recognized and unrecognized tokens")
    func mixedRecognizedUnrecognized() {
        let metadata = EXIFMetadataFactory.realisticMetadata(model: "iPhone 16 Pro")
        let result = EXIFTokenParser.substitute(
            "{camera_model} with {custom_token}", metadata: metadata
        )
        #expect(result == "iPhone 16 Pro with {custom_token}",
                "Mixed token handling failed. Got: '\(result)'")
    }

    // MARK: - ISO Dual-Type Handling (Research A4)

    @Test("ISO from [Int] array picks first element")
    func isoFromArrayPicksFirst() {
        let metadata = EXIFMetadataFactory.arrayISOMetadata(isoValues: [800, 1600])
        let result = EXIFTokenParser.substitute("{iso}", metadata: metadata)
        #expect(result == "ISO 800",
                "ISO from array should pick first element (800), got: '\(result)'")
    }

    @Test("ISO from scalar Int works")
    func isoFromScalar() {
        let metadata = EXIFMetadataFactory.scalarISOMetadata(iso: 200)
        let result = EXIFTokenParser.substitute("{iso}", metadata: metadata)
        #expect(result == "ISO 200",
                "ISO from scalar Int should format correctly, got: '\(result)'")
    }

    // MARK: - Edge Cases

    @Test("Empty text input returns empty string")
    func emptyTextReturnsEmpty() {
        let metadata = EXIFMetadataFactory.realisticMetadata()
        let result = EXIFTokenParser.substitute("", metadata: metadata)
        #expect(result == "",
                "Empty input should return empty string, got: '\(result)'")
    }

    @Test("Text with no tokens returns unchanged")
    func noTokensReturnsUnchanged() {
        let metadata = EXIFMetadataFactory.realisticMetadata()
        let text = "Plain watermark text with no tokens"
        let result = EXIFTokenParser.substitute(text, metadata: metadata)
        #expect(result == text,
                "Text without tokens should be unchanged, got: '\(result)'")
    }

    // MARK: - Formatting Edge Cases

    @Test("Shutter speed APEX -5 → 32s (long exposure decimal)")
    func shutterSpeedLongExposure() {
        // APEX -5 → exposureTime = 2^5 = 32s
        let metadata = EXIFMetadataFactory.realisticMetadata(shutterSpeedAPEX: -5.0)
        let result = EXIFTokenParser.substitute("{shutter_speed}", metadata: metadata)
        #expect(result == "32.0s",
                "Long exposure should be decimal seconds, got: '\(result)'")
    }

    @Test("Aperture f/0.95 renders as f/0.9 (%.1f floating-point rounding)")
    func apertureWideOpen() {
        let metadata = EXIFMetadataFactory.realisticMetadata(aperture: 0.95)
        let result = EXIFTokenParser.substitute("{aperture}", metadata: metadata)
        // String(format: "f/%.1f", 0.95) produces "f/0.9" due to floating-point representation
        #expect(result == "f/0.9",
                "f/0.95 with %.1f format should produce f/0.9 (FP representation), got: '\(result)'")
    }

    @Test("Focal length integer value renders without decimal")
    func focalLengthInteger() {
        let metadata = EXIFMetadataFactory.realisticMetadata(focalLength: 24.0)
        let result = EXIFTokenParser.substitute("{focal_length}", metadata: metadata)
        #expect(result == "24mm",
                "Integer focal length should render without decimals, got: '\(result)'")
    }

    @Test("Shutter speed 1/1000 renders as fraction")
    func shutterSpeedFastFraction() {
        // APEX 10 → exposureTime = 2^-10 ≈ 1/1024, rounds to 1/1000
        let metadata = EXIFMetadataFactory.realisticMetadata(shutterSpeedAPEX: 10.0)
        let result = EXIFTokenParser.substitute("{shutter_speed}", metadata: metadata)
        // 2^-10 = 1/1024, round(1024) = 1024
        #expect(result.contains("/"),
                "Fast shutter should be fractional, got: '\(result)'")
        #expect(!result.contains("."),
                "Fast shutter should not be decimal, got: '\(result)'")
    }

    @Test("GPS southern/eastern hemisphere formatting")
    func gpsSouthernEastern() {
        let metadata = EXIFMetadataFactory.realisticMetadata(lat: -33.8688, lon: 151.2093)
        let result = EXIFTokenParser.substitute("{gps}", metadata: metadata)
        #expect(result.contains("S"),
                "Negative latitude should render as S, got: '\(result)'")
        #expect(result.contains("E"),
                "Positive longitude should render as E, got: '\(result)'")
    }
}

// MARK: - Focal length

@Suite("35mm-equivalent focal length")
struct EquivalentFocalLengthTests {

    /// An unzoomed iPhone 6s frame: the file's own equivalent is sound and is
    /// used as-is. Values are this photo's real EXIF.
    private let unzoomed: [String: Any] = [
        "FocalLength": 4.15,
        "FocalLenIn35mmFilm": 29,
        "LensModel": "iPhone 6s back camera 4.15mm f/2.2",
    ]

    /// An iPhone 15 Pro Max frame at 5x. `FocalLenIn35mmFilm` reads 121 —
    /// the framing, not the lens — while Photos reports 24mm.
    private let zoomed: [String: Any] = [
        "FocalLength": 6.765,
        "FocalLenIn35mmFilm": 121,
        "DigitalZoomRatio": 2.539,
        "LensModel": "iPhone 15 Pro Max back triple camera 6.765mm f/1.78",
    ]

    @Test("A sound recorded equivalent is used unchanged")
    func trustsAGoodValue() {
        #expect(EXIFTokenParser.equivalentFocalLength(exif: unzoomed) == 29)
    }

    @Test("A zoom-inflated equivalent resolves to the lens's own")
    func correctsAnInflatedValue() {
        // 121mm implies a crop factor of 17.9, which no phone sensor has.
        #expect(EXIFTokenParser.equivalentFocalLength(exif: zoomed) == 24)
    }

    @Test("An unknown module falls back to dividing out the recorded zoom")
    func unknownModuleUndoesZoom() {
        let exif: [String: Any] = [
            "FocalLength": 8.8,          // not an Apple module
            "FocalLenIn35mmFilm": 200,
            "DigitalZoomRatio": 4.0,
        ]
        #expect(EXIFTokenParser.equivalentFocalLength(exif: exif) == 50)
    }

    @Test("Missing fields degrade instead of failing")
    func missingFields() {
        #expect(EXIFTokenParser.equivalentFocalLength(exif: [:]) == nil)
        #expect(EXIFTokenParser.equivalentFocalLength(exif: ["FocalLenIn35mmFilm": 35]) == 35)
        // An unknown optical focal with nothing to convert it by yields no
        // equivalent — the token then shows the optical focal as itself.
        #expect(EXIFTokenParser.equivalentFocalLength(exif: ["FocalLength": 50.0]) == nil)
        #expect(EXIFTokenParser.substitute("{focal_length}",
                                          metadata: ["{Exif}": ["FocalLength": 50.0]]) == "50mm")
    }

    @Test("The lens string shows the equivalent, keeping the lens's name")
    func lensStringIsRewritten() {
        let rendered = EXIFTokenParser.substitute("{lens}", metadata: ["{Exif}": zoomed])
        #expect(rendered == "iPhone 15 Pro Max back triple camera 24mm f/1.78")

        let plain = EXIFTokenParser.substitute("{lens}", metadata: ["{Exif}": unzoomed])
        #expect(plain == "iPhone 6s back camera 29mm f/2.2")
    }

    @Test("The focal-length token matches what the lens string shows")
    func tokensAgree() {
        #expect(EXIFTokenParser.substitute("{focal_length}", metadata: ["{Exif}": zoomed]) == "24mm")
        #expect(EXIFTokenParser.substitute("{focal_length}", metadata: ["{Exif}": unzoomed]) == "29mm")
    }
}

@Suite("Lens names survive the focal-length restatement")
struct LensNameIntegrityTests {

    private func lens(_ exif: [String: Any]) -> String {
        EXIFTokenParser.substitute("{lens}", metadata: ["{Exif}": exif])
    }

    @Test("A zoom lens keeps the focal range in its name")
    func zoomRangeIsUntouched() {
        // Regression: the range's "70mm" was rewritten to the shot's focal,
        // renaming an RF24-70 to an "RF24-50" — a lens Canon never made.
        let canon: [String: Any] = [
            "LensModel": "RF24-70mm F2.8 L IS USM",
            "FocalLength": 50.0,
            "FocalLenIn35mmFilm": 50,
        ]
        #expect(lens(canon) == "RF24-70mm F2.8 L IS USM")
    }

    @Test("A prime lens's name is left alone on a large sensor")
    func primeNameIsUntouched() {
        // XF35mmF1.4 is 53mm equivalent on APS-C, but "XF35mm" is the product
        // name — a crop factor of 1.5 is not phone-class, so nothing changes.
        let fuji: [String: Any] = [
            "LensModel": "XF35mmF1.4 R",
            "FocalLength": 35.0,
            "FocalLenIn35mmFilm": 53,
        ]
        #expect(lens(fuji) == "XF35mmF1.4 R")
    }

    @Test("A phone's optical focal is restated as the equivalent")
    func phoneSpecIsRestated() {
        let phone: [String: Any] = [
            "LensModel": "iPhone 6s back camera 4.15mm f/2.2",
            "FocalLength": 4.15,
            "FocalLenIn35mmFilm": 29,
        ]
        #expect(lens(phone) == "iPhone 6s back camera 29mm f/2.2")
    }

    @Test("A lens name with no millimetres at all is passed through")
    func noFocalInName() {
        let dji: [String: Any] = [
            "LensModel": "DJI Mini 3 Pro",
            "FocalLength": 6.7,
            "FocalLenIn35mmFilm": 24,
        ]
        #expect(lens(dji) == "DJI Mini 3 Pro")
    }
}
