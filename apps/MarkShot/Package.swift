// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "MarkShot", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [
.target(name: "MarkShotCore"),
.executableTarget(name: "MarkShot", dependencies: ["MarkShotCore", "MASKit"], resources: [.copy("Resources")]),
.testTarget(name: "MarkShotCoreTests", dependencies: ["MarkShotCore"])
])
