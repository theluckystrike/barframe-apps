// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "HashDock", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [.target(name: "HashDockCore"), .executableTarget(name: "HashDock", dependencies: ["HashDockCore", "MASKit"]), .testTarget(name: "HashDockCoreTests", dependencies: ["HashDockCore"])])
