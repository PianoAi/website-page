//
//  Soundengine.swift
//  PianoAi
//
//  Created by Fox on 5/21/26.
//
// SoundEngine.swift
// 负责播放钢琴音色
// 使用苹果原生 AVAudioEngine + AVAudioUnitSampler，无需第三方库
// 音色来自 .sf2 SoundFont 文件（需要自行添加到项目）
import Combine
import Foundation
import AVFoundation

class SoundEngine: ObservableObject {
    
    // MARK: - 音频核心组件
    
    private let audioEngine = AVAudioEngine()
    
    /// AVAudioUnitSampler：可加载 SF2 音色文件，支持 MIDI 音符播放
    private let sampler = AVAudioUnitSampler()
    
    /// SF2 文件是否加载成功
    @Published var isReady: Bool = false
    
    // MARK: - 初始化
    
    init() {
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        // 1. 将 Sampler 接入音频引擎
        audioEngine.attach(sampler)
        audioEngine.connect(sampler, to: audioEngine.mainMixerNode, format: nil)
        
        // 2. 配置音频会话（重要：允许和其他 App 混音，不打断背景音乐）
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("⚠️ 音频会话配置失败：\(error.localizedDescription)")
        }
        
        // 3. 启动音频引擎
        do {
            try audioEngine.start()
            print("✅ 音频引擎已启动")
        } catch {
            print("❌ 音频引擎启动失败：\(error.localizedDescription)")
            return
        }
        
        // 4. 加载 SF2 钢琴音色文件
        loadPianoSoundFont()
    }
    
    // MARK: - 加载 SF2 音色文件
    
    private func loadPianoSoundFont() {
        // 优先加载项目内的 piano.sf2（如 Salamander Grand Piano）
        // 若未找到，自动回退到 iOS 内置 GM 音库（施坦威采样，音质良好）
        let sf2URL = Bundle.main.url(forResource: "piano", withExtension: "sf2")

        // iOS 内置 General MIDI 音库路径（包含高质量施坦威大钢琴采样）
        let systemDLSPath = "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"
        let systemURL     = URL(fileURLWithPath: systemDLSPath)

        let soundBankURL: URL
        if let bundleURL = sf2URL {
            soundBankURL = bundleURL
        } else if FileManager.default.fileExists(atPath: systemDLSPath) {
            soundBankURL = systemURL
            print("ℹ️ piano.sf2 未找到，使用 iOS 内置 GM 音库（施坦威钢琴）")
        } else {
            print("⚠️ 音色加载失败：未找到 SF2 或系统音库")
            return
        }

        do {
            try sampler.loadSoundBankInstrument(
                at: soundBankURL,
                program: 0,      // 0 = Acoustic Grand Piano
                bankMSB: 0x79,   // kAUSampler_DefaultMelodicBankMSB
                bankLSB: 0
            )
            DispatchQueue.main.async { self.isReady = true }
            print("✅ 钢琴音色加载：\(soundBankURL.lastPathComponent)")
        } catch {
            print("❌ 音色加载失败：\(error.localizedDescription)")
        }
    }
    
    // MARK: - 播放控制
    
    /// 按下音符
    /// - Parameters:
    ///   - note: MIDI 音符编号（0-127，中央 C = 60）
    ///   - velocity: 力度（1-127，越大声音越强）
    func playNote(note: UInt8, velocity: UInt8 = 100) {
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)
    }
    
    /// 松开音符
    func stopNote(note: UInt8) {
        sampler.stopNote(note, onChannel: 0)
    }
    
    /// 停止所有音符（紧急静音）
    func stopAllNotes() {
        for note: UInt8 in 0...127 {
            sampler.stopNote(note, onChannel: 0)
        }
    }
}
