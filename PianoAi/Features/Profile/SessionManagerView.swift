import SwiftUI

struct SessionManagerView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [SessionItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showRevokeAllConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载中…").frame(maxHeight: .infinity)
                } else if let err = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(err).foregroundStyle(.secondary)
                        Button("重试") { Task { await load() } }.buttonStyle(.bordered)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    sessionList
                }
            }
            .navigationTitle("活跃设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if sessions.count > 1 {
                        Button("退出其他设备") { showRevokeAllConfirm = true }
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .confirmationDialog(
                "退出所有其他设备？",
                isPresented: $showRevokeAllConfirm,
                titleVisibility: .visible
            ) {
                Button("确认退出", role: .destructive) {
                    Task { await revokeOthers() }
                }
            } message: {
                Text("当前设备外的所有会话将被注销")
            }
        }
        .task { await load() }
    }

    // MARK: - Session list

    private var sessionList: some View {
        List {
            Section {
                ForEach(sessions) { session in
                    SessionRow(session: session) {
                        Task { await revoke(session) }
                    }
                }
            } footer: {
                Text("点击具体设备右侧按钮可单独退出该设备登录")
                    .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            sessions = try await authSession.fetchSessions()
        } catch {
            errorMessage = "加载失败，请重试"
        }
        isLoading = false
    }

    private func revoke(_ session: SessionItem) async {
        guard !session.isCurrent else { return }
        do {
            try await authSession.revokeSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = "操作失败"
        }
    }

    private func revokeOthers() async {
        do {
            _ = try await authSession.revokeOtherSessions()
            await load()
        } catch {
            errorMessage = "操作失败"
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: SessionItem
    let onRevoke: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: platformIcon)
                .font(.title2)
                .foregroundStyle(session.isCurrent ? .blue : .secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.deviceName ?? "未知设备")
                        .font(.subheadline).fontWeight(.medium)
                    if session.isCurrent {
                        Text("当前设备")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                Text(session.platform ?? "未知平台")
                    .font(.caption).foregroundStyle(.secondary)
                Text(lastUsedText)
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Spacer()

            if !session.isCurrent {
                Button("退出") { onRevoke() }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var platformIcon: String {
        let p = (session.platform ?? "").lowercased()
        if p.contains("ipad")  { return "ipad" }
        if p.contains("ios")   { return "iphone" }
        if p.contains("mac")   { return "laptopcomputer" }
        return "desktopcomputer"
    }

    private var lastUsedText: String {
        guard let date = session.lastUsedAt ?? Optional(session.createdAt) else {
            return "从未使用"
        }
        let diff = Date.now.timeIntervalSince(date)
        if diff < 60      { return "刚刚活跃" }
        if diff < 3600    { return "\(Int(diff/60)) 分钟前活跃" }
        if diff < 86400   { return "\(Int(diff/3600)) 小时前活跃" }
        return "\(Int(diff/86400)) 天前活跃"
    }
}
