// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "QuotaPace", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../kit/MASKit")],
    targets: [
        .target(name: "QuotaPaceCore"),
        .executableTarget(name: "QuotaPaceApp", dependencies: ["QuotaPaceCore", .product(name: "MASKit", package: "MASKit")], resources: [.copy("Resources")]),
        .testTarget(name: "QuotaPaceCoreTests", dependencies: ["QuotaPaceCore", "QuotaPaceApp"], resources: [.copy("Fixtures")])
    ]
)
