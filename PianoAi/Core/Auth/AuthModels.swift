import Foundation

// MARK: - Requests

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let displayName: String
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct AppleSignInRequest: Encodable {
    let identityToken: String
    let displayName: String?
}

// MARK: - Responses

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let sessionId: String
    let tokenType: String
}

struct SessionItem: Decodable, Identifiable {
    let id: String
    let deviceName: String?
    let platform: String?
    let lastUsedAt: Date?
    let createdAt: Date
    let isCurrent: Bool
}

struct RevokeOtherSessionsResponse: Decodable {
    let revoked: Int
}

struct UserInfo: Decodable, Equatable {
    let id: String
    let displayName: String
    let avatarUrl: String?
    let emailVerifiedAt: Date?

    var isEmailVerified: Bool { emailVerifiedAt != nil }
}
