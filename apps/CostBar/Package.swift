// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "CostBar", platforms: [.macOS(.v14)],
    products: [.executable(name: "CostBarApp", targets: ["CostBarApp"])],
    dependencies: [.package(path: "../../kit/MASKit")],
    targets: [
        .target(name: "CostBarCore"),
        .executableTarget(name: "CostBarApp", dependencies: ["CostBarCore", .product(name: "MASKit", package: "MASKit")], resources: [.copy("Fixtures"), .copy("PrivacyPolicy.txt"), .copy("Support.txt")]),
        .testTarget(name: "CostBarAppTests", dependencies: ["CostBarApp", "CostBarCore"]),
        .testTarget(name: "CostBarCoreTests", dependencies: ["CostBarCore"], resources: [.copy("Fixtures")])
    ]
)
