import CoreImage
import Foundation

/// Renders one watermark layer on its own, transparent background and all.
///
/// The editor draws this on top of the preview while a layer is being dragged:
/// re-rendering the whole composite per finger movement cannot keep up with a
/// finger, so the layer is lifted out of the composite and this copy moves
/// instead — the same pixels, so the drop is seamless.
public enum LayerPreviewImage {
    /// Nil when the layer has nothing to draw (e.g. text with nothing typed).
    public static func render(_ layer: WatermarkLayer, metadata: [String: Any] = [:]) -> CGImage? {
        let rendered: CIImage
        switch layer {
        case .text(let config, _, _, _, _):
            // A text layer with nothing typed in it draws nothing, and the
            // renderer still hands back a blank tile — the editor would lift an
            // invisible layer out of the composite for no reason.
            guard !config.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            rendered = TextWatermarkRenderer.render(config: config, metadata: metadata)
        case .image(let config, _, _, _, _):
            guard let image = try? ImageWatermarkRenderer.render(config: config) else { return nil }
            // Match the engine: rotation is part of what the layer looks like.
            rendered = ImageWatermarkRenderer.rotated(image, degrees: config.rotationDegrees)
        case .signature(let input, _, _, _, _):
            guard let image = try? SignatureRenderer.render(input: input) else { return nil }
            rendered = image
        }
        guard !rendered.extent.isInfinite, rendered.extent.width >= 1, rendered.extent.height >= 1
        else { return nil }
        return CIContextProvider.shared.createCGImage(rendered, from: rendered.extent)
    }
}
