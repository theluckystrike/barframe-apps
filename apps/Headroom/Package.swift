// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Headroom", platforms: [.macOS(.v14)], products: [.executable(name: "Headroom", targets: ["Headroom"])], targets: [.target(name: "CProbe"), .target(name: "HeadroomModel", dependencies: ["CProbe"]), .executableTarget(name: "Headroom", dependencies: ["HeadroomModel"], resources: [.copy("Resources/Upstream-LICENSE.txt")]), .testTarget(name: "HeadroomTests", dependencies: ["HeadroomModel", "CProbe"])])
