import Foundation

// Parses Standard MIDI Files (SMF format 0 and 1) into a flat MusicalNote sequence.
// Captures note duration by matching Note On / Note Off pairs.
// For polyphonic content, only the highest-pitched note at each onset is kept,
// giving a single-voice melody line suitable for one-at-a-time practice.
struct MIDIParser {

    // MARK: - Public

    static func parse(url: URL) throws -> [MusicalNote] {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    // MARK: - Private: file-level

    private static func parse(data: Data) throws -> [MusicalNote] {
        var offset = 0

        guard data.count > 14,
              data[0..<4].elementsEqual([0x4D, 0x54, 0x68, 0x64])  // "MThd"
        else { throw MIDIParseError.invalidFile }

        offset += 4
        let _ = readUInt32(data, at: offset); offset += 4   // header length (always 6)
        let _ = readUInt16(data, at: offset); offset += 2   // format (0 or 1)
        let ntrks = Int(readUInt16(data, at: offset)); offset += 2
        let ppqn  = Int(readUInt16(data, at: offset)); offset += 2

        guard ppqn & 0x8000 == 0 else { throw MIDIParseError.smpteNotSupported }

        var allNotes: [RawNote] = []
        var tempoUsPerBeat: Int? = nil

        for _ in 0..<ntrks {
            guard offset + 8 <= data.count,
                  data[offset..<(offset + 4)].elementsEqual([0x4D, 0x54, 0x72, 0x6B])  // "MTrk"
            else { break }
            offset += 4
            let trackLen = Int(readUInt32(data, at: offset)); offset += 4
            let trackEnd = min(offset + trackLen, data.count)

            let (notes, tempo) = parseTrack(data, start: offset, end: trackEnd)
            allNotes.append(contentsOf: notes)
            if tempoUsPerBeat == nil, let t = tempo { tempoUsPerBeat = t }

            offset = trackEnd
        }

        return deduplicatedNotes(allNotes, ppqn: max(1, ppqn))
    }

    // MARK: - Private: raw note (includes duration)

    private struct RawNote {
        let tick: Int           // Note On tick (onset time)
        let midiNumber: Int
        let durationTicks: Int  // Note Off tick − Note On tick; 0 if Note Off missing
    }

    // MARK: - Private: track-level

    private static func parseTrack(_ data: Data, start: Int, end: Int) -> ([RawNote], Int?) {
        var offset = start
        var absoluteTick = 0
        var notes: [RawNote] = []
        var pendingNoteOns: [Int: Int] = [:]   // midiNumber → Note On absoluteTick
        var runningStatus: UInt8 = 0
        var firstTempo: Int? = nil

        while offset < end {
            let (delta, dBytes) = readVLQ(data, at: offset)
            guard dBytes > 0 else { break }
            offset += dBytes
            absoluteTick += delta
            guard offset < end else { break }

            let firstByte = data[offset]
            var status: UInt8

            if firstByte & 0x80 != 0 {
                status = firstByte
                offset += 1
                if status < 0xF0 { runningStatus = status }
            } else {
                guard runningStatus != 0 else { offset += 1; continue }
                status = runningStatus
            }

            if status == 0xFF {
                // Meta event
                guard offset < end else { break }
                let metaType = data[offset]; offset += 1
                let (len, lb) = readVLQ(data, at: offset); offset += lb
                if metaType == 0x2F { break }  // End of Track
                if metaType == 0x51, len == 3, offset + 3 <= end {
                    let us = (Int(data[offset]) << 16) | (Int(data[offset + 1]) << 8) | Int(data[offset + 2])
                    if firstTempo == nil { firstTempo = us }
                }
                offset = min(offset + len, end)

            } else if status == 0xF0 || status == 0xF7 {
                // SysEx
                let (len, lb) = readVLQ(data, at: offset)
                offset = min(offset + lb + len, end)

            } else {
                let msgType = status & 0xF0
                switch msgType {
                case 0x90:  // Note On
                    guard offset + 1 < end else { break }
                    let noteNum = Int(data[offset]); offset += 1
                    let vel     = data[offset];      offset += 1
                    if vel > 0 {
                        pendingNoteOns[noteNum] = absoluteTick
                    } else {
                        // Note On velocity 0 = Note Off
                        if let startTick = pendingNoteOns.removeValue(forKey: noteNum) {
                            notes.append(RawNote(tick: startTick, midiNumber: noteNum,
                                                 durationTicks: absoluteTick - startTick))
                        }
                    }
                case 0x80:  // Note Off
                    guard offset + 1 < end else { break }
                    let noteNum = Int(data[offset]); offset += 1
                    offset += 1  // release velocity (ignored)
                    if let startTick = pendingNoteOns.removeValue(forKey: noteNum) {
                        notes.append(RawNote(tick: startTick, midiNumber: noteNum,
                                             durationTicks: absoluteTick - startTick))
                    }
                case 0xA0, 0xB0, 0xE0:  // Aftertouch / CC / Pitch Bend (2 bytes)
                    guard offset + 1 < end else { break }
                    offset += 2
                case 0xC0, 0xD0:        // Program Change / Channel Pressure (1 byte)
                    guard offset < end else { break }
                    offset += 1
                default:
                    if offset < end { offset += 1 }
                }
            }
        }

        // Notes without a matching Note Off get duration 0 (will be clamped to minimum later)
        for (midiNum, startTick) in pendingNoteOns {
            notes.append(RawNote(tick: startTick, midiNumber: midiNum, durationTicks: 0))
        }

        return (notes, firstTempo)
    }

    // MARK: - Private: group simultaneous notes → highest as melody, rest as chord context

    private static func deduplicatedNotes(_ raw: [RawNote], ppqn: Int) -> [MusicalNote] {
        guard !raw.isEmpty else { return [] }
        let sorted = raw.sorted { $0.tick < $1.tick }
        var result: [MusicalNote] = []
        var i = 0
        while i < sorted.count {
            let tick = sorted[i].tick
            var j = i + 1
            while j < sorted.count, sorted[j].tick == tick { j += 1 }

            let chordMidis = Array(Set((i..<j).map { sorted[$0].midiNumber })).sorted()
            let melody = chordMidis.last!

            // Use the longest duration among all occurrences of the melody pitch at this onset
            let melodyDuration = (i..<j)
                .filter { sorted[$0].midiNumber == melody }
                .map { sorted[$0].durationTicks }
                .max() ?? ppqn

            let durationBeats = Double(melodyDuration) / Double(ppqn)
            let startBeat    = Double(tick) / Double(ppqn)
            result.append(MusicalNote(
                midiNumber: melody,
                chordNotes: chordMidis,
                durationBeats: max(0.125, durationBeats),
                startBeat: startBeat
            ))
            i = j
        }
        return result
    }

    // MARK: - Helpers

    private static func readUInt32(_ data: Data, at i: Int) -> UInt32 {
        (UInt32(data[i]) << 24) | (UInt32(data[i+1]) << 16) | (UInt32(data[i+2]) << 8) | UInt32(data[i+3])
    }

    private static func readUInt16(_ data: Data, at i: Int) -> UInt16 {
        (UInt16(data[i]) << 8) | UInt16(data[i+1])
    }

    private static func readVLQ(_ data: Data, at offset: Int) -> (Int, Int) {
        var value = 0
        var bytesRead = 0
        var i = offset
        while i < data.count, bytesRead < 4 {
            let byte = Int(data[i]); i += 1; bytesRead += 1
            value = (value << 7) | (byte & 0x7F)
            if byte & 0x80 == 0 { break }
        }
        return (value, bytesRead)
    }
}

enum MIDIParseError: LocalizedError {
    case invalidFile
    case smpteNotSupported
    var errorDescription: String? {
        switch self {
        case .invalidFile:        return "无效的 MIDI 文件格式"
        case .smpteNotSupported:  return "不支持 SMPTE 时间格式"
        }
    }
}
