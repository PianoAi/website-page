import SwiftUI

// 水平 Piano Roll 条：以视觉宽度表示每个音符的时值
// 当前音符 = 高亮颜色 + 大尺寸；已弹 = 淡绿；待弹 = 灰色
struct PianoRollStripView: View {

    let notes: [MusicalNote]
    let currentIndex: Int
    let accentColor: Color   // 传入当前 feedback 颜色

    private let beatWidth: CGFloat = 38   // 每拍对应的像素宽度
    private let maxVisible = 9            // 最多显示几个音符

    private var visibleItems: [(index: Int, note: MusicalNote)] {
        let start = max(0, currentIndex - 1)
        let end   = min(notes.count, start + maxVisible)
        guard start < end else { return [] }
        return (start..<end).map { (index: $0, note: notes[$0]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("演奏序列", systemImage: "music.note.list")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(visibleItems, id: \.index) { item in
                        NoteBar(
                            note: item.note,
                            isCurrent: item.index == currentIndex,
                            isPast:    item.index < currentIndex,
                            accentColor: accentColor,
                            beatWidth: beatWidth
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - 单个音符条

private struct NoteBar: View {

    let note: MusicalNote
    let isCurrent: Bool
    let isPast: Bool
    let accentColor: Color
    let beatWidth: CGFloat

    private var barWidth: CGFloat {
        max(32, CGFloat(note.durationBeats) * beatWidth)
    }

    private var barHeight: CGFloat { isCurrent ? 60 : 42 }

    private var fillColor: Color {
        if isPast    { return .green.opacity(0.45) }
        if isCurrent { return accentColor }
        return .secondary.opacity(0.18)
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(fillColor)
                    .frame(width: barWidth, height: barHeight)

                VStack(spacing: 1) {
                    Text(note.name)
                        .font(isCurrent ? .subheadline.bold() : .caption2)
                        .foregroundStyle(.white)
                    // 只在宽度足够 或 当前音符 时显示时值标签
                    if isCurrent || barWidth > 44 {
                        Text(note.durationLabel)
                            .font(.system(size: 9, weight: isCurrent ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isCurrent)

            // 当前音符下方的小箭头
            if isCurrent {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(accentColor)
            } else {
                Color.clear.frame(height: 9)
            }
        }
    }
}
