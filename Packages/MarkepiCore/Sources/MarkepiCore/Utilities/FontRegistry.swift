import Foundation
#if canImport(UIKit)
import UIKit
import CoreText
#elseif canImport(AppKit)
import AppKit
import CoreText
#endif

public enum FontRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var registeredFonts: Set<String> = []

    public static func registerBundledFonts() {
        lock.lock()
        defer { lock.unlock() }

        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        // SwiftPM's `.process("Resources/Fonts")` FLATTENS the .ttf files into the
        // bundle root, not a "Fonts" subdirectory — so the old lookup with
        // `subdirectory: "Fonts"` returned nil and NOTHING registered (every
        // bundled font silently fell back to the system face). Search the root
        // and the subdirectory, deduplicated, so registration works regardless
        // of how the build system lays the resources out.
        var seen = Set<URL>()
        var fontURLs: [URL] = []
        for subdir in [nil, "Fonts"] as [String?] {
            for url in bundle.urls(forResourcesWithExtension: "ttf", subdirectory: subdir) ?? [] {
                if seen.insert(url).inserted { fontURLs.append(url) }
            }
        }
        guard !fontURLs.isEmpty else { return }

        for url in fontURLs {
            let fontName = url.deletingPathExtension().lastPathComponent
            guard !registeredFonts.contains(fontName) else { continue }

            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                registeredFonts.insert(fontName)
            }
        }
    }

    #if canImport(UIKit)
    public static func font(named postScriptName: String, size: CGFloat, fallbackToSystemFont: Bool = true) -> UIFont {
        if let font = UIFont(name: postScriptName, size: size) {
            return font
        }
        if fallbackToSystemFont {
            return UIFont.systemFont(ofSize: size, weight: .semibold)
        }
        return UIFont.systemFont(ofSize: size, weight: .semibold)
    }

    public static func cascadingFont(
        primaryName: String,
        size: CGFloat,
        fallbackNames: [String] = [],
        fallbackToSystemFont: Bool = true
    ) -> UIFont {
        if let primaryFont = UIFont(name: primaryName, size: size) {
            if fallbackNames.isEmpty && !fallbackToSystemFont {
                return primaryFont
            }
            let primaryDescriptor = primaryFont.fontDescriptor
            var cascadeList: [UIFontDescriptor] = []
            for name in fallbackNames {
                if let fb = UIFont(name: name, size: size) {
                    cascadeList.append(fb.fontDescriptor)
                }
            }
            if fallbackToSystemFont {
                let systemDesc = UIFont.systemFont(ofSize: size).fontDescriptor
                cascadeList.append(systemDesc)
            }
            if !cascadeList.isEmpty {
                let cascadingDesc = primaryDescriptor.addingAttributes([
                    .cascadeList: cascadeList
                ])
                return UIFont(descriptor: cascadingDesc, size: size)
            }
            return primaryFont
        }

        for name in fallbackNames {
            if let fb = UIFont(name: name, size: size) {
                return fb
            }
        }

        return UIFont.systemFont(ofSize: size, weight: .semibold)
    }

    public static func font(for watermarkFont: WatermarkFont, size: CGFloat) -> UIFont {
        registerBundledFonts()
        let primaryName = watermarkFont.postScriptName
        let fallbackNames: [String] = ["HelveticaNeue"]

        guard let baseFont = UIFont(name: primaryName, size: size) else {
            return cascadingFont(
                primaryName: "HelveticaNeue",
                size: size,
                fallbackNames: [],
                fallbackToSystemFont: true
            )
        }

        if watermarkFont.isSystemFont {
            return baseFont
        }

        let targetWeight: UIFont.Weight = watermarkFont.category == .serif ? .regular : .medium
        var descriptor = baseFont.fontDescriptor
        var traits = descriptor.fontAttributes[.traits] as? [UIFontDescriptor.TraitKey: Any] ?? [:]
        traits[.weight] = targetWeight
        descriptor = descriptor.addingAttributes([.traits: traits])

        let weightedFont = UIFont(descriptor: descriptor, size: size)
        let cascadeList: [UIFontDescriptor] = fallbackNames.compactMap { name in
            UIFont(name: name, size: size)?.fontDescriptor
        }
        if !cascadeList.isEmpty {
            let cascadingDesc = weightedFont.fontDescriptor.addingAttributes([
                .cascadeList: cascadeList
            ])
            return UIFont(descriptor: cascadingDesc, size: size)
        }
        return weightedFont
    }
    #elseif canImport(AppKit)
    public static func font(named postScriptName: String, size: CGFloat, fallbackToSystemFont: Bool = true) -> NSFont {
        if let font = NSFont(name: postScriptName, size: size) {
            return font
        }
        if fallbackToSystemFont {
            return NSFont.systemFont(ofSize: size, weight: .semibold)
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    public static func cascadingFont(
        primaryName: String,
        size: CGFloat,
        fallbackNames: [String] = [],
        fallbackToSystemFont: Bool = true
    ) -> NSFont {
        if let primaryFont = NSFont(name: primaryName, size: size) {
            return primaryFont
        }
        for name in fallbackNames {
            if let fb = NSFont(name: name, size: size) {
                return fb
            }
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    public static func font(for watermarkFont: WatermarkFont, size: CGFloat) -> NSFont {
        registerBundledFonts()
        return font(named: watermarkFont.postScriptName, size: size, fallbackToSystemFont: true)
    }
    #endif

    public static func isFontAvailable(_ postScriptName: String) -> Bool {
        #if canImport(UIKit)
        return UIFont(name: postScriptName, size: 12) != nil
        #elseif canImport(AppKit)
        return NSFont(name: postScriptName, size: 12) != nil
        #else
        return false
        #endif
    }
}
