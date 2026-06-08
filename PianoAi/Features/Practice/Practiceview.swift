import SwiftUI

struct PracticeView: View {

    @EnvironmentObject var midiManager:        MIDIManager
    @EnvironmentObject var soundEngine:        SoundEngine
    @EnvironmentObject var progressRepository: ProgressRepository

    @AppStorage("practiceMode")    private var practiceMode    = "standard"
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHour")    private var reminderHour    = 20
    @AppStorage("reminderMinute")  private var reminderMinute  = 0

    @State var engine: PracticeEngine
    @StateObject private var previewPlayer = PreviewPlayer()
    @State private var metronome       = Metronome()
    @State private var isMetronomeOn   = false
    @State private var holdProgress: Double = 0.0
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthSession.self) private var authSession
    @State private var hasUploadedCurrentRound = false

    // MARK: - Body（拆分避免 Swift 类型检查超时）

    var body: some View {
        practiceContent
            .navigationTitle(engine.song.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { restartButton } }
            .onAppear(perform: setupMIDI)
            .onChange(of: engine.isHolding) { old, new in onHoldingChanged(old, new) }
            .onChange(of: metronome.bpm)    { _, bpm in engine.bpm = bpm }
            .onChange(of: isMetronomeOn)    { _, on  in engine.bpm = on ? metronome.bpm : (engine.song.bpm ?? 60) }
            .onDisappear(perform: teardownMIDI)
            .task { await engine.load(session: authSession) }
            .onChange(of: engine.feedback)  { old, new in onFeedbackChanged(old, new) }
            .sheet(isPresented: Binding(get: { engine.feedback == .finished }, set: { _ in })) {
                FinishedView(engine: engine, onDismiss: { dismiss() })
            }
    }

    @ViewBuilder
    private var practiceContent: some View {
        if practiceMode == "beginner" { beginnerLayout } else { standardLayout }
    }

    private var restartButton: some View {
        Button("重新开始") { previewPlayer.stop(); engine.restart() }
            .foregroundStyle(.orange)
    }

    private func setupMIDI() {
        let eng = engine
        let snd = soundEngine
        midiManager.onNoteOn = { note, velocity in
            snd.playNote(note: note, velocity: velocity)
            eng.handleNoteOn(midiNumber: Int(note))
        }
        midiManager.onNoteOff = { note in
            snd.stopNote(note: note)
            eng.handleNoteOff(midiNumber: Int(note))
        }
    }

    private func teardownMIDI() {
        previewPlayer.stop(); metronome.stop(); holdProgress = 0.0
        midiManager.onNoteOn = { [weak soundEngine] note, vel in soundEngine?.playNote(note: note, velocity: vel) }
        midiManager.onNoteOff = { [weak soundEngine] note in soundEngine?.stopNote(note: note) }
        if !hasUploadedCurrentRound && (engine.correctCount + engine.wrongCount) > 0 {
            Task { await uploadSession() }
        }
    }

    private func onHoldingChanged(_ old: Bool, _ holding: Bool) {
        if holding {
            holdProgress = 0.0
            withAnimation(.linear(duration: engine.holdDuration)) { holdProgress = 1.0 }
        } else {
            withAnimation(.easeOut(duration: 0.12)) { holdProgress = 0.0 }
        }
    }

    private func onFeedbackChanged(_ old: FeedbackState, _ new: FeedbackState) {
        if new == .finished {
            soundEngine.stopAllNotes()
            hasUploadedCurrentRound = true
            Task { await uploadSession() }
            // didCompletePractice 是同步方法，不需要 await
            if reminderEnabled {
                NotificationManager.shared.didCompletePractice(
                    hour: reminderHour, minute: reminderMinute)
            }
        }
        if old == .finished && new == .waiting { hasUploadedCurrentRound = false }
    }

    // MARK: - 标准模式（完整功能）

    private var standardLayout: some View {
        VStack(spacing: 0) {

            // ── 1. 进度 ──
            progressSection
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)

            Divider()

            // ── 2. 试听 + 节拍器 ──
            controlsRow
                .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            // ── 3. 目标音符（弹性高度）──
            targetNoteSection
                .frame(maxHeight: .infinity)

            // ── 4. Piano Roll（固定高度）──
            PianoRollStripView(
                notes: engine.notes,
                currentIndex: engine.currentIndex,
                accentColor: noteCardColor
            )
            .frame(height: 96)
            .opacity(previewPlayer.isPlaying || previewPlayer.isDownloading ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: previewPlayer.isPlaying)

            // ── 5. 反馈（固定高度，opacity 切换）──
            feedbackArea
                .frame(height: 40)
                .padding(.horizontal)

            Divider()

            // ── 6. 键盘参考 ──
            miniKeyboardSection.padding(.bottom, 20)
        }
    }

    // MARK: - 初学者模式

    private var beginnerLayout: some View {
        VStack(spacing: 0) {
            // 进度（紧凑）
            progressSection
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)

            Divider()

            // 音符信息条（紧凑置顶）
            Group {
                switch engine.loadState {
                case .idle, .loading:
                    ProgressView().padding().frame(maxHeight: .infinity)

                case .failed(let msg):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 44)).foregroundStyle(.orange)
                        Text(msg).font(.caption).foregroundStyle(.tertiary)
                        Button("重试") { Task { await engine.retryLoad(session: authSession) } }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxHeight: .infinity)

                case .ready:
                    if engine.isFinished {
                        Text("完成！").font(.system(size: 56)).foregroundStyle(.orange)
                            .frame(maxHeight: .infinity)
                    } else if let note = engine.currentNote {
                        VStack(spacing: 0) {
                            // ── 顶部：音符信息栏 ──
                            beginnerNoteBar(note)

                            // ── 中部：指引 / 反馈文字（垂直居中）──
                            Spacer()
                            beginnerFeedback
                            Spacer()

                            // ── 底部：键盘 + 接下来 ──
                            beginnerKeyboard
                                .padding(.horizontal, 4)
                            beginnerNextNotes
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 16)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func beginnerNoteBar(_ note: MusicalNote) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.fullName)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(noteCardColor)
                Text(note.solfege)
                    .font(.title3).foregroundStyle(.secondary)
            }
            .padding(.leading, 20)

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(note.durationHint)
                    .font(.subheadline)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(noteCardColor.opacity(0.1))
                    .foregroundStyle(noteCardColor)
                    .clipShape(Capsule())

                // 时值进度条（初学者模式用简单横条）
                ProgressView(value: engine.isHolding || holdProgress > 0 ? holdProgress : 0)
                    .tint(noteCardColor)
                    .frame(width: 100)
                    .opacity(engine.isHolding || holdProgress > 0.01 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: engine.isHolding)
            }
            .padding(.trailing, 20)
        }
        .padding(.vertical, 10)
        .background(noteCardColor.opacity(0.05))
    }

    private var beginnerFeedback: some View {
        let correctPhrases = ["太棒了！","完美！","就是这个！","继续！","好极了！"]
        return Group {
            switch engine.feedback {
            case .waiting:
                Text(previewPlayer.isPlaying ? "正在试听…" : "弹这个键")
                    .foregroundStyle(.secondary)
            case .correct:
                // 用 correctCount 取固定下标，避免动画过渡时两帧取不同文字
                Text(correctPhrases[engine.correctCount % correctPhrases.count])
                    .fontWeight(.bold).foregroundStyle(.green)
            case .wrong:
                Text("再试一次").foregroundStyle(.red)
            case .finished:
                Text("完成！").foregroundStyle(.orange)
            }
        }
        .font(.system(size: 34, weight: .semibold, design: .rounded))
        .multilineTextAlignment(.center)
        .animation(.easeInOut(duration: 0.2), value: engine.feedback)
    }

    private var beginnerKeyboard: some View {
        let targetSet: Set<Int> = engine.currentNote.map { Set($0.chordNotes) } ?? []
        return VStack(spacing: 6) {
            // MIDI 连接状态（初学者也需要知道键盘是否已接入）
            HStack {
                if midiManager.connectedDeviceCount > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(.green).frame(width: 7, height: 7)
                            .shadow(color: .green, radius: 2)
                        Text("MIDI 键盘已连接").font(.caption2).foregroundStyle(.green)
                    }
                } else {
                    Text("触摸键盘").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)

            PianoKeyboardView(
                activeNotes: midiManager.activeNotes,
                targetNotes: (previewPlayer.isPlaying || previewPlayer.isDownloading) ? [] : targetSet,
                onNoteOn: { note, vel in
                    guard !previewPlayer.isPlaying, !previewPlayer.isDownloading else { return }
                    soundEngine.playNote(note: note, velocity: vel)
                    engine.handleNoteOn(midiNumber: Int(note))
                },
                onNoteOff: { note in
                    soundEngine.stopNote(note: note)
                    engine.handleNoteOff(midiNumber: Int(note))
                }
            )
            .frame(height: 200)
            .opacity(previewPlayer.isPlaying || previewPlayer.isDownloading ? 0.45 : 1.0)
            .allowsHitTesting(!previewPlayer.isPlaying && !previewPlayer.isDownloading)
            .animation(.easeInOut(duration: 0.2), value: previewPlayer.isPlaying)
        }
    }

    private var beginnerNextNotes: some View {
        let upcoming = Array(engine.notes.dropFirst(engine.currentIndex + 1).prefix(5))
        return HStack(spacing: 6) {
            Text("接下来：").font(.caption).foregroundStyle(.tertiary)
            ForEach(upcoming) { note in
                Text(note.name)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            if upcoming.isEmpty {
                Text("最后一个！").font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            // 试听入口（初学者也需要）
            Button(action: { previewPlayer.toggle(song: engine.song, session: authSession) }) {
                Image(systemName: previewPlayer.isPlaying ? "stop.circle" : "play.circle")
                    .foregroundStyle(previewPlayer.isPlaying ? .orange : .blue)
            }
        }
    }

    // MARK: - 1. 进度条

    private var progressSection: some View {
        VStack(spacing: 5) {
            HStack {
                Text("\(engine.currentIndex) / \(engine.notes.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 10) {
                    Label("\(engine.correctCount)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Label("\(engine.wrongCount)",   systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
                .font(.caption)
            }
            ProgressView(value: engine.progress)
                .tint(.blue)
                .animation(.easeInOut, value: engine.progress)
        }
    }

    // MARK: - 2. 试听 + 节拍器

    private var controlsRow: some View {
        VStack(spacing: 6) {
            // 试听按钮（独立居中）
            Button(action: { previewPlayer.toggle(song: engine.song, session: authSession) }) {
                HStack(spacing: 6) {
                    if previewPlayer.isDownloading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: previewPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    Text(previewPlayer.isDownloading ? "下载中…"
                         : previewPlayer.isPlaying   ? "停止试听"
                                                     : "试听完整曲目")
                        .font(.subheadline)
                }
                .foregroundStyle(previewPlayer.isPlaying ? .orange : .blue)
                .padding(.horizontal, 24).padding(.vertical, 9)
                .background((previewPlayer.isPlaying ? Color.orange : Color.blue).opacity(0.1))
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: previewPlayer.isPlaying)
            .animation(.easeInOut(duration: 0.2), value: previewPlayer.isDownloading)

            // 节拍器行（toggle + BPM + 节拍指示点）
            HStack(spacing: 10) {
                // 节拍闪烁点（极简，替代摆锤）
                Circle()
                    .fill(isMetronomeOn
                          ? (metronome.currentBeat == 0 ? Color.orange : Color.blue)
                          : Color.clear)
                    .frame(width: 7, height: 7)
                    .animation(.easeOut(duration: 0.06), value: metronome.currentBeat)

                Text("节拍器").font(.caption).foregroundStyle(.secondary)

                Toggle("", isOn: $isMetronomeOn)
                    .labelsHidden()
                    .onChange(of: isMetronomeOn) { _, on in
                        if on { configureAndStartMetronome() } else { metronome.stop() }
                    }

                Spacer()

                // BPM 控制（节拍器开启时显示）
                HStack(spacing: 8) {
                    Button { adjustBPM(-5) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    Text("\(metronome.bpm) BPM")
                        .font(.caption).fontWeight(.semibold).monospacedDigit()
                    Button { adjustBPM(+5) } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .font(.body)
                .opacity(isMetronomeOn ? 1 : 0)
                .allowsHitTesting(isMetronomeOn)
                .animation(.easeInOut(duration: 0.2), value: isMetronomeOn)
            }
        }
    }

    // MARK: - 3. 目标音符

    private var targetNoteSection: some View {
        VStack(spacing: 12) {
            switch engine.loadState {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView().scaleEffect(1.4)
                    Text("正在加载乐谱…").font(.subheadline).foregroundStyle(.secondary)
                }

            case .failed(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 44)).foregroundStyle(.orange)
                    Text("加载失败").font(.subheadline).foregroundStyle(.secondary)
                    Text(msg).font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    Button("重试") { Task { await engine.retryLoad(session: authSession) } }
                        .buttonStyle(.bordered)
                }

            case .ready:
                if engine.isFinished {
                    Text("完成！").font(.system(size: 56)).foregroundStyle(.orange)
                } else if let note = engine.currentNote {
                    noteCard(note: note)
                    if note.isChord { chordHint(note: note) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: 音符卡片（含时值遮罩动画）

    private func noteCard(note: MusicalNote) -> some View {
        VStack(spacing: 8) {
            // 状态标签
            Text(previewPlayer.isDownloading ? "下载中…"
                 : previewPlayer.isPlaying   ? "正在试听…"
                                             : "弹这个键")
                .font(.subheadline).foregroundStyle(.secondary)

            // 音符卡片
            ZStack {
                // 卡片底色
                RoundedRectangle(cornerRadius: 20)
                    .fill(noteCardColor)

                // 时值遮罩：暗色从右向左退去，逐渐显露卡片本色
                RoundedRectangle(cornerRadius: 20)
                    .fill(.black.opacity(0.42))
                    .scaleEffect(x: max(0, 1.0 - holdProgress), anchor: .trailing)
                    .opacity(engine.isHolding || holdProgress > 0.01 ? 1 : 0)

                // 内容
                VStack(spacing: 6) {
                    Text(note.fullName)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(note.solfege)
                        .font(.title3).foregroundStyle(.white.opacity(0.8))
                    Text(note.durationHint)
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 180, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: noteCardColor.opacity(0.35), radius: 10, y: 5)
            .opacity(previewPlayer.isPlaying || previewPlayer.isDownloading ? 0.5 : 1.0)
            .animation(.spring(duration: 0.3), value: engine.currentIndex)
            .animation(.easeInOut(duration: 0.2), value: previewPlayer.isPlaying)

            // 松键提醒（opacity，不改变高度）
            Text("再按久一点")
                .font(.caption).foregroundStyle(.orange)
                .frame(height: 18)
                .opacity(engine.showHoldHint ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: engine.showHoldHint)
        }
    }

    // MARK: 和弦提示

    private func chordHint(note: MusicalNote) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text("和弦").font(.caption2).foregroundStyle(.tertiary)
                ForEach(note.chordNotes, id: \.self) { midi in
                    let isPressed = engine.chordPressedNotes.contains(midi)
                    let isMelody  = midi == note.midiNumber
                    HStack(spacing: 3) {
                        Image(systemName: isPressed ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundStyle(isPressed ? .green : (isMelody ? .orange : .secondary))
                        Text(MusicalNote(midiNumber: midi).fullName)
                            .font(.caption).fontWeight(isMelody ? .semibold : .regular)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        isPressed ? Color.green.opacity(0.12)
                        : isMelody ? Color.orange.opacity(0.12)
                        : Color.gray.opacity(0.08))
                    .foregroundStyle(isPressed ? .green : (isMelody ? .orange : .secondary))
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.12), value: isPressed)
                }
            }

            // 和弦反馈（固定高度，opacity 切换）
            Group {
                if engine.showPerfectChord {
                    Text("完美和弦！").fontWeight(.semibold).foregroundStyle(.orange)
                } else if engine.showChordHint {
                    Text("记得一起按和弦").foregroundStyle(.secondary)
                } else {
                    Color.clear
                }
            }
            .font(.caption)
            .frame(height: 18)
            .animation(.easeInOut(duration: 0.2), value: engine.showPerfectChord)
            .animation(.easeInOut(duration: 0.2), value: engine.showChordHint)
        }
        .opacity(previewPlayer.isPlaying || previewPlayer.isDownloading ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: engine.chordPressedNotes)
        .animation(.easeInOut(duration: 0.2), value: previewPlayer.isPlaying)
    }

    // MARK: - 5. 反馈区（固定高度）

    private var feedbackArea: some View {
        let correctPhrases = ["太棒了！","完美！","就是这个！","继续！","好极了！"]
        return Group {
            if previewPlayer.isDownloading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text("正在下载 MIDI…").foregroundStyle(.secondary)
                }
            } else if previewPlayer.isPlaying {
                Text("先听一遍，感受节奏和旋律").foregroundStyle(.secondary)
            } else {
                switch engine.feedback {
                case .waiting:
                    Text("等待你弹奏…").foregroundStyle(.secondary)
                case .correct:
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(correctPhrases[engine.correctCount % correctPhrases.count])
                            .fontWeight(.semibold)
                    }.foregroundStyle(.green)
                case .wrong:
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                        Text("再试一次，目标是 \(engine.currentNote?.fullName ?? "")")
                    }.foregroundStyle(.red)
                case .finished:
                    Text("完成！").fontWeight(.bold).foregroundStyle(.orange)
                }
            }
        }
        .font(.subheadline)
        .lineLimit(1)
        .animation(.easeInOut(duration: 0.2), value: engine.feedback)
        .animation(.easeInOut(duration: 0.2), value: previewPlayer.isPlaying)
        .animation(.easeInOut(duration: 0.2), value: previewPlayer.isDownloading)
    }

    // MARK: - 6. 键盘参考

    private var miniKeyboardSection: some View {
        let targetSet: Set<Int> = engine.currentNote.map { Set($0.chordNotes) } ?? []
        return VStack(spacing: 6) {
            HStack {
                Text("键位参考").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if midiManager.connectedDeviceCount > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("MIDI 已连接").font(.caption2).foregroundStyle(.green)
                    }
                }
            }
            .padding(.horizontal, 8)

            PianoKeyboardView(
                activeNotes: midiManager.activeNotes,
                targetNotes: (previewPlayer.isPlaying || previewPlayer.isDownloading) ? [] : targetSet,
                onNoteOn: { note, vel in
                    guard !previewPlayer.isPlaying, !previewPlayer.isDownloading else { return }
                    soundEngine.playNote(note: note, velocity: vel)
                    engine.handleNoteOn(midiNumber: Int(note))
                },
                onNoteOff: { note in
                    soundEngine.stopNote(note: note)
                    engine.handleNoteOff(midiNumber: Int(note))
                }
            )
            .frame(height: 120)
            .padding(.horizontal, 8)
            .opacity(previewPlayer.isPlaying || previewPlayer.isDownloading ? 0.45 : 1.0)
            .allowsHitTesting(!previewPlayer.isPlaying && !previewPlayer.isDownloading)
            .animation(.easeInOut(duration: 0.2), value: previewPlayer.isPlaying)
            .animation(.easeInOut(duration: 0.2), value: previewPlayer.isDownloading)
        }
    }

    // MARK: - 辅助

    private var noteCardColor: Color {
        switch engine.feedback {
        case .waiting:  return .blue
        case .correct:  return .green
        case .wrong:    return .red
        case .finished: return .orange
        }
    }

    private func configureAndStartMetronome() {
        metronome.bpm = engine.song.bpm ?? 60
        if let sig = engine.song.timeSignature,
           let slash = sig.firstIndex(of: "/"),
           let beats = Int(sig[sig.startIndex..<slash]) {
            metronome.beatsPerMeasure = beats
        } else {
            metronome.beatsPerMeasure = 4
        }
        metronome.start()
    }

    private func adjustBPM(_ delta: Int) {
        let next = max(20, min(240, metronome.bpm + delta))
        guard next != metronome.bpm else { return }
        metronome.bpm = next
        if metronome.isRunning { metronome.stop(); metronome.start() }
    }

    // MARK: - 上传练习记录

    private func uploadSession() async {
        guard authSession.isAuthenticated else { return }
        guard engine.loadState == .ready, let startedAt = engine.startedAt else { return }
        let notesTotal   = engine.notes.count
        let attemptTotal = engine.correctCount + engine.wrongCount
        guard attemptTotal > 0 else { return }

        let score: Double
        if engine.isFinished {
            score = Double(engine.correctCount) / Double(attemptTotal) * 100
        } else {
            let pct = notesTotal > 0 ? Double(engine.correctCount) / Double(notesTotal) * 100 : 0
            score = min(94.0, pct)
        }

        let duration = max(1, Int(Date.now.timeIntervalSince(startedAt)))
        let body = PracticeSessionCreate(
            songId: engine.song.id, score: score, durationSeconds: duration,
            notesHit: engine.correctCount, notesTotal: notesTotal, startedAt: startedAt
        )
        do {
            let _: PracticeSessionResponse = try await authSession.request(.recordSession(body))
            await progressRepository.load()
        } catch {
            print("⚠️ 练习记录上传失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 完成页

struct FinishedView: View {
    let engine: PracticeEngine
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("完成！").font(.system(size: 64)).foregroundStyle(.orange)
            Text("完成了！").font(.largeTitle).bold()
            Text(engine.song.displayTitle).font(.title2).foregroundStyle(.secondary)

            HStack(spacing: 40) {
                statView("\(engine.correctCount)", "答对", .green)
                statView(engine.accuracyText,      "准确率", .blue)
                statView("\(engine.wrongCount)",    "答错", .red)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 12) {
                Button { engine.restart() } label: {
                    Label("再练一遍", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.blue).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button { onDismiss() } label: {
                    Label("选其他曲目", systemImage: "music.note.list")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.systemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private func statView(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack {
            Text(value).font(.system(size: 40, weight: .bold)).foregroundStyle(color)
            Text(label).foregroundStyle(.secondary)
        }
    }
}
