// swift-tools-version:5.9
import PackageDescription

// Maps the package directory to "." in #file and #filePath literals and in debug info,
// so no absolute build path is embedded in the products. Clang module breadcrumbs
// would otherwise keep module cache paths in debug info.
let pathHygiene: [SwiftSetting] = [
    .unsafeFlags([
        "-file-prefix-map", "\(Context.packageDirectory)=.",
        "-debug-prefix-map", "\(Context.packageDirectory)=.",
        "-Xfrontend", "-no-clang-module-breadcrumbs",
    ]),
]
// Object file paths in the linked debug map become relative to the package directory.
let relativeObjectPaths: [LinkerSetting] = [
    .unsafeFlags(["-Xlinker", "-oso_prefix", "-Xlinker", Context.packageDirectory + "/"]),
]

let package = Package(name: "NativeLedger", platforms: [.macOS(.v14)], targets: [
    .target(name: "LedgerCore", swiftSettings: pathHygiene),
    .executableTarget(name: "NativeLedger", dependencies: ["LedgerCore"], resources: [.copy("Resources")],
                      swiftSettings: pathHygiene, linkerSettings: relativeObjectPaths),
    .testTarget(name: "LedgerCoreTests", dependencies: ["LedgerCore"], swiftSettings: pathHygiene,
                linkerSettings: relativeObjectPaths),
    .testTarget(name: "NativeLedgerAppTests", dependencies: ["NativeLedger", "LedgerCore"], swiftSettings: pathHygiene,
                linkerSettings: relativeObjectPaths),
])
