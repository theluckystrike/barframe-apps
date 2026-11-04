// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "StepQuay", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [
.target(name: "StepQuayCore"),
.executableTarget(name: "StepQuay", dependencies: ["StepQuayCore", "MASKit"], resources: [.copy("LocalDocuments")]),
.testTarget(name: "StepQuayCoreTests", dependencies: ["StepQuayCore"]),
.testTarget(name: "StepQuayModelTests", dependencies: ["StepQuay", "StepQuayCore"])
])
