// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "MeetNext", platforms: [.macOS(.v14)], dependencies: [
    .package(path: "../../kit/MASKit")
], targets: [
    .target(name: "MeetNextCore"),
    .executableTarget(name: "MeetNext", dependencies: ["MeetNextCore", "MASKit"], resources: [.copy("Resources")]),
    .testTarget(name: "MeetNextCoreTests", dependencies: ["MeetNextCore"]),
    .testTarget(name: "AppRegressionTests", dependencies: ["MeetNext", "MeetNextCore", "MASKit"])
])
