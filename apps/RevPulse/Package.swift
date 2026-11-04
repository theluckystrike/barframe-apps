// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RevPulse", platforms: [.macOS(.v14)], dependencies: [
    .package(path: "../../kit/MASKit")
], targets: [
    .target(name: "RevPulseCore", dependencies: ["MASKit"]),
    .executableTarget(name: "RevPulse", dependencies: ["RevPulseCore"], resources: [.copy("Resources")]),
    .testTarget(name: "AppRegressionTests", dependencies: ["RevPulseCore", "RevPulse", "MASKit"], path: "Tests/AppRegressionTests")
])
