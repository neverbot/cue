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
        .library(name: "CueQueue", targets: ["CueQueue"]),
        .executable(name: "cue-resolve", targets: ["cue-resolve"]),
        .executable(name: "Cue", targets: ["Cue"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
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
        .target(
            name: "CueQueue",
            dependencies: ["CueCore", "CuePlayer", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "Cue",
            dependencies: ["CueCore", "CueMPV", "CuePlayer", "CueQueue"]
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
            name: "CueQueueTests",
            dependencies: ["CueCore", "CuePlayer", "CueQueue"]
        ),
        .testTarget(
            name: "CuePlayerTests",
            dependencies: ["CueCore", "CueMPV", "CuePlayer"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
