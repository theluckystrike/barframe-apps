import Foundation
import Testing
import RevPulseCore

struct SampleDataTests {
    var now: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 18))!
    }

    @Test func chargesFixtureParses() throws {
        let charges = try SampleData.charges(now: now)
        #expect(charges.count == 7)
        #expect(charges.allSatisfy { $0.currency == "usd" })
    }
    @Test func todayNet() throws {
        let snap = SampleData.snapshot(now: now)
        #expect(snap.today.netCents == 499 + 1900 - 104)  // 463+1832 = 2295
        #expect(snap.today.netCents == 2295)
    }
    @Test func failedPaymentCounted() throws {
        let snap = SampleData.snapshot(now: now)
        #expect(snap.failedPaymentsMTD == 1)
    }
    @Test func refundCounted() throws {
        let snap = SampleData.snapshot(now: now)
        #expect(snap.refundsMTDCents == 2400)
    }
    @Test func newCustomers() throws {
        let snap = SampleData.snapshot(now: now)
        #expect(snap.newCustomersMTD == 3)
    }
    @Test func newSubscriptions() throws {
        let snap = SampleData.snapshot(now: now)
        #expect(snap.newSubscriptionsMTD == 2)
    }
    @Test func goalProgress() {
        let snap = SampleData.snapshot(now: now)
        #expect(snap.goalCents == 10_000)
        #expect(abs(snap.goalProgress - Double(snap.monthToDateNetCents) / 10_000) < 0.0001)
        #expect(snap.goalProgress > 0)
    }
    @Test func last7DaysIsSevenEntries() throws {
        let snap = SampleData.snapshot(now: now)
        #expect(snap.last7Days.count == 7)
        #expect(snap.last7Days.last?.netCents == 2295)
    }
    @Test func yesterdayNet() throws {
        let snap = SampleData.snapshot(now: now)
        #expect(snap.yesterday.netCents == 942 + 4752)
    }
}
