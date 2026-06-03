import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem { Image(systemName: "popcorn.fill") }
                .tag(0)

            MyFilmsView()
                .tabItem { Image(systemName: "list.number") }
                .tag(1)

            SearchView()
                .tabItem { Image(systemName: "magnifyingglass") }
                .tag(2)

            SearchView()
                .tabItem { Image(systemName: "sparkles") }
                .tag(3)

            ProfileView()
                .tabItem { Image(systemName: "person.fill") }
                .tag(4)
        }
        .tint(CinemaTheme.Colors.gold)
    }
}
