// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CallReady",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CallCore"),
        .executableTarget(name: "CallReady", dependencies: ["CallCore"]),
        .testTarget(name: "CallReadyTests", dependencies: ["CallCore", "CallReady"])
    ]
)
