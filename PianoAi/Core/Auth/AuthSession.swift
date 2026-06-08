import Foundation
import Observation

@Observable
final class AuthSession {

    // MARK: - Public state

    private(set) var isAuthenticated: Bool = false
    private(set) var currentUser: UserInfo?
    private(set) var isSubscribed: Bool = false

    // MARK: - Private token storage

    private var accessToken: String?
    private var refreshToken: String?

    private let client: APIClient

    // MARK: - Init

    init(client: APIClient = APIClient()) {
        self.client = client
        accessToken  = Keychain.load(for: .accessToken)
        refreshToken = Keychain.load(for: .refreshToken)
        isAuthenticated = refreshToken != nil
    }

    // MARK: - Authenticated requests (auto-refresh on 401)

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        do {
            return try await client.send(endpoint, token: accessToken)
        } catch APIError.unauthorized {
            try await performRefresh()
            return try await client.send(endpoint, token: accessToken)
        }
    }

    // MARK: - Public (unauthenticated) requests

    func publicSend(_ endpoint: Endpoint) async throws {
        let _: EmptyResponse = try await client.send(endpoint, token: nil)
    }

    // MARK: - Password reset

    func requestPasswordReset(email: String) async throws {
        try await publicSend(.passwordResetRequest(email: email))
    }

    func confirmPasswordReset(token: String, newPassword: String) async throws {
        try await publicSend(.passwordResetConfirm(token: token, newPassword: newPassword))
    }

    // MARK: - Auth operations

    func login(email: String, password: String) async throws {
        let tokens: TokenResponse = try await client.send(
            .login(email: email, password: password)
        )
        apply(tokens)
    }

    func register(displayName: String, email: String, password: String) async throws {
        let tokens: TokenResponse = try await client.send(
            .register(email: email, password: password, displayName: displayName)
        )
        apply(tokens)
    }

    func loginWithApple(identityToken: String, displayName: String?) async throws {
        let tokens: TokenResponse = try await client.send(
            .appleSignIn(identityToken: identityToken, displayName: displayName)
        )
        apply(tokens)
    }

    func logout() async {
        if let rt = refreshToken {
            let _: EmptyResponse? = try? await client.send(.logout(refreshToken: rt))
        }
        clear()
    }

    func fetchCurrentUser() async throws {
        currentUser = try await request(.me)
    }

    func refreshSubscriptionStatus() async {
        guard isAuthenticated else { return }
        do {
            let status: SubscriptionStatusResponse = try await request(.subscriptionStatus)
            isSubscribed = status.isSubscribed
        } catch {
            print("⚠️ Failed to refresh subscription status: \(error)")
        }
    }

    // MARK: - Token lifecycle

    private func performRefresh() async throws {
        guard let rt = refreshToken else {
            clear()
            throw APIError.unauthorized
        }
        do {
            let tokens: TokenResponse = try await client.send(.refresh(token: rt))
            apply(tokens)
        } catch {
            clear()
            throw APIError.unauthorized
        }
    }

    // MARK: - Email verification

    func resendVerificationEmail() async throws {
        try await publicSend(.resendVerification)
    }

    // MARK: - Session management

    func fetchSessions() async throws -> [SessionItem] {
        try await request(.sessions)
    }

    func revokeSession(id: String) async throws {
        try await publicSend(.revokeSession(id: id))
    }

    func revokeOtherSessions() async throws -> Int {
        let result: RevokeOtherSessionsResponse = try await request(.revokeOtherSessions)
        return result.revoked
    }

    // MARK: - Token lifecycle

    private func apply(_ tokens: TokenResponse) {
        accessToken  = tokens.accessToken
        refreshToken = tokens.refreshToken
        Keychain.save(tokens.accessToken,  for: .accessToken)
        Keychain.save(tokens.refreshToken, for: .refreshToken)
        Keychain.save(tokens.sessionId,    for: .sessionId)
        isAuthenticated = true
    }

    private func clear() {
        accessToken  = nil
        refreshToken = nil
        currentUser  = nil
        isSubscribed = false
        Keychain.clear()
        isAuthenticated = false
    }
}
