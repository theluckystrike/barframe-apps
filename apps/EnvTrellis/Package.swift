// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "EnvTrellis", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [
.target(name: "EnvTrellisCore"),
.executableTarget(name: "EnvTrellis", dependencies: ["EnvTrellisCore", "MASKit"]),
.testTarget(name: "EnvTrellisCoreTests", dependencies: ["EnvTrellisCore", "EnvTrellis"])
])
