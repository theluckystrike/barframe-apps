// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PortSense",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PortSenseApp", targets: ["PortSenseApp"])],
    dependencies: [.package(path: "../../kit/MASKit")],
    targets: [
        .target(name: "PortSenseCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "PortSenseApp", dependencies: ["PortSenseCore", .product(name: "MASKit", package: "MASKit")], resources: [.copy("Content")]),
        .testTarget(name: "PortSenseCoreTests", dependencies: ["PortSenseCore", "PortSenseApp", .product(name: "MASKit", package: "MASKit")], resources: [.copy("Fixtures")])
    ]
)
