import Foundation
import Combine

protocol SongRepositoryProtocol {
    func fetchSongs() async throws -> [Song]
}

// MARK: - Observable store

class SongRepository: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private let repository: SongRepositoryProtocol

    init(session: AuthSession) {
        self.repository = RemoteSongRepository(session: session)
    }

    func load() {
        Task { @MainActor in
            isLoading = true
            errorMessage = nil
            do {
                songs = try await repository.fetchSongs()
                print("✅ 曲库加载成功：\(songs.count) 首")
            } catch {
                errorMessage = "曲库加载失败：\(error.localizedDescription)"
                print("❌ \(errorMessage!)")
            }
            isLoading = false
        }
    }
}

// MARK: - Remote

struct RemoteSongRepository: SongRepositoryProtocol {
    let session: AuthSession

    func fetchSongs() async throws -> [Song] {
        var all: [Song] = []
        var page = 1

        while true {
            let result: SongPage = try await session.request(
                .songs(page: page, pageSize: 100)
            )
            all.append(contentsOf: result.items)
            guard result.hasMore else { break }
            page += 1
        }

        return all
    }
}

// MARK: - Errors

enum RepositoryError: LocalizedError {
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "网络错误：\(msg)"
        }
    }
}
