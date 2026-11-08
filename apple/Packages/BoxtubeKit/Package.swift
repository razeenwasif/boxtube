// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoxtubeKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "BoxtubeCore", targets: ["BoxtubeCore"]),
        .library(name: "BoxtubeUI", targets: ["BoxtubeUI"]),
        .library(name: "BoxtubePlayer", targets: ["BoxtubePlayer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/kean/Nuke.git", from: "12.0.0"),
    ],
    targets: [
        .target(
            name: "BoxtubeCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "BoxtubeUI",
            dependencies: [
                "BoxtubeCore",
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke"),
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "BoxtubePlayer",
            dependencies: ["BoxtubeCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "BoxtubeCoreTests", dependencies: ["BoxtubeCore"]),
    ]
)
