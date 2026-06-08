import SwiftUI

struct RegisterView: View {
    @Bindable var vm: AuthViewModel

    var body: some View {
        VStack(spacing: 20) {
            TextField("昵称", text: $vm.displayName)
                .textContentType(.name)
                .textFieldStyle(.roundedBorder)

            TextField("邮箱", text: $vm.email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .textFieldStyle(.roundedBorder)

            SecureField("密码", text: $vm.password)
                .textContentType(.newPassword)
                .textFieldStyle(.roundedBorder)

            // 密码强度指示器
            if !vm.password.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 16) {
                        strengthItem("8位以上", met: vm.hasMinLength)
                        strengthItem("大写字母", met: vm.hasUppercase)
                        strengthItem("小写字母", met: vm.hasLowercase)
                        strengthItem("数字",     met: vm.hasDigit)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.2), value: vm.password)
            }

            VStack(alignment: .leading, spacing: 4) {
                SecureField("确认密码", text: $vm.confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                if vm.passwordMismatch {
                    Text("两次密码不一致")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.passwordMismatch)

            Button {
                Task { await vm.submit() }
            } label: {
                Group {
                    if vm.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("创建账号")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(vm.registerDisabled)
            .opacity(vm.registerDisabled ? 0.5 : 1)

            // Apple Sign In — requires paid Apple Developer account + capability
            // Uncomment when ready:
            // divider
            // SignInWithAppleButton(.signUp) { ... }
        }
    }

    private func strengthItem(_ label: String, met: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(met ? .green : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(met ? .green : .secondary)
        }
    }

    private var divider: some View {
        HStack {
            Rectangle().frame(height: 1).foregroundStyle(.separator)
            Text("或").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            Rectangle().frame(height: 1).foregroundStyle(.separator)
        }
    }
}
