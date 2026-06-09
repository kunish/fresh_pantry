import SwiftUI

/// Type ramp ported from the Flutter `AppTypography` text theme.
///
/// Display / headline / title-large render in **Plus Jakarta Sans**; body /
/// label / title-medium-small render in **Manrope** — the exact families the
/// Flutter app used via google_fonts, now bundled as TTFs (see
/// `Resources/Fonts/` + `UIAppFonts`). Each token scales with Dynamic Type via
/// `relativeTo:` while keeping the Flutter base size at the default setting.
enum FkFontFamily {
    case display // Plus Jakarta Sans
    case text // Manrope

    /// Exact bundled PostScript name for a requested weight. Plus Jakarta Sans
    /// only ships SemiBold/Bold/ExtraBold, so lighter display weights clamp to
    /// SemiBold.
    func postScriptName(for weight: Font.Weight) -> String {
        switch self {
        case .display:
            switch weight {
            case .black, .heavy: return "PlusJakartaSans-ExtraBold"
            case .bold: return "PlusJakartaSans-Bold"
            default: return "PlusJakartaSans-SemiBold"
            }
        case .text:
            switch weight {
            case .black, .heavy: return "Manrope-ExtraBold"
            case .bold: return "Manrope-Bold"
            case .semibold: return "Manrope-SemiBold"
            case .medium: return "Manrope-Medium"
            default: return "Manrope-Regular"
            }
        }
    }
}

extension Font {
    /// Resolves a (family, size, weight) token to the matching bundled font,
    /// scaling relative to a Dynamic Type text style.
    static func fk(
        _ family: FkFontFamily,
        size: CGFloat,
        weight: Font.Weight,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .custom(family.postScriptName(for: weight), size: size, relativeTo: textStyle)
    }

    // Display (Plus Jakarta Sans · ExtraBold)
    static let fkDisplayLarge = fk(.display, size: 32, weight: .heavy, relativeTo: .largeTitle)
    static let fkDisplayMedium = fk(.display, size: 28, weight: .heavy, relativeTo: .largeTitle)
    static let fkDisplaySmall = fk(.display, size: 24, weight: .heavy, relativeTo: .title)

    // Headline (Plus Jakarta Sans · Bold)
    static let fkHeadlineLarge = fk(.display, size: 28, weight: .bold, relativeTo: .title)
    static let fkHeadlineMedium = fk(.display, size: 24, weight: .bold, relativeTo: .title2)
    static let fkHeadlineSmall = fk(.display, size: 20, weight: .bold, relativeTo: .title3)

    // Title (Large: Plus Jakarta Sans SemiBold; Medium/Small: Manrope SemiBold)
    static let fkTitleLarge = fk(.display, size: 20, weight: .semibold, relativeTo: .title3)
    static let fkTitleMedium = fk(.text, size: 16, weight: .semibold, relativeTo: .headline)
    static let fkTitleSmall = fk(.text, size: 14, weight: .semibold, relativeTo: .subheadline)

    // Body (Manrope · Regular)
    static let fkBodyLarge = fk(.text, size: 16, weight: .regular, relativeTo: .body)
    static let fkBodyMedium = fk(.text, size: 14, weight: .regular, relativeTo: .callout)
    static let fkBodySmall = fk(.text, size: 12, weight: .regular, relativeTo: .footnote)

    // Label (Manrope · Bold/SemiBold)
    static let fkLabelLarge = fk(.text, size: 14, weight: .bold, relativeTo: .subheadline)
    static let fkLabelMedium = fk(.text, size: 12, weight: .semibold, relativeTo: .caption)
    static let fkLabelSmall = fk(.text, size: 11, weight: .semibold, relativeTo: .caption2)

    // Special
    /// Hero block 大数字(Dashboard / Shopping 进度卡)。
    static let fkHeroStat = fk(.display, size: 56, weight: .heavy, relativeTo: .largeTitle)
    /// 中量级 hero 数字(详情数量 / 剩余天数)。
    static let fkHeroSubStat = fk(.display, size: 28, weight: .heavy, relativeTo: .largeTitle)
    /// FK 顶栏大标题。
    static let fkSectionTitleLg = fk(.display, size: 22, weight: .bold, relativeTo: .title2)
    /// 等宽数字(数量 / 代码)。
    static let fkMono = Font.custom("JetBrainsMono-Regular", size: 14, relativeTo: .callout)
}
