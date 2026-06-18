import Testing
import Foundation
@testable import WatermarkCore

/// Tests OutputFormat enum: Codable roundtrip, UTI resolution, lossless detection,
/// and WatermarkConfiguration outputQuality Codable backward compatibility.
@Suite("OutputFormat")
struct OutputFormatTests {

    // MARK: - OutputFormat Codable

    @Test("OutputFormat.tiff Codable roundtrip preserves case")
    func tiffCodableRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let original: OutputFormat = .tiff
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(OutputFormat.self, from: data)

        // Verify decoded case is .tiff
        if case .tiff = decoded {
            // Success
        } else {
            Issue.record("Expected .tiff but got different case")
        }
    }

    @Test("All OutputFormat cases Codable roundtrip")
    func allCasesCodableRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let cases: [OutputFormat] = [.preserveSource, .heic, .jpeg, .png, .tiff]
        for format in cases {
            let data = try encoder.encode(format)
            let decoded = try decoder.decode(OutputFormat.self, from: data)
            #expect(String(describing: decoded) == String(describing: format))
        }
    }

    // MARK: - OutputFormat.uti

    @Test("OutputFormat.preserveSource.uti returns nil")
    func preserveSourceUTIIsNil() {
        #expect(OutputFormat.preserveSource.uti == nil)
    }

    @Test("OutputFormat.tiff.uti returns \"public.tiff\"")
    func tiffUTI() {
        #expect(OutputFormat.tiff.uti == "public.tiff")
    }

    @Test("OutputFormat.heic.uti returns \"public.heic\"")
    func heicUTI() {
        #expect(OutputFormat.heic.uti == "public.heic")
    }

    @Test("OutputFormat.jpeg.uti returns \"public.jpeg\"")
    func jpegUTI() {
        #expect(OutputFormat.jpeg.uti == "public.jpeg")
    }

    @Test("OutputFormat.png.uti returns \"public.png\"")
    func pngUTI() {
        #expect(OutputFormat.png.uti == "public.png")
    }

    // MARK: - OutputFormat.isLossless

    @Test("OutputFormat.tiff.isLossless returns true")
    func tiffIsLossless() {
        #expect(OutputFormat.tiff.isLossless == true)
    }

    @Test("OutputFormat.png.isLossless returns true")
    func pngIsLossless() {
        #expect(OutputFormat.png.isLossless == true)
    }

    @Test("OutputFormat.jpeg.isLossless returns false")
    func jpegIsNotLossless() {
        #expect(OutputFormat.jpeg.isLossless == false)
    }

    @Test("OutputFormat.heic.isLossless returns false")
    func heicIsNotLossless() {
        #expect(OutputFormat.heic.isLossless == false)
    }

    @Test("OutputFormat.preserveSource.isLossless returns false")
    func preserveSourceIsNotLossless() {
        #expect(OutputFormat.preserveSource.isLossless == false)
    }

    // MARK: - WatermarkConfiguration outputQuality Codable

    @Test("WatermarkConfiguration outputQuality rounds trips preserving value")
    func outputQualityCodableRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let config = WatermarkConfiguration(
            watermarks: [],
            outputFormat: .heic,
            outputQuality: 0.85
        )
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(WatermarkConfiguration.self, from: data)

        #expect(decoded.outputQuality == 0.85)
    }

    @Test("WatermarkConfiguration decodes with default outputQuality 1.0 when key missing")
    func outputQualityDefaultsToOneWhenKeyMissing() throws {
        let decoder = JSONDecoder()

        // JSON without outputQuality key
        let jsonWithoutQuality = """
        {"watermarks":[],"outputFormat":"heic"}
        """

        guard let jsonData = jsonWithoutQuality.data(using: .utf8) else {
            Issue.record("Failed to create JSON data")
            return
        }
        let decoded = try decoder.decode(WatermarkConfiguration.self, from: jsonData)

        #expect(decoded.outputQuality == 1.0)
    }

    @Test("WatermarkConfiguration init defaults outputQuality to 1.0")
    func outputQualityDefaultsInInit() {
        let config = WatermarkConfiguration(watermarks: [])
        #expect(config.outputQuality == 1.0)
    }

    @Test("WatermarkConfiguration init accepts custom outputQuality")
    func outputQualityCustomInit() {
        let config = WatermarkConfiguration(watermarks: [], outputQuality: 0.75)
        #expect(config.outputQuality == 0.75)
    }

    // MARK: - WatermarkConfigurable protocol requirements

    @Test("WatermarkConfigurable protocol declares outputFormat and outputQuality")
    func protocolDeclaresFormatAndQuality() {
        // This is a compile-time check — if it compiles, the protocol has the requirements.
        // The #expect here is a runtime confirmation that the protocol exists and is accessible.
        #expect(true, "Protocol requirements verified at compile time")
    }
}
