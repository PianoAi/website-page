//
//  SplashView.swift
//  PianoAi
//
// 启动动画页：Logo 弹入 + 浮动音符 + 钢琴键装饰

import SwiftUI

// MARK: - 品牌颜色

private enum Brand {
    static let navy = Color(red: 0.043, green: 0.059, blue: 0.420)  // #0B0F6B
    static let red  = Color(red: 0.898, green: 0.243, blue: 0.169)  // #E53E2B
    static let bg   = Color(red: 0.953, green: 0.957, blue: 0.996)  // 极淡蓝灰
}

// MARK: - SplashView

struct SplashView: View {
    let onFinished: () -> Void

    @State private var logoScale:      CGFloat = 0.1
    @State private var logoOpacity:    Double  = 0
    @State private var textOffset:     CGFloat = 28
    @State private var textOpacity:    Double  = 0
    @State private var keysOpacity:    Double  = 0
    @State private var isExiting:      Bool    = false
    @State private var hasStarted:     Bool    = false

    var body: some View {
        ZStack {
            // ── 背景渐变 ──────────────────────────────────────────────────
            LinearGradient(
                colors: [Brand.bg, .white],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // ── 浮动音符 ─────────────────────────────────────────────────
            FloatingNotesLayer()

            // ── 主体内容 ─────────────────────────────────────────────────
            VStack(spacing: 22) {

                // Logo（圆角 + 阴影）
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: Brand.navy.opacity(0.18), radius: 28, y: 14)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                // Piano·Ai + 标语
                VStack(spacing: 8) {
                    // 品牌名：红点分隔
                    HStack(spacing: 0) {
                        Text("Piano")
                            .foregroundStyle(Brand.navy)
                        Text("·")
                            .foregroundStyle(Brand.red)
                        Text("Ai")
                            .foregroundStyle(Brand.navy)
                    }
                    .font(.system(size: 38, weight: .bold, design: .rounded))

                    Text("智能钢琴练习")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .tracking(3)
                }
                .offset(y: textOffset)
                .opacity(textOpacity)
            }

            // ── 底部钢琴键装饰 ────────────────────────────────────────────
            VStack {
                Spacer()
                PianoKeysDecoration()
                    .opacity(keysOpacity)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .opacity(isExiting ? 0 : 1)
        .scaleEffect(isExiting ? 1.06 : 1)
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            animate()
        }
    }

    // MARK: - 动画序列

    private func animate() {
        // 1. Logo 弹性缩放进入
        withAnimation(.spring(duration: 0.75, bounce: 0.45)) {
            logoScale   = 1.0
            logoOpacity = 1.0
        }
        // 2. 文字上移淡入
        withAnimation(.easeOut(duration: 0.5).delay(0.55)) {
            textOffset  = 0
            textOpacity = 1
        }
        // 3. 钢琴键淡入
        withAnimation(.easeIn(duration: 0.6).delay(0.8)) {
            keysOpacity = 1
        }
        // 4. 展示 3 秒后退出（用 Task 避免 DispatchQueue 在 SwiftUI 里计时不准）
        Task {
            try? await Task.sleep(for: .seconds(3.0))
            withAnimation(.easeInOut(duration: 0.4)) { isExiting = true }
            try? await Task.sleep(for: .seconds(0.4))
            onFinished()
        }
    }
}

// MARK: - 浮动音符层

private struct FloatingNotesLayer: View {
    private struct NoteItem: Identifiable {
        let id: Int
        let symbol: String
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
        let duration: Double
        let delay: Double
        let rise: CGFloat
    }

    private let items: [NoteItem] = [
        NoteItem(id: 0, symbol: "♩", x: -150, y: -210, size: 22, opacity: 0.13, duration: 3.2, delay: 0.0, rise: 14),
        NoteItem(id: 1, symbol: "♪", x:  140, y: -170, size: 17, opacity: 0.10, duration: 2.8, delay: 0.5, rise: 10),
        NoteItem(id: 2, symbol: "♫", x: -110, y:   60, size: 26, opacity: 0.09, duration: 3.6, delay: 0.3, rise: 16),
        NoteItem(id: 3, symbol: "♬", x:  155, y:   90, size: 19, opacity: 0.11, duration: 3.0, delay: 0.8, rise: 12),
        NoteItem(id: 4, symbol: "♩", x:  -70, y:  210, size: 21, opacity: 0.08, duration: 3.4, delay: 0.2, rise: 18),
        NoteItem(id: 5, symbol: "♪", x:  120, y:  195, size: 15, opacity: 0.09, duration: 2.6, delay: 0.6, rise: 10),
    ]

    @State private var animating = false

    var body: some View {
        ZStack {
            ForEach(items) { item in
                Text(item.symbol)
                    .font(.system(size: item.size))
                    .foregroundStyle(Brand.navy.opacity(item.opacity))
                    .offset(x: item.x, y: item.y + (animating ? -item.rise : item.rise))
                    .animation(
                        .easeInOut(duration: item.duration)
                            .repeatForever(autoreverses: true)
                            .delay(item.delay),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - 底部钢琴键装饰

private struct PianoKeysDecoration: View {
    // 模拟钢琴键的宽窄节奏：true = 较窄较深（象征黑键区域分隔）
    private let pattern = [false, true, false, false, true, false, true, false,
                           false, true, false, false, true, false, true, false, false]

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(pattern.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Brand.navy.opacity(pattern[i] ? 0.10 : 0.055))
                    .frame(width: pattern[i] ? 18 : 22,
                           height: pattern[i] ? 58 : 82)
                    .frame(maxHeight: 82, alignment: .top)
            }
        }
        .padding(.bottom, 0)
    }
}
