import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "play.circle.fill") }
                .tag(0)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(1)

            RankingView()
                .tabItem { Label("Rank", systemImage: "trophy.fill") }
                .tag(2)

            LeaderboardView()
                .tabItem { Label("Leaderboard", systemImage: "chart.bar.fill") }
                .tag(3)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(4)
        }
        .tint(CinemaTheme.Colors.gold)
    }
}
