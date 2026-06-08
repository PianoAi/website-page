import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                PracticeHomeView()
            }
            .tabItem { Label("练习", systemImage: "music.note") }

            NavigationStack {
                DiscoverView()
            }
            .tabItem { Label("发现", systemImage: "magnifyingglass") }

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("我的", systemImage: "person.fill") }
        }
    }
}
