// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PageParcel", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [.target(name: "PageParcelCore"), .executableTarget(name: "PageParcel", dependencies: ["PageParcelCore", "MASKit"], resources: [.process("Resources")]), .testTarget(name: "PageParcelCoreTests", dependencies: ["PageParcelCore"]), .testTarget(name: "PageParcelModelTests", dependencies: ["PageParcel", "PageParcelCore"])])
