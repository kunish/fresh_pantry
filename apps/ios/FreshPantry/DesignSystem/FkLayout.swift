import CoreGraphics

/// Spacing scale (logical points). Ported from Flutter `AppSpacing`.
enum FkSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let huge: CGFloat = 32
}

/// Corner-radius scale. Ported from Flutter `AppRadius`.
enum FkRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let hero: CGFloat = 28
    /// FK search field / chip rectangle.
    static let chip: CGFloat = 14
}

/// Fixed icon/element sizes. Ported from Flutter `AppSize`.
enum FkSize {
    static let iconSm: CGFloat = 18
    static let iconMd: CGFloat = 20
    static let settingsIconBox: CGFloat = 32
}
