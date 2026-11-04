// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RouteLoom", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [
.target(name: "RouteLoomCore"),
.executableTarget(name: "RouteLoom", dependencies: ["RouteLoomCore", "MASKit"]),
.testTarget(name: "RouteLoomCoreTests", dependencies: ["RouteLoomCore", "RouteLoom"])
])
