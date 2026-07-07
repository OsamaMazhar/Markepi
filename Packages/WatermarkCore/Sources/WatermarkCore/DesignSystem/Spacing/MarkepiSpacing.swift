import CoreGraphics

/// Semantic spacing tokens for the Markepi design system.
///
/// Recurring values already present in the codebase, extracted to a single
/// source of truth. Isolated one-shot literals can stay inline — only
/// migrate values that repeat across files.
public enum MarkepiSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24
    public static let xxxl: CGFloat = 32
}
