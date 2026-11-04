// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MASKit",
    platforms: [.macOS(.v13)],
    products: [.library(name: "MASKit", targets: ["MASKit"])],
    targets: [
        .target(name: "MASKit"),
        .testTarget(name: "MASKitTests", dependencies: ["MASKit"])
    ]
)
