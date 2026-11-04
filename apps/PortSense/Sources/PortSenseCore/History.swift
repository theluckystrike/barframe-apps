import Foundation

public struct WattageSample: Codable, Equatable, Identifiable, Sendable {
    public let date: Date
    public let watts: Double?
    public let failure: String?
    public let supply: PowerSupply
    public var id: Date { date }
    public init(date: Date, watts: Double?, supply: PowerSupply, failure: String? = nil) {
        self.date = date
        self.watts = watts.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.supply = supply
        self.failure = failure
    }
    public init(snapshot: PowerSnapshot) {
        self.init(date: snapshot.date, watts: snapshot.adapter?.watts, supply: snapshot.supply)
    }
}

public struct WattagePlotPoint: Identifiable, Sendable {
    public let date: Date
    public let watts: Double
    public let segment: Int
    public var id: Date { date }
}

public struct WattageHistory: Sendable {
    public static let capacity = 60
    public private(set) var samples: [WattageSample] = []
    public init() {}
    public mutating func append(_ sample: WattageSample) {
        // Preserve chronological order across asynchronous refreshes and clock adjustments.
        guard samples.last.map({ sample.date > $0.date }) ?? true else { return }
        samples.append(sample)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }
    /// Periodic attempts always occupy a sample; failed manual attempts also break the line.
    public mutating func record(_ result: Result<PowerSnapshot, any Error>, date: Date, periodic: Bool) {
        switch result {
        case .success(let snapshot):
            if periodic || samples.last.map({ snapshot.date.timeIntervalSince($0.date) >= 14 }) ?? true {
                append(WattageSample(snapshot: snapshot))
            }
        case .failure(let error):
            append(WattageSample(date: date, watts: nil, supply: .unknown, failure: error.localizedDescription))
        }
    }
    public var failedReadCount: Int { samples.filter { $0.failure != nil }.count }
    public var latestFailure: WattageSample? { samples.last { $0.failure != nil } }
    public var plotPoints: [WattagePlotPoint] {
        var segment = 0
        return samples.compactMap { sample in
            guard let watts = sample.watts else { segment += 1; return nil }
            return WattagePlotPoint(date: sample.date, watts: watts, segment: segment)
        }
    }
    public var range: ClosedRange<Double>? {
        let values = samples.compactMap(\.watts)
        guard let minimum = values.min(), let maximum = values.max() else { return nil }
        return minimum...maximum
    }

    /// The smoke mode uses the same encoding as the container export.
    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(samples).write(to: url, options: .atomic)
    }
    public static func read(from url: URL) throws -> WattageHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let values = try decoder.decode([WattageSample].self, from: Data(contentsOf: url))
        var history = WattageHistory()
        for value in values.sorted(by: { $0.date < $1.date }) {
            history.append(WattageSample(date: value.date, watts: value.watts, supply: value.supply, failure: value.failure))
        }
        return history
    }
}

public enum ReadingFormat {
    public static let rawCapacityLabel = "Full charge capacity vs design (raw)"
    public static func statusAccessibilityLabel(_ snapshot: PowerSnapshot?, error: String? = nil, sample: Bool = false) -> String {
        let prefix = sample ? "PortSense, Sample" : "PortSense"
        guard error == nil else { return prefix + ", power reading unavailable" }
        guard let snapshot else { return prefix + ", checking power source" }
        var label = prefix + ", " + snapshot.supply.label
        if snapshot.supply == .battery, let charge = snapshot.battery?.chargePercent {
            label += ", battery \(charge) percent"
        } else if snapshot.adapter?.watts != nil {
            label += ", charger capacity " + watts(snapshot.adapter?.watts)
        }
        return label
    }
    public static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "Unavailable" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + " W"
    }
    public static func menuValue(_ snapshot: PowerSnapshot?) -> String {
        guard let snapshot else { return "" }
        if snapshot.supply == .battery, let percent = snapshot.battery?.chargePercent { return "\(percent)%" }
        if let watts = snapshot.adapter?.watts, watts > 0, watts < 1000 { return "\(Int(watts.rounded()))W" }
        return ""
    }
}

public enum HistoryAxis {
    public static let format = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()
    public static func ticks(_ history: WattageHistory) -> [Date] {
        guard let first = history.samples.first?.date, let last = history.samples.last?.date else { return [] }
        if first == last { return [first] }
        return [first, first.addingTimeInterval(last.timeIntervalSince(first) / 2), last]
    }
}
