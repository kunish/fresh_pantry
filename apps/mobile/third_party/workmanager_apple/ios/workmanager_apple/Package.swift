// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Vendored copy of workmanager_apple 0.9.1+2 with the Package.swift relocated to
// ios/workmanager_apple/ (the path Flutter's SPM integration expects:
// ios/<plugin_name>/Package.swift). Upstream ships it at ios/Package.swift, which
// Flutter does not detect, forcing a CocoaPods fallback. See third_party/README.
let package = Package(
    name: "workmanager_apple",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        // Product name must be the dash-cased package name: Flutter's
        // FlutterGeneratedPluginSwiftPackage references `.product(name:
        // "workmanager-apple", ...)`. Upstream declares it with an underscore,
        // which Xcode SPM can't resolve (the target keeps the underscore).
        .library(
            name: "workmanager-apple",
            targets: ["workmanager_apple"]
        )
    ],
    targets: [
        .target(
            name: "workmanager_apple",
            // Default path: Sources/workmanager_apple (relative to this manifest).
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
