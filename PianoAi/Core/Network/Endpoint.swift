import Foundation

enum HTTPMethod: String {
    case GET, POST, PATCH, DELETE
}

struct Endpoint {
    let path: String
    let method: HTTPMethod
    var bodyData: Data?
    var queryItems: [URLQueryItem]

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    init(path: String, method: HTTPMethod, queryItems: [URLQueryItem] = []) {
        self.path = path
        self.method = method
        self.bodyData = nil
        self.queryItems = queryItems
    }

    init<B: Encodable>(path: String, method: HTTPMethod, body: B, queryItems: [URLQueryItem] = []) {
        self.path = path
        self.method = method
        self.bodyData = try? Endpoint.encoder.encode(body)
        self.queryItems = queryItems
    }

    var url: URL {
        var components = URLComponents(
            url: Config.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        return components.url!
    }
}

// MARK: - Auth endpoints

extension Endpoint {
    static func login(email: String, password: String) -> Endpoint {
        Endpoint(path: "/auth/login", method: .POST,
                 body: LoginRequest(email: email, password: password))
    }

    static func register(email: String, password: String, displayName: String) -> Endpoint {
        Endpoint(path: "/auth/register", method: .POST,
                 body: RegisterRequest(email: email, password: password, displayName: displayName))
    }

    static func appleSignIn(identityToken: String, displayName: String?) -> Endpoint {
        Endpoint(path: "/auth/apple", method: .POST,
                 body: AppleSignInRequest(identityToken: identityToken, displayName: displayName))
    }

    static func refresh(token: String) -> Endpoint {
        Endpoint(path: "/auth/refresh", method: .POST,
                 body: RefreshRequest(refreshToken: token))
    }

    static func logout(refreshToken: String) -> Endpoint {
        Endpoint(path: "/auth/logout", method: .DELETE,
                 body: RefreshRequest(refreshToken: refreshToken))
    }

    static let me = Endpoint(path: "/auth/me", method: .GET)
}

// MARK: - Songs endpoints

extension Endpoint {
    static func songs(page: Int = 1, pageSize: Int = 100,
                      difficulty: String? = nil,
                      genre: String? = nil,
                      search: String? = nil) -> Endpoint {
        var items = [
            URLQueryItem(name: "page",      value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]
        if let v = difficulty { items.append(.init(name: "difficulty", value: v)) }
        if let v = genre      { items.append(.init(name: "genre",      value: v)) }
        if let v = search     { items.append(.init(name: "search",     value: v)) }
        return Endpoint(path: "/songs", method: .GET, queryItems: items)
    }

    static func songFiles(id: String) -> Endpoint {
        Endpoint(path: "/songs/\(id)/files", method: .GET)
    }
}

// MARK: - Progress endpoints

extension Endpoint {
    static func recordSession(_ body: PracticeSessionCreate) -> Endpoint {
        Endpoint(path: "/progress/sessions", method: .POST, body: body)
    }

    static let progressList   = Endpoint(path: "/progress",        method: .GET)
    static let progressStats  = Endpoint(path: "/progress/stats",  method: .GET)
    static let progressWeekly = Endpoint(path: "/progress/weekly", method: .GET)
}

// MARK: - Password reset / email verify endpoints

extension Endpoint {
    static func passwordResetRequest(email: String) -> Endpoint {
        Endpoint(path: "/auth/password-reset/request", method: .POST,
                 body: ["email": email])
    }

    static func passwordResetConfirm(token: String, newPassword: String) -> Endpoint {
        Endpoint(path: "/auth/password-reset/confirm", method: .POST,
                 body: ["token": token, "new_password": newPassword])
    }

    static func verifyEmail(token: String) -> Endpoint {
        Endpoint(path: "/auth/verify-email", method: .POST,
                 body: ["token": token])
    }

    static let resendVerification   = Endpoint(path: "/auth/resend-verification", method: .POST)
    static let sessions             = Endpoint(path: "/auth/sessions", method: .GET)
    static let revokeOtherSessions  = Endpoint(path: "/auth/sessions", method: .DELETE)

    static func revokeSession(id: String) -> Endpoint {
        Endpoint(path: "/auth/sessions/\(id)", method: .DELETE)
    }
}

// MARK: - Subscription endpoints

extension Endpoint {
    static let subscriptionStatus = Endpoint(path: "/subscriptions/status", method: .GET)

    static func verifyTransaction(_ jws: String) -> Endpoint {
        Endpoint(path: "/subscriptions/verify", method: .POST,
                 body: VerifyTransactionRequest(jwsTransaction: jws))
    }
}
