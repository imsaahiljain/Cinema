import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showRanking = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                MyFilmsView()
                    .tabItem { Label("My Films", systemImage: "list.number") }
                    .tag(0)

                WatchlistView()
                    .tabItem { Label("Watchlist", systemImage: "bookmark.fill") }
                    .tag(1)

                Color.clear
                    .tabItem { Label("Rank", systemImage: "film.fill") }
                    .tag(2)

                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(3)

                ProfileView()
                    .tabItem { Label("Profile", systemImage: "person.fill") }
                    .tag(4)
            }
            .tint(CinemaTheme.Colors.gold)
            .onChange(of: selectedTab) { _, new in
                if new == 2 {
                    showRanking = true
                    selectedTab = 0
                }
            }

            // Center rank button
            Button {
                showRanking = true
            } label: {
                ZStack {
                    Circle()
                        .fill(CinemaTheme.Colors.gold)
                        .frame(width: 56, height: 56)
                        .shadow(color: CinemaTheme.Colors.gold.opacity(0.4), radius: 12, y: 4)
                    Image(systemName: "film.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            .offset(y: -28)
        }
        .fullScreenCover(isPresented: $showRanking) {
            RankingView()
        }
    }
}
