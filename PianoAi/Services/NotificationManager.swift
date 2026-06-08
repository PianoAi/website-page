import Foundation
import UserNotifications
import Combine

// 每日练习提醒管理器
// 用户练习完成后自动取消今日提醒，避免打扰已练习的用户
@MainActor
final class NotificationManager: ObservableObject {

    static let shared = NotificationManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    private let identifier = "piano_daily_reminder"

    @Published private(set) var isAuthorized = false

    // MARK: - 权限

    func checkStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            return false
        }
    }

    // MARK: - 排期

    /// 安排每日重复提醒（已有同 ID 的提醒会被替换）
    func scheduleDailyReminder(hour: Int, minute: Int) {
        guard isAuthorized else { return }

        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = dailyTitle
        content.body  = dailyBody
        content.sound = .default

        var components = DateComponents()
        components.hour   = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    /// 用户完成练习后调用：取消今日提醒，重新安排使其从明天起生效
    func didCompletePractice(hour: Int, minute: Int) {
        guard isAuthorized else { return }
        // 先移除，再重新添加 → iOS 下次触发时间自动跳到明天
        scheduleDailyReminder(hour: hour, minute: minute)
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - 文案（按星期轮换，避免重复感）

    private var dailyTitle: String {
        let titles = [
            "今天还没练琴哦",
            "你的钢琴在等你",
            "别忘了今天的练习",
            "今天弹一首吧",
        ]
        return titles[Calendar.current.component(.weekday, from: Date()) % titles.count]
    }

    private var dailyBody: String {
        let bodies = [
            "每天一点，积累成大师",
            "继续你的练习之旅",
            "保持节奏，进步看得见",
            "15 分钟，让今天更有意义",
        ]
        return bodies[Calendar.current.component(.weekday, from: Date()) % bodies.count]
    }
}
