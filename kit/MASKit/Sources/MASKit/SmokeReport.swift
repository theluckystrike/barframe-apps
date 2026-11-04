import Foundation

/// One check in a smoke run. `pass` is the verdict; `detail` carries the measured value.
public struct SmokeCheck: Codable, Equatable {
    public let name: String
    public let pass: Bool
    public let detail: String

    public init(name: String, pass: Bool, detail: String) {
        self.name = name
        self.pass = pass
        self.detail = detail
    }
}

/// Smoke report contract read by kit/mas_gate.sh.
/// The app writes it to NSHomeDirectory()/smoke.json. Inside App Sandbox that path is
/// ~/Library/Containers/<bundle-id>/Data/smoke.json, which proves the sandbox is active.
public struct SmokeReport: Codable {
    public let app: String
    public let bundleID: String
    public let version: String
    public let sandboxed: Bool
    public let home: String
    public let checks: [SmokeCheck]
    public let pass: Bool
    public let generatedAt: String

    public init(app: String, bundleID: String, version: String, checks: [SmokeCheck]) {
        self.app = app
        self.bundleID = bundleID
        self.version = version
        self.sandboxed = SmokeReport.isSandboxed
        self.home = NSHomeDirectory()
        self.checks = checks
        self.pass = !checks.isEmpty && checks.allSatisfy(\.pass)
        self.generatedAt = ISO8601DateFormatter().string(from: Date())
    }

    /// True when the process runs inside App Sandbox.
    public static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Writes smoke.json atomically into the home (container) directory and returns its URL.
    @discardableResult
    public func write() throws -> URL {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("smoke.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        return url
    }
}

/// Command-line modes shared by every app.
public enum LaunchMode: Equatable {
    case normal
    case smoke
    case screenshots

    public static func current(_ arguments: [String] = CommandLine.arguments) -> LaunchMode {
        if arguments.contains("--smoke") { return .smoke }
        if arguments.contains("--screenshots") { return .screenshots }
        return .normal
    }
}
