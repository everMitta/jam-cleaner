// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MacSweep",
    platforms: [
        .macOS(.v26)
    ],
    products: {
        [
            .library(
                name: "MacSweepCore",
                targets: ["MacSweepCore"]
            ),
            .executable(
                name: "MacSweep",
                targets: ["MacSweepApp"]
            ),
        ]
    }(),
    targets: [
        .target(
            name: "MacSweepCore",
            path: "Sources/MacSweepCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "MacSweepApp",
            dependencies: ["MacSweepCore"],
            path: "Sources/MacSweepApp",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "MacSweepTests",
            dependencies: ["MacSweepCore"],
            path: "Tests/MacSweepTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
