// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GestureIMEProfileAuthoring",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "GestureIMEProfileAuthoring",
            targets: ["GestureIMEProfileAuthoring"]
        )
    ],
    targets: [
        .target(name: "GestureIMEProfileAuthoring"),
        .testTarget(
            name: "GestureIMEProfileAuthoringTests",
            dependencies: ["GestureIMEProfileAuthoring"]
        )
    ]
)
