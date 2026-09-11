// swift-tools-version: 6.0
import PackageDescription

/// libmpv is linked from the git-ignored cache filled by scripts/fetch-libmpv.sh. The absolute rpath lets `swift build`,
/// `swift run` and `scripts/test.sh` load it in place; scripts/make-app.sh replaces it with the bundle's Frameworks.
let libmpvDirectory = Context.packageDirectory + "/vendor/cache/libmpv/lib"

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
        .systemLibrary(name: "CMpv"),
        .target(
            name: "CueMPV",
            dependencies: ["CMpv"],
            linkerSettings: [.unsafeFlags(["-L", libmpvDirectory, "-Xlinker", "-rpath", "-Xlinker", libmpvDirectory])]
        ),
        .target(
            name: "CuePlayer",
            dependencies: ["CueCore", "CueMPV"]
        ),
        .testTarget(
            name: "CueCoreTests",
            dependencies: ["CueCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CueMPVTests",
            dependencies: ["CueMPV", "CMpv"]
        ),
        .testTarget(
            name: "CuePlayerTests",
            dependencies: ["CueCore", "CueMPV", "CuePlayer"]
        ),
    ]
)
