import SwiftUI

/// 忘记密码：两步流程
/// Step 0 → 输入邮箱，发送重置邮件
/// Step 1 → 输入邮件中的 token + 新密码，完成重置
/// Step 2 → 成功，提示重新登录
struct ForgotPasswordSheet: View {
    @Bindable var vm: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    switch vm.resetStep {
                    case 0:  requestStep
                    case 1:  resetStep
                    default: successStep
                    }
                }
                .padding(24)
            }
            .navigationTitle("找回密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Step 0：发送重置邮件

    private var requestStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("输入注册邮箱").font(.title3).bold()
                Text("我们会向该邮箱发送密码重置链接")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            TextField("邮箱", text: $vm.resetEmail)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .textFieldStyle(.roundedBorder)

            if let err = vm.resetErrorMessage {
                errorBanner(err)
            }

            Button {
                Task { await vm.requestPasswordReset() }
            } label: {
                Group {
                    if vm.isLoading { ProgressView().tint(.white) }
                    else { Text("发送重置邮件").fontWeight(.semibold) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .background(vm.resetEmail.isEmpty ? Color.gray : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(vm.resetEmail.isEmpty || vm.isLoading)
        }
    }

    // MARK: - Step 1：输入 token + 新密码

    private var resetStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("检查您的邮件").font(.title3).bold()
                Text("将邮件中的重置码粘贴到下方，再设置新密码")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            TextField("重置码（邮件中的 token=后面部分）", text: $vm.resetToken)
                .textContentType(.oneTimeCode)
                .autocapitalization(.none)
                .textFieldStyle(.roundedBorder)

            Divider()

            SecureField("新密码", text: $vm.resetNewPassword)
                .textContentType(.newPassword)
                .textFieldStyle(.roundedBorder)

            // 密码强度指示
            if !vm.resetNewPassword.isEmpty {
                HStack(spacing: 12) {
                    strengthDot("8位+",   vm.resetNewPassword.count >= 8)
                    strengthDot("大写",   vm.resetNewPassword.contains { $0.isUppercase })
                    strengthDot("小写",   vm.resetNewPassword.contains { $0.isLowercase })
                    strengthDot("数字",   vm.resetNewPassword.contains { $0.isNumber })
                }
            }

            SecureField("确认新密码", text: $vm.resetConfirmPassword)
                .textContentType(.newPassword)
                .textFieldStyle(.roundedBorder)

            if !vm.resetConfirmPassword.isEmpty && vm.resetNewPassword != vm.resetConfirmPassword {
                Text("两次密码不一致").font(.caption).foregroundStyle(.red)
            }

            if let err = vm.resetErrorMessage {
                errorBanner(err)
            }

            let canSubmit = !vm.resetToken.isEmpty &&
                            vm.resetNewPasswordStrong &&
                            vm.resetNewPassword == vm.resetConfirmPassword

            Button {
                Task { await vm.confirmPasswordReset() }
            } label: {
                Group {
                    if vm.isLoading { ProgressView().tint(.white) }
                    else { Text("重置密码").fontWeight(.semibold) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .background(canSubmit ? Color.accentColor : Color.gray)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(!canSubmit || vm.isLoading)
        }
    }

    // MARK: - Step 2：成功

    private var successStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
            Text("密码重置成功！").font(.title2).bold()
            Text("请用新密码重新登录").foregroundStyle(.secondary)
            Spacer()
            Button("返回登录") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func strengthDot(_ label: String, _ met: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.caption2).foregroundStyle(met ? .green : .secondary)
            Text(label).font(.caption2).foregroundStyle(met ? .green : .secondary)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(text).font(.caption).foregroundStyle(.red)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
