// swift-tools-version: 6.0
import PackageDescription

// ReliveCore holds everything that turns a set of photo/video references into a Story:
// models, the Memory Engine pipeline, clustering, similarity, scoring, naming and
// resurfacing. It depends on Foundation only, so it builds and tests on any platform
// (including Linux CI). Apple-only work — PhotoKit, Vision, geocoding — lives in the
// app target and plugs in through the protocols defined here.
let package = Package(
    name: "ReliveCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ReliveCore", targets: ["ReliveCore"]),
    ],
    targets: [
        .target(name: "ReliveCore"),
        .testTarget(name: "ReliveCoreTests", dependencies: ["ReliveCore"]),
    ]
)
