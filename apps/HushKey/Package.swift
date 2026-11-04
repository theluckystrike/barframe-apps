// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "HushKey", platforms: [.macOS(.v14)], dependencies: [
    .package(path: "../../kit/MASKit")
], targets: [
    .target(name: "HushKeyCore"),
    .executableTarget(name: "HushKey", dependencies: ["HushKeyCore", "MASKit"], resources: [.copy("Resources")]),
    .testTarget(name: "HushKeyCoreTests", dependencies: ["HushKeyCore"]),
    .testTarget(name: "AppRegressionTests", dependencies: ["HushKey", "HushKeyCore", "MASKit"])
])
