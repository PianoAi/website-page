import SwiftUI

/// 未登录用户尝试练习时弹出的轻量登录引导
struct LoginPromptSheet: View {
    let songTitle: String
    @Environment(AuthSession.self) private var authSession
    @Environment(\.dismiss)       private var dismiss

    @State private var showAuth = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(.blue.gradient)

                VStack(spacing: 8) {
                    Text("登录后开始练习").font(.title2).bold()
                    Text("《\(songTitle)》")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    featureRow("chart.bar.fill",  .green,  "追踪练习进度与准确率")
                    featureRow("music.note.list", .blue,   "解锁 100+ 首免费曲目")
                    featureRow("icloud.fill",     .purple, "数据云端安全同步")
                }
                .padding(20)
                .background(Color(.systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Spacer()

            VStack(spacing: 12) {
                Button("登录 / 注册") { showAuth = true }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Button("取消") { dismiss() }
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 40)
        .fullScreenCover(isPresented: $showAuth) {
            AuthView(session: authSession)
        }
        // 登录成功后自动关闭 sheet
        .onChange(of: authSession.isAuthenticated) { _, isAuth in
            if isAuth { dismiss() }
        }
    }

    private func featureRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 28)
            Text(text).font(.subheadline)
        }
    }
}
