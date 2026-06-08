import Foundation

// MARK: - MusicalNote (used by PracticeEngine)

struct MusicalNote: Identifiable, Sendable {
    let id = UUID()
    let midiNumber: Int         // melody note — required to progress
    let chordNotes: [Int]       // all simultaneous notes (includes midiNumber); used for keyboard highlight
    let durationBeats: Double   // duration in quarter-note beats (1.0 = ♩, 2.0 = 𝅗𝅥, 4.0 = ○)
    let startBeat: Double       // absolute onset position in beats from song start (for rhythm mode)

    init(midiNumber: Int, chordNotes: [Int]? = nil, durationBeats: Double = 1.0, startBeat: Double = 0.0) {
        self.midiNumber = midiNumber
        self.chordNotes = chordNotes ?? [midiNumber]
        self.durationBeats = durationBeats
        self.startBeat = startBeat
    }

    var name: String {
        ["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"][midiNumber % 12]
    }
    var octave: Int      { midiNumber / 12 - 1 }
    var fullName: String { "\(name)\(octave)" }
    var solfege: String {
        ["Do","Do♯","Re","Re♯","Mi","Fa","Fa♯","Sol","Sol♯","La","La♯","Ti"][midiNumber % 12]
    }
    var isChord: Bool { chordNotes.count > 1 }

    /// 节拍数文字，供 Piano Roll 标签显示
    var durationLabel: String {
        if durationBeats >= 3.5 { return "4拍" }
        if durationBeats >= 1.75 { return "2拍" }
        if durationBeats >= 0.875 { return "1拍" }
        if durationBeats >= 0.4  { return "½拍" }
        return "¼拍"
    }

    /// 供当前音符卡片显示的引导文字，结合节拍器使用
    var durationHint: String {
        if durationBeats >= 3.5  { return "按住 4 拍" }
        if durationBeats >= 1.75 { return "按住 2 拍" }
        if durationBeats >= 0.875 { return "按住 1 拍" }
        if durationBeats >= 0.4  { return "短按 半拍" }
        return "轻触"
    }
}

// MARK: - Song (matches backend SongResponse)

struct Song: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    /// 服务端根据 Accept-Language 自动选好的本地化标题，没有匹配翻译时为 nil
    let localizedTitle: String?
    let composer: String?
    let arranger: String?
    let difficulty: String      // "beginner" | "intermediate" | "advanced"
    let genre: String
    let durationSeconds: Int?
    let bpm: Int?
    let timeSignature: String?
    let keySignature: String?
    let isPremium: Bool
    let description: String?
    let createdAt: Date

    /// 展示用标题：优先本地化名，没有则用原名
    var displayTitle: String { localizedTitle ?? title }

    // Populated after MIDI download + parse (Step 3-4). Empty for now.
    var notes: [MusicalNote] { [] }

    var difficultyLabel: String {
        switch difficulty {
        case "beginner":     return "入门"
        case "intermediate": return "中级"
        case "advanced":     return "高级"
        default:             return difficulty
        }
    }

    var genreIcon: String {
        switch genre {
        case "classical": return "music.note"
        case "pop":       return "music.mic"
        case "jazz":      return "music.note.list"
        case "folk":      return "music.note.list"   // "guitars" is iOS 16+
        default:          return "music.note"         // "pianokeys" is iOS 16+
        }
    }
}

// MARK: - Bundled demo songs（引导流程中无需账号即可练习）

extension Song {
    static let bundledBeginner = Song(
        id: "02bc682e-b784-44f9-85de-1d1e89709bec",
        title: "Frère Jacques", localizedTitle: "两只老虎",
        composer: "Traditional", arranger: nil,
        difficulty: "beginner", genre: "folk",
        durationSeconds: nil, bpm: 100,
        timeSignature: "4/4", keySignature: nil,
        isPremium: false, description: nil, createdAt: .distantPast
    )
    static let bundledIntermediate = Song(
        id: "b6582fb7-87e6-4a17-8880-6df22b003099",
        title: "Das Wohltemperierte Clavier I, Praeludium I", localizedTitle: nil,
        composer: "BachJS", arranger: nil,
        difficulty: "intermediate", genre: "classical",
        durationSeconds: nil, bpm: 72,
        timeSignature: "4/4", keySignature: nil,
        isPremium: false, description: nil, createdAt: .distantPast
    )
    static let bundledAdvanced = Song(
        id: "0e2ab5b0-abda-47fc-bb0b-de431fdd0840",
        title: "Sonata No. 8 Pathetique (2nd Movement)", localizedTitle: "悲怆 第二乐章",
        composer: "BeethovenLv", arranger: nil,
        difficulty: "advanced", genre: "classical",
        durationSeconds: nil, bpm: 60,
        timeSignature: "3/4", keySignature: nil,
        isPremium: false, description: nil, createdAt: .distantPast
    )
}

// MARK: - Paginated response

struct SongPage: Decodable, Sendable {
    let items: [Song]
    let total: Int
    let page: Int
    let pageSize: Int
    let hasMore: Bool
}

// MARK: - Files (presigned URLs)

struct SongFilesResult: Sendable {
    let midiUrl: String?
    let sheetPdfUrl: String?
    let thumbnailUrl: String?
    let expiresIn: Int
}

// 显式 nonisolated 实现，避免 Swift 6 并发检查器把合成的 Decodable
// 推断为 main-actor-isolated（SongFilesResult 只有值类型，无 UI 依赖）
extension SongFilesResult: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        midiUrl       = try c.decodeIfPresent(String.self, forKey: .midiUrl)
        sheetPdfUrl   = try c.decodeIfPresent(String.self, forKey: .sheetPdfUrl)
        thumbnailUrl  = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        expiresIn     = try c.decode(Int.self, forKey: .expiresIn)
    }
    private enum CodingKeys: String, CodingKey {
        case midiUrl, sheetPdfUrl, thumbnailUrl, expiresIn
    }
}
