// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GestureIMEProductSettings",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "GestureIMEProductSettings",
            targets: ["GestureIMEProductSettings"]
        )
    ],
    targets: [
        .target(name: "GestureIMEProductSettings"),
        .testTarget(
            name: "GestureIMEProductSettingsTests",
            dependencies: ["GestureIMEProductSettings"]
        )
    ]
)
