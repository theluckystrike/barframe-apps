// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AgentPing", platforms: [.macOS(.v14)], targets: [
    .target(name: "AgentPingCore"),
    .executableTarget(name: "AgentPing", dependencies: ["AgentPingCore"]),
    .testTarget(name: "AgentPingCoreTests", dependencies: ["AgentPingCore", "AgentPing"])
])
