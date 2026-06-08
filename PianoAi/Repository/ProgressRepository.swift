import Foundation
import Combine

@MainActor
final class ProgressRepository: ObservableObject {

    @Published private(set) var progressBySongId: [String: ProgressResponse] = [:]
    @Published private(set) var stats: UserStatsResponse?
    @Published private(set) var weeklyData: [DailyPractice] = []
    @Published private(set) var isLoading = false

    private let session: AuthSession

    init(session: AuthSession) { self.session = session }

    /// 首次加载或后台静默刷新（已在加载中则跳过）
    func load() async {
        guard !isLoading else { return }
        await fetch()
    }

    /// 强制刷新，忽略 isLoading 状态（用于 ProfileView 打开时）
    func reload() async {
        await fetch()
    }

    private func fetch() async {
        isLoading = true
        if let list: [ProgressResponse] = try? await session.request(.progressList) {
            progressBySongId = Dictionary(uniqueKeysWithValues: list.map { ($0.songId, $0) })
        }
        if let s: UserStatsResponse = try? await session.request(.progressStats) {
            stats = s
        }
        if let w: [DailyPractice] = try? await session.request(.progressWeekly) {
            weeklyData = w
        }
        isLoading = false
    }
}
