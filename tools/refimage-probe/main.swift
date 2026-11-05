// Probe: can ImageIO round-trip an Apple Reference Image auxiliary item
// (HEIC `uri` item / JPEG APP3 segments), i.e. can our export pipeline
// carry it through a watermark re-encode?
//
// Run: swift tools/refimage-probe/main.swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let customType = "tag:apple.com,2025:photo:metadata:provenance:processedimage"
let gainType = kCGImageAuxiliaryDataTypeHDRGainMap as String
let secret = "APPLE-REFERENCE-IMAGE-PROBE-DEADBEEF-1234"
var passCount = 0
var failCount = 0

func report(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
    ok ? (passCount += 1) : (failCount += 1)
}

func makeTestImage() -> CGImage {
    let w = 64, h = 64
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    for x in 0..<w {
        ctx.setFillColor(red: CGFloat(x) / CGFloat(w), green: 0.3, blue: 0.6, alpha: 1)
        ctx.fill(CGRect(x: x, y: 0, width: 1, height: h))
    }
    return ctx.makeImage()!
}

let auxDict: [String: Any] = [
    kCGImageAuxiliaryDataInfoData as String: Data(secret.utf8),
    "isDataFloat": false,
]

func writeHEIC(auxType: String?, aux: [String: Any]?) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, "public.heic" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, makeTestImage(), nil)
    if let auxType, let aux {
        CGImageDestinationAddAuxiliaryDataInfo(dest, auxType as CFString, aux as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

func readAux(from data: Data, type: String) -> [String: Any]? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          CGImageSourceGetCount(src) > 0 else { return nil }
    return CGImageSourceCopyAuxiliaryDataInfoAtIndex(src, 0, type as CFString) as? [String: Any]
}

func contains(_ data: Data, _ needle: String) -> Bool {
    data.range(of: Data(needle.utf8)) != nil
}

// A. Control — known gain-map type proves the harness itself works.
if let heic = writeHEIC(auxType: gainType, aux: auxDict) {
    let back = readAux(from: heic, type: gainType)
    report("A1 gain-map aux write (AddAuxiliaryDataInfo) + read back", back != nil)
    report("A2 gain-map payload bytes in container", contains(heic, secret))
} else {
    report("A1 gain-map aux write", false, "encode failed")
}

// B. Custom provenance tag via AddAuxiliaryDataInfo (the API our writer already uses).
if let heic = writeHEIC(auxType: customType, aux: auxDict) {
    report("B1 custom-tag HEIC encode succeeds", true)
    let back = readAux(from: heic, type: customType)
    report("B2 custom aux read back via API", back != nil, "\(back ?? [:])")
    report("B3 custom payload bytes in container", contains(heic, secret))
} else {
    report("B1 custom-tag HEIC encode succeeds", false, "encode failed")
}

// C. iOS-only API (CGImageDestinationAddImageAndAuxiliaryDataInfo) — skipped on macOS.

// D. CopyImageSource passthrough: does the HEIC muxer keep an unknown uri item it
// didn't create? (diagnostic for container-level fidelity)
if let src = writeHEIC(auxType: customType, aux: auxDict) {
    let outData = NSMutableData()
    if let dest = CGImageDestinationCreateWithData(outData, "public.heic" as CFString, 1, nil),
       let source = CGImageSourceCreateWithData(src as CFData, nil) {
        CGImageDestinationAddImageFromSource(dest, source, 0, nil)
        let ok = CGImageDestinationFinalize(dest)
        report("D1 CopyImageSource finalize", ok)
        report("D2 custom payload survives CopyImageSource", contains(outData as Data, secret))
    }
}

// E. The real question — re-encode path (what ImageWriter does): read aux from a
// source carrying the custom item, re-encode pixels via AddImage, re-attach aux.
// If E holds, adding "reference image aux data" to the loader/writer contract suffices.
if let src = writeHEIC(auxType: customType, aux: auxDict),
   let carried = readAux(from: src, type: customType) {
    let outData = NSMutableData()
    if let dest = CGImageDestinationCreateWithData(outData, "public.heic" as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, makeTestImage(), nil)
        CGImageDestinationAddAuxiliaryDataInfo(dest, customType as CFString, carried as CFDictionary)
        let ok = CGImageDestinationFinalize(dest)
        report("E1 re-encode with re-attached custom aux finalizes", ok)
        report("E2 custom payload survives re-encode", contains(outData as Data, secret))
    }
} else {
    print("SKIP  E — custom aux not readable via API (see B2/C2); carry-through untestable at API level")
}

