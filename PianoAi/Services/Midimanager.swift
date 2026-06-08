//
//  Midimanager.swift
//  PianoAi
//
//  Created by Fox on 5/21/26.
//
// 负责处理所有 MIDI 输入（USB 连接 + 蓝牙 MIDI）
import Combine
import Foundation
import CoreMIDI

class MIDIManager: ObservableObject {
    
    // MARK: - 对外发布的状态（UI 可直接订阅）
    
    /// 当前正在按下的音符集合（MIDI 编号，如中央 C = 60）
    @Published var activeNotes: Set<Int> = []
    
    /// 当前检测到的 MIDI 输入设备数量
    @Published var connectedDeviceCount: Int = 0
    
    // MARK: - 回调（连接 SoundEngine 使用）
    
    /// 音符按下时调用：(音符编号, 力度)
    var onNoteOn: ((UInt8, UInt8) -> Void)?
    
    /// 音符松开时调用：(音符编号)
    var onNoteOff: ((UInt8) -> Void)?
    
    // MARK: - 私有 CoreMIDI 对象
    
    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    
    // MARK: - 启动 MIDI 监听
    
    func start() {
        // 1. 创建 MIDI 客户端，并监听设备变化（插拔、蓝牙连接断开等）
        let status = MIDIClientCreateWithBlock("PianoLearnClient" as CFString, &midiClient) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshConnections()
            }
        }
        
        guard status == noErr else {
            print("❌ MIDI 客户端创建失败，错误码：\(status)")
            return
        }
        
        // 2. 创建输入端口，接收 MIDI 数据
        //    使用新版 MIDIInputPortCreateWithProtocol（iOS 15+ / Xcode 26 推荐）
        let portStatus = MIDIInputPortCreateWithProtocol(
            midiClient,
            "PianoLearnInput" as CFString,
            MIDIProtocolID._1_0,  // 使用标准 MIDI 1.0 协议
            &inputPort
        ) { [weak self] eventList, _ in
            // 这里在非主线程运行，收到 MIDI 数据时触发
            self?.handleEventList(eventList)
        }
        
        guard portStatus == noErr else {
            print("❌ MIDI 输入端口创建失败，错误码：\(portStatus)")
            return
        }
        
        // 3. 连接所有已存在的 MIDI 输入源
        refreshConnections()
        print("✅ MIDI 系统已启动")
    }
    
    // MARK: - 连接/刷新所有 MIDI 输入源
    
    private func refreshConnections() {
        let count = MIDIGetNumberOfSources()
        DispatchQueue.main.async {
            self.connectedDeviceCount = count
        }
        
        // 连接每一个可用的 MIDI 源（USB、蓝牙配对后会自动出现在这里）
        for i in 0..<count {
            let source = MIDIGetSource(i)
            let connectStatus = MIDIPortConnectSource(inputPort, source, nil)
            if connectStatus == noErr {
                // 获取设备名称用于调试
                var name: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name)
                if let deviceName = name?.takeRetainedValue() {
                    print("🎹 已连接 MIDI 设备：\(deviceName)")
                }
            }
        }
    }
    
    // MARK: - 解析 MIDI 数据包
    
    private func handleEventList(_ eventList: UnsafePointer<MIDIEventList>) {
        var packet = eventList.pointee.packet
        let packetCount = eventList.pointee.numPackets
        
        for _ in 0..<packetCount {
            // 解析 UMP（Universal MIDI Packet）格式
            // MIDI 1.0 的音符消息格式（32-bit word）：
            // [31-28: 消息类型=0x2][27-24: 组][23-16: 状态字节][15-8: 音符][7-0: 力度]
            
            let wordCount = Int(packet.wordCount)
            withUnsafeBytes(of: packet.words) { rawBuffer in
                let words = rawBuffer.bindMemory(to: UInt32.self)
                for i in 0..<wordCount {
                    let word = words[i]
                    processUMPWord(word)
                }
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }
    
    private func processUMPWord(_ word: UInt32) {
        // 检查消息类型（高 4 位）
        // 0x2 = MIDI 1.0 Channel Voice Message（音符开/关、控制变化等）
        let messageType = (word >> 28) & 0xF
        guard messageType == 0x2 else { return }
        
        // 解析状态字节
        let status = UInt8((word >> 16) & 0xFF)
        let noteNumber = UInt8((word >> 8) & 0xFF)
        let velocity = UInt8(word & 0xFF)
        
        let messageKind = status & 0xF0  // 高 4 位是消息类型
        
        if messageKind == 0x90 && velocity > 0 {
            // Note On（velocity > 0 才算真正按下）
            DispatchQueue.main.async {
                self.activeNotes.insert(Int(noteNumber))
                self.onNoteOn?(noteNumber, velocity)
            }
            
        } else if messageKind == 0x80 || (messageKind == 0x90 && velocity == 0) {
            // Note Off（0x80 或 velocity=0 的 Note On 都算松键）
            DispatchQueue.main.async {
                self.activeNotes.remove(Int(noteNumber))
                self.onNoteOff?(noteNumber)
            }
        }
    }
}
