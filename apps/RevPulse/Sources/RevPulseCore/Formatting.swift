import Foundation

public enum Formatting {
    // Stripe keeps ISK/UGX in two-decimal API units for compatibility.
    // HUF/TWD balance movements use payment units, not payout rounding rules.
    public static func exponent(for currency: String) -> Int {
        let code = currency.uppercased()
        if ["ISK", "UGX", "HUF", "TWD"].contains(code) { return 2 }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }
    public static func money(_ units: Int, currency: String) -> String {
        let code = currency.count == 3 ? currency.uppercased() : "USD"
        let digits = exponent(for: code)
        let divisor = UInt(pow(10, Double(digits)))
        let value = units.magnitude
        let whole = format(String(value / divisor))
        let fraction = digits > 0 ? "." + String(repeating: "0", count: max(0, digits - String(value % divisor).count)) + String(value % divisor) : ""
        return (units < 0 ? "−" : "") + symbol(for: code) + whole + fraction
    }
    static func format(_ input: String) -> String {
        var digits = input, out = ""
        while digits.count > 3 { out = "," + digits.suffix(3) + out; digits = String(digits.dropLast(3)) }
        return digits + out
    }
    static func symbol(for code: String) -> String {
        switch code { case "USD": return "$"; case "EUR": return "€"; case "GBP": return "£"; case "JPY": return "¥"; default: return code + " " }
    }
    public static func menuBarTitle(snapshot: Revenue.Snapshot) -> String {
        snapshot.netComplete ? money(snapshot.today.netCents, currency: snapshot.currency) : "Net unavailable"
    }
    public static func percent(_ fraction: Double) -> String { String(format: "%.0f%%", fraction * 100) }
}
