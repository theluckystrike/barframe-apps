// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "CheckHarbor", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [.target(name: "CheckHarborCore"), .executableTarget(name: "CheckHarbor", dependencies: ["CheckHarborCore", "MASKit"], resources: [.process("Resources")]), .testTarget(name: "CheckHarborCoreTests", dependencies: ["CheckHarborCore"]), .testTarget(name: "ClientTests", dependencies: ["CheckHarbor", "CheckHarborCore"])])
