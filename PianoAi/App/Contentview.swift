import SwiftUI

// MARK: - Auth + Onboarding gate

struct ContentView: View {
    @Environment(AuthSession.self) private var authSession
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // Services live here so both onboarding and main app share the same instances.
    @StateObject private var midiManager = MIDIManager()
    @StateObject private var soundEngine = SoundEngine()
    // 引导期间（未登录）提供一个空的 ProgressRepository，避免 PracticeView 找不到 environmentObject
    @StateObject private var guestProgressRepo = ProgressRepository(session: AuthSession())

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                // Onboarding: no auth required — bundled MIDI, registration at the end.
                OnboardingView(onComplete: { hasCompletedOnboarding = true })
                    .environmentObject(midiManager)
                    .environmentObject(soundEngine)
                    .environmentObject(guestProgressRepo)
            } else {
                // 引导完成后始终显示主 App，无论是否登录
                // 未登录用户可以浏览歌曲，练习时再要求登录
                AppRootView(authSession: authSession)
                    .environmentObject(midiManager)
                    .environmentObject(soundEngine)
            }
        }
        .onAppear {
            midiManager.onNoteOn = { [weak soundEngine] note, vel in
                soundEngine?.playNote(note: note, velocity: vel)
            }
            midiManager.onNoteOff = { [weak soundEngine] note in
                soundEngine?.stopNote(note: note)
            }
            midiManager.start()
        }
    }
}

// MARK: - Main app (requires auth)

private struct AppRootView: View {
    let authSession: AuthSession

    @EnvironmentObject var midiManager:  MIDIManager
    @EnvironmentObject var soundEngine:  SoundEngine

    @StateObject private var songRepository:     SongRepository
    @StateObject private var progressRepository: ProgressRepository

    init(authSession: AuthSession) {
        self.authSession = authSession
        _songRepository     = StateObject(wrappedValue: SongRepository(session: authSession))
        _progressRepository = StateObject(wrappedValue: ProgressRepository(session: authSession))
    }

    var body: some View {
        MainTabView()
            .environmentObject(songRepository)
            .environmentObject(progressRepository)
            .onAppear {
                // Re-bind callbacks in case onboarding changed them.
                midiManager.onNoteOn = { [weak soundEngine] note, vel in
                    soundEngine?.playNote(note: note, velocity: vel)
                }
                midiManager.onNoteOff = { [weak soundEngine] note in
                    soundEngine?.stopNote(note: note)
                }
                songRepository.load()
                Task {
                    try? await authSession.fetchCurrentUser()
                    await progressRepository.load()
                }
            }
    }
}

#Preview {
    ContentView()
        .environment(AuthSession())
}
