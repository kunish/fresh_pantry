// swift-tools-version: 5.9
// Local fork: Swift Package Manager support for receive_sharing_intent (upstream 1.8.1).

import PackageDescription

let package = Package(
    name: "receive_sharing_intent",
    platforms: [
        .iOS("13.0"),
    ],
    products: [
        .library(name: "receive-sharing-intent", targets: ["receive_sharing_intent"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "receive_sharing_intent",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("Photos"),
            ]
        ),
    ]
)
