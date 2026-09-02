// iOS-only UI. Guarded so WatermarkCore also builds for macOS, where the
// `markepi` CLI target links the engine without the SwiftUI layer.
#if canImport(UIKit)
import SwiftUI

/// Semantic size tokens for the Markepi design system.
public enum MarkepiSizing {
    public static let thumbnailCell: CGFloat = 60
    public static let templateThumbnail: CGFloat = 48
    public static let controlIcon: CGFloat = 24
    public static let grabberWidth: CGFloat = 40
    public static let grabberHeight: CGFloat = 5
    public static let loadingGlyphSize: CGFloat = 64
    public static let removeBadgeSize: CGFloat = 22
    public static let minTouchTarget: CGFloat = 44
    public static let videoScrubBarPercentWidth: CGFloat = 40
    public static let batchCancelButtonWidth: CGFloat = 220
}

public enum MarkepiMetrics {
    public static func thumbnailStripHeight(dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let base: CGFloat = 72
        switch dynamicTypeSize {
        case .xSmall, .small, .medium: return base
        case .large: return base + 4
        case .xLarge: return base + 8
        case .xxLarge: return base + 12
        case .xxxLarge: return base + 16
        case .accessibility1: return base + 24
        case .accessibility2: return base + 32
        case .accessibility3: return base + 44
        case .accessibility4: return base + 56
        case .accessibility5: return base + 68
        @unknown default: return base
        }
    }

    public static func thumbnailCellSize(dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let base: CGFloat = 60
        switch dynamicTypeSize {
        case .xSmall, .small, .medium: return base
        case .large: return base + 6
        case .xLarge: return base + 12
        case .xxLarge: return base + 18
        case .xxxLarge: return base + 24
        case .accessibility1: return base + 34
        case .accessibility2: return base + 44
        case .accessibility3: return base + 54
        case .accessibility4: return base + 64
        case .accessibility5: return base + 74
        @unknown default: return base
        }
    }
}
#endif
