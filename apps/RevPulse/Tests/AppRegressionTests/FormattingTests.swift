import Foundation
import Testing
import RevPulseCore

struct FormattingTests {
    @Test func basicMoney() {
        #expect(Formatting.money(499, currency: "usd") == "$4.99")
    }
    @Test func zeroMoney() {
        #expect(Formatting.money(0, currency: "usd") == "$0.00")
    }
    @Test func negativeMoney() {
        #expect(Formatting.money(-12345, currency: "usd") == "−$123.45")
    }
    @Test func zeroAndThreeDecimalCurrencies() {
        #expect(Formatting.money(500, currency: "jpy") == "¥500")
        #expect(Formatting.money(-500, currency: "jpy") == "−¥500")
        #expect(Formatting.money(12345, currency: "bhd") == "BHD 12.345")
        #expect(Formatting.money(500, currency: "isk") == "ISK 5.00")
        #expect(Formatting.money(500, currency: "ugx") == "UGX 5.00")
    }
    @Test func thousandsSeparator() {
        #expect(Formatting.money(1_234_567, currency: "usd") == "$12,345.67")
    }
    @Test func euroSymbol() {
        #expect(Formatting.money(999, currency: "eur") == "€9.99")
    }
    @Test func unknownCurrencyKeepsCode() {
        #expect(Formatting.money(500, currency: "xyz") == "XYZ 5.00")
    }
    @Test func percent() {
        #expect(Formatting.percent(0.5) == "50%")
        #expect(Formatting.percent(0.999) == "100%")
    }
    @Test func menuBarTitle() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 14))!
        let snap = SampleData.snapshot(now: now)
        #expect(Formatting.menuBarTitle(snapshot: snap) == "$22.95")
    }
}
