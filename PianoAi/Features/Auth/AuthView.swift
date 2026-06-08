import SwiftUI

struct AuthView: View {
    @State private var vm: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    init(session: AuthSession) {
        _vm = State(wrappedValue: AuthViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    header

                    Picker("", selection: $vm.mode) {
                        Text("登录").tag(AuthViewModel.Mode.login)
                        Text("注册").tag(AuthViewModel.Mode.register)
                    }
                    .pickerStyle(.segmented)

                    if let error = vm.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    switch vm.mode {
                    case .login:    LoginView(vm: vm)
                    case .register: RegisterView(vm: vm)
                    }
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: vm.mode)
            .animation(.easeInOut(duration: 0.2), value: vm.errorMessage)
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

            Text("PianoAi")
                .font(.largeTitle.bold())
            Text("开始你的钢琴学习之旅")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }
}

#Preview {
    AuthView(session: AuthSession())
}
