import Foundation

/// Net payment movements in one validated settlement currency, bucketed by UTC date.
public enum Revenue {
    public struct Day: Equatable, Sendable {
        public let date: Date
        public let netCents: Int // Stripe minor units; retained name for source compatibility.
        public let charges: Int
        public init(date: Date, netCents: Int, charges: Int) { self.date = date; self.netCents = netCents; self.charges = charges }
    }
    public struct Snapshot: Equatable, Sendable {
        public let currency: String
        public let fetchedAt: Date
        public let today: Day
        public let yesterday: Day
        public let last7Days: [Day]
        public let monthToDateNetCents: Int
        public let newCustomersMTD: Int
        public let newSubscriptionsMTD: Int
        public let failedPaymentsMTD: Int
        public let refundsMTDCents: Int
        public var goalCents: Int
        public let netComplete: Bool
        public let netIssue: String?
        public var goalProgress: Double { netComplete && goalCents > 0 ? max(0, min(1, Double(monthToDateNetCents) / Double(goalCents))) : 0 }
    }
    public static func dayKey(_ unix: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        var cal = calendar; cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(unix)))
    }
    public static let paymentTypes: Set<String> = ["charge", "payment", "refund", "payment_refund", "refund_failure", "payment_failure_refund", "payment_reversal"]
    public static let refundTypes: Set<String> = ["refund", "payment_refund", "refund_failure", "payment_failure_refund"]
    public static func snapshot(charges: [StripeCharge], customers: [StripeCustomer],
        subscriptions: [StripeSubscription], refunds: [StripeRefund], currency: String, goalCents: Int,
        now: Date = Date(), balanceTransactions: [StripeBalanceTransaction]? = nil) -> Snapshot {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let todayStart = cal.startOfDay(for: now)
        let mtdStart = cal.date(from: cal.dateComponents([.year, .month], from: todayStart))!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: todayStart)!
        let movements = (balanceTransactions ?? []).filter { paymentTypes.contains($0.type) && dayKey($0.created) < tomorrow }
        let missingNet = charges.contains { $0.status == "succeeded" && ($0.net == nil || $0.settlementCurrency == nil || $0.settlementCreated == nil) }
        let multipleCurrencies = !movements.allSatisfy { $0.currency.lowercased() == currency.lowercased() }
        let complete = balanceTransactions != nil && !missingNet && !multipleCurrencies
        let issue = complete ? nil : (multipleCurrencies ? "Net unavailable: multiple settlement currencies. Totals are not combined." : "Net unavailable: balance movements are missing or incomplete. Please retry.")
        func day(_ start: Date) -> Day {
            let matching = movements.filter { dayKey($0.created) == start }
            return Day(date: start, netCents: complete ? matching.reduce(0) { $0 + $1.net } : 0,
                       charges: charges.filter { $0.status == "succeeded" && dayKey($0.created) == start }.count)
        }
        let week = (-6...0).map { day(cal.date(byAdding: .day, value: $0, to: todayStart)!) }
        func inMTD(_ unix: Int) -> Bool { let date = dayKey(unix); return date >= mtdStart && date < tomorrow }
        let mtd = movements.filter { inMTD($0.created) }
        return Snapshot(currency: currency, fetchedAt: now, today: week[6], yesterday: week[5], last7Days: week,
            monthToDateNetCents: complete ? mtd.reduce(0) { $0 + $1.net } : 0,
            newCustomersMTD: customers.filter { inMTD($0.created) }.count,
            newSubscriptionsMTD: subscriptions.filter { inMTD($0.created) }.count,
            failedPaymentsMTD: charges.filter { $0.status == "failed" && inMTD($0.created) }.count,
            refundsMTDCents: complete ? -mtd.filter { refundTypes.contains($0.type) }.reduce(0) { $0 + $1.amount } : 0,
            goalCents: goalCents, netComplete: complete, netIssue: issue)
    }
    public enum Event: Equatable, Sendable {
        case firstSaleToday(chargeID: String)
        case failedPayment(chargeID: String, message: String?)
    }
    public static func events(charges: [StripeCharge], now: Date = Date(), alreadyNotifiedSale: Bool = false) -> [Event] {
        let today = dayKey(Int(now.timeIntervalSince1970))
        let todays = charges.filter { dayKey($0.created) == today && $0.created <= Int(now.timeIntervalSince1970) }
        var result: [Event] = []
        if !alreadyNotifiedSale, let first = todays.filter({ $0.status == "succeeded" }).min(by: { $0.created < $1.created }) {
            result.append(.firstSaleToday(chargeID: first.id))
        }
        result += todays.filter { $0.status == "failed" }.map { .failedPayment(chargeID: $0.id, message: $0.failureMessage) }
        return result
    }
}

public struct NotificationHistory {
    public var tokens: Set<String>
    public init(tokens: Set<String> = []) { self.tokens = tokens }
    public mutating func pending(charges: [StripeCharge], now: Date, firstSale: Bool, failedPayment: Bool) -> [Revenue.Event] {
        let day = String(Int(Revenue.dayKey(Int(now.timeIntervalSince1970)).timeIntervalSince1970))
        tokens = tokens.filter { $0.hasPrefix(day + ":") }
        return Revenue.events(charges: charges, now: now).filter { event in
            let token: String
            switch event {
            case .firstSaleToday: guard firstSale else { return false }; token = day + ":sale"
            case .failedPayment(let id, _): guard failedPayment else { return false }; token = day + ":failed:" + id
            }
            return tokens.insert(token).inserted
        }
    }
}
