import Foundation

// MARK: - Session upload

struct PracticeSessionCreate: Encodable, Sendable {
    let songId: String
    let score: Double           // 0–100
    let durationSeconds: Int    // must be > 0
    let notesHit: Int?
    let notesTotal: Int?
    let startedAt: Date
}

struct PracticeSessionResponse: Decodable, Sendable {
    let id: String
    let score: Double
    let durationSeconds: Int
    let notesHit: Int?
    let notesTotal: Int?
    let startedAt: Date
    let endedAt: Date
}

// MARK: - Per-song progress

struct ProgressResponse: Decodable, Sendable {
    let id: String
    let songId: String
    let practiceCount: Int
    let bestScore: Double?
    let totalPracticeSeconds: Int
    let isCompleted: Bool
    let lastPracticedAt: Date?
    let updatedAt: Date
}

// MARK: - Aggregate stats

struct UserStatsResponse: Decodable, Sendable {
    let totalSongsPracticed: Int
    let totalPracticeSeconds: Int
    let songsCompleted: Int
    let averageScore: Double?
    let currentStreakDays: Int
}

// MARK: - Daily breakdown (from /progress/weekly)

struct DailyPractice: Decodable, Identifiable, Sendable {
    let date: Date
    let totalSeconds: Int
    let avgScore: Double?
    let sessionCount: Int

    var id: Date { date }
    var minutes: Double { Double(totalSeconds) / 60.0 }
}
