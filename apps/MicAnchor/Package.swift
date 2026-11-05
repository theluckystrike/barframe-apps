// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fidelity",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FidelityCore"),
        .executableTarget(name: "Fidelity", dependencies: ["FidelityCore"]),
        .testTarget(name: "FidelityCoreTests", dependencies: ["FidelityCore", "Fidelity"])
    ]
)
