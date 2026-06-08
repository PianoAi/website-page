import SwiftUI

// MARK: - 体验曲目（永久免费）与入门推荐（硬编码 ID）

// 不再硬编码 UUID，改为按标题匹配（更健壮，数据库重建也不受影响）

// MARK: - 主容器

struct OnboardingView: View {
    let onComplete: () -> Void   // called AFTER successful registration

    @AppStorage("userExperienceLevel") private var userLevel = "beginner"
    @State private var step = 0
    @State private var showRegistration = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch step {
                case 0:  WelcomePage { advance() }
                case 1:  LevelPage(selectedLevel: $userLevel) { advance() }
                default: ReadyPage(level: userLevel, onPracticeComplete: {
                    showRegistration = true
                })
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal:   .move(edge: .leading)
            ))
            .animation(.easeInOut(duration: 0.32), value: step)

            // 进度点
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(step == i ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: step == i ? 20 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.25), value: step)
                }
            }
            .padding(.bottom, 14)
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showRegistration) {
            RegistrationPromptView(onComplete: onComplete)
        }
    }

    private func advance() {
        withAnimation { step = min(step + 1, 2) }
    }
}

// MARK: - Page 1：欢迎

private struct WelcomePage: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                Image("AppLogo")
                    .resizable().scaledToFit()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)

                VStack(spacing: 10) {
                    Text("欢迎来到 PianoAi")
                        .font(.largeTitle).bold()
                    Text("从第一个音符开始\n用最自然的方式学钢琴")
                        .font(.title3).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 14) {
                    featureRow("music.note",     .blue,   "实时音符指导",   "一步一步跟着弹，不会走弯路")
                    featureRow("waveform",       .purple, "完整 MIDI 试听", "弹之前先听一遍，感受旋律")
                    featureRow("chart.bar.fill", .green,  "练习进度追踪",   "看着自己一点点进步")
                    featureRow("dot.radiowaves.left.and.right", .orange,
                               "支持 MIDI 键盘",  "可在「我的」中连接蓝牙 MIDI 键盘")
                }
                .padding(20)
                .background(Color(.systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Spacer()
            primaryButton("开始", action: onContinue)
        }
        .padding(.horizontal, 28).padding(.bottom, 56)
    }

    private func featureRow(_ icon: String, _ color: Color, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).bold()
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Page 2：水平选择

private struct LevelPage: View {
    @Binding var selectedLevel: String
    let onContinue: () -> Void

    private struct Option: Identifiable {
        let id = UUID()
        let storedValue: String
        let title: String
        let subtitle: String
        let icon: String
    }

    private let options: [Option] = [
        Option(storedValue: "beginner",     title: "零基础",     subtitle: "从未弹过钢琴，从第一个音符开始", icon: "hand.wave"),
        Option(storedValue: "beginner",     title: "略懂一点",   subtitle: "会弹几首简单的曲子",             icon: "music.note"),
        Option(storedValue: "intermediate", title: "有一定基础", subtitle: "能弹一些中等难度的曲子",         icon: "music.note.list"),
    ]

    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("你的钢琴水平如何？")
                        .font(.title2).bold()
                    Text("帮助我们为你推荐合适的曲目")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                        LevelCard(
                            title: opt.title, subtitle: opt.subtitle,
                            icon: opt.icon, isSelected: selectedIndex == idx
                        ) {
                            selectedIndex = idx
                            selectedLevel = opt.storedValue
                        }
                    }
                }
            }
            Spacer()
            primaryButton("继续") {
                selectedLevel = options[selectedIndex].storedValue
                onContinue()
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 56)
    }
}

