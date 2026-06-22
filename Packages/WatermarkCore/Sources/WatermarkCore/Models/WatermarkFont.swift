import Foundation

public enum FontCategory: String, Sendable, Codable, CaseIterable {
    case serif
    case sansSerif
    case script
    case monospace
}

public struct WatermarkFont: Sendable, Codable, Identifiable {
    public let id: String
    public let displayName: String
    public let postScriptName: String
    public let category: FontCategory
    public let isSystemFont: Bool
    public let fileName: String?

    public init(
        id: String,
        displayName: String,
        postScriptName: String,
        category: FontCategory,
        isSystemFont: Bool,
        fileName: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.postScriptName = postScriptName
        self.category = category
        self.isSystemFont = isSystemFont
        self.fileName = fileName
    }
}

public enum FontCatalog {
    public static let all: [WatermarkFont] = [
        // MARK: - Sans-Serif (Clean & Modern)
        WatermarkFont(
            id: "helvetica-neue",
            displayName: "Helvetica Neue",
            postScriptName: "HelveticaNeue",
            category: .sansSerif,
            isSystemFont: true
        ),
        WatermarkFont(
            id: "futura",
            displayName: "Futura",
            postScriptName: "Futura-Medium",
            category: .sansSerif,
            isSystemFont: true
        ),
        WatermarkFont(
            id: "montserrat",
            displayName: "Montserrat",
            postScriptName: "Montserrat-Thin",
            category: .sansSerif,
            isSystemFont: false,
            fileName: "Montserrat-Regular.ttf"
        ),
        WatermarkFont(
            id: "roboto",
            displayName: "Roboto",
            postScriptName: "Roboto-Regular",
            category: .sansSerif,
            isSystemFont: false,
            fileName: "Roboto-Regular.ttf"
        ),
        WatermarkFont(
            id: "lato",
            displayName: "Lato",
            postScriptName: "Lato-Regular",
            category: .sansSerif,
            isSystemFont: false,
            fileName: "Lato-Regular.ttf"
        ),
        WatermarkFont(
            id: "raleway",
            displayName: "Raleway",
            postScriptName: "Raleway-Thin",
            category: .sansSerif,
            isSystemFont: false,
            fileName: "Raleway-Regular.ttf"
        ),
        WatermarkFont(
            id: "open-sans",
            displayName: "Open Sans",
            postScriptName: "OpenSans-Regular",
            category: .sansSerif,
            isSystemFont: false,
            fileName: "OpenSans-Regular.ttf"
        ),
        WatermarkFont(
            id: "avenir",
            displayName: "Avenir",
            postScriptName: "Avenir-Book",
            category: .sansSerif,
            isSystemFont: true
        ),
        WatermarkFont(
            id: "gill-sans",
            displayName: "Gill Sans",
            postScriptName: "GillSans",
            category: .sansSerif,
            isSystemFont: true
        ),
        WatermarkFont(
            id: "optima",
            displayName: "Optima",
            postScriptName: "Optima-Regular",
            category: .sansSerif,
            isSystemFont: true
        ),

        // MARK: - Serif (Elegant & Classic)
        WatermarkFont(
            id: "playfair-display",
            displayName: "Playfair Display",
            postScriptName: "PlayfairDisplay-Regular",
            category: .serif,
            isSystemFont: false,
            fileName: "PlayfairDisplay-Regular.ttf"
        ),
        WatermarkFont(
            id: "bodoni-72",
            displayName: "Bodoni 72",
            postScriptName: "BodoniSvtyTwoITCTT-Book",
            category: .serif,
            isSystemFont: true
        ),
        WatermarkFont(
            id: "cormorant-garamond",
            displayName: "Cormorant Garamond",
            postScriptName: "CormorantGaramond-Light",
            category: .serif,
            isSystemFont: false,
            fileName: "CormorantGaramond-Regular.ttf"
        ),
        WatermarkFont(
            id: "didot",
            displayName: "Didot",
            postScriptName: "Didot",
            category: .serif,
            isSystemFont: true
        ),
        WatermarkFont(
            id: "georgia",
            displayName: "Georgia",
            postScriptName: "Georgia",
            category: .serif,
            isSystemFont: true
        ),
        WatermarkFont(
            id: "palatino",
            displayName: "Palatino",
            postScriptName: "Palatino-Roman",
            category: .serif,
            isSystemFont: true
        ),
        WatermarkFont(
            id: "hoefler-text",
            displayName: "Hoefler Text",
            postScriptName: "HoeflerText-Regular",
            category: .serif,
            isSystemFont: true
        ),

        // MARK: - Script (Personal & Hand-Crafted)
        WatermarkFont(
            id: "great-vibes",
            displayName: "Great Vibes",
            postScriptName: "GreatVibes-Regular",
            category: .script,
            isSystemFont: false,
            fileName: "GreatVibes-Regular.ttf"
        ),
        WatermarkFont(
            id: "pacifico",
            displayName: "Pacifico",
            postScriptName: "Pacifico-Regular",
            category: .script,
            isSystemFont: false,
            fileName: "Pacifico-Regular.ttf"
        ),
        WatermarkFont(
            id: "sacramento",
            displayName: "Sacramento",
            postScriptName: "Sacramento-Regular",
            category: .script,
            isSystemFont: false,
            fileName: "Sacramento-Regular.ttf"
        ),
        WatermarkFont(
            id: "allura",
            displayName: "Allura",
            postScriptName: "Allura-Regular",
            category: .script,
            isSystemFont: false,
            fileName: "Allura-Regular.ttf"
        ),
        WatermarkFont(
            id: "parisienne",
            displayName: "Parisienne",
            postScriptName: "Parisienne-Regular",
            category: .script,
            isSystemFont: false,
            fileName: "Parisienne-Regular.ttf"
        ),
        WatermarkFont(
            id: "alex-brush",
            displayName: "Alex Brush",
            postScriptName: "AlexBrush-Regular",
            category: .script,
            isSystemFont: false,
            fileName: "AlexBrush-Regular.ttf"
        ),
        WatermarkFont(
            id: "tangerine",
            displayName: "Tangerine",
            postScriptName: "Tangerine-Regular",
            category: .script,
            isSystemFont: false,
            fileName: "Tangerine-Regular.ttf"
        ),
        WatermarkFont(
            id: "pinyon-script",
            displayName: "Pinyon Script",
            postScriptName: "PinyonScript-Regular",
            category: .script,
            isSystemFont: false,
            fileName: "PinyonScript-Regular.ttf"
        ),
        WatermarkFont(
            id: "marck-script",
            displayName: "Marck Script",
            postScriptName: "MarckScript-Regular",
            category: .script,
            isSystemFont: false,
            fileName: "MarckScript-Regular.ttf"
        ),
        WatermarkFont(
            id: "niconne",
            displayName: "Niconne",
            postScriptName: "Niconne-Regular",
            category: .script,
            isSystemFont: false,
            fileName: "Niconne-Regular.ttf"
        ),
        WatermarkFont(
            id: "cookie",
            displayName: "Cookie",
            postScriptName: "Cookie-Regular",
            category: .script,
            isSystemFont: false,
            fileName: "Cookie-Regular.ttf"
        ),

        // MARK: - Monospace
        WatermarkFont(
            id: "courier",
            displayName: "Courier",
            postScriptName: "Courier",
            category: .monospace,
            isSystemFont: true
        ),
    ]

    public static func fonts(for category: FontCategory) -> [WatermarkFont] {
        all.filter { $0.category == category }
    }

    public static func font(byID id: String) -> WatermarkFont? {
        all.first { $0.id == id }
    }

    public static func font(byPostScriptName name: String) -> WatermarkFont? {
        all.first { $0.postScriptName == name }
    }
}
