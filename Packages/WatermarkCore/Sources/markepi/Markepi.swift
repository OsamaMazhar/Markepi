// markepi — command-line front end for the same WatermarkCore pipeline the app uses.
//
// Deliberately dependency-free: a small flag parser instead of
// swift-argument-parser keeps the app's package dependency graph unchanged.
// Nothing here is imported by the app — this is an extra executable target that
// Xcode never builds (it only builds the `WatermarkCore` library product).

import CoreGraphics
import Foundation
import WatermarkCore

// MARK: - Errors

struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Flag table

private let aliases: [String: String] = [
    "-o": "--output",
    "-f": "--force",
    "-h": "--help",
]

private let boolFlags: Set<String> = [
    "--help", "--force", "--list-fonts",
    "--border", "--border-no-text", "--border-keyline", "--border-no-keyline", "--border-no-logo",
    "--date-stamp",
]

private let valueFlags: Set<String> = [
    "--output", "--format", "--quality", "--padding", "--privacy",
    "--text", "--text-position", "--text-size", "--text-font", "--text-color", "--text-opacity",
    "--logo", "--logo-position", "--logo-size", "--logo-opacity", "--logo-rotation",
    "--border-width", "--border-caption", "--border-fields", "--border-text-color", "--border-text-size",
    "--border-style", "--border-mm", "--border-caption-mm", "--border-logo-mm", "--border-dpi", "--border-logo-variant",
    "--border-left-primary", "--border-left-secondary",
    "--border-right-primary", "--border-right-secondary",
    "--date-format", "--date-size", "--date-position",
]

/// Parses a caption slot argument. A bare `CaptionField` name selects that
/// field; anything else is free text, which may carry `{tokens}`. An empty
/// string clears the slot.
func captionSlot(_ raw: String?) -> CaptionSlot? {
    guard let raw else { return nil }
    if raw.isEmpty { return .empty }
    if let field = CaptionField(rawValue: raw) { return .field(field) }
    return .text(raw)
}

struct Flags {
    var values: [String: String] = [:]
    var present: Set<String> = []
    var positionals: [String] = []

    func has(_ flag: String) -> Bool { present.contains(flag) }
    func value(_ flag: String) -> String? { values[flag] }

    /// True when the feature's `--prefix…` group was touched at all, so
    /// `--border-caption "Shot on"` works without also passing `--border`.
    func touched(prefix: String) -> Bool {
        present.contains { $0.hasPrefix(prefix) } || values.keys.contains { $0.hasPrefix(prefix) }
    }
}

func parseFlags(_ argv: [String]) throws -> Flags {
    var flags = Flags()
    var index = 0
    while index < argv.count {
        var token = argv[index]
        var inlineValue: String?

        if token.hasPrefix("--"), let equals = token.firstIndex(of: "=") {
            inlineValue = String(token[token.index(after: equals)...])
            token = String(token[..<equals])
        }
        token = aliases[token] ?? token

        if boolFlags.contains(token) {
            guard inlineValue == nil else { throw CLIError("\(token) does not take a value") }
            flags.present.insert(token)
        } else if valueFlags.contains(token) {
            if let inlineValue {
                flags.values[token] = inlineValue
            } else {
                index += 1
                guard index < argv.count else { throw CLIError("missing value for \(token)") }
                flags.values[token] = argv[index]
            }
        } else if token.hasPrefix("-"), token != "-" {
            throw CLIError("unknown option \(token) — run `markepi --help`")
        } else {
            flags.positionals.append(token)
        }
        index += 1
    }
    return flags
}

// MARK: - Value conversion

func enumValue<T: RawRepresentable & CaseIterable>(
    _ raw: String, flag: String
) throws -> T where T.RawValue == String {
    if let exact = T(rawValue: raw) { return exact }
    // Case-insensitive so `bottomright` works for `bottomRight`.
    if let loose = T.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() }) {
        return loose
    }
    let all = T.allCases.map(\.rawValue).joined(separator: ", ")
    throw CLIError("invalid value \"\(raw)\" for \(flag). Expected one of: \(all)")
}

