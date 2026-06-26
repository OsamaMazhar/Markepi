import SwiftUI

/// The tools available in the main editor's persistent bottom dock.
///
/// Each tool maps to a focused control panel (the existing WatermarkCore leaf
/// views), letting the photo canvas stay full-bleed while only one group of
/// controls is revealed at a time — an Adobe/Photos-style editing model.
enum EditorTool: String, CaseIterable, Identifiable {
    case text
    case logo
    case signature
    case frame
    case layers
    case output

    var id: String { rawValue }

    /// Short label shown under the dock icon.
    var title: String {
        switch self {
        case .text: return "Text"
        case .logo: return "Logo"
        case .signature: return "Sign"
        case .frame: return "Frame"
        case .layers: return "Layers"
        case .output: return "More"
        }
    }

    /// Title shown in the tool panel header (can be longer than the dock label).
    var panelTitle: String {
        switch self {
        case .text: return "Text Watermark"
        case .logo: return "Logo"
        case .signature: return "Signature"
        case .frame: return "White Frame"
        case .layers: return "Layers"
        case .output: return "More Settings"
        }
    }

    /// SF Symbol for the dock button.
    var icon: String {
        switch self {
        case .text: return "textformat"
        case .logo: return "photo"
        case .signature: return "signature"
        case .frame: return "square.dashed"
        case .layers: return "square.stack.3d.up"
        case .output: return "slider.horizontal.3"
        }
    }
}
