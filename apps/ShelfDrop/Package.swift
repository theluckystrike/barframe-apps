// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShelfDock",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ShelfDockApp", targets: ["ShelfDockApp"])],
    dependencies: [.package(path: "../../kit/MASKit")],
    targets: [
        .target(name: "ShelfDockCore"),
        .executableTarget(name: "ShelfDockApp", dependencies: ["ShelfDockCore", .product(name: "MASKit", package: "MASKit")], resources: [.copy("Content")]),
        .testTarget(name: "ShelfDockCoreTests", dependencies: ["ShelfDockCore", "ShelfDockApp", .product(name: "MASKit", package: "MASKit")])
    ]
)