func doubleValue(_ raw: String, flag: String, in range: ClosedRange<Double>) throws -> Double {
    guard let value = Double(raw) else {
        throw CLIError("invalid number \"\(raw)\" for \(flag)")
    }
    guard range.contains(value) else {
        throw CLIError("\(flag) must be between \(range.lowerBound) and \(range.upperBound) (got \(value))")
    }
    return value
}

func colorValue(_ raw: String, flag: String) throws -> CGColor {
    var hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
    if hex.count == 6 { hex += "FF" }
    guard hex.count == 8, let packed = UInt32(hex, radix: 16) else {
        throw CLIError("invalid color \"\(raw)\" for \(flag). Expected #RRGGBB or #RRGGBBAA")
    }
    let components: [CGFloat] = [
        CGFloat((packed >> 24) & 0xFF) / 255,
        CGFloat((packed >> 16) & 0xFF) / 255,
        CGFloat((packed >> 8) & 0xFF) / 255,
        CGFloat(packed & 0xFF) / 255,
    ]
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let color = CGColor(colorSpace: space, components: components) else {
        throw CLIError("could not build a color from \"\(raw)\"")
    }
    return color
}

func outputFormat(_ raw: String) throws -> OutputFormat {
    switch raw.lowercased() {
    case "preserve", "preservesource": return .preserveSource
    case "heic": return .heic
    case "jpeg", "jpg": return .jpeg
    case "png": return .png
    case "tiff", "tif": return .tiff
    default:
        throw CLIError("invalid value \"\(raw)\" for --format. Expected one of: preserve, heic, jpeg, png, tiff")
    }
}

func privacyProfile(_ raw: String) throws -> MetadataPrivacyProfile {
    guard let profile = MetadataPrivacyProfile(rawValue: raw)
        ?? [MetadataPrivacyProfile.preserveAll, .stripSensitive, .minimalPublic]
            .first(where: { $0.rawValue.lowercased() == raw.lowercased() }) else {
        throw CLIError("invalid value \"\(raw)\" for --privacy. Expected one of: preserveAll, stripSensitive, minimalPublic")
    }
    return profile
}

// MARK: - Entry point

