// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "KeyOverlap", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [
.target(name: "KeyOverlapCore"),
.executableTarget(name: "KeyOverlap", dependencies: ["KeyOverlapCore", "MASKit"]),
.testTarget(name: "KeyOverlapCoreTests", dependencies: ["KeyOverlapCore"])
])
