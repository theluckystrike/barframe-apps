// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ColumnLatch", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [.target(name: "ColumnLatchCore"), .executableTarget(name: "ColumnLatch", dependencies: ["ColumnLatchCore", "MASKit"]), .testTarget(name: "ColumnLatchCoreTests", dependencies: ["ColumnLatchCore"])])
