import Foundation

/// Per-device memory: what volume a device had before it was muted by volume-zero,
/// and whether the user muted it through CallReady (so we can re-apply after a
/// default-device switch). Codable + JSON on disk inside the sandbox container.
public struct DeviceMemory: Codable, Equatable, Sendable {
    public var mutedByApp: [String: Bool]
    public var volumeBeforeMute: [String: Float]

    public init(mutedByApp: [String: Bool] = [:], volumeBeforeMute: [String: Float] = [:]) {
        self.mutedByApp = mutedByApp
        self.volumeBeforeMute = volumeBeforeMute
    }

    public func wasMutedByApp(_ id: String) -> Bool { mutedByApp[id] ?? false }
    public func rememberedVolume(_ id: String) -> Float? { volumeBeforeMute[id] }

    public mutating func markMuted(_ id: String, volumeBefore: Float?) {
        mutedByApp[id] = true
        if let volumeBefore, volumeBefore > 0 { volumeBeforeMute[id] = volumeBefore }
    }
    public mutating func markUnmuted(_ id: String) {
        mutedByApp[id] = false
    }
    public mutating func forget(_ id: String) {
        mutedByApp.removeValue(forKey: id)
        volumeBeforeMute.removeValue(forKey: id)
    }
}

/// JSON file store for DeviceMemory.
public struct MemoryStore {
    public let url: URL
    public init(directory: URL) {
        self.url = directory.appendingPathComponent("device-memory.json")
    }

    public func load() -> DeviceMemory {
        guard let data = try? Data(contentsOf: url) else { return DeviceMemory() }
        return (try? JSONDecoder().decode(DeviceMemory.self, from: data)) ?? DeviceMemory()
    }

    public func save(_ memory: DeviceMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
