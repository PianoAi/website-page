import SwiftUI

// MARK: - 发现 Tab：搜索常驻顶部 + 难度/风格筛选 + 全曲库列表

struct DiscoverView: View {

    @EnvironmentObject var songRepository:     SongRepository
    @EnvironmentObject var progressRepository: ProgressRepository
    @Environment(AuthSession.self)             private var authSession
    @Environment(SubscriptionManager.self)     private var subscriptionManager

    @State private var searchText              = ""
    @State private var selectedDifficulty: String? = nil
    @State private var selectedGenre: String?       = nil
    @State private var paywallSong: Song?            = nil
    @State private var loginPromptSong: Song?        = nil   // 未登录时的练习引导
    @State private var practiceDestination: Song?    = nil
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterBar
            Divider()
            songList
        }
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $practiceDestination) { song in
            PracticeView(engine: PracticeEngine(song: song))
        }
        .sheet(item: $paywallSong) { song in
            PaywallView(triggeredBySong: song)
                .environment(authSession)
                .environment(subscriptionManager)
        }
        .sheet(item: $loginPromptSong) { song in
            LoginPromptSheet(songTitle: song.displayTitle)
                .environment(authSession)
        }
    }

    // MARK: - 搜索栏（常驻）

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索曲目或作曲家", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal).padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    // MARK: - 筛选栏（常驻）

    private var filterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    GenreChip(label: "全部", color: .blue,
                              isSelected: selectedDifficulty == nil) {
                        selectedDifficulty = nil; selectedGenre = nil
                    }
                    ForEach(difficulties, id: \.key) { item in
                        GenreChip(label: item.label, color: item.color,
                                  isSelected: selectedDifficulty == item.key) {
                            selectedDifficulty = selectedDifficulty == item.key ? nil : item.key
                            selectedGenre = nil
                        }
                    }
                    if availableGenres.count > 1 {
                        Divider().frame(height: 20)
                        ForEach(availableGenres, id: \.key) { genre in
                            GenreChip(label: genre.label, color: .purple,
                                      isSelected: selectedGenre == genre.key) {
                                selectedGenre = selectedGenre == genre.key ? nil : genre.key
                            }
                        }
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 歌曲列表

    private var songList: some View {
        List {
            if filteredSongs.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36)).foregroundStyle(.tertiary)
                        Text("没有找到符合条件的曲目").foregroundStyle(.secondary)
                        if selectedDifficulty != nil || selectedGenre != nil || !searchText.isEmpty {
                            Button("清除筛选") {
                                searchText = ""; selectedDifficulty = nil; selectedGenre = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
                }
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(filteredSongs) { song in
                        if song.isPremium && !subscriptionManager.isSubscribed {
                            Button { paywallSong = song } label: {
                                SongRowView(
                                    song: song,
                                    progress: progressRepository.progressBySongId[song.id],
                                    isLocked: true, showDifficulty: true
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                if authSession.isAuthenticated {
                                    practiceDestination = song
                                } else {
                                    loginPromptSong = song
                                }
                            } label: {
                                SongRowView(
                                    song: song,
                                    progress: progressRepository.progressBySongId[song.id],
                                    isLocked: false, showDifficulty: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(filteredSongs.count) 首")
                            .foregroundStyle(.secondary).fontWeight(.regular)
                        Spacer()
                        let locked = filteredSongs.filter { $0.isPremium && !subscriptionManager.isSubscribed }.count
                        if locked > 0 {
                            Button { paywallSong = filteredSongs.first { $0.isPremium } } label: {
                                Label("解锁全部", systemImage: "crown.fill")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await progressRepository.load() }
    }

    // MARK: - 数据

    private var difficulties: [(key: String, label: String, color: Color)] {
        [("beginner", "入门", Color.green), ("intermediate", "中级", Color.orange), ("advanced", "高级", Color.red)]
            .filter { item in songRepository.songs.contains { $0.difficulty == item.0 } }
    }

    private var availableGenres: [(key: String, label: String)] {
        let labels: [String: String] = [
            "classical": "古典", "pop": "流行", "jazz": "爵士",
            "folk": "民谣", "children": "儿歌", "modern": "现代",
        ]
        let base = selectedDifficulty.map { d in songRepository.songs.filter { $0.difficulty == d } }
            ?? songRepository.songs
        return Set(base.map { $0.genre }).sorted()
            .compactMap { k in labels[k].map { (key: k, label: $0) } }
    }

    private var filteredSongs: [Song] {
        var result = songRepository.songs
        if !searchText.isEmpty {
            result = result.filter {
                ($0.localizedTitle ?? $0.title).localizedCaseInsensitiveContains(searchText) ||
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.composer ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        if let d = selectedDifficulty { result = result.filter { $0.difficulty == d } }
        if let g = selectedGenre      { result = result.filter { $0.genre == g } }
        // 免费曲目置顶，其余保持原顺序
        return result.sorted { !$0.isPremium && $1.isPremium }
    }
}
