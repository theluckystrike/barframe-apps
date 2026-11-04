import Foundation
import Testing
@testable import LedgerCore

func runTool(_ tool: String, _ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

/// A small ad hoc signed bundle made from a copy of /usr/bin/true, signed with codesign in a temporary folder.
/// A copy of a system app is not used: off the system volume its custom omit rules fail strict validation.
func adHocSignedBundle(in dir: URL) throws -> URL {
    let app = dir.appendingPathComponent("Tiny.app")
    let macos = app.appendingPathComponent("Contents/MacOS")
    try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": "com.example.tiny", "CFBundleExecutable": "Tiny", "CFBundleName": "Tiny",
                                "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macos.appendingPathComponent("Tiny"))
    #expect(try runTool("/usr/bin/codesign", ["--force", "--sign", "-", app.path]) == 0)
    return app
}

struct StrictSignatureTests {
    @Test func appendedBytesAfterLastSliceAreInvalid() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = try adHocSignedBundle(in: dir)
        #expect(SystemInspectionSource.validity(of: app) == .valid)
        let handle = try FileHandle(forWritingTo: app.appendingPathComponent("Contents/MacOS/Tiny"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0x41, count: 64))
        try handle.close()
        // codesign --verify --strict rejects the appended bytes, and so does the inspector's check.
        #expect(try runTool("/usr/bin/codesign", ["--verify", "--strict", app.path]) != 0)
        guard case .invalid = SystemInspectionSource.checkValidity(of: app, timeout: 20) else {
            Issue.record("appended bytes were not reported as invalid"); return
        }
    }
}
