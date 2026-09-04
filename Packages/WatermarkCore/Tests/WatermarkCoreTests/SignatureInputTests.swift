import Testing
import CoreImage
@testable import WatermarkCore

/// Tests SignatureInput Codable round-trip, default values,
/// WatermarkLayer .signature case encoding/decoding, backward
/// compatibility with old configs.
@Suite("SignatureInput")
struct SignatureInputTests {

    // MARK: - Helpers

    /// Creates a minimal PKDrawing stroke data (a single line segment).
    /// We cannot import PencilKit directly in the test target without
    /// adding the framework dependency, so we construct raw stroke data
    /// that represents a valid-but-minimal PKDrawing.
    ///
    /// PKDrawing.dataRepresentation() is the `Data` blob we store.
    /// For testing, we use a hardcoded valid minimal PKDrawing.
    private func makeTestStrokeData() -> Data {
        // A pre-serialized minimal PKDrawing created by initializing
        // a PKDrawing() (empty canvas) with a single stroke and calling
        // .dataRepresentation(). This is a known-good blob.
        // Note: We cannot create this without PencilKit linkage, so
        // for tests that need valid stroke data we use the encoder
        // available via WatermarkCore's PencilKit import.
        // For basic Codable tests, any non-empty Data works — the
        // actual PKDrawing validation is in SignatureRenderer.
        return Data(repeating: 0xAB, count: 32)
    }

    // MARK: - SignatureInput Codable Round-Trip

    @Test("SignatureInput round-trip preserves strokeData, inkColor, strokeWidth")
    func testSignatureInputCodableRoundTrip() throws {
        let inkColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let input = SignatureInput(
            strokeData: makeTestStrokeData(),
            inkColor: inkColor,
            strokeWidth: 5.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(input)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SignatureInput.self, from: data)

        #expect(decoded.strokeData == input.strokeData)
        #expect(decoded.strokeWidth == 5.0)
        // Check color components
        let decodedComponents = decoded.inkColor.components ?? []
        #expect(decodedComponents.count >= 3)
        #expect(abs(decodedComponents[0] - 1.0) < 0.01) // Red
        #expect(abs(decodedComponents[1] - 0.0) < 0.01) // Green
        #expect(abs(decodedComponents[2] - 0.0) < 0.01) // Blue
    }

    // MARK: - Default Values

    @Test("SignatureInput defaults: inkColor white, strokeWidth 3.0")
    func testSignatureInputDefaultValues() throws {
        let strokeData = makeTestStrokeData()
        let input = SignatureInput(strokeData: strokeData)

        #expect(input.strokeData == strokeData)
        #expect(input.strokeWidth == 3.0)

        // Default inkColor is opaque sRGB white — what a signature renders as
        // on the photo, whatever colour the capture canvas draws in.
        let components = input.inkColor.components ?? []
        #expect(components.count == 4)
        #expect(components[0] == 1.0)
        #expect(components[1] == 1.0)
        #expect(components[2] == 1.0)
        #expect(components[3] == 1.0)
    }

    // MARK: - WatermarkLayer .signature Codable Round-Trip

    @Test("WatermarkLayer .signature round-trip through JSON")
    func testWatermarkLayerSignatureCodableRoundTrip() throws {
        let inkColor = CGColor(red: 0, green: 0, blue: 1, alpha: 1) // Blue
        let signatureInput = SignatureInput(
            strokeData: makeTestStrokeData(),
            inkColor: inkColor,
            strokeWidth: 3.0
        )

        let config = WatermarkConfiguration(watermarks: [
            .signature(signatureInput, position: .topLeft, scale: 0.2, opacity: 0.8, isVisible: true)
        ])

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WatermarkConfiguration.self, from: data)

        #expect(decoded.watermarks.count == 1)
        let layer = decoded.watermarks[0]
        #expect(layer.position == .topLeft)
        #expect(abs(layer.scale - 0.2) < 0.001)
        #expect(abs(layer.opacity - 0.8) < 0.001)
        #expect(layer.isVisible == true)

        if case .signature(let input, _, _, _, _) = layer {
            #expect(input.strokeData == signatureInput.strokeData)
            #expect(input.strokeWidth == 3.0)
        } else {
            Issue.record("Decoded layer is not .signature")
        }
    }

    // MARK: - Backward Compatibility

    @Test("Old config JSON (no signature layer) decodes without crash")
    func testOldConfigWithoutSignatureDecodes() throws {
        // JSON with only .text and .image layers — no signatureConfig key
        let oldJSON = """
        {
          "watermarks": [
            {
              "type": "text",
              "textConfig": { "text": "Hello", "fontSize": 48, "colorRGBA": [1, 1, 1, 1], "opacity": 0.8 },
              "position": "bottomRight",
              "scale": 0.15,
              "opacity": 1,
              "isVisible": true
            }
          ],
          "padding": 20
        }
        """

        let data = oldJSON.data(using: .utf8)!
        let decoder = JSONDecoder()

        // Should NOT throw — backward compatible decoding
        let config = try decoder.decode(WatermarkConfiguration.self, from: data)
        #expect(config.watermarks.count == 1)

        // Verify the layer is .text, not .signature
        if case .text = config.watermarks[0] {
            // Expected — old config decoded as text layer
        } else {
            Issue.record("Expected .text layer, got something else")
        }
    }
}
