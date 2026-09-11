// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cue",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CueCore", targets: ["CueCore"]),
    ],
    targets: [
        .target(
            name: "CueCore",
            resources: [.copy("Resources/ejs")]
        ),
        .testTarget(
            name: "CueCoreTests",
            dependencies: ["CueCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
