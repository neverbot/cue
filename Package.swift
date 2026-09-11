// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cue",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CueCore", targets: ["CueCore"]),
        .executable(name: "cue-resolve", targets: ["cue-resolve"]),
    ],
    targets: [
        .target(
            name: "CueCore",
            resources: [.copy("Resources/ejs")]
        ),
        .executableTarget(
            name: "cue-resolve",
            dependencies: ["CueCore"]
        ),
        .testTarget(
            name: "CueCoreTests",
            dependencies: ["CueCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
