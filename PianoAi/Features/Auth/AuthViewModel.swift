import Foundation
import Observation
import AuthenticationServices

@Observable
final class AuthViewModel {

    enum Mode { case login, register }

    // MARK: - Form state

    var mode: Mode = .login
    var email: String = ""
    var password: String = ""
    var confirmPassword: String = ""
    var displayName: String = ""

    // MARK: - UI state

    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Password strength

    var hasMinLength: Bool  { password.count >= 8 }
    var hasUppercase: Bool  { password.contains { $0.isUppercase } }
    var hasLowercase: Bool  { password.contains { $0.isLowercase } }
    var hasDigit: Bool      { password.contains { $0.isNumber } }
    var passwordStrong: Bool { hasMinLength && hasUppercase && hasLowercase && hasDigit }

    // MARK: - Validation

    var loginDisabled: Bool {
        email.isEmpty || password.isEmpty || isLoading
    }

    var registerDisabled: Bool {
        displayName.isEmpty || email.isEmpty ||
        !passwordStrong || password != confirmPassword || isLoading
    }

    var passwordMismatch: Bool {
        mode == .register && !confirmPassword.isEmpty && password != confirmPassword
    }

    // MARK: - Forgot password state

    var resetEmail: String = ""
    var resetToken: String = ""
    var resetNewPassword: String = ""
    var resetConfirmPassword: String = ""
    var resetStep: Int = 0        // 0=idle 1=sent 2=done
    var resetErrorMessage: String?

    var resetNewPasswordStrong: Bool {
        let p = resetNewPassword
        return p.count >= 8 &&
               p.contains { $0.isUppercase } &&
               p.contains { $0.isLowercase } &&
               p.contains { $0.isNumber }
    }

    // MARK: - Actions

    private let session: AuthSession

    init(session: AuthSession) {
        self.session = session
    }

    func submit() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            switch mode {
            case .login:
                try await session.login(email: email, password: password)
            case .register:
                try await session.register(
                    displayName: displayName,
                    email: email,
                    password: password
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleAppleCredential(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData   = credential.identityToken,
                let tokenString = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Apple 登录凭证无效"
                return
            }

            let fullName = [
                credential.fullName?.givenName,
                credential.fullName?.familyName
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty

            isLoading = true
            defer { isLoading = false }

            do {
                try await session.loginWithApple(
                    identityToken: tokenString,
                    displayName: fullName
                )
            } catch {
                errorMessage = error.localizedDescription
            }

        case .failure(let error):
            let code = (error as? ASAuthorizationError)?.code
            switch code {
            case .canceled, .unknown:
                break   // user dismissed or capability not configured — stay silent
            default:
                errorMessage = error.localizedDescription
            }
        }
    }

    func switchMode() {
        mode = mode == .login ? .register : .login
        errorMessage = nil
        password = ""
        confirmPassword = ""
    }

    // MARK: - Forgot password

    func requestPasswordReset() async {
        guard !resetEmail.isEmpty else { return }
        resetErrorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await session.requestPasswordReset(email: resetEmail)
            resetStep = 1
        } catch {
            resetErrorMessage = "发送失败，请检查邮箱地址"
        }
    }

    func confirmPasswordReset() async {
        guard resetNewPassword == resetConfirmPassword else {
            resetErrorMessage = "两次密码不一致"
            return
        }
        resetErrorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await session.confirmPasswordReset(token: resetToken, newPassword: resetNewPassword)
            resetStep = 2
        } catch {
            resetErrorMessage = "重置失败，链接可能已过期"
        }
    }

    func resetForgotPasswordState() {
        resetEmail = ""; resetToken = ""
        resetNewPassword = ""; resetConfirmPassword = ""
        resetStep = 0; resetErrorMessage = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
