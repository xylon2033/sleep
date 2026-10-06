// swift-tools-version: 5.10
import PackageDescription

// Pure, platform-independent logic: audio epoch features, sleep/wake estimation,
// regularity metrics, coaching and n-of-1 statistics. No Apple-only frameworks,
// so `swift test` runs on macOS and Linux.
let package = Package(
    name: "SleepCore",
    platforms: [.iOS("17.0"), .macOS("14.0")],
    products: [
        .library(name: "SleepCore", targets: ["SleepCore"]),
    ],
    targets: [
        .target(name: "SleepCore"),
        .testTarget(name: "SleepCoreTests", dependencies: ["SleepCore"]),
    ]
)
