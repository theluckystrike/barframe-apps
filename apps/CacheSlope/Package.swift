// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "CacheSlope", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../kit/MASKit")], targets: [.target(name: "CacheSlopeCore"), .executableTarget(name: "CacheSlope", dependencies: ["CacheSlopeCore", "MASKit"]), .testTarget(name: "CacheSlopeCoreTests", dependencies: ["CacheSlopeCore"])])
