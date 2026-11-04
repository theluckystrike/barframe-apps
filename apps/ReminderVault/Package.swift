// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ReminderVault", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [
.target(name: "VaultCore"), .executableTarget(name: "ReminderVault", dependencies: ["VaultCore", "MASKit"], resources: [.copy("Resources")]), .testTarget(name: "VaultCoreTests", dependencies: ["VaultCore"])])
