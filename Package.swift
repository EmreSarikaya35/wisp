// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wisp",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WispCore"),
        .executableTarget(name: "Wisp", dependencies: ["WispCore"]),
        .testTarget(name: "WispCoreTests", dependencies: ["WispCore"]),
    ]
)
