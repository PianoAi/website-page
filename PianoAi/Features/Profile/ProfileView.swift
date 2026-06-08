import Charts
import CoreAudioKit
import SwiftUI

// MARK: - 我的 Tab

struct ProfileView: View {

    @Environment(AuthSession.self)          private var authSession
    @Environment(SubscriptionManager.self)  private var subscriptionManager
    @EnvironmentObject private var progressRepository: ProgressRepository

    @AppStorage("dailyGoalMinutes")  private var dailyGoalMinutes  = 0
    @AppStorage("practiceMode")      private var practiceMode      = "standard"
    @AppStorage("reminderEnabled")   private var reminderEnabled   = false
    @AppStorage("reminderHour")      private var reminderHour      = 20
    @AppStorage("reminderMinute")    private var reminderMinute    = 0

    @StateObject private var notificationManager = NotificationManager.shared

    @State private var showPaywall          = false
    @State private var showBluetooth        = false
    @State private var showAuth             = false
    @State private var showSessionManager   = false
    @State private var isResendingVerify    = false
    @State private var resendVerifyMessage: String?
    @State private var showGoalPicker  = false

    var body: some View {
        List {

            // 未登录：显示登录引导，隐藏个人数据
            if !authSession.isAuthenticated {
                Section {
                    VStack(spacing: 20) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 64)).foregroundStyle(.secondary)
                        VStack(spacing: 6) {
                            Text("登录以追踪练习进度").font(.headline)
                            Text("创建账号，保存你的每一次进步")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Button("登录 / 注册") { showAuth = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowSeparator(.hidden)
            }

            // MARK: 用户信息（已登录）
            if authSession.isAuthenticated {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue.gradient)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(authSession.currentUser?.displayName ?? "—")
                            .font(.title3).bold()
                        Text("PianoAi 学员")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // MARK: 练习统计
            Section("练习统计") {
                if progressRepository.isLoading && progressRepository.stats == nil {
                    HStack(spacing: 10) { ProgressView(); Text("加载中…").foregroundStyle(.secondary) }
                } else if let stats = progressRepository.stats {
                    todayRingRow
                    weekCalendarRow
                    weekBarChartRow
                    statsGrid(stats)
                    if progressRepository.weeklyData.count >= 2 { accuracyTrendRow }
                } else {
                    Text("暂无练习记录").foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showGoalPicker) { GoalPickerSheet(goalMinutes: $dailyGoalMinutes) }

                // 邮箱未验证提示
                if let user = authSession.currentUser, !user.isEmailVerified {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "envelope.badge.fill")
                                    .foregroundStyle(.orange)
                                Text("邮箱尚未验证").font(.subheadline).fontWeight(.medium)
                            }
                            Text("验证邮箱可保障账号安全，找回密码时也需要用到")
                                .font(.caption).foregroundStyle(.secondary)

                            if let msg = resendVerifyMessage {
                                Text(msg).font(.caption)
                                    .foregroundStyle(msg.contains("已") ? .green : .red)
                            }

                            Button {
                                Task {
                                    isResendingVerify = true
                                    do {
                                        try await authSession.resendVerificationEmail()
                                        resendVerifyMessage = "验证邮件已发送，请检查收件箱"
                                    } catch {
                                        resendVerifyMessage = "发送失败，请稍后重试"
                                    }
                                    isResendingVerify = false
                                }
                            } label: {
                                if isResendingVerify {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Text("重新发送验证邮件")
                                }
                            }
                            .font(.caption).foregroundStyle(.blue)
                            .disabled(isResendingVerify)
                        }
                        .padding(.vertical, 4)
                    }
                }

            } // end if authSession.isAuthenticated (用户信息 + 统计)

            // MARK: 订阅状态（仅已登录时显示）
            if authSession.isAuthenticated {
            Section("订阅") {
                if subscriptionManager.isSubscribed {
                    HStack {
                        Label("已订阅 PianoAi Pro", systemImage: "crown.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        if let exp = subscriptionManager.expiresAt {
                            Text(exp, style: .date)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button { showPaywall = true } label: {
                        HStack {
                            Label("升级 Pro 解锁全部曲目", systemImage: "crown.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            } // end subscription section

            // MARK: 练习设置
            Section("练习设置") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("练习界面模式").font(.subheadline)
                    Picker("", selection: $practiceMode) {
                        Text("初学者").tag("beginner")
                        Text("标准").tag("standard")
                    }
                    .pickerStyle(.segmented)
                    Text(practiceMode == "beginner"
                         ? "大键盘，简洁界面，适合零基础和儿童"
                         : "完整功能，含节拍器和演奏序列")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // MARK: 练习提醒
            Section("练习提醒") {
                Toggle("每日提醒", isOn: $reminderEnabled)
                    .onChange(of: reminderEnabled) { _, on in
                        Task {
                            if on {
                                let granted = await notificationManager.requestPermission()
                                if granted {
                                    notificationManager.scheduleDailyReminder(
                                        hour: reminderHour, minute: reminderMinute)
                                } else {
                                    reminderEnabled = false
                                }
                            } else {
                                notificationManager.cancelAll()
                            }
                        }
                    }

                if reminderEnabled {
                    DatePicker("提醒时间",
                               selection: reminderTimeBinding,
                               displayedComponents: .hourAndMinute)
                        .onChange(of: reminderHour) { _, h in
                            notificationManager.scheduleDailyReminder(hour: h, minute: reminderMinute)
                        }
                        .onChange(of: reminderMinute) { _, m in
                            notificationManager.scheduleDailyReminder(hour: reminderHour, minute: m)
                        }

                    Text("已练习当天不会再提醒")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .task { await notificationManager.checkStatus() }

            // MARK: 安全
            if authSession.isAuthenticated {
                Section("安全") {
                    Button {
                        showSessionManager = true
                    } label: {
                        HStack {
                            Label("活跃设备", systemImage: "macbook.and.iphone")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            // MARK: 设备
            Section("设备") {
                Button { showBluetooth = true } label: {
                    HStack {
                        Label("蓝牙 MIDI 键盘", systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }

            // MARK: 账号（已登录时显示退出，未登录时不显示）
            if authSession.isAuthenticated {
                Section {
                    Button(role: .destructive) {
                        Task { await authSession.logout() }
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.large)
        .task { if authSession.isAuthenticated { await progressRepository.reload() } }
        .fullScreenCover(isPresented: $showAuth) {
            AuthView(session: authSession)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(authSession)
                .environment(subscriptionManager)
        }
        .sheet(isPresented: $showBluetooth) {
            BluetoothMIDIPickerView()
                .navigationTitle("蓝牙 MIDI 设备")
        }
        .sheet(isPresented: $showSessionManager) {
            SessionManagerView()
                .environment(authSession)
        }
    }

    // MARK: - 今日练习环

    private var todaySeconds: Int {
        progressRepository.weeklyData
            .first { Calendar.current.isDateInToday($0.date) }?.totalSeconds ?? 0
    }

    private var ringProgress: Double {
        guard dailyGoalMinutes > 0 else { return 0 }
        return min(1.0, Double(todaySeconds) / Double(dailyGoalMinutes * 60))
    }

    private var todayRingRow: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(Color.blue,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: ringProgress)
                VStack(spacing: 0) {
                    Text("\(todaySeconds / 60)")
                        .font(.title2.bold())
                    Text("分钟").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                Text("今日练习").font(.headline)
                if dailyGoalMinutes > 0 {
                    Text("目标：\(dailyGoalMinutes) 分钟")
                        .font(.caption).foregroundStyle(.secondary)
                    if ringProgress >= 1 {
                        Label("已完成！", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                } else {
                    Text("尚未设定每日目标")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(dailyGoalMinutes > 0 ? "修改目标" : "设定目标") {
                    showGoalPicker = true
                }
                .font(.caption).foregroundStyle(.blue)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - 本周日历点

    private var weekDays: [Date] {
        (0..<7).map {
            Calendar.current.date(byAdding: .day, value: -(6 - $0), to: Date())!
        }
    }

    private func minutesFor(_ day: Date) -> Double {
        progressRepository.weeklyData
            .first { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .map { Double($0.totalSeconds) / 60 } ?? 0
    }

    private var weekCalendarRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本周活跃天数").font(.subheadline).fontWeight(.semibold)
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    let active = minutesFor(day) > 0
                    VStack(spacing: 5) {
                        Circle()
                            .fill(active ? Color.blue : Color.secondary.opacity(0.2))
                            .frame(width: 10, height: 10)
                        Text(day, format: .dateTime.weekday(.narrow))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 过去 7 天柱状图

    private var chartData: [(day: Date, minutes: Double)] {
        weekDays.map { day in (day: day, minutes: minutesFor(day)) }
    }

    private var weekBarChartRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("过去 7 天练习时长（分钟）")
                .font(.subheadline).fontWeight(.semibold)
            Chart(chartData, id: \.day) { item in
                BarMark(
                    x: .value("日期", item.day, unit: .day),
                    y: .value("分钟", item.minutes)
                )
                .foregroundStyle(
                    Calendar.current.isDateInToday(item.day)
                        ? Color.blue.gradient
                        : Color.blue.opacity(0.45).gradient
                )
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 1)) {
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisValueLabel()
                }
            }
            .frame(height: 110)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 准确率趋势折线图

    private var accuracyTrendRow: some View {
        let data = progressRepository.weeklyData.filter { $0.avgScore != nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text("准确率趋势（本周）")
                .font(.subheadline).fontWeight(.semibold)
            Chart(data) { item in
                LineMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value("准确率", item.avgScore ?? 0)
                )
                .foregroundStyle(Color.indigo)
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value("准确率", item.avgScore ?? 0)
                )
                .foregroundStyle(Color.indigo)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 1)) {
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let d = value.as(Double.self) { Text("\(Int(d))%") }
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 110)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 提醒时间绑定

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = reminderHour; c.minute = reminderMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                reminderHour   = Calendar.current.component(.hour,   from: date)
                reminderMinute = Calendar.current.component(.minute, from: date)
            }
        )
    }

    // MARK: - 统计卡片网格

    private func statsGrid(_ stats: UserStatsResponse) -> some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(icon: "flame.fill",          color: .orange,
                         value: "\(stats.currentStreakDays)",    unit: "天", label: "连续练习")
                StatCard(icon: "clock.fill",           color: .blue,
                         value: shortTime(stats.totalPracticeSeconds).0,
                         unit: shortTime(stats.totalPracticeSeconds).1, label: "累计时长")
                StatCard(icon: "checkmark.seal.fill",  color: .green,
                         value: "\(stats.songsCompleted)",       unit: "首", label: "完成曲目")
                StatCard(icon: "music.note.list",      color: .purple,
                         value: "\(stats.totalSongsPracticed)",  unit: "首", label: "练习曲目")
            }

            if let avg = stats.averageScore {
                VStack(spacing: 8) {
                    HStack {
                        Label("平均准确率", systemImage: "chart.bar.fill")
                            .font(.subheadline).foregroundStyle(.indigo)
                        Spacer()
                        Text("\(Int(avg))%").font(.headline).foregroundStyle(.indigo)
                    }
                    ProgressView(value: avg / 100)
                        .tint(.indigo)
                }
                .padding(14)
                .background(Color.indigo.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.vertical, 4)
    }

    private func shortTime(_ seconds: Int) -> (String, String) {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return ("\(h)", "小时") }
        if m > 0 { return ("\(m)", "分钟") }
        return ("<1", "分钟")
    }
}

// MARK: - 统计卡片

private struct StatCard: View {
    let icon: String
    let color: Color
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            VStack(spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value).font(.title2.bold())
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 每日目标选择器

private struct GoalPickerSheet: View {
    @Binding var goalMinutes: Int
    @Environment(\.dismiss) private var dismiss

    private let options = [5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        NavigationStack {
            List(options, id: \.self) { minutes in
                Button {
                    goalMinutes = minutes
                    dismiss()
                } label: {
                    HStack {
                        Text("\(minutes) 分钟 / 天")
                        Spacer()
                        if goalMinutes == minutes {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("每日练习目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 蓝牙 MIDI 配对（从 HomeView 移入）

struct BluetoothMIDIPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let btVC = CABTMIDICentralViewController()
        let nav = UINavigationController(rootViewController: btVC)
        btVC.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "完成", style: .plain,
            target: context.coordinator, action: #selector(Coordinator.done)
        )
        return nav
    }

    func updateUIViewController(_ vc: UINavigationController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    class Coordinator: NSObject {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        @objc func done() { dismiss() }
    }
}
