import Foundation

/// App identity read from the main bundle's Info.plist — used by the Settings
/// 关于 section. Reads `CFBundleShortVersionString` (marketing version) and
/// `CFBundleVersion` (build), with safe fallbacks if a key is missing.
enum AppVersion {
    /// `CFBundleDisplayName` if present, else `CFBundleName`, else "Fresh Pantry".
    static var appName: String {
        bundleString("CFBundleDisplayName")
            ?? bundleString("CFBundleName")
            ?? "Fresh Pantry"
    }

    /// The marketing version, e.g. "1.2.1".
    static var marketingVersion: String {
        bundleString("CFBundleShortVersionString") ?? "—"
    }

    /// The build number, e.g. "1".
    static var buildNumber: String {
        bundleString("CFBundleVersion") ?? "—"
    }

    /// Combined display string, e.g. "1.2.1 (1)".
    static var displayString: String {
        "\(marketingVersion) (\(buildNumber))"
    }

    private static func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
