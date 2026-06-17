import CoreImage

/// Provides a shared CIContext instance configured for HDR rendering.
///
/// Creates ONE context and reuses it across all rendering operations to avoid
/// GPU resource churn (Pitfall 4). Configured with CIFormat.RGBAh (16-bit float)
/// and displayP3 working color space for HDR-capable output.
///
/// Do NOT create CIContext instances per operation — always use this shared instance.
public struct CIContextProvider {

    /// Shared CIContext singleton with HDR-capable configuration.
    ///
    /// - workingFormat: `.RGBAh` — 16-bit float for HDR preservation
    /// - workingColorSpace: `displayP3` — wide gamut color space
    public static let shared: CIContext = {
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)
        return CIContext(options: [
            .workingColorSpace: colorSpace as Any,
            .workingFormat: CIFormat.RGBAh,
        ])
    }()
}
