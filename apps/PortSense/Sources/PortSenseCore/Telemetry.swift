import Foundation

public enum PowerTelemetry {
    public static func watts(millivolts: Double?, milliamps: Double?) -> Double? {
        guard let voltage = millivolts, voltage.isFinite, voltage > 0,
              let current = milliamps, current.isFinite else { return nil }
        let watts = voltage * current / 1_000_000
        return watts.isFinite && abs(watts) <= 1000 ? watts : nil
    }
    public static func inputWatts(_ properties: [String: Any]) -> Double? {
        if let value = ReadValue.number(properties["SystemPowerIn"]), (0...1_000_000).contains(value) { return value / 1000 }
        return watts(millivolts: ReadValue.positive(properties["SystemVoltageIn"]), milliamps: ReadValue.number(properties["SystemCurrentIn"]))
            .flatMap { $0 >= 0 ? $0 : nil }
    }
}

public enum DetailFormat {
    public static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Unavailable" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + " W"
    }
    public static func temperature(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + " °C" } ?? "Unavailable"
    }
    public static func minutes(_ value: Int?) -> String {
        guard let value, value >= 0, value != 65535 else { return "Unavailable" }
        if value == 0 { return "Less than 1 min" }
        return value >= 60 ? "\(value / 60) h \(value % 60) min" : "\(value) min"
    }
}
