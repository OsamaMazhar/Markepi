import C2PA
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Paths

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
// main.swift is at <pkg>/Sources/c2pa-spike/main.swift → go up 3 to reach pkg root
let pkgRoot = scriptDir
    .deletingLastPathComponent()  // Sources/
    .deletingLastPathComponent()  // <pkg>/
let certsDir = pkgRoot.appendingPathComponent("Certs")

// Allow override via CLI args: <chain.pem> <leaf-key.pem> <input.jpg>
let args = CommandLine.arguments
let useTestAssets = args.contains("--use-test-assets")
let chainURL = useTestAssets
    ? certsDir.appendingPathComponent("test-chain.pem")
    : certsDir.appendingPathComponent("chain.pem")
let leafKeyURL = useTestAssets
    ? certsDir.appendingPathComponent("test-leaf-key.pem")
    : certsDir.appendingPathComponent("leaf-key.pem")
let fixedInputURL = useTestAssets ? URL(fileURLWithPath: "/tmp/c2pa-spike-pexels.jpg") : nil

// MARK: - Step 1: Render a solid-color JPEG test image

func makeTestJPEG() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("c2pa-spike-input-\(UUID().uuidString).jpg")
    let width = 200, height = 200
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { throw NSError(domain: "spike", code: 1) }
    ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let cgImage = ctx.makeImage() else { throw NSError(domain: "spike", code: 2) }

    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ) else { throw NSError(domain: "spike", code: 3) }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "spike", code: 4) }
    return url
}

// MARK: - Main

do {
    print("[1/5] Rendering test JPEG…")
    let inputURL = try fixedInputURL ?? makeTestJPEG()
    let shouldCleanupInput = fixedInputURL == nil
    defer { if shouldCleanupInput { try? FileManager.default.removeItem(at: inputURL) } }
    print("      ✓ \(inputURL.lastPathComponent)")

    print("[2/5] Loading signing credentials…")
    let chainPEM = try String(contentsOf: chainURL, encoding: .utf8)
    let leafKeyPEM = try String(contentsOf: leafKeyURL, encoding: .utf8)
    print("      ✓ chain.pem (\(chainPEM.count) bytes), leaf-key.pem (\(leafKeyPEM.count) bytes)")

    print("[3/5] Building manifest JSON…")
    let manifestJSON = """
    {
        "claim_generator_info": [
            {"name": "Markepi", "version": "1.0"}
        ],
        "assertions": [
            {"label": "c2pa.test", "data": {"test": true}}
        ]
    }
    """
    print("      ✓ claim_generator_info name=Markepi")

    print("[4/5] Signing (Builder/Signer/Stream API)…")
    let signerInfo = SignerInfo(
        algorithm: .es256,
        certificatePEM: chainPEM,
        privateKeyPEM: leafKeyPEM,
        tsa: nil
    )
    let signer = try Signer(info: signerInfo)
    let builder = try Builder(manifestJSON: manifestJSON)
    let sourceStream = try Stream(readFrom: inputURL)
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("c2pa-spike-output-\(UUID().uuidString).jpg")
    defer { try? FileManager.default.removeItem(at: outputURL) }
    let destStream = try Stream(writeTo: outputURL)

    let signStart = Date()
    let manifestData = try builder.sign(
        format: "image/jpeg",
        source: sourceStream,
        destination: destStream,
        signer: signer
    )
    let signMs = Int(Date().timeIntervalSince(signStart) * 1000)
    let fileExists = FileManager.default.fileExists(atPath: outputURL.path)
    let outSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
    print("      ✓ signed in \(signMs)ms, manifest \(manifestData.count) bytes, file exists=\(fileExists), output \(outSize) bytes")

    print("[5/5] Reading manifest back…")
    let readStart = Date()
    let manifestBack = try C2PA.readFile(at: outputURL)
    let readMs = Int(Date().timeIntervalSince(readStart) * 1000)
    print("      ✓ read in \(readMs)ms, \(manifestBack.count) chars")

    // Verify the claim generator is present
    let containsGenerator = manifestBack.contains("Markepi")
    let containsClaimGen = manifestBack.contains("claim_generator")

    // Print any validation_status entries honestly
    if let data = manifestBack.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let claims = json["claims"] as? [[String: Any]] {
        for claim in claims {
            if let status = claim["validation_status"] as? [[String: Any]] {
                for s in status {
                    let code = s["code"] ?? "?"
                    let url = s["url"] ?? ""
                    print("      validation_status: \(code) \(url)")
                }
            }
        }
    }

    print("")
    if containsGenerator && containsClaimGen {
        print("RESULT: PASS — signed JPEG written, manifest reads back with Markepi claim generator.")
    } else {
        print("RESULT: FAIL — manifest did not contain expected Markepi claim_generator.")
        print("Manifest excerpt:")
        print(String(manifestBack.prefix(2000)))
        exit(1)
    }

    // Print a short manifest excerpt for the record
    print("")
    print("Manifest excerpt (first 1500 chars):")
    print(String(manifestBack.prefix(1500)))

} catch {
    print("")
    print("RESULT: FAIL — \(error)")
    exit(1)
}
