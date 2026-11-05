// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "CronSpindle", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [
.target(name: "CronSpindleCore"),
.executableTarget(name: "CronSpindle", dependencies: ["CronSpindleCore", "MASKit"], resources: [.copy("Resources")]),
.testTarget(name: "CronSpindleCoreTests", dependencies: ["CronSpindleCore"]),
.testTarget(name: "AppRegressionTests", dependencies: ["CronSpindle", "CronSpindleCore"])
])
