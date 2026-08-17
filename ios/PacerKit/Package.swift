// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PacerKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PacerKit", targets: ["PacerKit"])
    ],
    targets: [
        .target(
            name: "PacerKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PacerKitTests",
            dependencies: ["PacerKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
