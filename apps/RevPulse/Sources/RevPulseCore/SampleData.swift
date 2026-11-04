import Foundation

/// Deterministic fixture responses shaped like the examples in the Stripe API
/// docs. Sample mode renders these instead of calling the network.
public enum SampleData {

    /// One Stripe charges.list page (docs example shape, expanded balance_transaction).
    public static func chargesJSON(now: Date) -> Data {
        let cal = Calendar(identifier: .gregorian)
        var utc = cal; utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        func unix(_ dayOffset: Int, _ hour: Int) -> Int {
            let day = utc.date(byAdding: .day, value: dayOffset, to: utc.startOfDay(for: now))!
            return Int(day.addingTimeInterval(TimeInterval(hour * 3600)).timeIntervalSince1970)
        }
        func charge(_ id: String, amount: Int, net: Int, day: Int, hour: Int,
                    status: String = "succeeded", customer: String? = "cus_Sample001",
                    invoice: String? = nil, failure: String? = nil, refunded: Int = 0) -> [String: Any] {
            var json: [String: Any] = [
                "id": id, "object": "charge", "amount": amount, "amount_captured": amount,
                "amount_refunded": refunded, "currency": "usd", "created": unix(day, hour),
                "status": status, "paid": status == "succeeded",
                "balance_transaction": ["id": "txn_\(id)", "object": "balance_transaction", "net": net, "currency": "usd", "created": unix(day, hour)],
                "customer": customer as Any? ?? NSNull(), "invoice": invoice as Any? ?? NSNull()
            ]
            if refunded > 0 { json["refunds"] = ["object": "list", "data": []] }
            if let f = failure {
                json["failure_code"] = "card_declined"
                json["failure_message"] = f
            }
            return json
        }
        let page: [String: Any] = [
            "object": "list",
            "data": [
                charge("ch_Sample07", amount: 499, net: 463, day: 0, hour: 9),
                charge("ch_Sample06", amount: 1900, net: 1832, day: 0, hour: 11, customer: "cus_Sample002"),
                charge("ch_Sample05", amount: 1200, net: 0, day: 0, hour: 13, status: "failed",
                       customer: "cus_Sample003", failure: "Your card was declined."),
                charge("ch_Sample04", amount: 990, net: 942, day: -1, hour: 8),
                charge("ch_Sample03", amount: 4900, net: 4752, day: -1, hour: 15, customer: "cus_Sample002"),
                charge("ch_Sample02", amount: 2400, net: 2318, day: -3, hour: 10, refunded: 2400),
                charge("ch_Sample01", amount: 1200, net: 1158, day: -5, hour: 12, customer: "cus_Sample004")
            ],
            "has_more": false
        ]
        return try! JSONSerialization.data(withJSONObject: page)
    }

    public static func charges(now: Date = Date()) throws -> [StripeCharge] {
        try StripeDecoder.page(chargesJSON(now: now)) { try StripeDecoder.charge($0) }.items
    }

    public static func customersJSON(now: Date) -> Data {
        let cal = Calendar(identifier: .gregorian)
        var utc = cal; utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        func unix(_ dayOffset: Int) -> Int {
            Int(utc.date(byAdding: .day, value: dayOffset, to: utc.startOfDay(for: now))!.timeIntervalSince1970)
        }
        let page: [String: Any] = [
            "object": "list",
            "data": [
                ["id": "cus_Sample002", "object": "customer", "created": unix(-1), "email": "sample2@example.com"],
                ["id": "cus_Sample003", "object": "customer", "created": unix(0), "email": "sample3@example.com"],
                ["id": "cus_Sample004", "object": "customer", "created": unix(-5), "email": "sample4@example.com"]
            ],
            "has_more": false
        ]
        return try! JSONSerialization.data(withJSONObject: page)
    }

    public static func customers(now: Date = Date()) throws -> [StripeCustomer] {
        try StripeDecoder.page(customersJSON(now: now)) { json in
            guard let id = json["id"] as? String, let created = json["created"] as? Int else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "customer"))
            }
            return StripeCustomer(id: id, created: created)
        }.items
    }

    public static func subscriptionsJSON(now: Date) -> Data {
        let cal = Calendar(identifier: .gregorian)
        var utc = cal; utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let created = Int(utc.startOfDay(for: now).timeIntervalSince1970)
        let page: [String: Any] = [
            "object": "list",
            "data": [
                ["id": "sub_Sample01", "object": "subscription", "status": "active", "created": created],
                ["id": "sub_Sample02", "object": "subscription", "status": "active", "created": created]
            ],
            "has_more": false
        ]
        return try! JSONSerialization.data(withJSONObject: page)
    }

    public static func subscriptions(now: Date = Date()) throws -> [StripeSubscription] {
        try StripeDecoder.page(subscriptionsJSON(now: now)) { json in
            guard let id = json["id"] as? String, let status = json["status"] as? String,
                  let created = json["created"] as? Int else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "subscription"))
            }
            return StripeSubscription(id: id, status: status, created: created)
        }.items
    }

    public static func refundsJSON(now: Date) -> Data {
        let cal = Calendar(identifier: .gregorian)
        var utc = cal; utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let created = Int(utc.date(byAdding: .day, value: -3, to: utc.startOfDay(for: now))!.timeIntervalSince1970)
        let page: [String: Any] = [
            "object": "list",
            "data": [["id": "re_Sample01", "object": "refund", "amount": 2400, "created": created, "currency": "usd"]],
            "has_more": false
        ]
        return try! JSONSerialization.data(withJSONObject: page)
    }

    public static func refunds(now: Date = Date()) throws -> [StripeRefund] {
        try StripeDecoder.page(refundsJSON(now: now)) { json in
            guard let id = json["id"] as? String, let amount = json["amount"] as? Int,
                  let created = json["created"] as? Int else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "refund"))
            }
            return StripeRefund(id: id, amount: amount, created: created)
        }.items
    }

    public static func balanceTransactions(now: Date = Date()) -> [StripeBalanceTransaction] {
        let charges = (try? Self.charges(now: now)) ?? []
        let refunds = (try? Self.refunds(now: now)) ?? []
        return charges.filter { $0.status == "succeeded" }.map {
            StripeBalanceTransaction(id: "txn_" + $0.id, amount: $0.amount, net: $0.net!, currency: "usd", created: $0.created, type: "charge")
        } + refunds.map {
            StripeBalanceTransaction(id: "txn_" + $0.id, amount: -$0.amount, net: -$0.amount, currency: "usd", created: $0.created, type: "refund")
        }
    }
    /// The full sample snapshot.
    public static func snapshot(now: Date = Date(), goalCents: Int = 10_000) -> Revenue.Snapshot {
        let charges = (try? Self.charges(now: now)) ?? []
        let customers = (try? Self.customers(now: now)) ?? []
        let subs = (try? Self.subscriptions(now: now)) ?? []
        let refunds = (try? Self.refunds(now: now)) ?? []
        return Revenue.snapshot(charges: charges, customers: customers, subscriptions: subs,
                                refunds: refunds, currency: "usd", goalCents: goalCents, now: now, balanceTransactions: balanceTransactions(now: now))
    }
}
