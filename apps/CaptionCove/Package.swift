// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "CaptionCove", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [
.target(name: "CaptionCoveCore"),
.executableTarget(name: "CaptionCove", dependencies: ["CaptionCoveCore", "MASKit"], resources: [.copy("LocalDocuments")]),
.testTarget(name: "CaptionCoveCoreTests", dependencies: ["CaptionCoveCore"]),
.testTarget(name: "CaptionCoveAppTests", dependencies: ["CaptionCove", "CaptionCoveCore"])
])
