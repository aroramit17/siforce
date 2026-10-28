// swift-tools-version:5.9
// The game rules (stunt detection, fuel, claims) are plain Swift with no UIKit or CoreMotion,
// so they build as a package and their tests run with `swift test`, no simulator needed.
// The app target compiles the same files directly.
import PackageDescription

let package = Package(
    name: "StuntCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "StuntCore", targets: ["StuntCore"]),
    ],
    targets: [
        .target(name: "StuntCore", path: "RoadsterStuntCoach/Core"),
        .testTarget(name: "StuntCoreTests", dependencies: ["StuntCore"], path: "Tests/StuntCoreTests"),
    ]
)