@main
struct Markepi {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            FileHandle.standardError.write(Data("markepi: \(message)\n".utf8))
            exit(1)
        }
    }

    static func run(_ argv: [String]) async throws {
        let flags = try parseFlags(argv)

        if flags.has("--help") || (argv.isEmpty) {
            print(helpText)
            return
        }
        if flags.has("--list-fonts") {
            printFonts()
            return
        }

        // Bundled fonts (Pacifico, Montserrat, …) must be registered with
        // CoreText before the renderer can look them up by PostScript name.
        FontRegistry.registerBundledFonts()

        // MARK: Input / output

        guard flags.positionals.count <= 1 else {
            throw CLIError("expected one input image, got \(flags.positionals.count). Quote paths that contain spaces.")
        }
        guard let inputPath = flags.positionals.first else {
            throw CLIError("no input image. Usage: markepi <input> -o <output> [options]")
        }
        let input = URL(fileURLWithPath: (inputPath as NSString).expandingTildeInPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw CLIError("no such file: \(input.path)")
        }
        if WatermarkEngine.mediaType(for: input) == .video {
            throw CLIError("\(input.lastPathComponent) is a video — the CLI handles images only.")
        }

        guard let outputPath = flags.value("--output") else {
            throw CLIError("missing -o/--output")
        }
        let output = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath).standardizedFileURL
        if FileManager.default.fileExists(atPath: output.path), !flags.has("--force") {
            throw CLIError("\(output.path) already exists — pass --force to overwrite")
        }

        // MARK: Configuration

        var config = WatermarkConfiguration()
        config.outputFormat = try flags.value("--format").map(outputFormat) ?? .preserveSource
        config.outputQuality = Float(try flags.value("--quality").map {
            try doubleValue($0, flag: "--quality", in: 0...1)
        } ?? 1.0)
        config.padding = CGFloat(try flags.value("--padding").map {
            try doubleValue($0, flag: "--padding", in: 0...10_000)
        } ?? 20)

        if let text = flags.value("--text") {
            config.watermarks.append(.text(
                TextWatermarkInput(
                    text: text,
                    // Rasterization size only — the engine rescales the rendered
                    // text to `scale` × image height, so a large raster just
                    // keeps the glyph edges crisp on multi-thousand-pixel photos.
                    fontSize: 256,
                    color: try flags.value("--text-color").map { try colorValue($0, flag: "--text-color") }
                        ?? CGColor(gray: 1, alpha: 1),
                    opacity: CGFloat(try flags.value("--text-opacity").map {
                        try doubleValue($0, flag: "--text-opacity", in: 0...1)
                    } ?? 1.0),
                    fontName: resolveFont(flags.value("--text-font"))
                ),
                position: try flags.value("--text-position").map {
                    try enumValue($0, flag: "--text-position")
                } ?? .bottomRight,
                scale: CGFloat(try flags.value("--text-size").map {
                    try doubleValue($0, flag: "--text-size", in: 0.01...0.90)
                } ?? Double(WatermarkConfiguration.defaultTextScale)),
                opacity: 1.0,
                isVisible: true
            ))
        }

        if let logoPath = flags.value("--logo") {
            let logoURL = URL(fileURLWithPath: (logoPath as NSString).expandingTildeInPath)
            guard let logoData = try? Data(contentsOf: logoURL), !logoData.isEmpty else {
                throw CLIError("could not read logo image: \(logoURL.path)")
            }
            config.watermarks.append(.image(
                // 0.90 is the highest scale the model accepts; it keeps the
                // logo raster near full resolution, and the final on-image size
                // comes from the layer scale below (see WatermarkScaling).
                try ImageWatermarkInput(
                    pngData: logoData,
                    scale: 0.90,
                    opacity: 1.0,
                    rotationDegrees: CGFloat(try flags.value("--logo-rotation").map {
                        try doubleValue($0, flag: "--logo-rotation", in: -3600...3600)
                    } ?? 0)
                ),
                position: try flags.value("--logo-position").map {
                    try enumValue($0, flag: "--logo-position")
                } ?? .bottomRight,
                scale: CGFloat(try flags.value("--logo-size").map {
                    try doubleValue($0, flag: "--logo-size", in: 0.01...0.90)
                } ?? 0.15),
                opacity: CGFloat(try flags.value("--logo-opacity").map {
                    try doubleValue($0, flag: "--logo-opacity", in: 0...1)
                } ?? 1.0),
                isVisible: true
            ))
        }

        if flags.has("--border") || flags.touched(prefix: "--border-") {
            config.whiteFrame = WhiteFrameConfig(
                isEnabled: true,
                frameWidthRatio: CGFloat(try flags.value("--border-width").map {
                    try doubleValue($0, flag: "--border-width", in: 0.03...0.05)
                } ?? 0.04),
                metadataTextEnabled: !flags.has("--border-no-text"),
                captionPrefix: flags.value("--border-caption") ?? "",
                captionFields: try flags.value("--border-fields").map(captionFields) 
                    ?? WhiteFrameConfig.defaultCaptionFields,
                textColor: try flags.value("--border-text-color").map {
                    try colorValue($0, flag: "--border-text-color")
                },
                textFontSizeRatio: CGFloat(try flags.value("--border-text-size").map {
                    try doubleValue($0, flag: "--border-text-size", in: 0.005...0.05)
                } ?? 0.018),
                style: try flags.value("--border-style").map { try enumValue($0, flag: "--border-style") }
                    ?? WhiteFrameConfig().style,
                // Defer to the model's defaults rather than restating them,
                // so the CLI and the app cannot drift apart.
                borderMillimetres: CGFloat(try flags.value("--border-mm").map {
                    try doubleValue($0, flag: "--border-mm", in: 0.5...50)
                } ?? Double(WhiteFrameConfig().borderMillimetres)),
                captionTextMillimetres: CGFloat(try flags.value("--border-caption-mm").map {
                    try doubleValue($0, flag: "--border-caption-mm", in: 0.5...20)
                } ?? Double(WhiteFrameConfig().captionTextMillimetres)),
                logoHeightMillimetres: CGFloat(try flags.value("--border-logo-mm").map {
                    try doubleValue($0, flag: "--border-logo-mm", in: 0.5...30)
                } ?? Double(WhiteFrameConfig().logoHeightMillimetres)),
                keylineEnabled: flags.has("--border-no-keyline")
                    ? false
                    : (flags.has("--border-keyline") || WhiteFrameConfig().keylineEnabled),
                logoEnabled: !flags.has("--border-no-logo"),
                outputDPI: try flags.value("--border-dpi").map {
                    CGFloat(try doubleValue($0, flag: "--border-dpi", in: 36...2400))
                },
                logoVariant: try flags.value("--border-logo-variant").map {
                    try enumValue($0, flag: "--border-logo-variant")
                } ?? .color,
                leftPrimary: captionSlot(flags.value("--border-left-primary"))
                    ?? WhiteFrameConfig.defaultLeftPrimary,
                leftSecondary: captionSlot(flags.value("--border-left-secondary"))
                    ?? WhiteFrameConfig.defaultLeftSecondary,
                rightPrimary: captionSlot(flags.value("--border-right-primary"))
                    ?? WhiteFrameConfig.defaultRightPrimary,
                rightSecondary: captionSlot(flags.value("--border-right-secondary"))
                    ?? WhiteFrameConfig.defaultRightSecondary
            )
        }

        if flags.has("--date-stamp") || flags.touched(prefix: "--date-") {
            config.dateStamp = DateStampConfig(
                isEnabled: true,
                format: try flags.value("--date-format").map { try enumValue($0, flag: "--date-format") }
                    ?? .dayMonthYear,
                sizeRatio: CGFloat(try flags.value("--date-size").map {
                    try doubleValue($0, flag: "--date-size", in: 0.015...0.12)
                } ?? Double(DateStampConfig.defaultSizeRatio)),
                position: try flags.value("--date-position").map {
                    try enumValue($0, flag: "--date-position")
                } ?? .bottomLeft
            )
        }

        guard !config.watermarks.isEmpty || config.whiteFrame != nil || config.dateStamp != nil else {
            throw CLIError("nothing to apply — pass --text, --logo, --border or --date-stamp")
        }

        // Metadata stripping runs through the engine's provenance path, so it is
        // only engaged when the user actually asks for it. Signing stays off:
        // the noop client never writes a C2PA manifest.
        let profile = try flags.value("--privacy").map(privacyProfile) ?? .preserveAll
        config.metadataPrivacyProfile = profile
        let provenance: ProvenanceExportOptions? = profile == .preserveAll ? nil : ProvenanceExportOptions(
            rights: RightsMetadata(),
            privacyProfile: profile,
            includeC2PA: false,
            userDeclaration: .none,
            appVersion: "markepi-cli",
            c2paClient: NoopC2PAProvenanceClient()
        )

        // MARK: Run

        let result = try await WatermarkEngine.shared.process(
            sourceURL: input,
            config: config,
            provenance: provenance
        )
        guard let temp = result.url else {
            throw CLIError("the engine produced no output file")
        }
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        try FileManager.default.moveItem(at: temp, to: output)
        print("\(output.path)  [\(result.outputUTI)]")
    }

    /// Accepts a `--list-fonts` id, a display name, or a raw PostScript name.
    static func resolveFont(_ requested: String?) -> String {
        guard let requested else { return WatermarkConfiguration.defaultFontPostScriptName }
        let needle = requested.lowercased()
        if let match = FontCatalog.all.first(where: {
            $0.id.lowercased() == needle || $0.displayName.lowercased() == needle
        }) {
            return match.postScriptName
        }
        return requested
    }

    static func captionFields(_ raw: String) throws -> [CaptionField] {
        try raw.split(separator: ",").map {
            try enumValue(String($0).trimmingCharacters(in: .whitespaces), flag: "--border-fields")
        }
    }

    static func printFonts() {
        for category in FontCategory.allCases {
            let fonts = FontCatalog.all.filter { $0.category == category }
            guard !fonts.isEmpty else { continue }
            print("\n\(category.rawValue.uppercased())")
            for font in fonts {
                let id = font.id.padding(toLength: max(24, font.id.count), withPad: " ", startingAt: 0)
                print("  \(id)\(font.displayName)  (\(font.postScriptName))")
            }
        }
        print("\nUse an id with --text-font, or pass any PostScript name installed on this Mac.")
    }
}
