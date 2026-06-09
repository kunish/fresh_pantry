import SwiftUI

extension Color {
    /// Builds a color from a packed `0xRRGGBB` literal (optionally with a
    /// separate alpha) in the sRGB space, mirroring how the Flutter design
    /// tokens were authored.
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

/// Fresh Pantry brand palette — a warm, cream-surfaced light theme with a
/// cornflower-blue primary. Ported 1:1 from the Flutter `AppColors` tokens so
/// the rewritten UI matches the shipped design exactly.
///
/// The app currently ships light-only; these are fixed brand colors (not
/// system-semantic), and the root applies `.preferredColorScheme(.light)` to
/// preserve the tuned palette. Dark mode is a deliberate future enhancement.
extension Color {
    // Primary · cornflower blue
    static let fkPrimary = Color(hex: 0x5B7FD4)
    static let fkPrimaryContainer = Color(hex: 0x3F60B5)
    static let fkOnPrimary = Color(hex: 0xFFFFFF)
    static let fkOnPrimaryContainer = Color(hex: 0xE5ECFA)
    static let fkPrimaryLight = Color(hex: 0x8AA3E0)
    static let fkPrimarySoft = Color(hex: 0xE5ECFA)

    // Warn · butter yellow (临期 soon)
    static let fkWarn = Color(hex: 0xFFC857)
    static let fkWarnSoft = Color(hex: 0xFFF3D6)
    static let fkOnWarn = Color(hex: 0x2D2438)
    static let fkOnWarnContainer = Color(hex: 0x9B7A2A)
    /// 「用临期」火苗强调色 — 比 soon ink 更暖的橙,刻意区分。
    static let fkWarnInk = Color(hex: 0xB26A1F)

    // Danger · coral (过期 / 不足)
    static let fkDanger = Color(hex: 0xE76F51)
    static let fkDangerSoft = Color(hex: 0xFBE0D7)
    static let fkOnDanger = Color(hex: 0xFFFFFF)
    static let fkOnDangerContainer = Color(hex: 0xB5523A)

    // Success green — 完成态 / toast check
    static let fkSuccess = Color(hex: 0x5CC9A7)
    // Alert red — 邀请角标 / 未读徽章(纯红,有别于 danger 珊瑚)
    static let fkAlert = Color(hex: 0xE5484D)

    // Surface · warm cream ramp
    static let fkSurface = Color(hex: 0xFBF8F3)
    static let fkSurfaceDim = Color(hex: 0xE8E3DA)
    static let fkSurfaceBright = Color(hex: 0xFFFFFF)
    static let fkSurfaceContainerLowest = Color(hex: 0xFFFFFF)
    static let fkSurfaceContainerLow = Color(hex: 0xF6F2EB)
    static let fkSurfaceContainer = Color(hex: 0xF0EBE3)
    static let fkSurfaceContainerHigh = Color(hex: 0xE9E2D6)
    static let fkSurfaceContainerHighest = Color(hex: 0xE3DCCB)

    // On-surface · deep plum-ink
    static let fkOnSurface = Color(hex: 0x2D2438)
    static let fkOnSurfaceVariant = Color(hex: 0x4F4358)
    static let fkOutline = Color(hex: 0x9B92A5)
    static let fkOutlineVariant = Color(hex: 0xC7C1CE)
    static let fkHair = Color(hex: 0x2D2438, alpha: 0.078)

    // Switch off-track
    static let fkSwitchTrackOff = Color(hex: 0xD9DDD8)

    // Overlays / scrims
    static let fkOnImageScrim = Color(hex: 0x000000, alpha: 0.2)
    static let fkModalBarrier = Color(hex: 0x000000, alpha: 0.278)
    static let fkSubtleShadow = Color(hex: 0x000000, alpha: 0.059)

    // Warm shadow tints
    static let fkShadowWarm = Color(hex: 0x3C2D1E, alpha: 0.161)
    static let fkShadowSoft = Color(hex: 0x263A34, alpha: 0.039)
}
