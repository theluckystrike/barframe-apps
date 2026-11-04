// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Starglass",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../kit/MASKit")
    ],
    targets: [
        .target(
            name: "StarglassCore",
            dependencies: []
        ),
        .executableTarget(
            name: "Starglass",
            dependencies: [
                "StarglassCore",
                "MASKit"
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "StarglassCoreTests",
            dependencies: ["StarglassCore"]
        ),
        .testTarget(
            name: "AppRegressionTests",
            dependencies: ["StarglassCore", "Starglass"],
            path: "Tests/AppRegressionTests"
        )
    ]
)