// F. JPEG APP3: byte-inject an APP3 segment, then test passthrough vs re-encode.
do {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
        throw NSError(domain: "probe", code: 1)
    }
    CGImageDestinationAddImage(dest, makeTestImage(), nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "probe", code: 2) }
    var jpeg = data as Data

    // Inject APP3 right after SOI: FF E3 <len:2> <payload>
    let payload = Data(secret.utf8)
    var segment = Data([0xFF, 0xE3])
    segment.append(UInt8((payload.count + 2) >> 8))
    segment.append(UInt8((payload.count + 2) & 0xFF))
    segment.append(payload)
    jpeg.insert(contentsOf: segment, at: 2)
    report("F1 APP3-injected JPEG still parses", CGImageSourceCreateWithData(jpeg as CFData, nil) != nil)

    let out2 = NSMutableData()
    if let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
       let cdest = CGImageDestinationCreateWithData(out2, "public.jpeg" as CFString, 1, nil) {
        CGImageDestinationAddImageFromSource(cdest, source, 0, nil)
        _ = CGImageDestinationFinalize(cdest)
        report("F2 APP3 survives CopyImageSource", contains(out2 as Data, secret))
    }
    let out3 = NSMutableData()
    if let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
       let cdest = CGImageDestinationCreateWithData(out3, "public.jpeg" as CFString, 1, nil) {
        CGImageDestinationAddImage(cdest, makeTestImage(), nil)
        _ = CGImageDestinationFinalize(cdest)
        report("F3 APP3 survives AddImage re-encode (our path)", contains(out3 as Data, secret))
    }
} catch {
    report("F JPEG APP3 probe", false, "\(error)")
}

// G/H/I. Real iPhone 18 Pro sample (path from argv[1]): what does ImageIO expose,
// and what survives passthrough vs our re-encode path?
if CommandLine.arguments.count > 1 {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let data = try? Data(contentsOf: url)
    let source = data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
    guard let data, let source, CGImageSourceGetCount(source) > 0 else {
        report("G1 sample loads + parses via CGImageSource", false)
        exit(1)
    }
    do {
        let uti = (CGImageSourceGetType(source) as String?) ?? "public.jpeg"
        report("G1 sample loads + parses via CGImageSource", true)
        report("G2 provenance bytes in source container", contains(data, "provenance:processedimage"),
               "uti=\(uti)")
        let back = readAux(from: data, type: customType)
        report("G3 CGImageSourceCopyAuxiliaryDataInfoAtIndex(custom tag)", back != nil, "\(back?.keys.map { "\($0)" } ?? [])")

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let maker = props[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] ?? [:]
        report("G4 MakerApple dict present with keys", !maker.isEmpty,
               "makerKeys=\(maker.keys.count) sampleValues=\(Array(maker.values.prefix(5)))")
        let propsText = String(describing: props)
        report("G5 properties mention provenance anywhere", propsText.contains("rovenance"))

        // H. CopyImageSource passthrough (re-mux without re-encode).
        let passthrough = NSMutableData()
        if let cdest = CGImageDestinationCreateWithData(passthrough, uti as CFString, 1, nil) {
            CGImageDestinationAddImageFromSource(cdest, source, 0, nil)
            let ok = CGImageDestinationFinalize(cdest)
            report("H1 CopyImageSource finalize", ok)
            report("H2 provenance bytes survive passthrough", contains(passthrough as Data, "provenance:processedimage"))
            try? (passthrough as Data).write(to: URL(fileURLWithPath: "/tmp/refimage-sample/passthrough.out"))
        }

        // I. AddImage re-encode — the path ImageWriter uses (pixels replaced, metadata dict re-attached).
        let reencoded = NSMutableData()
        if let cdest = CGImageDestinationCreateWithData(reencoded, uti as CFString, 1, nil) {
            var writeProps = props
            writeProps[kCGImageDestinationLossyCompressionQuality as String] = 0.9
            CGImageDestinationAddImage(cdest, makeTestImage(), writeProps as CFDictionary)
            let ok = CGImageDestinationFinalize(cdest)
            report("I1 AddImage re-encode finalize", ok)
            report("I2 provenance bytes survive re-encode", contains(reencoded as Data, "provenance:processedimage"))
            let reSource = CGImageSourceCreateWithData(reencoded as CFData, nil)
            let reProps = reSource.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) } as? [String: Any] ?? [:]
            let reMaker = reProps[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] ?? [:]
            report("I3 MakerApple dict survives re-encode", !reMaker.isEmpty,
                   "makerKeys=\(reMaker.keys.count)")
            try? (reencoded as Data).write(to: URL(fileURLWithPath: "/tmp/refimage-sample/reencoded.out"))
        }
    }
}

print("\n\(passCount) passed, \(failCount) failed")
