// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CutScreen",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CutScreen", targets: ["CutScreen"])
    ],
    targets: [
        .executableTarget(
            name: "CutScreen",
            path: "Sources/CutScreen",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "CutScreenTests",
            dependencies: ["CutScreen"],
            path: "Tests/CutScreenTests"
        )
    ]
)
