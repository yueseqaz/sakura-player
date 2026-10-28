// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SakuraPlayer",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SakuraPlayerCore", targets: ["SakuraPlayerCore"]),
        .executable(name: "SakuraPlayer", targets: ["SakuraPlayerApp"]),
        .executable(name: "SakuraPlayerCoreChecks", targets: ["SakuraPlayerCoreChecks"])
    ],
    targets: [
        .target(name: "SakuraPlayerCore"),
        .executableTarget(name: "SakuraPlayerApp", dependencies: ["SakuraPlayerCore"]),
        .executableTarget(name: "SakuraPlayerCoreChecks", dependencies: ["SakuraPlayerCore"]),
        .testTarget(name: "SakuraPlayerPresentationTests", dependencies: ["SakuraPlayerApp", "SakuraPlayerCore"])
    ]
)
