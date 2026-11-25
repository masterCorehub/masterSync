// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NexusMasterSync",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NexusMasterSync", targets: ["NexusMasterSync"]),
        .library(name: "NexusCore", targets: ["NexusCore"])
    ],
    targets: [
        .target(name: "NexusCore"),
        .executableTarget(name: "NexusMasterSync", dependencies: ["NexusCore"]),
        .testTarget(name: "NexusCoreTests", dependencies: ["NexusCore", "NexusMasterSync"])
    ]
)
