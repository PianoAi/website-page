//
//  Previewplayer.swift
//  PianoAi
//
//  Created by Fox on 5/22/26.
//
// 试听播放器：下载并用 AVMIDIPlayer 播放完整 MIDI 文件

import Foundation
import AVFoundation
import Combine

class PreviewPlayer: ObservableObject {

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isDownloading: Bool = false
    @Published private(set) var currentSongId: String?

    private var midiPlayer: AVMIDIPlayer?
    private var playTask: Task<Void, Never>?

    // MARK: - 播放 / 暂停

    func toggle(song: Song, session: AuthSession) {
        if (isPlaying || isDownloading) && currentSongId == song.id {
            stop()
        } else {
            play(song: song, session: session)
        }
    }

    func play(song: Song, session: AuthSession) {
        stop()
        currentSongId = song.id

        playTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.isDownloading = true
                let midiURL = try await MIDICache.shared.fetch(song: song, session: session)
                self.isDownloading = false
                guard !Task.isCancelled else { return }

                // AVMIDIPlayer 对 SF2 支持不稳定，直接使用 iOS 内置 DLS（施坦威采样）
                // 与 SoundEngine 使用同一音源，确保按键音和试听音一致
                let dlsPath = "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"
                let dlsURL  = FileManager.default.fileExists(atPath: dlsPath)
                              ? URL(fileURLWithPath: dlsPath) : nil
                self.midiPlayer = try AVMIDIPlayer(contentsOf: midiURL, soundBankURL: dlsURL)
                self.midiPlayer?.prepareToPlay()
                self.isPlaying = true
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.midiPlayer?.play { continuation.resume() }
                }
                self.isPlaying = false
                self.currentSongId = nil
                print("▶️ 开始试听：\(song.title)")
            } catch is CancellationError {
                // User tapped stop — state already reset by stop()
            } catch {
                self.isDownloading = false
                self.currentSongId = nil
                print("❌ 试听失败：\(error.localizedDescription)")
            }
        }
    }

    func stop() {
        playTask?.cancel()
        playTask = nil
        midiPlayer?.stop()
        midiPlayer = nil
        isPlaying = false
        isDownloading = false
        currentSongId = nil
    }

    deinit { stop() }
}
