import SwiftUI

// MARK: - 练习 Tab：问候 + 推荐曲目

struct PracticeHomeView: View {

    @EnvironmentObject var midiManager:        MIDIManager
    @EnvironmentObject var songRepository:     SongRepository
    @EnvironmentObject var progressRepository: ProgressRepository
    @Environment(AuthSession.self)             private var authSession
    @Environment(SubscriptionManager.self)     private var subscriptionManager

    @AppStorage("userExperienceLevel") private var userLevel = "beginner"
    @State private var paywallSong: Song?         = nil
    @State private var loginPromptSong: Song?     = nil
    @State private var practiceDestination: Song? = nil

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                greetingHeader

                midiStatusBadge.padding(.horizontal)

                if !recentSongs.isEmpty {
                    songSection(title: "继续练习", songs: recentSongs)
                }

                if !beginnerSongs.isEmpty {
                    let title    = userLevel == "intermediate" ? "免费曲目" : "入门推荐"
                    let subtitle = userLevel == "intermediate" ? "从这些曲目开始热身" : "免费曲目，从这里出发"
                    songSection(title: title, subtitle: subtitle, songs: beginnerSongs)
                }

                if userLevel == "intermediate", !showcaseSongs.isEmpty {
                    songSection(title: "体验曲目", subtitle: "为你解锁的免费中级曲目",
                                songs: showcaseSongs)
                }

                if !subscriptionManager.isSubscribed, !featuredSongs.isEmpty {
                    songSection(title: "经典精选", subtitle: "订阅后可解锁全部",
                                songs: featuredSongs, locked: true)
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("PianoAi")
        .navigationBarTitleDisplayMode(.large)
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

    // MARK: - 问候

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting).font(.title2).bold()
            Text("准备好今天的练习了吗？")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "早上好" }
        if h < 18 { return "下午好" }
        return "晚上好"
    }

    // MARK: - MIDI 状态（连接时绿色，未连接时给入口）

    @State private var showBluetooth = false

    private var midiStatusBadge: some View {
        Group {
            if midiManager.connectedDeviceCount > 0 {
                HStack(spacing: 8) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                        .shadow(color: .green, radius: 3)
                    Text("MIDI 键盘已连接").font(.subheadline).foregroundStyle(.green)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Button { showBluetooth = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("连接 MIDI 键盘").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(.systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showBluetooth) {
            BluetoothMIDIPickerView()
                .navigationTitle("蓝牙 MIDI 设备")
        }
    }

    // MARK: - 曲目横向区块

    private func songSection(title: String, subtitle: String? = nil,
                             songs: [Song], locked: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3).fontWeight(.bold)
                if let sub = subtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(songs) { song in
                        let isLocked = locked || (song.isPremium && !subscriptionManager.isSubscribed)
                        if isLocked {
                            Button { paywallSong = song } label: {
                                SongCard(song: song, isLocked: true)
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
                                SongCard(song: song, isLocked: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 数据

    private var recentSongs: [Song] {
        let map = progressRepository.progressBySongId
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        return Array(
            songRepository.songs
                .filter { song in
                    guard let last = map[song.id]?.lastPracticedAt else { return false }
                    return last >= cutoff
                }
                .sorted {
                    (map[$0.id]?.lastPracticedAt ?? .distantPast) >
                    (map[$1.id]?.lastPracticedAt ?? .distantPast)
                }
                .prefix(6)
        )
    }

    private var beginnerSongs: [Song] {
        Array(songRepository.songs
            .filter { $0.difficulty == "beginner" && !$0.isPremium }
            .prefix(10))
    }

    /// 中高级但免费的曲目 = 体验曲，按难度排序后置顶展示
    private var showcaseSongs: [Song] {
        songRepository.songs
            .filter { !$0.isPremium && $0.difficulty != "beginner" }
    }

    private var featuredSongs: [Song] {
        Array(songRepository.songs
            .filter { $0.isPremium && $0.difficulty == "intermediate" }
            .prefix(8))
    }
}

// MARK: - 曲目卡片

private struct SongCard: View {
    let song: Song
    let isLocked: Bool

    private var difficultyColor: Color {
        switch song.difficulty {
        case "beginner":     return .green
        case "intermediate": return .orange
        case "advanced":     return .red
        default:             return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(difficultyColor.opacity(0.12))
                    .frame(width: 140, height: 84)
                    .overlay(
                        Image(systemName: song.genreIcon)
                            .font(.system(size: 30))
                            .foregroundStyle(difficultyColor)
                    )
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2).foregroundStyle(.orange)
                        .padding(6)
                }
            }

            Text(song.displayTitle)
                .font(.caption.bold())
                .lineLimit(2)
                .frame(width: 140, alignment: .leading)

            if let composer = song.composer {
                Text(composer)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
        }
        .frame(width: 140)
        .opacity(isLocked ? 0.72 : 1.0)
    }
}
