// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrashTrimCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CrashTrimCore", targets: ["CrashTrimCore"])],
    targets: [
        .target(name: "CrashTrimCore"),
        .testTarget(name: "CrashTrimCoreTests", dependencies: ["CrashTrimCore"])
    ]
)