private struct LevelCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .blue)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(subtitle).font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                }
            }
            .padding(16)
            .background(isSelected ? Color.blue : Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

// MARK: - Page 3：根据水平分两条路径

private struct ReadyPage: View {
    let level: String
    let onPracticeComplete: () -> Void   // 练完或跳过后调用，触发注册页

    @EnvironmentObject private var midiManager: MIDIManager
    @EnvironmentObject private var soundEngine: SoundEngine

    @State private var practiceSession: Song? = nil

    // 使用打包的 demo 曲目，无需账号和网络
    private var demoSongs: [Song] {
        switch level {
        case "intermediate": return [.bundledIntermediate, .bundledAdvanced]
        case "advanced":     return [.bundledAdvanced, .bundledIntermediate]
        default:             return []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if level == "beginner" {
                beginnerContent
            } else {
                intermediateContent
            }

            Spacer()
        }
        .padding(.horizontal, 28).padding(.bottom, 56)
        // 练习完成时触发注册流程
        .fullScreenCover(item: $practiceSession, onDismiss: onPracticeComplete) { song in
            NavigationStack {
                PracticeView(engine: PracticeEngine(song: song))
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                practiceSession = nil   // dismiss → onDismiss → onPracticeComplete
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("完成")
                                }
                            }
                        }
                    }
            }
            .environmentObject(midiManager)
            .environmentObject(soundEngine)
        }
    }

    // MARK: 入门路径（两只老虎，保证有数据）

    private var beginnerContent: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Text("推荐你的第一首曲子").font(.title2).bold()
                Text("先弹熟这首，App 的使用方式你就全明白了")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button { practiceSession = .bundledBeginner } label: {
                MiniSongCard(song: .bundledBeginner, badge: "点击开始")
            }
            .buttonStyle(.plain)

            tipBlock(tips: [
                "看音符卡片提示弹哪个键",
                "进度条告诉你这个音要按多久",
                "弹对了自动进入下一个音符",
            ])

            primaryButton("就练这首") { practiceSession = .bundledBeginner }
        }
    }

    // MARK: 中级/高级路径（体验曲）

    private var intermediateContent: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Text("为你准备了体验曲目").font(.title2).bold()
                Text("选一首开始，感受 App 是否符合你的练习习惯")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                ForEach(demoSongs) { song in
                    Button { practiceSession = song } label: {
                        MiniSongCard(song: song, badge: "点击体验")
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("稍后再选") { onPracticeComplete() }
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    // MARK: 提示列表

    private func tipBlock(tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(tips, id: \.self) { tip in
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.blue).font(.subheadline)
                    Text(tip).font(.subheadline)
                }
            }
        }
        .padding(20)
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 曲目小卡片（引导内用）

private struct MiniSongCard: View {
    let song: Song
    let badge: String?

    private var difficultyColor: Color {
        switch song.difficulty {
        case "beginner":     return .green
        case "intermediate": return .orange
        default:             return .gray
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(difficultyColor.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: song.genreIcon)
                        .font(.title3).foregroundStyle(difficultyColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(song.displayTitle).font(.headline).lineLimit(1)
                if let composer = song.composer {
                    Text(composer).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let badge {
                Text(badge)
                    .font(.caption2).fontWeight(.semibold)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 注册引导页（练完第一首后出现）

struct RegistrationPromptView: View {
    let onComplete: () -> Void   // hasCompletedOnboarding = true

    @Environment(AuthSession.self) private var authSession
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Text("体验得怎么样？").font(.largeTitle).bold()
                        Text("创建账号，开始记录你的每一次进步")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        regBenefit("chart.bar.fill",      .green,  "追踪练习进度与准确率")
                        regBenefit("music.note.list",     .blue,   "解锁 100+ 首免费曲目")
                        regBenefit("icloud.fill",         .purple, "数据安全云端同步")
                    }
                    .padding(20)
                    .background(Color(.systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Spacer()

                VStack(spacing: 12) {
                    primaryButton("创建账号") { showAuth = true }
                    Button("以后再说") { onComplete() }
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 40)
            .navigationBarHidden(true)
        }
        .fullScreenCover(isPresented: $showAuth) {
            AuthView(session: authSession)
        }
        .onChange(of: authSession.isAuthenticated) { _, isAuth in
            if isAuth { onComplete() }
        }
    }

    private func regBenefit(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 28)
            Text(text).font(.subheadline)
        }
    }
}

// MARK: - 共用：主按钮

private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
}
