import CoreImage

/// Provides a shared CIContext instance configured for HDR rendering.
///
/// Creates ONE context and reuses it across all rendering operations to avoid
/// GPU resource churn (Pitfall 4). Configured with CIFormat.RGBAh (16-bit float)
/// and a wide-gamut RGB working color space.
///
/// Do NOT create CIContext instances per operation — always use this shared instance.
public struct CIContextProvider {

    /// A guaranteed-valid wide-gamut RGB working color space.
    ///
    /// `CGColorSpace(name: .displayP3)` can fail in some environments (observed
    /// on Simulator: "CGColorSpaceCreateWithName failed for Display P3"). When it
    /// returns nil and is passed as a CIContext working color space, untagged
    /// images render with desaturated/grey color. We therefore fall back through
    /// sRGB and finally device RGB, which never fails — so the working space is
    /// ALWAYS a valid RGB space and color is preserved.
    public static let workingColorSpace: CGColorSpace = {
        if let p3 = CGColorSpace(name: CGColorSpace.displayP3) { return p3 }
        if let srgb = CGColorSpace(name: CGColorSpace.sRGB) { return srgb }
        if let ext = CGColorSpace(name: CGColorSpace.extendedSRGB) { return ext }
        return CGColorSpaceCreateDeviceRGB()
    }()

    /// Shared CIContext singleton with HDR-capable configuration.
    ///
    /// - workingFormat: `.RGBAh` — 16-bit float for HDR preservation
    /// - workingColorSpace: a guaranteed-valid wide-gamut RGB space
    public static let shared: CIContext = {
        return CIContext(options: [
            .workingColorSpace: workingColorSpace,
            .workingFormat: CIFormat.RGBAh,
        ])
    }()
}
