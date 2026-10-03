// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GestureIMECore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "GestureIMECore", targets: ["GestureIMECore"])
    ],
    targets: [
        .target(name: "GestureIMECore"),
        .testTarget(name: "GestureIMECoreTests", dependencies: ["GestureIMECore"])
    ]
)
