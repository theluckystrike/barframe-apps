// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PermitPeek", platforms: [.macOS(.v14)], dependencies: [
    .package(path: "../../kit/MASKit")
], targets: [
    .target(name: "PermitPeekCore"),
    .executableTarget(name: "PermitPeek", dependencies: ["PermitPeekCore", "MASKit"], resources: [.copy("Resources")]),
    .testTarget(name: "PermitPeekCoreTests", dependencies: ["PermitPeekCore"]),
    .testTarget(name: "PermitPeekAppTests", dependencies: ["PermitPeek", "PermitPeekCore"])
])
