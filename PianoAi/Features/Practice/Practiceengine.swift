import Foundation
import Observation

// MARK: - 状态枚举

enum FeedbackState: Equatable {
    case waiting
    case correct
    case wrong
    case finished
}

enum LoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

// MARK: - 跟练引擎

@Observable
@MainActor
class PracticeEngine {

    // MARK: 对外状态

    let song: Song

    /// 当前练习 BPM，可由外部（节拍器）同步更新
    var bpm: Int

    private(set) var notes: [MusicalNote] = []
    private(set) var loadState: LoadState = .idle

    private(set) var currentIndex: Int = 0
    private(set) var feedback: FeedbackState = .waiting
    private(set) var correctCount: Int = 0
    private(set) var wrongCount: Int = 0
    private(set) var startedAt: Date?

    // 时值填充进度
    private(set) var isHolding: Bool = false
    private(set) var holdDuration: Double = 0.0

    // 松键软提醒（路径 A）
    private(set) var showHoldHint: Bool = false

    // 和弦收集状态（方案 C）
    private(set) var chordPressedNotes: Set<Int> = []
    private(set) var showPerfectChord: Bool = false   // "完美和弦！"
    private(set) var showChordHint: Bool = false      // "记得一起按"

    // MARK: 计算属性

    var currentNote: MusicalNote? {
        guard loadState == .ready, currentIndex < notes.count else { return nil }
        return notes[currentIndex]
    }

    var progress: Double {
        notes.isEmpty ? 0 : Double(currentIndex) / Double(notes.count)
    }

    var isFinished: Bool { loadState == .ready && currentIndex >= notes.count }

    var accuracyText: String {
        let total = correctCount + wrongCount
        guard total > 0 else { return "—" }
        return "\(Int(Double(correctCount) / Double(total) * 100))%"
    }

    // MARK: 私有

    private var advanceTask: Task<Void, Never>?
    private var chordWindowTask: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    private var holdStartTime: Date?

    // MARK: 初始化

    init(song: Song) {
        self.song = song
        self.bpm = song.bpm ?? 60
    }

    // MARK: - 加载 MIDI

    func load(session: AuthSession) async {
        guard loadState == .idle else { return }
        loadState = .loading
        do {
            let midiURL = try await MIDICache.shared.fetch(song: song, session: session)
            let parsed = try MIDIParser.parse(url: midiURL)
            notes = parsed
            startedAt = Date()
            loadState = .ready
        } catch is CancellationError {
            loadState = .idle
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func retryLoad(session: AuthSession) async {
        loadState = .idle
        await load(session: session)
    }

    // MARK: - Note On 路由

    func handleNoteOn(midiNumber: Int) {
        guard feedback == .waiting, let target = currentNote else { return }
        if target.isChord {
            handleChordNoteOn(midiNumber: midiNumber, target: target)
        } else {
            handleSingleNoteOn(midiNumber: midiNumber, target: target)
        }
    }

    // MARK: - Note Off（松键软检测）

    func handleNoteOff(midiNumber: Int) {
        guard isHolding,
              let target = currentNote,
              midiNumber == target.midiNumber,
              let start = holdStartTime else { return }

        let elapsed = Date.now.timeIntervalSince(start)
        guard elapsed < holdDuration * 0.7 else { return }

        showHoldHint = true
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            showHoldHint = false
        }
    }

    // MARK: - 重新开始

    func restart() {
        advanceTask?.cancel()
        chordWindowTask?.cancel()
        hintTask?.cancel()
        currentIndex = 0
        feedback = .waiting
        correctCount = 0
        wrongCount = 0
        isHolding = false
        holdDuration = 0
        holdStartTime = nil
        chordPressedNotes = []
        showHoldHint = false
        showPerfectChord = false
        showChordHint = false
        startedAt = Date()
    }

    // MARK: - 私有：单音处理

    private func handleSingleNoteOn(midiNumber: Int, target: MusicalNote) {
        if midiNumber == target.midiNumber {
            feedback = .correct
            correctCount += 1
            startHold(for: target)
        } else {
            feedback = .wrong
            wrongCount += 1
            scheduleReset(delay: 0.6)
        }
    }

    // MARK: - 私有：和弦处理（方案 C）

    private func handleChordNoteOn(midiNumber: Int, target: MusicalNote) {
        let chordSet = Set(target.chordNotes)

        if chordSet.contains(midiNumber) {
            chordPressedNotes.insert(midiNumber)

            // 第一个和弦音按下时启动收集窗口
            if chordWindowTask == nil {
                startChordWindow(target: target)
            }

            // 全部和弦音已收集 → 完美和弦
            if chordSet.isSubset(of: chordPressedNotes) {
                chordWindowTask?.cancel()
                chordWindowTask = nil
                completePerfectChord(target: target)
            }

        } else if chordPressedNotes.isEmpty {
            // 窗口未开启时按了错误音 → 算错
            feedback = .wrong
            wrongCount += 1
            scheduleReset(delay: 0.6)
        }
        // 收集中途按了错误音 → 宽容忽略（防止误触）
    }

    private func startChordWindow(target: MusicalNote) {
        chordWindowTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            chordWindowTask = nil
            let melodyPressed = chordPressedNotes.contains(target.midiNumber)
            chordPressedNotes = []

            if melodyPressed {
                // 旋律音已按，宽容过关 + 软提醒
                feedback = .correct
                correctCount += 1
                showChordHint = true
                startHold(for: target)
                hintTask?.cancel()
                hintTask = Task {
                    try? await Task.sleep(for: .seconds(2.0))
                    guard !Task.isCancelled else { return }
                    showChordHint = false
                }
            } else {
                // 连旋律音都没按 → 算错
                feedback = .wrong
                wrongCount += 1
                scheduleReset(delay: 0.6)
            }
        }
    }

    private func completePerfectChord(target: MusicalNote) {
        chordPressedNotes = []
        feedback = .correct
        correctCount += 1
        showPerfectChord = true
        startHold(for: target)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showPerfectChord = false
        }
    }

    // MARK: - 私有：时值驱动推进

    private func startHold(for note: MusicalNote) {
        let beatSec = 60.0 / Double(max(20, bpm))
        let duration = max(0.35, note.durationBeats * beatSec)
        isHolding = true
        holdDuration = duration
        holdStartTime = Date.now
        showHoldHint = false

        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self.advanceToNext()
        }
    }

    private func scheduleReset(delay: Double) {
        advanceTask?.cancel()
        chordWindowTask?.cancel()
        chordWindowTask = nil
        chordPressedNotes = []
        advanceTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self.feedback = .waiting
        }
    }

    private func advanceToNext() {
        isHolding = false
        holdStartTime = nil
        chordWindowTask?.cancel()
        chordWindowTask = nil
        chordPressedNotes = []
        showChordHint = false
        showPerfectChord = false
        currentIndex += 1
        feedback = isFinished ? .finished : .waiting
    }
}
