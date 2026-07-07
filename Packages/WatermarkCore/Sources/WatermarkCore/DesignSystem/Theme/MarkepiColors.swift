import SwiftUI

/// Color tokens for the Markepi design system.
///
/// Every token adapts to the current appearance via dynamic providers, so the
/// chrome follows the user's light/dark/system preference:
/// - **Canvas:** The photo/video backdrop and the onboarding surface read as
///   white in light mode (clean editing workspace) and true black in dark mode
///   (media stays the hero). Text drawn over the canvas mirrors that.
/// - **Chrome:** Panel backgrounds, control strokes, pill backgrounds, and
///   status colors adapt via the dynamic provider.
///
/// Scope boundary: `MarkepiColors` is for **UI chrome only.** Do NOT route
/// the watermark render path through it — rendering keeps its own colors.
public enum MarkepiColors {

    // MARK: - Canvas (adapts: white in light, black in dark)

    /// Backdrop behind the photo/video canvas and the onboarding surface.
    /// White in light mode (clean editing workspace) and true black in dark
    /// mode (media stays the hero), so the letterboxing follows the appearance.
    public static let canvasBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
    })

    /// Backdrop behind the photo/video in the editor preview. Always dark (true
    /// black) regardless of appearance, so the media stays the hero and the
    /// letterbox reads as part of the surface even in Light mode — matching how
    /// the canvas already looks in Dark mode. Distinct from `canvasBackground`
    /// (adaptive), which backs text-bearing surfaces (onboarding / empty state)
    /// whose `.primary` text needs the light/dark pairing to stay legible.
    public static let photoCanvasBackground: Color = Color.black

    /// Text/glyphs drawn directly over the canvas — black on the white
    /// light-mode canvas, white on the black dark-mode canvas.
    public static let canvasOverlayText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
    })

    // MARK: - Chrome backgrounds

    public static let panelBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.10, alpha: 1)
            : UIColor.systemGroupedBackground
    })

    public static let chromeBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.06, alpha: 1)
            : UIColor.systemBackground
    })

    // MARK: - Chrome strokes / separators

    public static let controlStroke = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.08)
            : UIColor(white: 0, alpha: 0.10)
    })

    public static let panelStroke = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.08)
            : UIColor(white: 0, alpha: 0.06)
    })

    // MARK: - Pill / selection backgrounds

    public static let pillBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.08)
            : UIColor(white: 0, alpha: 0.04)
    })

    public static let pillStroke = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.12)
            : UIColor(white: 0, alpha: 0.08)
    })

    public static let activePillBackground = Color.accentColor.opacity(0.14)

    // MARK: - Status

    public static let statusSuccess = Color.green
    public static let statusError = Color.red
    public static let statusWarning = Color.orange
}
