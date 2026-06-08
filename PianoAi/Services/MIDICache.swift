import Foundation

// Downloads MIDI files from presigned S3 URLs and caches them locally.
// Actor serialization prevents duplicate concurrent downloads for the same song.
actor MIDICache {

    static let shared = MIDICache()
    private init() {}

    // Bundle resource names for the three demo songs — no auth needed.
    private static let bundled: [String: String] = [
        "02bc682e-b784-44f9-85de-1d1e89709bec": "bundle_beginner",
        "b6582fb7-87e6-4a17-8880-6df22b003099": "bundle_intermediate",
        "0e2ab5b0-abda-47fc-bb0b-de431fdd0840": "bundle_advanced",
    ]

    nonisolated func localURL(for songId: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("midi/\(songId).mid")
    }

    nonisolated func isCached(_ songId: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: songId).path)
    }

    /// Returns a local URL for the song's MIDI file, downloading it first if needed.
    nonisolated func fetch(song: Song, session: AuthSession) async throws -> URL {
        let dest = localURL(for: song.id)
        if FileManager.default.fileExists(atPath: dest.path) { return dest }

        // Check app bundle first — works without auth (used during onboarding)
        if let name = MIDICache.bundled[song.id],
           let url  = Bundle.main.url(forResource: name, withExtension: "mid") {
            return url
        }

        let result: SongFilesResult = try await session.request(.songFiles(id: song.id))
        guard let midiStr = result.midiUrl, let remote = URL(string: midiStr) else {
            throw MIDICacheError.noMIDIFile
        }

        // Presigned URL — no auth header needed
        let (tmp, _) = try await URLSession.shared.download(from: remote)

        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}

enum MIDICacheError: LocalizedError {
    case noMIDIFile
    var errorDescription: String? { "该曲目暂无 MIDI 文件" }
}
