import CoreImage
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import CoreText
#endif

/// Renders a white frame border with device metadata text as a CIImage
/// via UIGraphicsImageRenderer (iOS) / Core Graphics (macOS testing) →
/// Core Image bridge.
///
/// The white frame is a uniform 4-sided border with proportional width
/// (3-5% of the shorter image dimension per D-05) and optional centered
/// "Taken by: [Device Model]" attribution text on the bottom frame (D-06).
///
/// Pipeline:
///   1. Calculate frame width from baseExtent shorter dimension × frameWidthRatio
///   2. Draw full white rect over entire extent, then cut transparent inner area
///      using `.clear` blend mode (per D-04: uniform border, not solid fill)
///   3. Optionally render metadata attribution text centered on bottom frame
///   4. Convert rendered image to CIImage for compositing
///
/// Uses `UIGraphicsImageRenderer` with `.extended` preferredRange on iOS for
/// HDR compatibility. On macOS (swift test), uses a CGContext-based fallback
/// that produces equivalent pixel output for structural testing.
public struct WhiteFrameRenderer {

    /// Renders a white frame border with optional metadata text.
    ///
    /// - Parameters:
    ///   - config: White frame configuration (isEnabled, frameWidthRatio, text settings)
    ///   - baseExtent: The base image extent (determines frame dimensions)
    ///   - metadata: Source image metadata dictionary with String keys
    ///               (used for device model extraction when customAttributionText is nil)
    ///   - scale: Display scale factor for Retina/HDR rendering (default: 1.0)
    /// - Returns: A CIImage with the white frame border + optional text
    /// - Throws: `PipelineError.frameRenderFailed` if image conversion fails
    public static func render(
        config: WhiteFrameConfig,
        baseExtent: CGRect,
        metadata: [String: Any],
        scale: CGFloat = 1.0
    ) throws -> CIImage {
        // 1. Calculate frame width from shorter dimension × ratio (D-05)
        let shorterDimension = min(baseExtent.width, baseExtent.height)
        let frameWidth = shorterDimension * config.frameWidthRatio

        // 2. Determine attribution text (if metadata text is enabled)
        let attributionText: String?
        if config.metadataTextEnabled {
            if let customText = config.customAttributionText {
                attributionText = customText
            } else {
                attributionText = DeviceMetadataProvider.attributionText(from: metadata)
            }
        } else {
            attributionText = nil
        }

        // 3. Render via platform-specific path
        #if canImport(UIKit)
        return try renderWithUIGraphics(
            baseExtent: baseExtent,
            frameWidth: frameWidth,
            attributionText: attributionText,
            config: config,
            scale: scale
        )
        #else
        return try renderWithCoreGraphics(
            baseExtent: baseExtent,
            frameWidth: frameWidth,
            attributionText: attributionText,
            config: config,
            scale: scale
        )
        #endif
    }

    // MARK: - iOS rendering path (UIGraphicsImageRenderer)

    #if canImport(UIKit)
    private static func renderWithUIGraphics(
        baseExtent: CGRect,
        frameWidth: CGFloat,
        attributionText: String?,
        config: WhiteFrameConfig,
        scale: CGFloat
    ) throws -> CIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.preferredRange = .extended  // HDR compatibility

        let renderSize = baseExtent.size
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)

        let uiImage = renderer.image { ctx in
            drawFrame(
                cgContext: ctx.cgContext,
                baseExtent: baseExtent,
                frameWidth: frameWidth,
                attributionText: attributionText,
                config: config
            )
        }

        guard let ciImage = CIImage(image: uiImage) else {
            throw PipelineError.frameRenderFailed
        }

        return ciImage
    }
    #endif

    // MARK: - macOS rendering path (Core Graphics fallback for swift test)

    #if !canImport(UIKit)
    private static func renderWithCoreGraphics(
        baseExtent: CGRect,
        frameWidth: CGFloat,
        attributionText: String?,
        config: WhiteFrameConfig,
        scale: CGFloat
    ) throws -> CIImage {
        let width = Int(baseExtent.width * scale)
        let height = Int(baseExtent.height * scale)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        guard let cgContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PipelineError.frameRenderFailed
        }

        // Scale the context to match the target dimensions
        let scaledExtent = CGRect(
            x: 0, y: 0,
            width: baseExtent.width * scale,
            height: baseExtent.height * scale
        )

        // Flip the coordinate system: CGContext uses bottom-left origin by
        // default, but our drawFrame logic expects top-left (matching UIKit).
        // Flip so text positioning matches iOS behavior.
        cgContext.translateBy(x: 0, y: scaledExtent.height)
        cgContext.scaleBy(x: 1.0, y: -1.0)

        drawFrame(
            cgContext: cgContext,
            baseExtent: scaledExtent,
            frameWidth: frameWidth * scale,
            attributionText: attributionText,
            config: config
        )

        guard let cgImage = cgContext.makeImage() else {
            throw PipelineError.frameRenderFailed
        }

        return CIImage(cgImage: cgImage)
    }
    #endif

    // MARK: - Shared drawing logic (platform-agnostic Core Graphics)

    private static func drawFrame(
        cgContext: CGContext,
        baseExtent: CGRect,
        frameWidth: CGFloat,
        attributionText: String?,
        config: WhiteFrameConfig
    ) {
        // 1. Fill entire canvas with white
        cgContext.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        cgContext.fill(baseExtent)

        // 2. Cut out transparent inner area using .clear blend mode (D-04)
        let innerRect = baseExtent.insetBy(dx: frameWidth, dy: frameWidth)
        cgContext.setBlendMode(.clear)
        cgContext.fill(innerRect)
        cgContext.setBlendMode(.normal)

        // 3. Render metadata attribution text centered on bottom frame
        if let text = attributionText, frameWidth > 0 {
            let fontSize = frameWidth * config.textFontSizeRatio
            let textColor = platformColor(from: config.textColor)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: platformFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: textColor,
            ]

            let attributed = NSAttributedString(
                string: text,
                attributes: attributes
            )

            let textSize = attributed.size()

            // Center horizontally on bottom frame portion
            let textX = (baseExtent.width - textSize.width) / 2
            let textY = baseExtent.height - (frameWidth / 2) - (textSize.height / 2)

            #if canImport(UIKit)
            // On iOS, draw using NSAttributedString into UIGraphicsImageRenderer context
            let textRect = CGRect(
                x: textX,
                y: textY,
                width: textSize.width,
                height: textSize.height
            )
            attributed.draw(in: textRect)
            #else
            // On macOS, use Core Text to draw directly into the CGContext
            // (NSAttributedString.draw(in:) requires NSGraphicsContext, not CGContext)
            let line = CTLineCreateWithAttributedString(attributed)
            cgContext.textPosition = CGPoint(x: textX, y: textY)
            CTLineDraw(line, cgContext)
            #endif
        }
    }

    // MARK: - Cross-platform font/color helpers

    #if canImport(UIKit)
    private static func platformFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    private static func platformColor(from cgColor: CGColor) -> UIColor {
        return UIColor(cgColor: cgColor)
    }
    #elseif canImport(AppKit)
    private static func platformFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    private static func platformColor(from cgColor: CGColor) -> NSColor {
        return NSColor(cgColor: cgColor) ?? NSColor.darkGray
    }
    #endif
}
