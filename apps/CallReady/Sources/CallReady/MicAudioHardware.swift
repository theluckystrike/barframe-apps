import CoreAudio
import IOKit
import Foundation
import CallCore

struct HardwareError: LocalizedError {
    let operation: String
    let status: OSStatus
    var errorDescription: String? { "Audio devices changed — retrying." }
    var diagnosticDescription: String { "\(operation): CoreAudio status \(status)" }
}

protocol AudioHardwareAccess: AnyObject {
    var skippedIDs: [AudioObjectID] { get }
    func devices() throws -> [AudioDevice]
    func defaultInput() throws -> AudioObjectID
    func defaultOutput() throws -> AudioObjectID
    func lidClosed() -> Bool?
    func setInput(_ id: AudioObjectID) throws
    func startListening(_ changed: @escaping () -> Void) throws
    @discardableResult func stopListening() -> [OSStatus]
}

final class AudioHardware: AudioHardwareAccess {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private let queue = DispatchQueue.main
    private(set) var skippedIDs: [AudioObjectID] = []
    private(set) var callbackCount = 0

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw HardwareError(operation: operation, status: status) }
    }

    func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> UInt32 {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "Read \(selector) on \(object)")
        return value
    }

    private func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "Read string on \(object)")
        guard let value else { throw HardwareError(operation: "Read empty string on \(object)", status: -1) }
        return value.takeRetainedValue() as String
    }

    private func channelCount(_ object: AudioObjectID, scope: AudioObjectPropertyScope) throws -> Int {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), "Read stream size on \(object)")
        guard size > 0 else { return 0 }
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { data.deallocate() }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, data), "Read channels on \(object)")
        let buffers = UnsafeMutableAudioBufferListPointer(data.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    func devices() throws -> [AudioDevice] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(Self.system, &address, 0, nil, &size), "Read device list size")
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        if size > 0 {
            try ids.withUnsafeMutableBytes { data in
                try check(AudioObjectGetPropertyData(Self.system, &address, 0, nil, &size, data.baseAddress!), "Read devices")
            }
        }
        return readDevices(ids: ids)
    }

    func readDevices(ids: [AudioObjectID]) -> [AudioDevice] {
        skippedIDs = []
        return ids.compactMap { id -> AudioDevice? in
            do {
                return AudioDevice(id: id,
                    uid: try string(id, kAudioDevicePropertyDeviceUID),
                    name: try string(id, kAudioObjectPropertyName),
                    transport: Transport.classify(try uint32(id, kAudioDevicePropertyTransportType)),
                    inputChannels: try channelCount(id, scope: kAudioDevicePropertyScopeInput),
                    outputChannels: try channelCount(id, scope: kAudioDevicePropertyScopeOutput),
                    isAlive: try uint32(id, kAudioDevicePropertyDeviceIsAlive) != 0,
                    dataSourceAvailable: try dataSourceAvailable(id))
            } catch {
                skippedIDs.append(id)
                return nil
            }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func dataSourceAvailable(_ id: AudioObjectID) throws -> Bool {
        var sourceAddress = Self.address(kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeInput)
        var sourcesAddress = Self.address(kAudioDevicePropertyDataSources, scope: kAudioDevicePropertyScopeInput)
        guard AudioObjectHasProperty(id, &sourceAddress), AudioObjectHasProperty(id, &sourcesAddress) else { return true }
        var source: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(id, &sourceAddress, 0, nil, &size, &source), "Read input data source")
        try check(AudioObjectGetPropertyDataSize(id, &sourcesAddress, 0, nil, &size), "Read input data sources size")
        guard size > 0 else { return false }
        var sources = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.size)
        try sources.withUnsafeMutableBytes {
            try check(AudioObjectGetPropertyData(id, &sourcesAddress, 0, nil, &size, $0.baseAddress!), "Read input data sources")
        }
        return sources.contains(source)
    }

    func lidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    func defaultInput() throws -> AudioObjectID { try uint32(Self.system, kAudioHardwarePropertyDefaultInputDevice) }
    func defaultOutput() throws -> AudioObjectID { try uint32(Self.system, kAudioHardwarePropertyDefaultOutputDevice) }

    func setInput(_ id: AudioObjectID) throws {
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        var value = id
        try check(AudioObjectSetPropertyData(Self.system, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value), "Set default input")
    }

    func startListening(_ changed: @escaping () -> Void) throws {
        stopListening()
        do {
            for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
                var address = Self.address(selector)
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    self?.callbackCount += 1
                    changed()
                }
                try check(AudioObjectAddPropertyListenerBlock(Self.system, &address, queue, block), "Add listener \(selector)")
                listeners.append((address, block))
            }
        } catch {
            stopListening()
            throw error
        }
    }

    @discardableResult func stopListening() -> [OSStatus] {
        let statuses = listeners.map { item -> OSStatus in
            var address = item.0
            return AudioObjectRemovePropertyListenerBlock(Self.system, &address, queue, item.1)
        }
        listeners.removeAll()
        return statuses
    }

    deinit { stopListening() }
}
