// swift-tools-version: 6.2

import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "YouxPC",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "YouxPC", targets: ["YouxPC"]),
        .executable(name: "youxpc", targets: ["YouxPCCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/steipete/AXorcist.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "YouxPC",
            dependencies: [
                .product(name: "AXorcist", package: "AXorcist"),
            ],
            path: "Sources/YouxPC",
            swiftSettings: concurrencySettings,
            linkerSettings: [.linkedFramework("ScreenCaptureKit")]
        ),
        .executableTarget(
            name: "YouxPCCLI",
            dependencies: ["YouxPC"],
            path: "Sources/CLI",
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "YouxPCTests",
            dependencies: ["YouxPC"],
            path: "Tests/YouxPCTests",
            swiftSettings: concurrencySettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
