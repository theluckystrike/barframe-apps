// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "NameWeave", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [
.target(name: "NameWeaveCore"),
.executableTarget(name: "NameWeave", dependencies: ["NameWeaveCore", "MASKit"], resources: [.process("LocalPolicies")]),
.testTarget(name: "NameWeaveCoreTests", dependencies: ["NameWeaveCore"]),
.testTarget(name: "AppRegressionTests", dependencies: ["NameWeave", "NameWeaveCore"])
])
