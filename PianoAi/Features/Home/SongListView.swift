import SwiftUI

// MARK: - 风格 Chip（首页筛选共用）

struct GenreChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(isSelected ? color : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - 曲目行

struct SongRowView: View {
    let song: Song
    let progress: ProgressResponse?
    var isLocked: Bool = false
    var showDifficulty: Bool = false   // 混合难度列表时显示难度标签

    private var difficultyColor: Color {
        switch song.difficulty {
        case "beginner":     return .green
        case "intermediate": return .orange
        case "advanced":     return .red
        default:             return .gray
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: song.genreIcon)
                .font(.system(size: 26))
                .foregroundStyle(difficultyColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.displayTitle).font(.headline)

                if song.localizedTitle != nil {
                    Text(song.title)
                        .font(.caption).foregroundStyle(.tertiary)
                }

                if let composer = song.composer {
                    Text(composer).font(.caption).foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    // 难度标签（仅混合列表时显示）
                    if showDifficulty {
                        Text(song.difficultyLabel)
                            .font(.caption2)
                            .foregroundStyle(difficultyColor)
                    }

                    if let bpm = song.bpm {
                        Text("\(bpm) BPM").font(.caption2).foregroundStyle(.tertiary)
                    } else if let dur = song.durationSeconds {
                        Text("\(dur / 60):\(String(format: "%02d", dur % 60))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    } else if song.isPremium {
                        Image(systemName: "crown.fill")
                            .font(.caption2).foregroundStyle(.yellow)
                    }

                    Spacer()
                    progressBadge
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isLocked ? 0.65 : 1.0)
    }

    @ViewBuilder
    private var progressBadge: some View {
        if let p = progress {
            if p.isCompleted {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.seal.fill")
                    if let best = p.bestScore { Text("\(Int(best))%") }
                }
                .font(.caption2).foregroundStyle(.green)
            } else if p.practiceCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("\(p.practiceCount)次")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
