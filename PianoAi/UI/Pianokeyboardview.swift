//
//  Pianokeyboardview.swift
//  PianoAi
//
//  Created by Fox on 5/21/26.
//
// 钢琴键盘 UI
// activeNotes = 正在按下的键（蓝色）
// targetNotes = 目标提示键（黄色）

import SwiftUI

struct PianoKeyboardView: View {

    let activeNotes: Set<Int>
    var targetNotes: Set<Int> = []
    var onNoteOn: ((UInt8, UInt8) -> Void)?
    var onNoteOff: ((UInt8) -> Void)?

    let startNote = 48
    let octaveCount = 2
    let whiteKeyOffsets = [0, 2, 4, 5, 7, 9, 11]
    let blackKeyData: [(position: Double, semitone: Int)] = [
        (0.6, 1), (1.6, 3), (3.6, 6), (4.6, 8), (5.6, 10)
    ]

    var whiteKeys: [Int] {
        var keys: [Int] = []
        for octave in 0..<octaveCount {
            for semitone in whiteKeyOffsets {
                keys.append(startNote + octave * 12 + semitone)
            }
        }
        return keys
    }

    var body: some View {
        GeometryReader { geo in
            let totalWhiteKeys = whiteKeys.count
            let whiteKeyWidth = (geo.size.width - CGFloat(totalWhiteKeys - 1) * 2) / CGFloat(totalWhiteKeys)
            let whiteKeyHeight = geo.size.height
            let blackKeyWidth = whiteKeyWidth * 0.6
            let blackKeyHeight = whiteKeyHeight * 0.62

            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(whiteKeys, id: \.self) { note in
                        WhiteKeyView(
                            note: note,
                            isActive: activeNotes.contains(note),
                            isTarget: targetNotes.contains(note),
                            width: whiteKeyWidth,
                            height: whiteKeyHeight,
                            onNoteOn: onNoteOn,
                            onNoteOff: onNoteOff
                        )
                    }
                }

                ForEach(0..<octaveCount, id: \.self) { octave in
                    ForEach(blackKeyData, id: \.semitone) { blackKey in
                        let note = startNote + octave * 12 + blackKey.semitone
                        let octaveOffset = CGFloat(octave * 7) * (whiteKeyWidth + 2)
                        let xOffset = octaveOffset + (blackKey.position * (whiteKeyWidth + 2)) - blackKeyWidth / 2
                        BlackKeyView(
                            note: note,
                            isActive: activeNotes.contains(note),
                            isTarget: targetNotes.contains(note),
                            width: blackKeyWidth,
                            height: blackKeyHeight,
                            onNoteOn: onNoteOn,
                            onNoteOff: onNoteOff
                        )
                        .offset(x: xOffset)
                    }
                }
            }
        }
    }
}

// MARK: - 白键

struct WhiteKeyView: View {
    let note: Int
    let isActive: Bool
    let isTarget: Bool
    let width: CGFloat
    let height: CGFloat
    var onNoteOn: ((UInt8, UInt8) -> Void)?
    var onNoteOff: ((UInt8) -> Void)?

    @State private var isTouched = false
    var isPressed: Bool { isActive || isTouched }

    var keyColor: Color {
        if isPressed { return .blue.opacity(0.35) }
        if isTarget  { return .yellow.opacity(0.5) }
        return .white
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(keyColor)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.4), lineWidth: 1))
            .overlay(
                VStack {
                    Spacer()
                    if note % 12 == 0 {
                        let octave = note / 12 - 1
                        Text("C\(octave)")
                            .font(.system(size: min(width * 0.45, 10), weight: .medium))
                            .foregroundStyle(.gray)
                            .padding(.bottom, 4)
                    }
                    if isTarget && !isPressed {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .padding(.bottom, 8)
                    }
                }
            )
            .frame(width: width, height: height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isTouched {
                            isTouched = true
                            onNoteOn?(UInt8(note), 100)
                        }
                    }
                    .onEnded { _ in
                        isTouched = false
                        onNoteOff?(UInt8(note))
                    }
            )
            .animation(.easeInOut(duration: 0.05), value: isPressed)
            .animation(.easeInOut(duration: 0.1), value: isTarget)
    }
}

// MARK: - 黑键

struct BlackKeyView: View {
    let note: Int
    let isActive: Bool
    let isTarget: Bool
    let width: CGFloat
    let height: CGFloat
    var onNoteOn: ((UInt8, UInt8) -> Void)?
    var onNoteOff: ((UInt8) -> Void)?

    @State private var isTouched = false
    var isPressed: Bool { isActive || isTouched }

    var keyColor: Color {
        if isPressed { return .blue }
        if isTarget  { return .yellow }
        return .black
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(keyColor)
            .frame(width: width, height: height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isTouched {
                            isTouched = true
                            onNoteOn?(UInt8(note), 110)
                        }
                    }
                    .onEnded { _ in
                        isTouched = false
                        onNoteOff?(UInt8(note))
                    }
            )
            .animation(.easeInOut(duration: 0.05), value: isPressed)
            .animation(.easeInOut(duration: 0.1), value: isTarget)
            .zIndex(1)
    }
}

#Preview {
    PianoKeyboardView(activeNotes: [60], targetNotes: [64])
        .frame(height: 160)
        .padding()
}
