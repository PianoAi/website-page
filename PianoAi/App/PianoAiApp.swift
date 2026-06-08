//
//  PianoAiApp.swift
//  PianoAi
//
//  Created by Fox on 5/21/26.
//

import SwiftUI

@main
struct PianoAiApp: App {
    @State private var authSession         = AuthSession()
    @State private var subscriptionManager = SubscriptionManager()
    @State private var showSplash          = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(authSession)
                    .environment(subscriptionManager)
                    .task {
                        await subscriptionManager.refreshStatus(session: authSession)
                    }

                if showSplash {
                    SplashView { showSplash = false }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSplash)
        }
    }
}
