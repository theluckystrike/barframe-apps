import Foundation
@testable import LedgerCore

// Synthetic bundles on disk. None of them is a real app.
let thinArm64Header = Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]) + Data(count: 24)

func fatHeader(_ cpus: [UInt32]) -> Data {
    func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }
    var bytes: [UInt8] = [0xca, 0xfe, 0xba, 0xbe] + be(UInt32(cpus.count))
    for cpu in cpus { bytes += be(cpu) + be(0) + be(0x4000) + be(0x100) + be(14) }
    return Data(bytes) + Data(count: 64)
}

@discardableResult
func makeApp(_ root: URL, _ relative: String, id: String, version: String = "1.0", exe: Data = thinArm64Header,
             extra: [String: Any] = [:], codeResources: Bool = true) throws -> URL {
    let fm = FileManager.default
    let app = root.appendingPathComponent(relative)
    try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    var plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "Main",
                                "CFBundleShortVersionString": version, "CFBundleVersion": version.replacingOccurrences(of: ".", with: "")]
    plist.merge(extra) { _, new in new }
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
    try exe.write(to: app.appendingPathComponent("Contents/MacOS/Main"))
    if codeResources {
        try fm.createDirectory(at: app.appendingPathComponent("Contents/_CodeSignature"), withIntermediateDirectories: true)
        try Data("resources".utf8).write(to: app.appendingPathComponent("Contents/_CodeSignature/CodeResources"))
    }
    return app
}

func relativeNames(_ urls: [URL], in root: URL) -> [String] {
    let base = root.standardizedFileURL.path
    return urls.map { String($0.standardizedFileURL.path.dropFirst(base.count + 1)) }
}

/// Records every call and reads the bundle identifier, version and executable digest from disk.
final class FakeInspector: @unchecked Sendable {
    var calls: [String] = []
    var failure: InspectionFailure?
    func inspect(_ url: URL) -> InspectionResult {
        calls.append(url.lastPathComponent)
        if let failure { return .failed(failure) }
        let plist = MachOArchitecture.infoPlist(url)
        let sha = MachOArchitecture.executableURL(forBundle: url).flatMap { SystemInspectionSource.sha256(of: $0) }
        return InspectionResult(observation: obs(plist["CFBundleIdentifier"] as? String ?? "unknown",
                                                 version: plist["CFBundleShortVersionString"] as? String ?? "1.0",
                                                 sha: sha, at: t0.addingTimeInterval(Double(calls.count))), failure: nil)
    }
}

/// An observation that recorded the extended fields.
func extendedObs(usage: [String: String] = ["NSCameraUsageDescription": "Scans pages."], background: [String] = ["com.example.editor.helper"],
                 feed: String? = "https://updates.example.com/appcast.xml", minimum: String? = "14.0",
                 slices: [String] = ["arm64", "x86_64"], validity: SignatureValidity = .valid, extended: Bool = true,
                 cdhash: String? = String(repeating: "a", count: 40), sha: String? = String(repeating: "b", count: 64),
                 at: Date = t0) -> LedgerObservation {
    var o = obs(cdhash: cdhash, sha: sha, at: at)
    o.usageDescriptions = usage; o.backgroundItems = background.sorted(); o.updateFeedURL = feed
    o.minimumSystemVersion = minimum; o.architectureSlices = slices.sorted(); o.signatureValidity = validity
    o.extendedFields = extended
    return o
}
