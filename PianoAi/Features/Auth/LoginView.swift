import SwiftUI

struct LoginView: View {
    @Bindable var vm: AuthViewModel
    @State private var showForgotPassword = false

    var body: some View {
        VStack(spacing: 20) {
            TextField("邮箱", text: $vm.email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .trailing, spacing: 4) {
                SecureField("密码", text: $vm.password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)

                Button("忘记密码？") {
                    vm.resetEmail = vm.email   // 预填当前邮箱
                    vm.resetForgotPasswordState()
                    vm.resetEmail = vm.email
                    showForgotPassword = true
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }

            Button {
                Task { await vm.submit() }
            } label: {
                Group {
                    if vm.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("登录")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(vm.loginDisabled)
            .opacity(vm.loginDisabled ? 0.5 : 1)

            // Apple Sign In — requires paid Apple Developer account + capability
            // Uncomment when ready:
            // divider
            // SignInWithAppleButton(.signIn) { ... }
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(vm: vm)
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
