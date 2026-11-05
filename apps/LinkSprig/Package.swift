// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "LinkSprig", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [
.target(name: "LinkSprigCore"),
.executableTarget(name: "LinkSprig", dependencies: ["LinkSprigCore", "MASKit"], resources: [.process("LocalPages")]),
.testTarget(name: "LinkSprigCoreTests", dependencies: ["LinkSprigCore"]),
.testTarget(name: "LinkSprigUITests", dependencies: ["LinkSprig", "LinkSprigCore"])
])
