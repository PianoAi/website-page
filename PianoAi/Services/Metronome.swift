import Foundation
import AudioToolbox
import UIKit

@Observable
@MainActor
final class Metronome {

    private(set) var isRunning = false
    private(set) var currentBeat = 0   // 0 = 强拍，1…n-1 = 弱拍
    var bpm: Int = 60
    var beatsPerMeasure: Int = 4

    private var timer: Timer?
    private var beatCount = 0
    private let accentFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let weakFeedback   = UIImpactFeedbackGenerator(style: .light)

    func start() {
        stop()
        isRunning = true
        beatCount = 0
        accentFeedback.prepare()
        weakFeedback.prepare()
        tick()   // 立即打第一拍
        let interval = 60.0 / Double(bpm.clamped(to: 20...240))
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        currentBeat = 0
        beatCount = 0
    }

    // MARK: - Private

    private func tick() {
        let beat = beatCount % max(1, beatsPerMeasure)
        currentBeat = beat
        beatCount += 1

        if beat == 0 {
            AudioServicesPlaySystemSound(1052)
            accentFeedback.impactOccurred()
        } else {
            AudioServicesPlaySystemSound(1104)
            weakFeedback.impactOccurred()
        }
    }
}

// MARK: - Comparable clamp helper (avoids importing extra modules)

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
