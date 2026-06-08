import Foundation

struct SubscriptionStatusResponse: Decodable, Sendable {
    let isSubscribed: Bool
    let expiresAt: Date?
}

struct VerifyTransactionRequest: Encodable, Sendable {
    let jwsTransaction: String
}
