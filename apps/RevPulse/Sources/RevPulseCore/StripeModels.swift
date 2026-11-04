import Foundation

public struct StripeCharge: Codable, Sendable, Equatable {
    public let id: String
    public let amount: Int          // cents, charge currency
    public let currency: String
    public let net: Int?            // cents from expanded balance_transaction
    public let settlementCurrency: String?
    public let settlementCreated: Int?
    public let refunded: Int
    public let created: Int         // unix
    public let customer: String?    // expanded customer object id
    public let invoice: String?     // invoice id when subscription charge
    public let failureCode: String?
    public let failureMessage: String?
    public let status: String

    enum CodingKeys: String, CodingKey {
        case id, amount, currency, net, settlementCurrency, settlementCreated, refunded, created, customer, invoice, status
        case failureCode = "failure_code"
        case failureMessage = "failure_message"
    }

    public init(id: String, amount: Int, currency: String, net: Int?, refunded: Int, created: Int,
                customer: String?, invoice: String?, failureCode: String?, failureMessage: String?, status: String, settlementCurrency: String? = nil, settlementCreated: Int? = nil) {
        self.id = id; self.amount = amount; self.currency = currency; self.net = net
        self.settlementCurrency = settlementCurrency; self.settlementCreated = settlementCreated
        self.refunded = refunded; self.created = created; self.customer = customer
        self.invoice = invoice; self.failureCode = failureCode; self.failureMessage = failureMessage; self.status = status
    }
}

public struct StripeCustomer: Codable, Sendable, Equatable {
    public let id: String
    public let created: Int
    public init(id: String, created: Int) { self.id = id; self.created = created }
}

public struct StripeSubscription: Codable, Sendable, Equatable {
    public let id: String
    public let status: String
    public let created: Int
    public init(id: String, status: String, created: Int) { self.id = id; self.status = status; self.created = created }
}

public struct StripeRefund: Codable, Sendable, Equatable {
    public let id: String
    public let amount: Int
    public let created: Int
    public init(id: String, amount: Int, created: Int) { self.id = id; self.amount = amount; self.created = created }
}

public struct StripeAccount: Codable, Sendable, Equatable {
    public let id: String
    public let defaultCurrency: String?
    enum CodingKeys: String, CodingKey { case id; case defaultCurrency = "default_currency" }
    public init(id: String, defaultCurrency: String?) { self.id = id; self.defaultCurrency = defaultCurrency }
}

public struct StripeAPIError: Error, LocalizedError, Equatable {
    public let kind: Kind
    public enum Kind: Equatable { case http(Int, String), unauthorized, network(String) }
    public init(_ kind: Kind) { self.kind = kind }
    public var errorDescription: String? {
        switch kind {
        case .http(let code, let message): return "Stripe API error \(code): \(message)"
        case .unauthorized: return "Stripe rejected the key. Check the restricted key in Settings."
        case .network(let m): return "Network error: \(m)"
        }
    }
}

public struct StripePage<T: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public let data: [T]
    public let hasMore: Bool
    enum CodingKeys: String, CodingKey { case data; case hasMore = "has_more" }
}

/// Decodes a charge JSON object shaped like Stripe API docs examples.
public enum StripeDecoder {
    public static func charge(_ json: [String: Any]) throws -> StripeCharge {
        guard let id = json["id"] as? String,
              let amount = json["amount"] as? Int,
              let currency = json["currency"] as? String,
              let created = json["created"] as? Int else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "charge missing core fields")) }
        var net: Int?
        if let bt = json["balance_transaction"] as? [String: Any], let n = bt["net"] as? Int { net = n }
        if json["balance_transaction"] is String { net = nil } // unexpanded id carries no net value
        let refunded = (json["amount_refunded"] as? Int) ?? 0
        let customer: String?
        if let c = json["customer"] as? String { customer = c }
        else if let c = json["customer"] as? [String: Any] { customer = c["id"] as? String }
        else { customer = nil }
        let invoice: String?
        if let i = json["invoice"] as? String { invoice = i }
        else if let i = json["invoice"] as? [String: Any] { invoice = i["id"] as? String }
        else { invoice = nil }
        return StripeCharge(id: id, amount: amount, currency: currency, net: net, refunded: refunded,
                            created: created, customer: customer, invoice: invoice,
                            failureCode: json["failure_code"] as? String,
                            failureMessage: json["failure_message"] as? String,
                            status: (json["status"] as? String) ?? "",
                            settlementCurrency: (json["balance_transaction"] as? [String: Any])?["currency"] as? String,
                            settlementCreated: (json["balance_transaction"] as? [String: Any])?["created"] as? Int)
    }

    public static func page<T>(_ data: Data, decode: ([String: Any]) throws -> T) throws -> (items: [T], hasMore: Bool) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = root["data"] as? [[String: Any]] else { throw StripeAPIError(.http(0, "unexpected response shape")) }
        return (try array.map(decode), (root["has_more"] as? Bool) ?? false)
    }
}

public struct StripeBalanceTransaction: Codable, Sendable, Equatable {
    public let id: String
    public let amount: Int
    public let net: Int
    public let currency: String
    public let created: Int
    public let type: String
    public init(id: String, amount: Int, net: Int, currency: String, created: Int, type: String) {
        self.id = id; self.amount = amount; self.net = net; self.currency = currency; self.created = created; self.type = type
    }
}
